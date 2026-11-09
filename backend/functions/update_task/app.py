"""
app.py (update_task)
author: Kabera Clapton

description: PUT /tasks/{taskId}. Admins may change title, description, deadline, status and
             assignee; members may change only the status of their own tasks. The client must send
             the version it last read (optimistic locking), and the rules are re-checked inside
             DynamoDB's condition expression so a race between read and write cannot bypass them.
"""

from botocore.exceptions import ClientError

from common import db, tasks, users
from common.auth import get_caller
from common.http import ApiError, api_handler, parse_body, path_param, response


def _expected_version(body):
    version = body.pop("version", None)
    # bool is a subclass of int in Python, so exclude it explicitly
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise ApiError(400, "version is required: send the version you last read")
    return version


def _check_fields(body, caller):
    allowed = tasks.ADMIN_UPDATE_FIELDS if caller.is_admin else tasks.MEMBER_UPDATE_FIELDS
    disallowed = set(body) - allowed
    if disallowed:
        if not caller.is_admin and disallowed <= tasks.ADMIN_UPDATE_FIELDS:
            raise ApiError(403, "Members can only change: status")
        raise ApiError(400, f"Unknown fields: {', '.join(sorted(disallowed))}")
    if not body:
        raise ApiError(400, "Nothing to update")


def _clean(field, value):
    cleaners = {
        "title": tasks.clean_title,
        "description": tasks.clean_description,
        "status": tasks.clean_status,
        "deadline": tasks.clean_deadline,
        "assigneeId": tasks.clean_assignee_id,
    }
    return cleaners[field](value)


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    task_id = tasks.clean_task_id(path_param(event, "taskId"))
    body = parse_body(event)
    expected = _expected_version(body)
    _check_fields(body, caller)

    found = db.client().get_item(TableName=db.table_name(), Key=db.task_key(task_id),
                                 ConsistentRead=True)
    current = db.from_item(found["Item"]) if "Item" in found else None
    if current is None or (not caller.is_admin and current.get("assigneeId") != caller.sub):
        raise ApiError(404, "Task not found")
    if int(current["version"]) != expected:
        raise ApiError(409, f"Task has changed (current version {int(current['version'])}); reload and retry")

    new = {}
    changes = {}
    for field, raw in body.items():
        value = _clean(field, raw)
        if value == current.get(field):
            continue
        changes[field] = {"from": current.get(field), "to": value}
        new[field] = value
        if field == "assigneeId":
            new["assigneeEmail"] = users.get_member(value)["email"]

    if not changes:
        return response(200, tasks.to_api(current))  # no-op: nothing written, version unchanged

    new["updatedAt"] = tasks.now_iso()
    new["updatedBy"] = caller.sub  # the notifier uses this to decide who to tell
    new["version"] = expected + 1

    names = {f"#{key}": key for key in new}
    values = {f":{key}": value for key, value in new.items()}
    set_parts = [f"#{key} = :{key}" for key in new]
    remove_parts = []

    # Keep the sparse reminder index in sync: only unfinished tasks have openDueDate.
    final_status = new.get("status", current["status"])
    final_deadline = new.get("deadline", current["deadline"])
    names["#openDueDate"] = "openDueDate"
    if final_status == "DONE":
        remove_parts.append("#openDueDate")
    else:
        set_parts.append("#openDueDate = :openDueDate")
        values[":openDueDate"] = tasks.due_date(final_deadline)
    if "deadline" in new or "assigneeId" in new:
        # New deadline or new person: the reminder should fire again (used in batch 3).
        names["#reminderSentAt"] = "reminderSentAt"
        remove_parts.append("#reminderSentAt")

    update_expression = "SET " + ", ".join(set_parts)
    if remove_parts:
        update_expression += " REMOVE " + ", ".join(remove_parts)

    condition = "attribute_exists(pk) AND #version = :expected"
    values[":expected"] = expected
    if not caller.is_admin:
        condition += " AND assigneeId = :caller"
        values[":caller"] = caller.sub

    history = tasks.history_event(task_id, caller.sub, "UPDATED", changes)

    try:
        db.client().transact_write_items(TransactItems=[
            {"Update": {
                "TableName": db.table_name(),
                "Key": db.task_key(task_id),
                "UpdateExpression": update_expression,
                "ConditionExpression": condition,
                "ExpressionAttributeNames": names,
                "ExpressionAttributeValues": db.to_values(values),
            }},
            {"Put": {"TableName": db.table_name(), "Item": db.to_item(history)}},
        ])
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "TransactionCanceledException":
            # Someone changed the task between our read and our write.
            raise ApiError(409, "Task was changed by someone else; reload and retry") from None
        raise

    updated = {**current, **new}
    if final_status == "DONE":
        updated.pop("openDueDate", None)
    return response(200, tasks.to_api(updated))
