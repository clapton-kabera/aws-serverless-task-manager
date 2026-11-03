#---------------------------------------------------------------------------------------------------- 
# versions.tf
# author: Kabera Clapton
#
# description: Sets up the remote backend and the pin versions for different providers
#----------------------------------------------------------------------------------------------------  

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "~> 3.6.3"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4.2"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.1"
    }
  }

  backend "s3" {
    bucket       = "sandbox-remote-backend723354237"
    key          = "terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}


