# Terraform Remote State Datasource
# Reads the outputs of the VPC project from its local state file (VPC-module must be applied first)

# VPC project outputs (vpc_id, public_subnets, vpc_cidr_block, ...)
data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = var.vpc_state_path
  }
}
