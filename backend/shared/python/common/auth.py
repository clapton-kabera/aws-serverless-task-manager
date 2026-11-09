"""
auth.py
author: Kabera Clapton

description: Who is calling, and what may they do. API Gateway has already verified the token
             (authentication); this module does authorization from the verified claims.
"""

from dataclasses import dataclass

from common.http import ApiError

ADMIN = "admin"
MEMBER = "member"


def parse_groups(raw):
    """Turn the cognito:groups claim into a set of exact group names.

    HTTP APIs pass list claims as ONE string, e.g. "[admin member]". A substring check like
    `"admin" in raw` would wrongly accept "[superadmin]", so we split and compare exactly.
    """
    if raw is None:
        return frozenset()
    if isinstance(raw, (list, tuple)):
        return frozenset(str(group) for group in raw)
    text = str(raw).strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    return frozenset(part for part in text.replace(",", " ").split() if part)


@dataclass(frozen=True)
class Caller:
    sub: str
    groups: frozenset

    @property
    def is_admin(self):
        return ADMIN in self.groups

    @property
    def is_member(self):
        return MEMBER in self.groups


def get_caller(event):
    try:
        claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    except (KeyError, TypeError):
        raise ApiError(401, "Unauthorized") from None

    sub = claims.get("sub")
    if not sub:
        raise ApiError(401, "Unauthorized")

    caller = Caller(sub=sub, groups=parse_groups(claims.get("cognito:groups")))
    # A valid user in neither group (e.g. created but never added to one) gets nothing.
    if not (caller.is_admin or caller.is_member):
        raise ApiError(403, "Forbidden")
    return caller


def require_admin(caller):
    if not caller.is_admin:
        raise ApiError(403, "Admin access required")
