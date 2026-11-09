#----------------------------------------------------------------------------------------------------
# outputs.tf
# author: Kabera Clapton
#
# description: Values the scripts and the front end read with `terraform output`.
#----------------------------------------------------------------------------------------------------

output "gateway_url" {
  description = "Base URL of the HTTP API"
  value       = aws_apigatewayv2_api.serverless_gateway.api_endpoint
}

output "user_pool_id" {
  value = aws_cognito_user_pool.lambda_users.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.pool_client.id
}

output "table_name" {
  value = aws_dynamodb_table.tasks.name
}

output "topic_arn" {
  value = aws_sns_topic.task_notifications.arn
}

output "attachments_bucket" {
  value = aws_s3_bucket.attachments.bucket
}

output "notifier_dlq_url" {
  value = aws_sqs_queue.notifier_dlq.url
}

output "function_names" {
  description = "Lambda function names by key, e.g. deadline_reminder"
  value       = { for key, fn in aws_lambda_function.function : key => fn.function_name }
}

output "frontend_url" {
  description = "The live application link"
  value       = local.frontend_url
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}
