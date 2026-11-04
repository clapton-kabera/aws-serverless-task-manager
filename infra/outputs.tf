output "gateway_url" {
  value = aws_apigatewayv2_stage.staged_gateway.invoke_url
}
