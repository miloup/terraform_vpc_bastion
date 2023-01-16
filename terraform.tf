terraform {
  required_providers {
    aws = {
      source  = "tfregistry.cloud.socgen/hashicorp/aws"
      version = "~> 4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
