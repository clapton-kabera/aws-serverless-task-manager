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
  type = "zip"
  source_file = "${path.root}/../backend/functions/hello/app.py"
  output_path = "${path.root}/../backend/functions/hello/app.zip"
}

/*
  Create the lambda function that just returns hello
*/
resource "aws_lambda_function" "hello_function" {
  filename = data.archive_file.function_zip.output_path
  function_name = "say_hello_function"
  role = aws_iam_role.lambda_role.arn
  handler = "app.lambda_handler"
  code_sha256 = data.archive_file.function_zip.output_base64sha256

  runtime = "python3.15"
}

/*
  Create a permission that allows API Gateway to trigger the lambda function
*/
resource "aws_lambda_permission" "api_gateway_perm" {
  statement_id = "AllowTriggerFromApiGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_function.function_name
  principal = "apigateway.amazonaws.com"
}
