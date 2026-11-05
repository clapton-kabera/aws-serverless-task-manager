#----------------------------------------------------------------------------------------------------
# api.tf
# author: Kabera Clapton
#
# description: TF file that provisions the API Gateway and sets up routes and endpoints 
#              to the lambda function
#----------------------------------------------------------------------------------------------------

/*
  Create an HTTP API - API Gateway container since this is cheaper and we are using it for a simple
  use case
*/
resource "aws_apigatewayv2_api" "serverless_gateway" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"
}

/*
  Point the API gateway to the lambda function to which it should direct requests
*/
resource "aws_apigatewayv2_integration" "gateway_lambda_integration" {
  api_id           = aws_apigatewayv2_api.serverless_gateway.id
  integration_type = "AWS_PROXY"

  description            = "Integration with the hello lambda function"
  integration_uri        = aws_lambda_function.hello_function.invoke_arn
  payload_format_version = "2.0"
}

/*
  Create the http route which when accessed will trigger the the lambda function
*/
resource "aws_apigatewayv2_route" "function_route" {
  api_id    = aws_apigatewayv2_api.serverless_gateway.id
  route_key = "GET /hello"

  target             = "integrations/${aws_apigatewayv2_integration.gateway_lambda_integration.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

/*
  Deploy the gateway for it to be accessible to the internet
*/
resource "aws_apigatewayv2_stage" "staged_gateway" {
  api_id      = aws_apigatewayv2_api.serverless_gateway.id
  name        = "$default"
  auto_deploy = true
}

/*
  Attach the cognito auth capabilities on the api gateway so that each request needs to auth'd
*/
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.serverless_gateway.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    issuer   = "https://${aws_cognito_user_pool.lambda_users.endpoint}"
    audience = [aws_cognito_user_pool_client.pool_client.id]
  }
}
