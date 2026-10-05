# Define Local Values in Terraform
locals {
  owners      = var.business_divsion
  environment = var.environment
  name        = "${var.business_divsion}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }

  # Capacity providers associated to the ECS cluster, read from its state:
  #   fargate mode -> output "cluster_capacity_providers" = ["FARGATE", "FARGATE_SPOT"]
  #   ec2 mode     -> output "capacity_providers"         = ["ec2"]
  cluster_capacity_providers = try(
    data.terraform_remote_state.ecs_cluster.outputs.cluster_capacity_providers,
    data.terraform_remote_state.ecs_cluster.outputs.capacity_providers,
    []
  )

  # Container image:
  #   ecr_repository + image_tag -> image of ECR-module pinned by its digest (repo@sha256:...)
  #   image                      -> used as is
  use_ecr = var.service.ecr_repository != null
  container_image = (
    local.use_ecr
    ? "${data.terraform_remote_state.ecr[0].outputs.repository_urls[var.service.ecr_repository]}@${data.aws_ecr_image.this[0].image_digest}"
    : var.service.image
  )
}
