# Terraform Remote State Datasources
# Reads the outputs of the other projects from their local state files
# (relative to services/<name>/manifests/, so the paths go up 4 levels)

# VPC project outputs (vpc_id, private_subnets, ...)
data "terraform_remote_state" "vpc" {
  backend = "local"
  config = {
    path = var.vpc_state_path
  }

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
  backend = "local"
  config = {
    path = var.alb_state_path
  }
}

# ECS cluster project outputs (cluster_arn, cluster_name, capacity providers, ...)
data "terraform_remote_state" "ecs_cluster" {
  backend = "local"
  config = {
    path = var.ecs_cluster_state_path
  }
}

# ECR project outputs (repository_urls, repository_names) - only when the service uses an ECR image
data "terraform_remote_state" "ecr" {
  count   = local.use_ecr ? 1 : 0
  backend = "local"
  config = {
    path = var.ecr_state_path
  }
}

# The image tag must already be pushed to ECR (ECR-module/push-image.sh): otherwise the plan fails here,
# before deploying tasks that could not pull the image. Its digest pins the exact image deployed.
data "aws_ecr_image" "this" {
  count           = local.use_ecr ? 1 : 0
  repository_name = data.terraform_remote_state.ecr[0].outputs.repository_names[var.service.ecr_repository]
  image_tag       = var.service.image_tag
}
