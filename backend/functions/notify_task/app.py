"""
app.py (notify_task)
author: Kabera Clapton

description: POST /tasks/{taskId}/notify (admin only). Manually nudges the assignee about a task,
             e.g. when a deadline is close and nothing has changed.
"""

from common import db, notify, tasks
from common.auth import get_caller, require_admin
from common.http import ApiError, api_handler, path_param, response


@api_handler
def lambda_handler(event, context):
    require_admin(get_caller(event))
    task_id = tasks.clean_task_id(path_param(event, "taskId"))

    found = db.client().get_item(TableName=db.table_name(), Key=db.task_key(task_id))
    if "Item" not in found:
        raise ApiError(404, "Task not found")
    task = db.from_item(found["Item"])
    if task["status"] == "DONE":
        raise ApiError(400, "Task is already done")

    notify.to_assignee(task, f"Reminder: {task['title']}",
                       "An admin sent you a reminder about this task.\n\n" + notify.task_summary(task))
    return response(200, {"notified": task.get("assigneeEmail"), "taskId": task_id})
