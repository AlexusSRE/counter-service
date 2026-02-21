terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "alex-counter-service-tfstate"
    key            = "infra/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "alex-counter-service-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}
