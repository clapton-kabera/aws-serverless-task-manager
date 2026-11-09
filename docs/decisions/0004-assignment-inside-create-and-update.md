# 0004: Task assignment handled by create and update, not a separate endpoint

**Status:** Accepted

**Context.** The brief lists a separate "Task Assignment Lambda".

**Decision.** Assignment happens in `POST /tasks` (assigneeId is required) and reassignment in
`PUT /tasks/{taskId}` (admin only). Both check that the assignee is an active user in the member group.

**Consequences.** One fewer function and route, and no window where a task exists without an
assignee. The assignment rules live in one shared place (`common/users.py`). Reassignment is recorded in
the task's history like any other change.
