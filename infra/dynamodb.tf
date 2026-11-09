#----------------------------------------------------------------------------------------------------
# dynamodb.tf
# author: Kabera Clapton
#
# description: Single table for tasks and their history events.
#   Table:            pk = TASK#<id>, sk = META (the task) or EVENT#<time>#<rand> (history)
#   by_assignee:      assigneeId + deadline   -> "my tasks, soonest first"
#   open_by_due_date: openDueDate + deadline  -> reminder job; SPARSE, only unfinished tasks
#                     have openDueDate, so finished tasks drop out of the index automatically
#   Stream:           every change, with before and after images, feeds the task_notifier Lambda
#----------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "tasks" {
  name         = "${local.name_prefix}-tasks"
  billing_mode = "PAY_PER_REQUEST" # on-demand: no capacity to size, pay per request, ~free when idle

  hash_key  = "pk"
  range_key = "sk"

  # Only attributes used as keys (table or index) are declared; everything else is schemaless.
  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }
  attribute {
    name = "assigneeId"
    type = "S"
  }
  attribute {
    name = "deadline"
    type = "S"
  }
  attribute {
    name = "openDueDate"
    type = "S"
  }

  global_secondary_index {
    name = "by_assignee"
    key_schema {
      attribute_name = "assigneeId"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "deadline"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }

  global_secondary_index {
    name = "open_by_due_date"
    key_schema {
      attribute_name = "openDueDate"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "deadline"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }

  # Change feed for notifications. NEW_AND_OLD_IMAGES so the notifier can see what changed.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Restore the table to any second in the last 35 days (e.g. after a bad deploy deletes data).
  point_in_time_recovery {
    enabled = true
  }
}
