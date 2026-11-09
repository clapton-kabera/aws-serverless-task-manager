"""
users.py
author: Kabera Clapton

description: Cognito lookups. Cognito is the single source of truth for users; there is no
             separate users table to keep in sync.
"""

import os

import boto3

from common.auth import MEMBER
from common.http import ApiError

_client = None


def cognito():
    global _client
    if _client is None:
        _client = boto3.client("cognito-idp")
    return _client


def _pool_id():
    return os.environ["USER_POOL_ID"]


def _attributes(user):
    return {attr["Name"]: attr["Value"] for attr in user.get("Attributes", [])}


def get_member(sub):
    """Return {id, email} for an enabled user in the member group, or raise 400.

    `sub` must already be validated as a UUID (tasks.clean_assignee_id), because it is placed
    inside a filter string.
    """
    found = cognito().list_users(UserPoolId=_pool_id(), Filter=f'sub = "{sub}"', Limit=1)
    users = found.get("Users", [])
    if not users or not users[0].get("Enabled", True):
        raise ApiError(400, "assigneeId does not match an active user")

    user = users[0]
    groups = cognito().admin_list_groups_for_user(UserPoolId=_pool_id(), Username=user["Username"])
    if not any(group["GroupName"] == MEMBER for group in groups.get("Groups", [])):
        raise ApiError(400, "Tasks can only be assigned to users in the member group")

    return {"id": sub, "email": _attributes(user).get("email")}


def list_members():
    members = []
    kwargs = {"UserPoolId": _pool_id(), "GroupName": MEMBER, "Limit": 60}
    while True:
        page = cognito().list_users_in_group(**kwargs)
        for user in page.get("Users", []):
            attrs = _attributes(user)
            members.append({"id": attrs.get("sub"), "email": attrs.get("email"),
                            "enabled": user.get("Enabled", True)})
        if not page.get("NextToken"):
            return members
        kwargs["NextToken"] = page["NextToken"]
