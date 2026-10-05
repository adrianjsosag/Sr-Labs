# Define Local Values in Terraform
locals {
  owners      = var.business_divsion
  environment = var.environment
  name        = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }
  # Bastion Host name - also used as the Key Pair name and the local .pem file name
  bastion_name = "${local.name}-BastionHost"
}
