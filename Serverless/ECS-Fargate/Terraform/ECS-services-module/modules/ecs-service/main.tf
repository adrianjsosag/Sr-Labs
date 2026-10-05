# ECS Service module - target group + listener rule + ECS service (Fargate or EC2)

locals {
  # Capacity provider strategy depending on the launch type
  #   FARGATE -> FARGATE (base 1) + FARGATE_SPOT (only if fargate_spot_weight > 0)
  #   EC2     -> the EC2 Auto Scaling Group capacity provider of the cluster
  capacity_provider_strategy = (
    var.launch_type == "EC2"
    ? {
      for cp in [var.ec2_capacity_provider_name] : cp => {
        capacity_provider = cp
        base              = 1
        weight            = 1
      }
    }
    : {
      for cp, weight in { FARGATE = 1, FARGATE_SPOT = var.fargate_spot_weight } : cp => {
        capacity_provider         = cp
        base                      = cp == "FARGATE" ? 1 : 0
        weight                    = weight
      } if weight > 0
    }
  )

  # URL of the service: first path pattern without the trailing "*" and "/", plus "/"
  service_url = "http://${var.alb_dns_name}${trimsuffix(trimsuffix(var.path_patterns[0], "*"), "/")}/"
}

# ALB Target Group - receives the IPs of the service tasks (awsvpc network mode)
resource "aws_lb_target_group" "this" {
  name                 = substr("${var.service_name}-${var.environment}-tg", 0, 32)
  target_type          = "ip"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    port                = "traffic-port"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}-tg", Service = var.service_name })

  lifecycle {
    # The capacity providers needed by the service must be associated to the ECS cluster
    precondition {
      condition     = length(setsubtract(keys(local.capacity_provider_strategy), var.cluster_capacity_providers)) == 0
      error_message = "El servicio \"${var.service_name}\" usa launch_type ${var.launch_type} y necesita los capacity providers [${join(", ", keys(local.capacity_provider_strategy))}], pero el cluster ECS solo tiene [${join(", ", var.cluster_capacity_providers)}]. Cambia el modo del cluster con ECS-cluster-module/switch-launch-type.sh (y aplica) o cambia el launch_type del servicio."
    }
    precondition {
      condition     = var.autoscaling_max >= var.desired_count
      error_message = "autoscaling_max (${var.autoscaling_max}) must be >= desired_count (${var.desired_count})."
    }
  }
}

# ALB Listener Rule - forwards the service paths of the shared HTTP listener to its target group
resource "aws_lb_listener_rule" "this" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = var.path_patterns
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${var.service_name}-rule", Service = var.service_name })
}

# ECS Service (task definition + service + security group + IAM roles + logs + autoscaling)
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "7.6.1"

  name        = "${var.name_prefix}-${var.service_name}"
  cluster_arn = var.cluster_arn

  # Launch type: FARGATE or EC2 through the capacity provider strategy (launch_type is ignored when it is set)
  capacity_provider_strategy = local.capacity_provider_strategy
  requires_compatibilities   = [var.launch_type]
  network_mode               = "awsvpc"

  cpu           = var.cpu
  memory        = var.memory
  desired_count = var.desired_count

  container_definitions = {
    (var.service_name) = {
      image     = var.image
      essential = true
      command   = var.command
      portMappings = [
        {
          name          = var.service_name
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [for name, value in var.environment_variables : { name = name, value = value }]

      readonlyRootFilesystem = var.readonly_root_filesystem

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_retention_in_days = var.log_retention_in_days
    }
  }

  # Register the tasks in the target group. The ARN is taken from the listener rule so the
  # service waits until the target group is attached to the ALB.
  load_balancer = {
    service = {
      target_group_arn = one(aws_lb_listener_rule.this.action).target_group_arn
      container_name   = var.service_name
      container_port   = var.container_port
    }
  }
  health_check_grace_period_seconds = 60

  # Network - private subnets, outbound through the NAT Gateway
  subnet_ids       = var.private_subnets
  assign_public_ip = false

  # Security Group - application port only from the ALB, egress all
  security_group_ingress_rules = {
    alb = {
      description                  = "Application port from the ALB"
      from_port                    = var.container_port
      to_port                      = var.container_port
      ip_protocol                  = "tcp"
      referenced_security_group_id = var.alb_security_group_id
    }
  }
  security_group_egress_rules = {
    all = {
      description = "All outbound traffic (image pull via NAT, logs, ECS Exec)"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  enable_execute_command = true

  # IAM roles: short names (AWS limits the role name_prefix to 38 characters)
  task_exec_iam_role_name = "${var.service_name}-${var.environment}-exec"
  tasks_iam_role_name     = "${var.service_name}-${var.environment}-task"

  enable_autoscaling       = true
  autoscaling_min_capacity = var.desired_count
  autoscaling_max_capacity = var.autoscaling_max

  tags = merge(var.tags, { Service = var.service_name })
}
