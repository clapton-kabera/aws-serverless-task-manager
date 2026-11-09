"""
tasks.py
author: Kabera Clapton

description: Task rules: allowed statuses and fields per role, input validation, time handling
             (always UTC, ISO-8601 with a trailing Z so strings sort in time order), history events,
             and the shape of a task in API responses.
"""

import re
import uuid
from datetime import datetime, timezone

from common.http import ApiError

STATUSES = ("OPEN", "IN_PROGRESS", "DONE")
TITLE_MAX = 200
DESCRIPTION_MAX = 2000

CREATE_FIELDS = frozenset({"title", "description", "deadline", "assigneeId"})
ADMIN_UPDATE_FIELDS = frozenset({"title", "description", "deadline", "status", "assigneeId"})
MEMBER_UPDATE_FIELDS = frozenset({"status"})

_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_ISO_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

# Internal attributes never returned to clients
_INTERNAL = frozenset({"pk", "sk", "openDueDate"})


def now_iso():
    return datetime.now(timezone.utc).strftime(_ISO_FORMAT)


def is_uuid(value):
    return isinstance(value, str) and bool(_UUID.match(value))


def clean_task_id(value):
    if not is_uuid(value):
        raise ApiError(404, "Task not found")
    return value


def clean_title(value):
    if not isinstance(value, str) or not value.strip():
        raise ApiError(400, "title is required")
    value = value.strip()
    if len(value) > TITLE_MAX:
        raise ApiError(400, f"title must be at most {TITLE_MAX} characters")
    return value


def clean_description(value):
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ApiError(400, "description must be a string")
    value = value.strip()
    if len(value) > DESCRIPTION_MAX:
        raise ApiError(400, f"description must be at most {DESCRIPTION_MAX} characters")
    return value


def clean_status(value):
    if value not in STATUSES:
        raise ApiError(400, f"status must be one of: {', '.join(STATUSES)}")
    return value


def clean_assignee_id(value):
    # Strict format check also prevents injection into the Cognito ListUsers filter string.
    if not is_uuid(value):
        raise ApiError(400, "assigneeId must be a user ID (UUID)")
    return value


def clean_deadline(value):
    """Accept any ISO-8601 time WITH a timezone; store it normalised to UTC. Must be in the future."""
    if not isinstance(value, str):
        raise ApiError(400, "deadline must be an ISO-8601 string, e.g. 2026-11-20T17:00:00Z")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise ApiError(400, "deadline must be an ISO-8601 string, e.g. 2026-11-20T17:00:00Z") from None
    if parsed.tzinfo is None:
        raise ApiError(400, "deadline must include a timezone, e.g. 2026-11-20T17:00:00Z")
    deadline = parsed.astimezone(timezone.utc).strftime(_ISO_FORMAT)
    if deadline <= now_iso():  # same fixed format, so string comparison = time comparison
        raise ApiError(400, "deadline must be in the future")
    return deadline


def due_date(deadline):
    """Partition key of the open_by_due_date index: the deadline's UTC day, e.g. 2026-11-20."""
    return deadline[:10]


def history_event(task_id, actor, action, changes):
    timestamp = now_iso()
    return {
        "pk": f"TASK#{task_id}",
        # Random suffix keeps two events in the same second from overwriting each other.
        "sk": f"EVENT#{timestamp}#{uuid.uuid4().hex[:8]}",
        "action": action,
        "actor": actor,
        "at": timestamp,
        "changes": changes,
    }


def to_api(item):
    return {key: value for key, value in item.items() if key not in _INTERNAL}


def event_to_api(item):
    return {"action": item.get("action"), "actor": item.get("actor"), "at": item.get("at"),
            "changes": item.get("changes", {})}
