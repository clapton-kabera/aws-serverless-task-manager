"""
app.py (list_tasks)
author: Kabera Clapton

description: GET /tasks. Role-aware: admins get every task (paginated Scan); members get only their
             own tasks, soonest deadline first (Query on the by_assignee index).
             Optional query parameters: status, limit (1-100), nextToken.
"""

from botocore.exceptions import ClientError

from common import db, tasks
from common.auth import get_caller
from common.http import ApiError, api_handler, response

DEFAULT_LIMIT = 50
MAX_LIMIT = 100


def _limit(params):
    raw = params.get("limit")
    if raw is None:
        return DEFAULT_LIMIT
    try:
        value = int(raw)
    except ValueError:
        raise ApiError(400, "limit must be a number") from None
    if not 1 <= value <= MAX_LIMIT:
        raise ApiError(400, f"limit must be between 1 and {MAX_LIMIT}")
    return value


@api_handler
def lambda_handler(event, context):
    caller = get_caller(event)
    params = event.get("queryStringParameters") or {}

    names = {}
    values = {}
    filters = []
    if params.get("status"):
        # "status" is a DynamoDB reserved word, so it must go through an attribute name placeholder.
        names["#status"] = "status"
        values[":status"] = tasks.clean_status(params["status"])
        filters.append("#status = :status")

    kwargs = {"TableName": db.table_name(), "Limit": _limit(params)}
    start_key = db.decode_token(params.get("nextToken"))
    if start_key:
        kwargs["ExclusiveStartKey"] = start_key

    if caller.is_admin:
        # Scan reads every item (including history events) and filters AFTER reading, so cost grows
        # with table size and a page can come back short. Fine for a small team; see ADR.
        values[":meta"] = "META"
        filters.insert(0, "sk = :meta")
        operation = db.client().scan
    else:
        kwargs["IndexName"] = db.BY_ASSIGNEE_INDEX
        kwargs["KeyConditionExpression"] = "assigneeId = :me"
        values[":me"] = caller.sub
        operation = db.client().query

    if filters:
        kwargs["FilterExpression"] = " AND ".join(filters)
    if names:
        kwargs["ExpressionAttributeNames"] = names
    kwargs["ExpressionAttributeValues"] = db.to_values(values)

    try:
        result = operation(**kwargs)
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ValidationException" and start_key:
            raise ApiError(400, "Invalid nextToken") from None
        raise

    items = [tasks.to_api(db.from_item(item)) for item in result.get("Items", [])]
    return response(200, {"items": items, "nextToken": db.encode_token(result.get("LastEvaluatedKey"))})
