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
