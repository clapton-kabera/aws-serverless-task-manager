"""
test_notifications.py
author: Kabera Clapton

description: Tests for notifications: who is told about which change (stream notifier), the hourly
             deadline reminder (window, one reminder per task, DONE tasks skipped), the manual notify
             endpoint, and SNS subject rules.
"""

from datetime import datetime, timedelta, timezone

import boto3
from conftest import REGION, TABLE_NAME, call, load_handler, make_event

from common import notify


def as_user(person, **kwargs):
    return make_event(person["sub"], person["groups"], **kwargs)


def in_hours(hours):
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")


def create(aws, hours=72, assignee="alice"):
    body = {"title": "Inspect site A", "deadline": in_hours(hours), "assigneeId": aws[assignee]["sub"]}
    status, task = call("create_task", as_user(aws["admin"], method="POST", body=body))
    assert status == 201
    return task


def raw_item(task_id):
    return boto3.client("dynamodb", region_name=REGION).get_item(
        TableName=TABLE_NAME, Key={"pk": {"S": f"TASK#{task_id}"}, "sk": {"S": "META"}})["Item"]


def stream_event(name, old=None, new=None, seq="1"):
    images = {"SequenceNumber": seq}
    if old:
        images["OldImage"] = old
    if new:
        images["NewImage"] = new
    return {"Records": [{"eventID": "e1", "eventName": name, "dynamodb": images}]}


def update(person, task_id, body):
    return call("update_task", as_user(person, method="PUT", body=body, path_params={"taskId": task_id}))


notifier = load_handler("task_notifier")
reminder = load_handler("deadline_reminder")


# ---------- stream notifier ----------

def test_new_task_notifies_assignee_only(aws, sent):
    task = create(aws)
    result = notifier(stream_event("INSERT", new=raw_item(task["taskId"])), None)

    assert result == {"batchItemFailures": []}
    assert len(sent) == 1
    subject, _, attributes = sent[0]
    assert subject.startswith("New task assigned")
    assert attributes == {"audience": "member", "assigneeId": aws["alice"]["sub"]}


def test_member_status_change_notifies_admins(aws, sent):
    task = create(aws)
    before = raw_item(task["taskId"])
    update(aws["alice"], task["taskId"], {"status": "IN_PROGRESS", "version": 1})

    notifier(stream_event("MODIFY", old=before, new=raw_item(task["taskId"])), None)

    assert [attrs for _, _, attrs in sent] == [{"audience": "admin"}]
    assert "IN_PROGRESS" in sent[0][1]


def test_admin_change_notifies_assignee(aws, sent):
    task = create(aws)
    before = raw_item(task["taskId"])
    update(aws["admin"], task["taskId"], {"title": "Inspect site B", "version": 1})

    notifier(stream_event("MODIFY", old=before, new=raw_item(task["taskId"])), None)

    assert [attrs["audience"] for _, _, attrs in sent] == ["member"]


def test_reassignment_notifies_new_and_previous_assignee(aws, sent):
    task = create(aws, assignee="alice")
    before = raw_item(task["taskId"])
    update(aws["admin"], task["taskId"], {"assigneeId": aws["bob"]["sub"], "version": 1})

    notifier(stream_event("MODIFY", old=before, new=raw_item(task["taskId"])), None)

    told = [attrs["assigneeId"] for _, _, attrs in sent]
    assert told == [aws["bob"]["sub"], aws["alice"]["sub"]]


def test_reminder_bookkeeping_is_not_a_notification(aws, sent):
    task = create(aws)
    before = raw_item(task["taskId"])
    after = dict(before, reminderSentAt={"S": "2026-01-01T00:00:00Z"})  # same version

    notifier(stream_event("MODIFY", old=before, new=after), None)
    assert sent == []


def test_failed_record_is_reported_not_raised(aws, monkeypatch):
    def broken(*args, **kwargs):
        raise RuntimeError("SNS down")

    monkeypatch.setattr(notify, "publish", broken)
    task = create(aws)
    result = notifier(stream_event("INSERT", new=raw_item(task["taskId"]), seq="42"), None)
    assert result == {"batchItemFailures": [{"itemIdentifier": "42"}]}


# ---------- deadline reminder ----------

def test_reminder_sends_once_for_tasks_due_within_24h(aws, sent):
    soon = create(aws, hours=5)
    create(aws, hours=72)  # outside the window

    assert reminder({}, None) == {"remindersSent": 1}
    assert sent[0][2]["assigneeId"] == aws["alice"]["sub"]
    assert "reminderSentAt" in raw_item(soon["taskId"])

    assert reminder({}, None) == {"remindersSent": 0}  # second run: already reminded


def test_reminder_skips_done_tasks(aws, sent):
    task = create(aws, hours=5)
    update(aws["alice"], task["taskId"], {"status": "DONE", "version": 1})

    assert reminder({}, None) == {"remindersSent": 0}


def test_new_deadline_rearms_reminder(aws, sent):
    task = create(aws, hours=5)
    reminder({}, None)
    update(aws["admin"], task["taskId"], {"deadline": in_hours(10), "version": 1})

    assert reminder({}, None) == {"remindersSent": 1}


def test_failed_reminder_releases_claim(aws, monkeypatch):
    task = create(aws, hours=5)
    monkeypatch.setattr(notify, "publish", lambda *a: (_ for _ in ()).throw(RuntimeError("down")))

    try:
        reminder({}, None)
        raise AssertionError("expected the run to fail")
    except RuntimeError:
        pass
    assert "reminderSentAt" not in raw_item(task["taskId"])


# ---------- manual notify endpoint ----------

def test_admin_can_nudge_assignee(aws, sent):
    task = create(aws)
    status, body = call("notify_task", as_user(aws["admin"], method="POST",
                                               path_params={"taskId": task["taskId"]}))
    assert status == 200 and body["notified"] == "alice@example.com"
    assert len(sent) == 1


def test_member_cannot_nudge(aws, sent):
    task = create(aws)
    status, _ = call("notify_task", as_user(aws["alice"], method="POST",
                                            path_params={"taskId": task["taskId"]}))
    assert status == 403 and sent == []


# ---------- SNS details ----------

def test_subject_is_ascii_single_line_and_short():
    subject = notify._subject("Tâche: inspect\nsite " + "x" * 200)
    assert subject.isascii() and "\n" not in subject and len(subject) < 100


def test_real_publish_against_mocked_sns(aws):
    notify.to_admins("Hello", "Body")  # raises if the call shape is wrong
