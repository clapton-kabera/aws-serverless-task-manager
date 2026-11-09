"""
notify.py
author: Kabera Clapton

description: Publishing task notifications to the single SNS topic. Who receives a message is decided
             by SNS subscription filter policies on the message attributes:
               member subscriptions: {"assigneeId": ["<their sub>"]}  -> only their own tasks
               admin subscriptions:  {"audience": ["admin"]}           -> admin notifications
"""

import os

import boto3

_client = None


def sns():
    global _client
    if _client is None:
        _client = boto3.client("sns")
    return _client


def _subject(text):
    # SNS email subjects must be ASCII, single-line and under 100 characters, or Publish fails.
    clean = " ".join(text.encode("ascii", "ignore").decode().split())
    return (clean or "Task notification")[:99]


def format_deadline(deadline):
    """2026-11-20T17:00:00Z -> 2026-11-20 17:00 UTC"""
    return f"{deadline[:10]} {deadline[11:16]} UTC" if deadline else "no deadline"


def publish(subject, message, attributes):
    sns().publish(
        TopicArn=os.environ["TOPIC_ARN"],
        Subject=_subject(subject),
        Message=message,
        MessageAttributes={
            key: {"DataType": "String", "StringValue": value} for key, value in attributes.items()
        },
    )


def to_assignee(task, subject, message):
    publish(subject, message, {"audience": "member", "assigneeId": task["assigneeId"]})


def to_admins(subject, message):
    publish(subject, message, {"audience": "admin"})


def task_summary(task):
    return (
        f"Task: {task.get('title')}\n"
        f"Status: {task.get('status')}\n"
        f"Deadline: {format_deadline(task.get('deadline'))}\n"
        f"Assigned to: {task.get('assigneeEmail')}\n"
        f"Task ID: {task.get('taskId')}\n"
    )
