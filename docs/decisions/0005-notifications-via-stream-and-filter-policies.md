# 0005: Notifications from the DynamoDB stream, targeted with SNS filter policies

**Status:** Accepted

**Context.** Members must be told about their own tasks only; admins about member updates. SNS topics
deliver to every subscriber. Email is the only channel (SNS SMS starts in a sandbox with spending limits
and registration requirements).

**Decision.**
- One topic. Each person has an email subscription with a filter policy on message attributes:
  members `{"assigneeId": ["<sub>"]}`, admins `{"audience": ["admin"]}`.
- The API Lambdas do not publish. A `task_notifier` Lambda reads the table's stream (filtered to task
  items) and decides who to tell from the before/after images.
- An hourly EventBridge Scheduler job sends one reminder per task due within 24 hours, using the sparse
  `open_by_due_date` index. It claims a task (conditional write) before emailing, and releases the
  claim if the email fails.
- Step Functions is not used: an hourly query is simpler and cheaper than one state machine per task.

**Consequences.** API requests never fail or slow down because of SNS. Failed stream records are
retried, then kept in an SQS dead-letter queue for 14 days. Each new user must confirm their
subscription by email before receiving anything. Reminders arrive up to an hour after a task enters
the 24-hour window.
