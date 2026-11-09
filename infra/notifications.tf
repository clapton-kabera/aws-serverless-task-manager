#----------------------------------------------------------------------------------------------------
# notifications.tf
# author: Kabera Clapton
#
# description: What triggers the notification Lambdas.
#   1. DynamoDB stream -> task_notifier, filtered to task items only, with retries, per-record
#      failure reporting and a dead-letter queue for records that keep failing.
#   2. EventBridge Scheduler -> deadline_reminder, every hour.
#----------------------------------------------------------------------------------------------------

# Records that still fail after all retries land here instead of being lost.
resource "aws_sqs_queue" "notifier_dlq" {
  name                      = "${local.name_prefix}-notifier-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum: time to investigate
  sqs_managed_sse_enabled   = true
}

resource "aws_lambda_event_source_mapping" "task_stream" {
  event_source_arn  = aws_dynamodb_table.tasks.stream_arn
  function_name     = aws_lambda_function.function["task_notifier"].arn
  starting_position = "LATEST"
  batch_size        = 10

  # Only task items (sk = META) invoke the function; history events are filtered out by Lambda
  # before invocation, so they cost nothing.
  filter_criteria {
    filter {
      pattern = jsonencode({ dynamodb = { Keys = { sk = { S = ["META"] } } } })
    }
  }

  # Retry a failing batch a few times, splitting it to isolate the bad record; the function also
  # reports failures per record, so records that succeeded are not reprocessed.
  maximum_retry_attempts         = 3
  bisect_batch_on_function_error = true
  function_response_types        = ["ReportBatchItemFailures"]

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.notifier_dlq.arn
    }
  }

  # Lambda checks that the role can read the stream when the mapping is created.
  depends_on = [aws_iam_role_policy.function]
}

/*
  EventBridge Scheduler invokes the reminder Lambda using an IAM ROLE it assumes (unlike API Gateway,
  which is allowed in through the function's resource policy).
*/

# fetch the current account ID.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Confused-deputy protection: only schedules in THIS account may use the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.function["deadline_reminder"].arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "${local.name_prefix}-scheduler-invoke"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule" "deadline_reminder" {
  name                         = "${local.name_prefix}-deadline-reminder"
  schedule_expression          = "rate(1 hour)"
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.function["deadline_reminder"].arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "scheduler" })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}
