"""
test_hello.py
author: Kabera Clapton

description: Unit tests for the hello Lambda, using a minimal HTTP API (payload format 2.0) event
             that includes the JWT authorizer claims.
"""

import importlib.util
import json
from pathlib import Path

FUNCTIONS_DIR = Path(__file__).resolve().parents[1] / "functions"


def load_handler(function_name):
    """Load functions/<name>/app.py under a unique module name.

    Every function's file is called app.py, so a plain "import app" would
    collide once there is more than one function.
    """
    path = FUNCTIONS_DIR / function_name / "app.py"
    spec = importlib.util.spec_from_file_location(f"{function_name}_app", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.lambda_handler


def make_event(sub="1111-2222", groups="[admin]"):
    return {
        "requestContext": {
            "http": {"method": "GET", "path": "/hello"},
            "authorizer": {
                "jwt": {"claims": {"sub": sub, "cognito:groups": groups}}
            },
        }
    }


handler = load_handler("hello")


def test_returns_200_with_json_body():
    response = handler(make_event(), None)

    assert response["statusCode"] == 200
    assert response["headers"]["Content-Type"] == "application/json"
    body = json.loads(response["body"])  # fails if body is not valid JSON
    assert body["message"] == "hello"
    assert body["method"] == "GET"


def test_returns_caller_identity_from_claims():
    body = json.loads(handler(make_event(sub="abc-123", groups="[member]"), None)["body"])

    assert body["sub"] == "abc-123"
    assert body["groups"] == "[member]"


def test_missing_groups_claim_returns_none():
    event = make_event()
    del event["requestContext"]["authorizer"]["jwt"]["claims"]["cognito:groups"]

    body = json.loads(handler(event, None)["body"])

    assert body["groups"] is None
