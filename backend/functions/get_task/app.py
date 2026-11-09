"""
app.py (get_task)
author: Kabera Clapton

description: GET /tasks/{taskId}. Returns the task and its history in ONE Query, because the task
             and its events share a partition key (an "item collection"). Members only see their own
             tasks; any other task returns 404, not 403, so members cannot probe which IDs exist.
"""

from common import db, tasks
from common.auth import get_caller
from common.http import ApiError, api_handler, path_param, response


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    task_id = tasks.clean_task_id(path_param(event, "taskId"))

    result = db.client().query(
        TableName=db.table_name(),
        KeyConditionExpression="pk = :pk",
        ExpressionAttributeValues=db.to_values({":pk": db.task_pk(task_id)}),
    )
    items = [db.from_item(item) for item in result.get("Items", [])]

    task = next((item for item in items if item["sk"] == "META"), None)
    if task is None or (not caller.is_admin and task.get("assigneeId") != caller.sub):
        raise ApiError(404, "Task not found")

    # Sort keys sort as strings: "EVENT#<time>..." < "META", so events arrive oldest first.
    history = [tasks.event_to_api(item) for item in items if item["sk"].startswith("EVENT#")]
    return response(200, {**tasks.to_api(task), "history": history})
