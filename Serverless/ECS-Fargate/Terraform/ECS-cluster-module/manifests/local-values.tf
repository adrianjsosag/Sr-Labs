# Define Local Values in Terraform
locals {
  owners      = var.business_divsion
  environment = var.environment
  name        = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }
  # ECS Cluster name
  cluster_name = "${local.name}-ecs-cluster"
  # >>> [EC2] disabled
  #   # Key Pair name for the cluster EC2 instances (different from the Bastion Host key)
  #   ec2_key_name = "${local.cluster_name}-ec2"
  # <<< [EC2]
}
