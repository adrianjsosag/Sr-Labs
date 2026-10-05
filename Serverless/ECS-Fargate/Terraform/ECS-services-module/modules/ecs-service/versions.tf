# Reusable module: one ECS service published behind the shared ALB.
# The provider is configured by the caller (services/<name>/manifests/versions.tf).
terraform {
  required_version = ">= 1.16"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}
