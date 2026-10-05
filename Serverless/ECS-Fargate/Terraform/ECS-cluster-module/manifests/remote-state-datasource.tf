# >>> [EC2] disabled
# # Terraform Remote State Datasource
# # Only the EC2 launch type needs it: the Fargate cluster itself does not use any VPC value
# # (the network of the Fargate tasks is defined by each ECS service).
# # Reads the outputs of the VPC project from its local state file (VPC-module must be applied first).
#
# # VPC project outputs (vpc_id, vpc_cidr_block, private_subnets, public_subnets_cidr_blocks, ...)
# data "terraform_remote_state" "vpc" {
#   backend = "local"
#   config = {
#     path = var.vpc_state_path
#   }
# }
# <<< [EC2]
