# Define Local Values in Terraform
locals {
  owners      = var.business_divsion
  environment = var.environment
  name        = "${var.business_divsion}-${var.environment}"
  name_lower  = lower(local.name)
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }

  account_id = data.aws_caller_identity.current.account_id
  # Same name as S3-tfstate-backend-module: <division>-<environment>-tfstate-<account_id>
  state_bucket = coalesce(var.state_bucket, "${local.name_lower}-tfstate-${local.account_id}")
  github_repo  = "${var.github_owner}/${var.github_repository}"
}

data "aws_caller_identity" "current" {}
