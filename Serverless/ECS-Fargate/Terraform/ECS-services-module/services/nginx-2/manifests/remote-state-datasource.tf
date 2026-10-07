# Terraform Remote State Datasources
# The states live in the S3 bucket created by S3-tfstate-backend-module (one key per project).
# Tests only: set remote_state_local_dir to read local <project>.tfstate files instead of S3.

data "aws_caller_identity" "current" {}

locals {
  state_bucket = coalesce(var.state_bucket, "${lower(var.business_divsion)}-${lower(var.environment)}-tfstate-${data.aws_caller_identity.current.account_id}")

  # Backend configuration of each remote state: S3 (default) or local files (tests)
  remote_state_config = {
    for project, key in {
      vpc         = "VPC-module"
      alb         = "ALB-module"
      ecs_cluster = "ECS-cluster-module"
      ecr         = "ECR-module"
      } : project => (
      var.remote_state_local_dir == null
      ? tomap({ bucket = local.state_bucket, key = "${key}/terraform.tfstate", region = var.aws_region })
      : tomap({ path = "${var.remote_state_local_dir}/${key}.tfstate" })
    )
  }
  remote_state_backend = var.remote_state_local_dir == null ? "s3" : "local"
}

# VPC project outputs (vpc_id, private_subnets, ...)
data "terraform_remote_state" "vpc" {
  backend = local.remote_state_backend
  config  = local.remote_state_config["vpc"]

  lifecycle {
    # Safety check for copied services: services/<directory>/manifests must deploy the service <directory>.
    # A copy that keeps the old name would try to create AWS resources that already exist.
    precondition {
      condition     = var.service.name == basename(dirname(abspath(path.root)))
      error_message = "service.name (\"${var.service.name}\") must be equal to the service directory name (\"${basename(dirname(abspath(path.root)))}\"). Edit service.auto.tfvars of the copied service."
    }
  }
}

# ALB project outputs (http_listener_arn, alb_security_group_id, alb_dns_name, ...)
data "terraform_remote_state" "alb" {
  backend = local.remote_state_backend
  config  = local.remote_state_config["alb"]
}

# ECS cluster project outputs (cluster_arn, cluster_name, capacity providers, ...)
data "terraform_remote_state" "ecs_cluster" {
  backend = local.remote_state_backend
  config  = local.remote_state_config["ecs_cluster"]
}

# ECR project outputs (repository_urls, repository_names) - only when the service uses an ECR image
data "terraform_remote_state" "ecr" {
  count   = local.use_ecr ? 1 : 0
  backend = local.remote_state_backend
  config  = local.remote_state_config["ecr"]
}

# The image tag must already be pushed to ECR (ECR-module/push-image.sh): otherwise the plan fails here,
# before deploying tasks that could not pull the image. Its digest pins the exact image deployed.
data "aws_ecr_image" "this" {
  count           = local.use_ecr ? 1 : 0
  repository_name = data.terraform_remote_state.ecr[0].outputs.repository_names[var.service.ecr_repository]
  image_tag       = var.service.image_tag
}
