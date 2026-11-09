#----------------------------------------------------------------------------------------------------
# iam.tf
# author: Kabera Clapton
#
# description: Sets up the necessary iam roles and policies for lambda and API gateway
#---------------------------------------------------------------------------------------------------- 

/*
  Create a policy document for creating and putting log streams in cloud watch
  This is better than using jsonencode because terraform can easily flag errors
*/
data "aws_iam_policy_document" "log_policy_doc" {
  statement {
    sid = "1"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = values(aws_cloudwatch_log_group.function)[*].arn
  }
}

/*
  Create an IAM policy that allows a role to create log streams and put log streams in cloudwatch only
*/
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging_policy"
  path        = "/"
  description = "IAM policy for logging to cloudwatch from a lambda function"

  policy = data.aws_iam_policy_document.log_policy_doc.json
}

/*
  This resource will create a role that we shall assign to the AWS lambda service in our account
*/
resource "aws_iam_role" "lambda_role" {
  name = "lambda_exec_role"

  /* This says that lambda can take on the role that will be provisioned here */
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
    }
  )

  tags = {
    service     = "lambda"
    description = "lambda role for what the lambda function can do"
  }
}

/*
  Now we can define what policies/privilges that this role will have
*/
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}
