"""
access.py
author: Kabera Clapton

description: Loading a task on behalf of a caller. Admins can see every task; members only their own.
             A task the caller may not see is reported as "not found" (404), so members cannot probe
             which task IDs exist.
"""

from common import db, tasks
from common.http import ApiError


def load_visible_task(caller, task_id):
    task_id = tasks.clean_task_id(task_id)
    found = db.client().get_item(TableName=db.table_name(), Key=db.task_key(task_id))
    task = db.from_item(found["Item"]) if "Item" in found else None
    if task is None or (not caller.is_admin and task.get("assigneeId") != caller.sub):
        raise ApiError(404, "Task not found")
    return task
