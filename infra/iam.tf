#----------------------------------------------------------------------------------------------------
# iam.tf
# author: Kabera Clapton
#
# description: Sets up the necessary iam roles and policies for lambda and API gateway
#---------------------------------------------------------------------------------------------------- 

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
        Sid = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
    }
  )

  tags = {
    service = "lambda"
    description = "lambda role for what the lambda function can do"
  }
}

/*
  Now we can define what policies/privilges that this role will have
*/
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role = aws_iam_role.lambda_role.name
  policy = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 
}
