"""
conftest.py
author: Kabera Clapton

description: Pytest setup shared by all tests: makes the `common` layer importable, stops Python
             writing __pycache__ into function folders (which would change the Lambda zips and force
             needless redeploys), and provides a mocked AWS (moto) with the same table and Cognito
             layout that Terraform creates.
"""

import importlib.util
import json
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

sys.dont_write_bytecode = True

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND / "shared" / "python"))

TABLE_NAME = "test-tasks"
REGION = "eu-west-1"


def load_handler(function_name):
    """Load functions/<name>/app.py under a unique module name (every function file is app.py)."""
    path = BACKEND / "functions" / function_name / "app.py"
    spec = importlib.util.spec_from_file_location(f"{function_name}_app", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.lambda_handler


@pytest.fixture
def sent(monkeypatch):
    """Record notifications instead of (only) publishing them: list of (subject, message, attributes)."""
    from common import notify

    messages = []
    monkeypatch.setattr(notify, "publish",
                        lambda subject, message, attributes: messages.append((subject, message, attributes)))
    return messages


def make_event(sub, groups, body=None, path_params=None, query=None, method="GET"):
    event = {
        "requestContext": {
            "http": {"method": method},
            "authorizer": {"jwt": {"claims": {"sub": sub, "cognito:groups": groups}}},
        },
        "pathParameters": path_params,
        "queryStringParameters": query,
    }
    if body is not None:
        event["body"] = json.dumps(body)
    return event


def call(function_name, event):
    result = load_handler(function_name)(event, None)
    return result["statusCode"], json.loads(result["body"])


@pytest.fixture
def aws(monkeypatch):
    """Mocked AWS with the tasks table, a user pool, groups, one admin and two members."""
    monkeypatch.setenv("AWS_DEFAULT_REGION", REGION)
    monkeypatch.setenv("AWS_REGION", REGION)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("TABLE_NAME", TABLE_NAME)

    from common import attachments, db, notify, users

    with mock_aws():
        db._client = None  # force fresh clients inside the mock
        users._client = None
        notify._client = None
        attachments._client = None
        attachments._client = None

        boto3.client("s3", region_name=REGION).create_bucket(
            Bucket="test-attachments",
            CreateBucketConfiguration={"LocationConstraint": REGION})
        monkeypatch.setenv("ATTACHMENTS_BUCKET", "test-attachments")

        topic_arn = boto3.client("sns", region_name=REGION).create_topic(Name="test-topic")["TopicArn"]
        monkeypatch.setenv("TOPIC_ARN", topic_arn)

        ddb = boto3.client("dynamodb", region_name=REGION)
        ddb.create_table(
            TableName=TABLE_NAME,
            BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[
                {"AttributeName": name, "AttributeType": "S"}
                for name in ("pk", "sk", "assigneeId", "deadline", "openDueDate")
            ],
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"},
                       {"AttributeName": "sk", "KeyType": "RANGE"}],
            GlobalSecondaryIndexes=[
                {"IndexName": "by_assignee",
                 "KeySchema": [{"AttributeName": "assigneeId", "KeyType": "HASH"},
                               {"AttributeName": "deadline", "KeyType": "RANGE"}],
                 "Projection": {"ProjectionType": "ALL"}},
                {"IndexName": "open_by_due_date",
                 "KeySchema": [{"AttributeName": "openDueDate", "KeyType": "HASH"},
                               {"AttributeName": "deadline", "KeyType": "RANGE"}],
                 "Projection": {"ProjectionType": "ALL"}},
            ],
        )

        idp = boto3.client("cognito-idp", region_name=REGION)
        pool_id = idp.create_user_pool(PoolName="test", UsernameAttributes=["email"])["UserPool"]["Id"]
        monkeypatch.setenv("USER_POOL_ID", pool_id)
        for group in ("admin", "member"):
            idp.create_group(UserPoolId=pool_id, GroupName=group)

        people = {}
        for key, email, group in (("admin", "admin@example.com", "admin"),
                                  ("alice", "alice@example.com", "member"),
                                  ("bob", "bob@example.com", "member")):
            user = idp.admin_create_user(
                UserPoolId=pool_id, Username=email,
                UserAttributes=[{"Name": "email", "Value": email}])["User"]
            sub = next(a["Value"] for a in user["Attributes"] if a["Name"] == "sub")
            idp.admin_add_user_to_group(UserPoolId=pool_id, Username=user["Username"], GroupName=group)
            people[key] = {"sub": sub, "email": email, "groups": f"[{group}]"}

        yield people

        db._client = None
        users._client = None
        notify._client = None
        attachments._client = None
