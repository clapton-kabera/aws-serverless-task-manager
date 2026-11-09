"""
app.py (task_notifier)
author: Kabera Clapton

description: Triggered by the tasks table's DynamoDB stream (task items only, via an event source
             filter). Turns changes into notifications:
               new task / reassignment -> the new assignee (and the previous one, if reassigned)
               member changed status   -> admins
               admin changed details   -> the assignee
             Decoupled from the API on purpose: an SNS problem never fails a user's request, and
             failed records are retried and then sent to a dead-letter queue.
"""

import json
import logging

from common import db, notify

logger = logging.getLogger()
logger.setLevel(logging.INFO)

WATCHED_FIELDS = ("title", "description", "deadline", "status", "assigneeId")


def _changes(old, new):
    return [field for field in WATCHED_FIELDS if old.get(field) != new.get(field)]


def _describe(old, new, fields):
    lines = []
    for field in fields:
        before, after = old.get(field), new.get(field)
        if field == "deadline":
            before, after = notify.format_deadline(before), notify.format_deadline(after)
        lines.append(f"- {field}: {before} -> {after}")
    return "\n".join(lines)


def handle_insert(task):
    notify.to_assignee(task, f"New task assigned: {task['title']}",
                       "You have been assigned a new task.\n\n" + notify.task_summary(task))


def handle_modify(old, new):
    # The reminder job only stamps reminderSentAt and does not bump the version:
    # that is bookkeeping, not a change anyone should be notified about.
    if old.get("version") == new.get("version"):
        return

    fields = _changes(old, new)
    if not fields:
        return

    if "assigneeId" in fields:
        handle_insert(new)
        notify.to_assignee(old, f"Task reassigned: {old['title']}",
                           "This task has been reassigned to someone else.\n\n"
                           + notify.task_summary(new))
        return

    details = _describe(old, new, fields)
    if new.get("updatedBy") == new.get("assigneeId"):
        notify.to_admins(f"Task updated by assignee: {new['title']}",
                         f"{new.get('assigneeEmail')} updated a task:\n{details}\n\n"
                         + notify.task_summary(new))
    else:
        notify.to_assignee(new, f"Task updated: {new['title']}",
                           f"An admin updated your task:\n{details}\n\n" + notify.task_summary(new))


def handle_record(record):
    images = record["dynamodb"]
    new = db.from_item(images["NewImage"]) if "NewImage" in images else None
    old = db.from_item(images["OldImage"]) if "OldImage" in images else None

    if record["eventName"] == "INSERT" and new:
        handle_insert(new)
    elif record["eventName"] == "MODIFY" and old and new:
        handle_modify(old, new)
    # REMOVE: tasks are not deleted through the API; nothing to notify.


def lambda_handler(event, context):
    """Report failures per record, so one bad record does not make the whole batch retry."""
    failures = []
    for record in event.get("Records", []):
        try:
            handle_record(record)
        except Exception:  # noqa: BLE001 - retried by Lambda, then sent to the DLQ
            logger.exception("Failed to process record %s", record.get("eventID"))
            failures.append({"itemIdentifier": record["dynamodb"]["SequenceNumber"]})

    logger.info(json.dumps({"records": len(event.get("Records", [])), "failed": len(failures)}))
    return {"batchItemFailures": failures}
