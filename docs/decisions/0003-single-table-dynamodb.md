# 0003: Single DynamoDB table designed around access patterns

**Status:** Accepted

**Context.** Access patterns: get a task; list my tasks by deadline; list all tasks (admin); find open
tasks due soon (reminders); show a task's history.

**Decision.** One table with generic keys. `pk = TASK#<id>`; `sk = META` for the task and
`EVENT#<time>#<rand>` for history, so a task and its history come back in one Query.
GSI `by_assignee` (assigneeId, deadline) serves "my tasks". Sparse GSI `open_by_due_date`
(openDueDate, deadline) serves reminders: only unfinished tasks carry `openDueDate`.
Users are not stored in DynamoDB; Cognito is the single source of truth.

**Admin list uses Scan, deliberately.** A Scan reads the whole table, so cost and latency grow with
size, and filtering happens after reading (pages can be short). For a field team of tens of users and
thousands of items this is cheap and simple. If the table grows large, add a GSI keyed by status.

**Consequences.** Writes use optimistic locking (`version`) and condition expressions that re-check
ownership, so a race between read and write cannot bypass the rules.
