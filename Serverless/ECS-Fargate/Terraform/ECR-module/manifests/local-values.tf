# Define Local Values in Terraform
locals {
  owners      = var.business_divsion
  environment = var.environment
  name        = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }
  # ECR repository names must be lowercase: cloudengineering-stag/<repository>
  repo_prefix = lower(local.name)
}
