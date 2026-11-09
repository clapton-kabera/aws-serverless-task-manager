"""
http.py
author: Kabera Clapton

description: HTTP helpers: a typed API error, JSON responses (Decimal-safe), body and path parsing,
             and a decorator that turns errors into clean JSON responses without leaking internals.
"""

import base64
import functools
import json
import logging
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class ApiError(Exception):
    """An error that should be returned to the client with a specific status code."""

    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _json_default(value):
    # DynamoDB returns every number as Decimal, which json.dumps cannot serialise.
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serialisable")


def response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=_json_default),
    }


def parse_body(event):
    raw = event.get("body")
    if not raw:
        raise ApiError(400, "Request body is required")
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise ApiError(400, "Request body must be valid JSON") from None
    if not isinstance(data, dict):
        raise ApiError(400, "Request body must be a JSON object")
    return data


def path_param(event, name):
    value = (event.get("pathParameters") or {}).get(name)
    if not value:
        raise ApiError(400, f"Missing path parameter: {name}")
    return value


def api_handler(func):
    """Wrap a handler: ApiError -> its status; anything else -> logged, generic 500."""

    @functools.wraps(func)
    def wrapper(event, context):
        try:
            return func(event, context)
        except ApiError as exc:
            logger.info(json.dumps({"status": exc.status, "error": exc.message}))
            return response(exc.status, {"error": exc.message})
        except Exception:  # noqa: BLE001 - last-resort handler, details go to CloudWatch only
            logger.exception("Unhandled error")
            return response(500, {"error": "Internal server error"})

    return wrapper
