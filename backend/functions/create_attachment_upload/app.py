"""
app.py (create_attachment_upload)
author: Kabera Clapton

description: POST /tasks/{taskId}/attachments. For an admin or the task's assignee, returns a
             presigned POST the browser uses to upload ONE file directly to S3 within 5 minutes.
             Body: {"fileName": "...", "contentType": "...", "size": <bytes>}
             S3 enforces the size limit and content type from the signed policy, so a client cannot
             upload something different from what it asked for.
"""

import uuid

from common import attachments
from common.access import load_visible_task
from common.auth import get_caller
from common.http import ApiError, api_handler, parse_body, path_param, response

FIELDS = frozenset({"fileName", "contentType", "size"})


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    task = load_visible_task(caller, path_param(event, "taskId"))

    body = parse_body(event)
    unknown = set(body) - FIELDS
    if unknown:
        raise ApiError(400, f"Unknown fields: {', '.join(sorted(unknown))}")

    file_name = attachments.safe_file_name(body.get("fileName"))
    content_type = attachments.clean_content_type(body.get("contentType"))
    attachments.clean_size(body.get("size"))  # early, friendly check; S3 enforces it for real

    attachment_id = str(uuid.uuid4())
    key = f"{attachments.task_prefix(task['taskId'])}{attachment_id}/{file_name}"
    upload = attachments.presigned_upload(key, content_type, caller.sub)

    return response(201, {
        "attachmentId": attachment_id,
        "fileName": file_name,
        "upload": upload,  # {"url": ..., "fields": {...}}: POST multipart/form-data, file field LAST
        "expiresIn": attachments.URL_TTL_SECONDS,
    })
