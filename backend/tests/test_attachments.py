"""
test_attachments.py
author: Kabera Clapton

description: Tests for attachments: who may upload/list, input validation, the presigned POST policy
             (size limit, fixed content type, regional URL), file name sanitising, and listing with
             download links.
"""

import base64
import json

import boto3
from conftest import REGION, call, make_event

from common.attachments import MAX_BYTES, safe_file_name

FUTURE = "2099-01-15T17:00:00Z"
PDF = "application/pdf"


def as_user(person, **kwargs):
    return make_event(person["sub"], person["groups"], **kwargs)


def create_task(aws, assignee="alice"):
    body = {"title": "Inspect site A", "deadline": FUTURE, "assigneeId": aws[assignee]["sub"]}
    return call("create_task", as_user(aws["admin"], method="POST", body=body))[1]


def request_upload(person, task_id, **overrides):
    body = {"fileName": "report.pdf", "contentType": PDF, "size": 1024, **overrides}
    return call("create_attachment_upload", as_user(person, method="POST", body=body,
                                                    path_params={"taskId": task_id}))


def test_assignee_gets_presigned_post_with_enforced_policy(aws):
    task = create_task(aws)
    status, body = request_upload(aws["alice"], task["taskId"])

    assert status == 201
    upload = body["upload"]
    assert upload["url"].startswith("https://test-attachments.s3.eu-west-1.amazonaws.com")
    assert upload["fields"]["key"] == f"tasks/{task['taskId']}/{body['attachmentId']}/report.pdf"

    policy = json.loads(base64.b64decode(upload["fields"]["policy"]))
    assert ["content-length-range", 1, MAX_BYTES] in policy["conditions"]
    assert {"Content-Type": PDF} in policy["conditions"]


def test_other_member_cannot_upload_or_list(aws):
    task = create_task(aws, assignee="bob")
    assert request_upload(aws["alice"], task["taskId"])[0] == 404
    status, _ = call("list_attachments", as_user(aws["alice"], path_params={"taskId": task["taskId"]}))
    assert status == 404


def test_rejects_disallowed_type_and_oversized_file(aws):
    task = create_task(aws)
    assert request_upload(aws["alice"], task["taskId"], contentType="text/html")[0] == 400
    assert request_upload(aws["alice"], task["taskId"], size=MAX_BYTES + 1)[0] == 400


def test_file_names_are_sanitised():
    assert safe_file_name("../../etc/passwd") == "passwd"
    assert safe_file_name("C:\\Users\\me\\site photo (1).png") == "site_photo_1_.png"
    assert safe_file_name("raport_ikibazo.pdf") == "raport_ikibazo.pdf"


def test_list_returns_files_with_download_links(aws):
    task = create_task(aws)
    _, body = request_upload(aws["alice"], task["taskId"])
    key = body["upload"]["fields"]["key"]
    # Simulate the browser's direct upload to S3
    boto3.client("s3", region_name=REGION).put_object(Bucket="test-attachments", Key=key, Body=b"%PDF-1.4")

    status, listing = call("list_attachments", as_user(aws["admin"], path_params={"taskId": task["taskId"]}))
    assert status == 200
    [item] = listing["items"]
    assert item["fileName"] == "report.pdf" and item["size"] == 8
    assert "response-content-disposition=attachment" in item["downloadUrl"]
