# Provider configuration. Kept in its own file so the backend and provider
# settings are easy to find, separate from the resources themselves.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "scaler-devops-homework"
      Session     = "18-terraform-iac"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
