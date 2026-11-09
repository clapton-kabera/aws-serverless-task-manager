"""
app.py (deadline_reminder)
author: Kabera Clapton

description: Runs hourly (EventBridge Scheduler). Finds unfinished tasks due in the next 24 hours
             that have not been reminded yet, using the sparse open_by_due_date index (one Query per
             UTC day the window touches), and emails each assignee once.

             Each task is CLAIMED first (conditional write of reminderSentAt) and only then emailed,
             so overlapping or retried runs cannot send duplicates. If the email fails, the claim is
             released so the next run tries again.
"""

import json
import logging
from datetime import datetime, timedelta, timezone

from botocore.exceptions import ClientError

from common import db, notify

logger = logging.getLogger()
logger.setLevel(logging.INFO)

WINDOW = timedelta(hours=24)
ISO = "%Y-%m-%dT%H:%M:%SZ"


def _due_soon(now, end):
    days = sorted({now[:10], end[:10]})  # the window can cross midnight UTC
    for day in days:
        kwargs = {
            "TableName": db.table_name(),
            "IndexName": db.OPEN_BY_DUE_DATE_INDEX,
            "KeyConditionExpression": "openDueDate = :day AND deadline BETWEEN :now AND :end",
            "FilterExpression": "attribute_not_exists(reminderSentAt)",
            "ExpressionAttributeValues": db.to_values({":day": day, ":now": now, ":end": end}),
        }
        while True:
            page = db.client().query(**kwargs)
            for item in page.get("Items", []):
                yield db.from_item(item)
            if "LastEvaluatedKey" not in page:
                break
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]


def _claim(task, now):
    """Mark the task as reminded. False if another run got there first or it is now DONE."""
    try:
        db.client().update_item(
            TableName=db.table_name(),
            Key=db.task_key(task["taskId"]),
            UpdateExpression="SET reminderSentAt = :now",
            ConditionExpression=("attribute_exists(pk) AND attribute_not_exists(reminderSentAt) "
                                 "AND #status <> :done"),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues=db.to_values({":now": now, ":done": "DONE"}),
        )
        return True
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise


def _release(task):
    db.client().update_item(
        TableName=db.table_name(),
        Key=db.task_key(task["taskId"]),
        UpdateExpression="REMOVE reminderSentAt",
    )


def lambda_handler(event, context):
    now_dt = datetime.now(timezone.utc)
    now, end = now_dt.strftime(ISO), (now_dt + WINDOW).strftime(ISO)

    sent, failed = 0, 0
    for task in _due_soon(now, end):
        if not _claim(task, now):
            continue
        try:
            notify.to_assignee(task, f"Deadline approaching: {task['title']}",
                               "This task is due within 24 hours.\n\n" + notify.task_summary(task))
            sent += 1
        except Exception:  # noqa: BLE001 - release the claim so the next hourly run retries
            logger.exception("Reminder failed for task %s", task["taskId"])
            _release(task)
            failed += 1

    logger.info(json.dumps({"window": [now, end], "sent": sent, "failed": failed}))
    if failed:
        raise RuntimeError(f"{failed} reminder(s) failed; claims released for retry")
    return {"remindersSent": sent}
