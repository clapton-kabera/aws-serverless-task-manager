"""
app.py (create_task)
author: Kabera Clapton

description: POST /tasks (admin only). Validates input, checks the assignee is an active member,
             and writes the task and its first history event in one transaction.
"""

import uuid

from common import db, tasks, users
from common.auth import get_caller, require_admin
from common.http import ApiError, api_handler, parse_body, response


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    require_admin(caller)

    body = parse_body(event)
    unknown = set(body) - tasks.CREATE_FIELDS
    if unknown:
        raise ApiError(400, f"Unknown fields: {', '.join(sorted(unknown))}")

    title = tasks.clean_title(body.get("title"))
    description = tasks.clean_description(body.get("description"))
    deadline = tasks.clean_deadline(body.get("deadline"))
    assignee = users.get_member(tasks.clean_assignee_id(body.get("assigneeId")))

    task_id = str(uuid.uuid4())
    now = tasks.now_iso()
    task = {
        "pk": db.task_pk(task_id),
        "sk": "META",
        "taskId": task_id,
        "title": title,
        "description": description,
        "status": "OPEN",
        "assigneeId": assignee["id"],
        "assigneeEmail": assignee["email"],
        "deadline": deadline,
        "openDueDate": tasks.due_date(deadline),  # sparse index: present only while not DONE
        "createdBy": caller.sub,
        "updatedBy": caller.sub,
        "createdAt": now,
        "updatedAt": now,
        "version": 1,
    }
    created = tasks.history_event(task_id, caller.sub, "CREATED",
                                  {"assigneeId": assignee["id"], "deadline": deadline})

    # Both writes succeed or neither does: no task without its history, or vice versa.
    db.client().transact_write_items(TransactItems=[
        {"Put": {"TableName": db.table_name(), "Item": db.to_item(task),
                 "ConditionExpression": "attribute_not_exists(pk)"}},
        {"Put": {"TableName": db.table_name(), "Item": db.to_item(created)}},
    ])

    return response(201, tasks.to_api(task))
