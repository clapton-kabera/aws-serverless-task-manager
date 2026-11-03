#---------------------------------------------------------------------------------------------------- 
# providers.tf
# author: Kabera Clapton
#
# description: Defines the required providers
#----------------------------------------------------------------------------------------------------  

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "serverless-task-manager"
    }
  }
}
