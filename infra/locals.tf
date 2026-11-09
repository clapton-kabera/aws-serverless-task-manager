#----------------------------------------------------------------------------------------------------
# locals.tf
# author: Kabera Clapton
#
# description: Shared names and the map of Lambda functions. Adding a function = adding one entry
#              to local.functions (plus its code folder under backend/functions/<key>/).
#----------------------------------------------------------------------------------------------------

locals {
  # Used in every resource name, so names
  # never collide with resources from other labs in the same account.
  name_prefix = "task-manager"

  # Newest generally-available Python runtime (3.15 is still in preview).
  lambda_runtime = "python3.14"

  log_retention_days = 14

  # Browser origins allowed to call the API and the attachments bucket (CORS):
  # the CloudFront site, and Vite's dev server for local development.
  frontend_url     = "https://${aws_cloudfront_distribution.frontend.domain_name}"
  frontend_origins = [local.frontend_url, "http://localhost:5173"]

  table_arn  = aws_dynamodb_table.tasks.arn
  stream_arn = aws_dynamodb_table.tasks.stream_arn
  pool_arn   = aws_cognito_user_pool.lambda_users.arn
  topic_arn  = aws_sns_topic.task_notifications.arn
  bucket_arn = aws_s3_bucket.attachments.arn

  # Reused permission sets. TransactWriteItems has no IAM action of its own: each item in the
  # transaction needs its normal action (PutItem, UpdateItem, ...).
  find_member = {
    actions   = ["cognito-idp:ListUsers", "cognito-idp:AdminListGroupsForUser"]
    resources = [local.pool_arn]
  }

  /*
    One entry per Lambda. Fields:
      route             - HTTP API route key that invokes it, or null for functions triggered
                          by something else (DynamoDB stream, schedule)
      timeout / memory  - seconds / MB
      policy_statements - EXTRA permissions on top of writing its own logs (empty = logs only).
                          Each: { actions = [...], resources = [...] } and optionally
                          conditions = [{ test = ..., variable = ..., values = [...] }]
  */
  functions = {
    hello = {
      route             = "GET /hello"
      timeout           = 10
      memory            = 128
      policy_statements = []
    }

    create_task = {
      route   = "POST /tasks"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:PutItem"], resources = [local.table_arn] },
        local.find_member,
      ]
    }

    list_tasks = {
      route   = "GET /tasks"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:Scan"], resources = [local.table_arn] },                         # admin
        { actions = ["dynamodb:Query"], resources = ["${local.table_arn}/index/by_assignee"] }, # member
      ]
    }

    get_task = {
      route             = "GET /tasks/{taskId}"
      timeout           = 10
      memory            = 256
      policy_statements = [{ actions = ["dynamodb:Query"], resources = [local.table_arn] }]
    }

    update_task = {
      route   = "PUT /tasks/{taskId}"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:PutItem"], resources = [local.table_arn] },
        local.find_member,
      ]
    }

    list_users = {
      route             = "GET /users"
      timeout           = 10
      memory            = 256
      policy_statements = [{ actions = ["cognito-idp:ListUsersInGroup"], resources = [local.pool_arn] }]
    }

    notify_task = {
      route   = "POST /tasks/{taskId}/notify"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:GetItem"], resources = [local.table_arn] },
        { actions = ["sns:Publish"], resources = [local.topic_arn] },
      ]
    }

    task_notifier = {
      route   = null # triggered by the table's DynamoDB stream (notifications.tf)
      timeout = 30
      memory  = 256
      policy_statements = [
        # What the event source mapping needs to read the stream on the function's behalf
        {
          actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator"]
          resources = [local.stream_arn]
        },
        # ListStreams has no resource-level permissions; it only lists stream names, no data.
        { actions = ["dynamodb:ListStreams"], resources = ["*"] },
        { actions = ["sns:Publish"], resources = [local.topic_arn] },
        # Records that still fail after retries are sent here (on-failure destination)
        { actions = ["sqs:SendMessage"], resources = [aws_sqs_queue.notifier_dlq.arn] },
      ]
    }

    deadline_reminder = {
      route   = null # triggered hourly by EventBridge Scheduler (notifications.tf)
      timeout = 60
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:Query"], resources = ["${local.table_arn}/index/open_by_due_date"] },
        { actions = ["dynamodb:UpdateItem"], resources = [local.table_arn] },
        { actions = ["sns:Publish"], resources = [local.topic_arn] },
      ]
    }

    create_attachment_upload = {
      route   = "POST /tasks/{taskId}/attachments"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:GetItem"], resources = [local.table_arn] },
        # A presigned URL acts with the SIGNER's permissions, so this role needs PutObject itself.
        { actions = ["s3:PutObject"], resources = ["${local.bucket_arn}/tasks/*"] },
      ]
    }

    list_attachments = {
      route   = "GET /tasks/{taskId}/attachments"
      timeout = 10
      memory  = 256
      policy_statements = [
        { actions = ["dynamodb:GetItem"], resources = [local.table_arn] },
        { actions = ["s3:GetObject"], resources = ["${local.bucket_arn}/tasks/*"] },
        {
          actions    = ["s3:ListBucket"]
          resources  = [local.bucket_arn]
          conditions = [{ test = "StringLike", variable = "s3:prefix", values = ["tasks/*"] }]
        },
      ]
    }
  }

  # Only functions with a route are wired to API Gateway.
  api_functions = { for name, fn in local.functions : name => fn if fn.route != null }
}
