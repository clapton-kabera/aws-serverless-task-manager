"""
app.py (list_attachments)
author: Kabera Clapton

description: GET /tasks/{taskId}/attachments. For an admin or the task's assignee, lists the task's
             files with a presigned download URL for each (valid 5 minutes).
"""

from common import attachments
from common.access import load_visible_task
from common.auth import get_caller
from common.http import api_handler, path_param, response


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    task = load_visible_task(caller, path_param(event, "taskId"))
    return response(200, {"items": attachments.list_for_task(task["taskId"])})
