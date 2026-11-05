#----------------------------------------------------------------------------------------------------
# cognito.tf
# author: Kabera Clapton
#
# description: Set up amazon cognito for handling user creating, and generation of JWTs for auth
#----------------------------------------------------------------------------------------------------

/*
  Create a user pool which is a managed storage of all users allowed to access the lambda function
*/
resource "aws_cognito_user_pool" "lambda_users" {
  name = "lambda_users"

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_uppercase                = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # only admins can create accounts
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
}

/* Create the admin user group */
resource "aws_cognito_user_group" "admin_group" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.lambda_users.id
  precedence   = 1
}

/* Create the member user group */
resource "aws_cognito_user_group" "member_group" {
  name         = "member"
  user_pool_id = aws_cognito_user_pool.lambda_users.id
  precedence   = 10
}

/*
  Create permissions for a client (our frontend in this case) to access the user pool storage to authenticate
  users
*/
resource "aws_cognito_user_pool_client" "pool_client" {
  name                          = "task_mgt_client"
  user_pool_id                  = aws_cognito_user_pool.lambda_users.id
  prevent_user_existence_errors = "ENABLED"

  generate_secret = false
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH"
  ]

  # A user removed from the admin group keeps admin rights until their access token expires,
  # because API Gateway does not re-check with Cognito. 60 minutes bounds that window.
  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  enable_token_revocation = true
}

