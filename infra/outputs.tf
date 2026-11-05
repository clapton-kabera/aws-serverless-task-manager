output "gateway_url" {
  value = aws_apigatewayv2_stage.staged_gateway.invoke_url
}

output "user_pool_id" {
  value = aws_cognito_user_pool.lambda_users.id
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.pool_client.id
}
