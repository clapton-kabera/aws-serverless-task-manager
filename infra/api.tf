#----------------------------------------------------------------------------------------------------
# api.tf
# author: Kabera Clapton
#
# description: HTTP API with a Cognito JWT authorizer. One integration and one route per function in
#              local.api_functions; every route requires a valid Cognito access token.
#----------------------------------------------------------------------------------------------------

/*
  HTTP API (not REST API): cheaper, native JWT authorizer, simpler. REST-only features
  (usage plans, request validation, direct WAF) are not needed here.
*/
resource "aws_apigatewayv2_api" "serverless_gateway" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  /*
    With CORS configured, API Gateway answers browser preflight (OPTIONS) requests itself, before the
    JWT authorizer, and adds the CORS headers to every response. Only our own origins are allowed.
  */
  cors_configuration {
    allow_origins = local.frontend_origins
    allow_methods = ["GET", "POST", "PUT", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

/*
  Authenticates every request: signature, issuer, expiry, audience. Authorization (admin vs member)
  is NOT done here; the Lambdas do that.
*/
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.serverless_gateway.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    # The pool's endpoint attribute has no scheme, but the token's iss claim does.
    issuer   = "https://${aws_cognito_user_pool.lambda_users.endpoint}"
    audience = [aws_cognito_user_pool_client.pool_client.id]
  }
}

resource "aws_apigatewayv2_integration" "function" {
  for_each = local.api_functions

  api_id                 = aws_apigatewayv2_api.serverless_gateway.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.function[each.key].invoke_arn
  payload_format_version = "2.0" # Terraform defaults to 1.0; our handlers expect 2.0 events
  description            = "Lambda proxy integration for ${each.key}"
}

resource "aws_apigatewayv2_route" "function" {
  for_each = local.api_functions

  api_id             = aws_apigatewayv2_api.serverless_gateway.id
  route_key          = each.value.route
  target             = "integrations/${aws_apigatewayv2_integration.function[each.key].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# $default stage + auto_deploy: every change is live, and the URL has no stage prefix.
resource "aws_apigatewayv2_stage" "staged_gateway" {
  api_id      = aws_apigatewayv2_api.serverless_gateway.id
  name        = "$default"
  auto_deploy = true
}

/*
  Route keys must be unique per API. Without these moves, Terraform would try to create the new
  "GET /hello" route while the old one still exists, and fail with ConflictException.
  Delete these blocks after one successful apply.
*/
moved {
  from = aws_apigatewayv2_route.function_route
  to   = aws_apigatewayv2_route.function["hello"]
}

moved {
  from = aws_apigatewayv2_integration.gateway_lambda_integration
  to   = aws_apigatewayv2_integration.function["hello"]
}
