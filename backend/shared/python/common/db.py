"""
db.py
author: Kabera Clapton

description: DynamoDB access: a lazily created low-level client, conversion between Python values
             and DynamoDB's typed JSON, and key helpers for the single-table design.
"""

import base64
import json
import os

import boto3
from boto3.dynamodb.types import TypeDeserializer, TypeSerializer

from common.http import ApiError

_serializer = TypeSerializer()
_deserializer = TypeDeserializer()
_client = None

BY_ASSIGNEE_INDEX = "by_assignee"
OPEN_BY_DUE_DATE_INDEX = "open_by_due_date"


def client():
    # Created on first use (not at import) so it is reused across warm invocations
    # and so unit tests can mock AWS before it exists.
    global _client
    if _client is None:
        _client = boto3.client("dynamodb")
    return _client


def table_name():
    return os.environ["TABLE_NAME"]


def to_item(data):
    """Python dict -> DynamoDB item. Top-level None values are dropped (attribute absent)."""
    return {key: _serializer.serialize(value) for key, value in data.items() if value is not None}


def from_item(item):
    return {key: _deserializer.deserialize(value) for key, value in item.items()}


def to_values(data):
    return {key: _serializer.serialize(value) for key, value in data.items()}


def task_pk(task_id):
    return f"TASK#{task_id}"


def task_key(task_id):
    return {"pk": {"S": task_pk(task_id)}, "sk": {"S": "META"}}


def encode_token(last_key):
    """Pagination cursor for the client: opaque base64 of DynamoDB's LastEvaluatedKey."""
    if not last_key:
        return None
    return base64.urlsafe_b64encode(json.dumps(last_key).encode()).decode()


def decode_token(token):
    if not token:
        return None
    try:
        key = json.loads(base64.urlsafe_b64decode(token.encode()).decode())
    except (ValueError, UnicodeDecodeError):
        raise ApiError(400, "Invalid nextToken") from None
    if not isinstance(key, dict):
        raise ApiError(400, "Invalid nextToken")
    return key
