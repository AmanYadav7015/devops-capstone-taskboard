terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  skip_credentials_validation = var.skip_aws_api_checks
  skip_metadata_api_check     = var.skip_aws_api_checks
  skip_requesting_account_id  = var.skip_aws_api_checks

  default_tags {
    tags = local.common_tags
  }
}
