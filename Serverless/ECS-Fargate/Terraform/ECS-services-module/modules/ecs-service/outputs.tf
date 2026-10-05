# ECS Service module - Outputs

output "service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_service.name
}

output "url" {
  description = "HTTP URL of the service (ALB DNS + first path)"
  value       = local.service_url
}

output "launch_type" {
  description = "Launch type of the service"
  value       = var.launch_type
}

output "capacity_providers" {
  description = "Capacity providers used by the service"
  value       = keys(local.capacity_provider_strategy)
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = module.ecs_service.task_definition_arn
}

output "target_group_arn" {
  description = "ARN of the service target group"
  value       = aws_lb_target_group.this.arn
}

output "listener_rule_arn" {
  description = "ARN of the service listener rule"
  value       = aws_lb_listener_rule.this.arn
}

output "security_group_id" {
  description = "ID of the Security Group of the service tasks"
  value       = module.ecs_service.security_group_id
}

output "log_group" {
  description = "CloudWatch log group of the container"
  value       = try(module.ecs_service.container_definitions[var.service_name].cloudwatch_log_group_name, null)
}
