#----------------------------------------------------------------------------------------------------
# lambda.tf
# author: Kabera Clapton
#
# description: Packages, deploys and permissions every Lambda in local.functions. Each function gets
#              its own log group, its own least-privilege execution role, and a resource policy that
#              lets only this project's HTTP API invoke it. Shared code ships as one Lambda layer.
#              Replaces the old lambda.tf AND iam.tf.
#----------------------------------------------------------------------------------------------------

# Zip each function's folder. source_dir (not source_file) so a function can have several files.
data "archive_file" "function" {
  for_each = local.functions

  type        = "zip"
  source_dir  = "${path.module}/../backend/functions/${each.key}"
  output_path = "${path.module}/build/${each.key}.zip" # outside the source folder; build/ is gitignored
}

/*
  Shared code (backend/shared/python/common) as a layer. Lambda unpacks layers into /opt and adds
  /opt/python to sys.path, which is why the folder inside the zip must be called "python".
*/
data "archive_file" "common_layer" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/shared"
  output_path = "${path.module}/build/common_layer.zip"
}

resource "aws_lambda_layer_version" "common" {
  layer_name               = "${local.name_prefix}-common"
  filename                 = data.archive_file.common_layer.output_path
  source_code_hash         = data.archive_file.common_layer.output_base64sha256
  compatible_runtimes      = [local.lambda_runtime]
  compatible_architectures = ["arm64"]
}

# Log group created by Terraform (not by Lambda) so retention is set and nothing is kept forever.
resource "aws_cloudwatch_log_group" "function" {
  for_each = local.functions

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = local.log_retention_days
}

# Trust policy: only the Lambda service can assume these roles.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "function" {
  for_each = local.functions

  name               = "${local.name_prefix}-${each.key}-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permissions per function: write to ITS OWN log streams, plus any extra statements from the map.
data "aws_iam_policy_document" "function" {
  for_each = local.functions

  statement {
    sid     = "WriteOwnLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    # ":*" matches the log STREAMS inside the group; the bare group ARN would deny every write.
    resources = ["${aws_cloudwatch_log_group.function[each.key].arn}:*"]
  }

  dynamic "statement" {
    for_each = each.value.policy_statements

    content {
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = try(statement.value.conditions, [])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "function" {
  for_each = local.functions

  name   = "${local.name_prefix}-${each.key}-policy"
  role   = aws_iam_role.function[each.key].id
  policy = data.aws_iam_policy_document.function[each.key].json
}

resource "aws_lambda_function" "function" {
  for_each = local.functions

  function_name = "${local.name_prefix}-${each.key}"
  role          = aws_iam_role.function[each.key].arn
  runtime       = local.lambda_runtime
  handler       = "app.lambda_handler"
  architectures = ["arm64"] # Graviton: cheaper per ms; no compiled dependencies to rebuild
  timeout       = each.value.timeout
  memory_size   = each.value.memory

  filename         = data.archive_file.function[each.key].output_path
  source_code_hash = data.archive_file.function[each.key].output_base64sha256 # redeploy on code change
  layers           = [aws_lambda_layer_version.common.arn]

  # Configuration via environment, never hardcoded: the same code works in any environment.
  environment {
    variables = {
      TABLE_NAME         = aws_dynamodb_table.tasks.name
      USER_POOL_ID       = aws_cognito_user_pool.lambda_users.id
      TOPIC_ARN          = aws_sns_topic.task_notifications.arn
      ATTACHMENTS_BUCKET = aws_s3_bucket.attachments.bucket
    }
  }

  # Log group and permissions must exist before the function can run and log.
  depends_on = [
    aws_cloudwatch_log_group.function,
    aws_iam_role_policy.function,
  ]
}

# Resource policy: API Gateway may invoke the function, but only on behalf of THIS API.
resource "aws_lambda_permission" "api_invoke" {
  for_each = local.api_functions

  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.serverless_gateway.execution_arn}/*/*"
}
