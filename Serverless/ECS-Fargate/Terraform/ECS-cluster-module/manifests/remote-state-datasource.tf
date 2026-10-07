# >>> [EC2] disabled
# # Terraform Remote State Datasource
# # Only the EC2 launch type needs it: the Fargate cluster itself does not use any VPC value
# # (the network of the Fargate tasks is defined by each ECS service).
# # The states live in the S3 bucket created by S3-tfstate-backend-module (one key per project).
# # Tests only: set remote_state_local_dir to read local <project>.tfstate files instead of S3.
#
# data "aws_caller_identity" "current" {}
#
# locals {
#   state_bucket = coalesce(var.state_bucket, "${lower(var.business_divsion)}-${lower(var.environment)}-tfstate-${data.aws_caller_identity.current.account_id}")
#
#   # Backend configuration of each remote state: S3 (default) or local files (tests)
#   remote_state_config = {
#     for project, key in { vpc = "VPC-module" } : project => (
#       var.remote_state_local_dir == null
#       ? tomap({ bucket = local.state_bucket, key = "${key}/terraform.tfstate", region = var.aws_region })
#       : tomap({ path = "${var.remote_state_local_dir}/${key}.tfstate" })
#     )
#   }
#   remote_state_backend = var.remote_state_local_dir == null ? "s3" : "local"
# }
#
# # VPC project outputs (vpc_id, vpc_cidr_block, private_subnets, public_subnets_cidr_blocks, ...)
# data "terraform_remote_state" "vpc" {
#   backend = local.remote_state_backend
#   config  = local.remote_state_config["vpc"]
# }
# <<< [EC2]
