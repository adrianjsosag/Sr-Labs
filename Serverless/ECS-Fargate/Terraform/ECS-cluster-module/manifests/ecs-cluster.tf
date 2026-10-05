# AWS ECS Cluster Terraform Module
# The launch type is selected with ../switch-launch-type.sh (fargate | ec2), which comments /
# uncomments the "# >>> [FARGATE]" and "# >>> [EC2]" blocks of the manifests.
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "7.6.1"

  name = local.cluster_name

  # CloudWatch Container Insights
  setting = [
    {
      name  = "containerInsights"
      value = var.ecs_container_insights
    }
  ]

  # >>> [FARGATE] enabled
  # Capacity Providers - AWS Fargate (on-demand) and Fargate Spot (cheaper, can be interrupted)
  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # Tasks without an explicit strategy run on Fargate (on-demand)
  default_capacity_provider_strategy = {
    FARGATE = {
      weight = 100
      base   = 1
    }
  }
  # <<< [FARGATE]

  # >>> [EC2] disabled
  #   # Capacity Provider - EC2 instances of the Auto Scaling Group
  #   capacity_providers = {
  #     ec2 = {
  #       auto_scaling_group_provider = {
  #         auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
  #         managed_draining               = "ENABLED"
  #         managed_termination_protection = "ENABLED"
  #
  #         managed_scaling = {
  #           status                    = "ENABLED"
  #           target_capacity           = var.ecs_target_capacity
  #           minimum_scaling_step_size = 1
  #           maximum_scaling_step_size = 2
  #         }
  #       }
  #     }
  #   }
  #
  #   # Tasks without an explicit strategy run on the EC2 capacity provider
  #   default_capacity_provider_strategy = {
  #     ec2 = {
  #       weight = 100
  #       base   = 1
  #     }
  #   }
  # <<< [EC2]

  # Only needed for ECS Managed Instances, not for Fargate or an Auto Scaling Group
  create_security_group          = false
  create_infrastructure_iam_role = false

  cloudwatch_log_group_retention_in_days = 7

  tags = local.common_tags
}
