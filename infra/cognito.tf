#----------------------------------------------------------------------------------------------------
# cognito.tf
# author: Kabera Clapton
#
# description: Cognito user pool (email sign-in, admin-created users only), the admin/member groups,
#              and the public app client used by the front end and by CLI testing.
#----------------------------------------------------------------------------------------------------

/*
  User pool: the directory of everyone allowed to use the task manager.
  NOTE: username_attributes can only be set at creation time. Adding it forces Terraform to REPLACE
  the pool (new pool ID, all users deleted). Expected this once; re-run scripts/admin_setup.sh after.
*/
resource "aws_cognito_user_pool" "lambda_users" {
  name = "task-manager-users"

  # Users sign in with their email address, and every user therefore has an email attribute
  # (needed for password recovery and for SNS task notifications later).
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Only admins can create accounts: no public self sign-up.
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_uppercase                = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

/*
  Groups drive role-based access. Lower precedence number = higher priority,
  so admin wins if a user is ever in both groups.
*/
resource "aws_cognito_user_group" "admin_group" {
  name         = "admin"
  description  = "Can create, assign, update and view all tasks"
  user_pool_id = aws_cognito_user_pool.lambda_users.id
  precedence   = 1
}

resource "aws_cognito_user_group" "member_group" {
  name         = "member"
  description  = "Can view and update tasks assigned to them"
  user_pool_id = aws_cognito_user_pool.lambda_users.id
  precedence   = 10
}

/*
  App client for the browser front end. Public client: no secret, because anything shipped to a
  browser can be read by the user.
*/
resource "aws_cognito_user_pool_client" "pool_client" {
  name         = "task-manager-web"
  user_pool_id = aws_cognito_user_pool.lambda_users.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",            # front end sign-in (password never sent)
    "ALLOW_REFRESH_TOKEN_AUTH",       # renew sessions
    "ALLOW_ADMIN_USER_PASSWORD_AUTH", # CLI testing only; requires IAM credentials to call
  ]

  # Same error for "no such user" and "wrong password", so emails can't be enumerated.
  prevent_user_existence_errors = "ENABLED"

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
