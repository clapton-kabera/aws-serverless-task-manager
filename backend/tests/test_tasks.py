"""
test_tasks.py
author: Kabera Clapton

description: Tests for the task API Lambdas against mocked AWS (moto): role rules, ownership,
             validation, optimistic locking, history, and the sparse reminder index.
"""

import boto3
from conftest import REGION, TABLE_NAME, call, make_event

from common.auth import parse_groups

FUTURE = "2099-01-15T17:00:00Z"


def as_user(person, **kwargs):
    return make_event(person["sub"], person["groups"], **kwargs)


def create(aws, assignee="alice", **overrides):
    body = {"title": "Inspect site A", "description": "Check the pumps", "deadline": FUTURE,
            "assigneeId": aws[assignee]["sub"], **overrides}
    return call("create_task", as_user(aws["admin"], body=body, method="POST"))


# ---------- groups parsing (the "[superadmin]" trap) ----------

def test_parse_groups_is_exact_match():
    assert parse_groups("[admin member]") == {"admin", "member"}
    assert "admin" not in parse_groups("[superadmin]")
    assert parse_groups(None) == set()


# ---------- create ----------

def test_admin_creates_task(aws):
    status, task = create(aws)
    assert status == 201
    assert task["status"] == "OPEN"
    assert task["version"] == 1
    assert task["assigneeEmail"] == "alice@example.com"
    assert "pk" not in task and "openDueDate" not in task  # internal fields hidden


def test_member_cannot_create(aws):
    status, _ = call("create_task", as_user(aws["alice"], method="POST", body={
        "title": "x", "deadline": FUTURE, "assigneeId": aws["alice"]["sub"]}))
    assert status == 403


def test_create_rejects_past_deadline_and_missing_timezone(aws):
    assert create(aws, deadline="2000-01-01T00:00:00Z")[0] == 400
    assert create(aws, deadline="2099-01-15T17:00:00")[0] == 400


def test_cannot_assign_to_admin(aws):
    assert create(aws, assignee="admin")[0] == 400


def test_create_rejects_unknown_fields(aws):
    assert create(aws, status="DONE")[0] == 400


# ---------- list / get ----------

def test_admin_sees_all_member_sees_own(aws):
    create(aws, assignee="alice")
    create(aws, assignee="bob")

    status, admin_view = call("list_tasks", as_user(aws["admin"]))
    assert status == 200 and len(admin_view["items"]) == 2

    status, alice_view = call("list_tasks", as_user(aws["alice"]))
    assert status == 200
    assert [t["assigneeId"] for t in alice_view["items"]] == [aws["alice"]["sub"]]


def test_member_gets_404_for_someone_elses_task(aws):
    _, task = create(aws, assignee="bob")
    status, _ = call("get_task", as_user(aws["alice"], path_params={"taskId": task["taskId"]}))
    assert status == 404


def test_get_returns_history(aws):
    _, task = create(aws)
    status, body = call("get_task", as_user(aws["alice"], path_params={"taskId": task["taskId"]}))
    assert status == 200
    assert [event["action"] for event in body["history"]] == ["CREATED"]


# ---------- update ----------

def update(person, task_id, body):
    return call("update_task", as_user(person, method="PUT", body=body,
                                       path_params={"taskId": task_id}))


def test_member_updates_status_of_own_task(aws):
    _, task = create(aws)
    status, updated = update(aws["alice"], task["taskId"], {"status": "IN_PROGRESS", "version": 1})
    assert status == 200
    assert updated["status"] == "IN_PROGRESS" and updated["version"] == 2


def test_member_cannot_change_title(aws):
    _, task = create(aws)
    assert update(aws["alice"], task["taskId"], {"title": "mine now", "version": 1})[0] == 403


def test_member_cannot_update_other_members_task(aws):
    _, task = create(aws, assignee="bob")
    assert update(aws["alice"], task["taskId"], {"status": "DONE", "version": 1})[0] == 404


def test_stale_version_conflicts(aws):
    _, task = create(aws)
    assert update(aws["alice"], task["taskId"], {"status": "IN_PROGRESS", "version": 1})[0] == 200
    status, body = update(aws["admin"], task["taskId"], {"title": "Renamed", "version": 1})
    assert status == 409 and "version 2" in body["error"]


def test_version_is_required(aws):
    _, task = create(aws)
    assert update(aws["alice"], task["taskId"], {"status": "DONE"})[0] == 400


def test_done_task_leaves_reminder_index(aws):
    _, task = create(aws)
    update(aws["alice"], task["taskId"], {"status": "DONE", "version": 1})

    ddb = boto3.client("dynamodb", region_name=REGION)
    item = ddb.get_item(TableName=TABLE_NAME,
                        Key={"pk": {"S": f"TASK#{task['taskId']}"}, "sk": {"S": "META"}})["Item"]
    assert "openDueDate" not in item


def test_admin_reassigns_task(aws):
    _, task = create(aws, assignee="alice")
    status, updated = update(aws["admin"], task["taskId"],
                             {"assigneeId": aws["bob"]["sub"], "version": 1})
    assert status == 200 and updated["assigneeEmail"] == "bob@example.com"
    assert call("list_tasks", as_user(aws["alice"]))[1]["items"] == []


def test_noop_update_does_not_bump_version(aws):
    _, task = create(aws)
    status, same = update(aws["alice"], task["taskId"], {"status": "OPEN", "version": 1})
    assert status == 200 and same["version"] == 1


# ---------- users ----------

def test_admin_lists_members_only(aws):
    status, body = call("list_users", as_user(aws["admin"]))
    assert status == 200
    assert sorted(user["email"] for user in body["items"]) == ["alice@example.com", "bob@example.com"]


def test_member_cannot_list_users(aws):
    assert call("list_users", as_user(aws["alice"]))[0] == 403
