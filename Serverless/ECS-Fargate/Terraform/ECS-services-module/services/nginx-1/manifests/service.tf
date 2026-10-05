# ECS Service - uses the reusable module ../../../modules/ecs-service
module "service" {
  source = "../../../modules/ecs-service"

  # Naming
  name_prefix  = local.name
  environment  = var.environment
  service_name = var.service.name
  tags         = local.common_tags

  # Container
  image                    = local.container_image
  container_port           = var.service.container_port
  command                  = var.service.command
  environment_variables    = var.service.environment
  readonly_root_filesystem = var.service.readonly_root_filesystem

  # Size, count and autoscaling
  cpu             = var.service.cpu
  memory          = var.service.memory
  desired_count   = var.service.desired_count
  autoscaling_max = var.service.autoscaling_max

  # Launch type
  launch_type                = var.service.launch_type
  fargate_spot_weight        = var.service.fargate_spot_weight
  ec2_capacity_provider_name = var.ec2_capacity_provider_name

  # ALB routing and health check
  path_patterns          = var.service.path_patterns
  listener_rule_priority = var.service.listener_rule_priority
  health_check_path      = var.service.health_check_path
  health_check_matcher   = var.service.health_check_matcher

  # Platform values read from the other projects' states
  vpc_id                     = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnets            = data.terraform_remote_state.vpc.outputs.private_subnets
  listener_arn               = data.terraform_remote_state.alb.outputs.http_listener_arn
  alb_security_group_id      = data.terraform_remote_state.alb.outputs.alb_security_group_id
  alb_dns_name               = data.terraform_remote_state.alb.outputs.alb_dns_name
  cluster_arn                = data.terraform_remote_state.ecs_cluster.outputs.cluster_arn
  cluster_capacity_providers = local.cluster_capacity_providers
}
