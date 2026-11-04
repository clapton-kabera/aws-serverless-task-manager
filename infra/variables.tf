#---------------------------------------------------------------------------------------------------- 
# variables.tf
# author: Kabera Clapton
#
# description: A file that stores the input variables for the terraform config
#---------------------------------------------------------------------------------------------------- 

variable "region" {
  type        = string
  description = "Region where the AWS account belongs"
  default     = "eu-west-1"
}

variable "lambda_function_name" {
  type        = string
  description = "The name of the lambda function."
  default     = "say_hello_function"
}

variable "api_gateway_name" {
  type        = string
  description = "Name of the api gateway"
  default     = "serverless_gateway"
}
