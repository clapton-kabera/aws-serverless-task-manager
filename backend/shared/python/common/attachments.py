"""
attachments.py
author: Kabera Clapton

description: Task attachments in S3. Files never pass through API Gateway or Lambda (their request
             size limits are ~10 MB and 6 MB); the browser uploads straight to S3 with a short-lived
             presigned POST, and downloads with a short-lived presigned GET.
             Object layout: tasks/<taskId>/<attachmentId>/<safe file name>
             S3 is the source of truth for attachments; nothing is duplicated in DynamoDB.
"""

import os
import re

import boto3
from botocore.config import Config

from common.http import ApiError

MAX_BYTES = 10 * 1024 * 1024
URL_TTL_SECONDS = 300  # 5 minutes: long enough to upload, short enough that a leaked URL is useless

# Only types the team needs. Blocking HTML/SVG/JS means an uploaded file can never run as a web page.
ALLOWED_TYPES = frozenset({
    "image/jpeg",
    "image/png",
    "application/pdf",
    "text/plain",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",  # .docx
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",        # .xlsx
})

_UNSAFE = re.compile(r"[^A-Za-z0-9._-]+")
_client = None


def s3():
    global _client
    if _client is None:
        region = os.environ.get("AWS_REGION", "eu-west-1")
        # Regional endpoint + SigV4: the global endpoint can answer a new bucket with a redirect,
        # which browsers refuse to follow during a CORS upload.
        _client = boto3.client(
            "s3",
            region_name=region,
            endpoint_url=f"https://s3.{region}.amazonaws.com",
            config=Config(signature_version="s3v4", s3={"addressing_style": "virtual"}),
        )
    return _client


def bucket():
    return os.environ["ATTACHMENTS_BUCKET"]


def task_prefix(task_id):
    return f"tasks/{task_id}/"


def safe_file_name(name):
    """Keep a readable, safe name: no paths, no spaces or odd characters, at most 100 characters."""
    if not isinstance(name, str):
        raise ApiError(400, "fileName is required")
    base = name.replace("\\", "/").rsplit("/", 1)[-1]  # drop any directory part
    cleaned = _UNSAFE.sub("_", base).strip("._")[:100]
    if not cleaned:
        raise ApiError(400, "fileName is not valid")
    return cleaned


def clean_content_type(value):
    if value not in ALLOWED_TYPES:
        raise ApiError(400, "contentType is not allowed. Allowed: " + ", ".join(sorted(ALLOWED_TYPES)))
    return value


def clean_size(value):
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= MAX_BYTES:
        raise ApiError(400, f"size must be between 1 and {MAX_BYTES} bytes")
    return value


def presigned_upload(key, content_type, uploader):
    """Presigned POST rather than PUT: its policy lets S3 itself enforce the size limit and type."""
    return s3().generate_presigned_post(
        Bucket=bucket(),
        Key=key,
        Fields={"Content-Type": content_type, "x-amz-meta-uploaded-by": uploader},
        Conditions=[
            {"Content-Type": content_type},
            {"x-amz-meta-uploaded-by": uploader},
            ["content-length-range", 1, MAX_BYTES],
        ],
        ExpiresIn=URL_TTL_SECONDS,
    )


def presigned_download(key, file_name):
    # "attachment" makes browsers download the file instead of displaying it inline.
    return s3().generate_presigned_url(
        "get_object",
        Params={
            "Bucket": bucket(),
            "Key": key,
            "ResponseContentDisposition": f'attachment; filename="{file_name}"',
        },
        ExpiresIn=URL_TTL_SECONDS,
    )


def list_for_task(task_id):
    items = []
    kwargs = {"Bucket": bucket(), "Prefix": task_prefix(task_id)}
    while True:
        page = s3().list_objects_v2(**kwargs)
        for obj in page.get("Contents", []):
            parts = obj["Key"].split("/")  # tasks/<taskId>/<attachmentId>/<name>
            if len(parts) != 4:
                continue
            items.append({
                "attachmentId": parts[2],
                "fileName": parts[3],
                "size": obj["Size"],
                "uploadedAt": obj["LastModified"].strftime("%Y-%m-%dT%H:%M:%SZ"),
                "downloadUrl": presigned_download(obj["Key"], parts[3]),
            })
        if not page.get("IsTruncated"):
            return sorted(items, key=lambda item: item["uploadedAt"])
        kwargs["ContinuationToken"] = page["NextContinuationToken"]
