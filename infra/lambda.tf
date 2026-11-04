#----------------------------------------------------------------------------------------------------
# lambda.tf
# author: Kabera Clapton
#
# description: TF file that provisions lambda functions
#----------------------------------------------------------------------------------------------------

/*
  Package the lambda function code as a zip file
*/
data "archive_file" "function_zip" {
  type        = "zip"
  source_file = "${path.root}/../backend/functions/hello/app.py"
  output_path = "${path.root}/../build/app.zip"
}

/*
  Create the lambda function that just returns hello
*/
resource "aws_lambda_function" "hello_function" {
  filename      = data.archive_file.function_zip.output_path
  function_name = var.lambda_function_name

  role        = aws_iam_role.lambda_role.arn
  handler     = "app.lambda_handler"
  code_sha256 = data.archive_file.function_zip.output_base64sha256

  runtime = "python3.14"

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
    aws_iam_role_policy_attachment.lambda_policy,
  ]
}

/*
  Create a log group so that AWS does not create a hidden managed log group that terraform does not control.
  This can lead to piling up of logs which are never deleted.
*/
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 3
}

/*
  Create a permission that allows API Gateway to trigger the lambda function
*/
resource "aws_lambda_permission" "api_gateway_perm" {
  statement_id  = "AllowTriggerFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigateway_api.serverless_gateway.execution_arn}/*/*"
}
