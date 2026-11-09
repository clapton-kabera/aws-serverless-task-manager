"""
app.py (list_users)
author: Kabera Clapton

description: GET /users (admin only). Lists members, so the admin can pick an assignee.
"""

from common import users
from common.auth import get_caller, require_admin
from common.http import api_handler, response


@api_handler
def lambda_handler(event, context):
    require_admin(get_caller(event))
    return response(200, {"items": users.list_members()})
