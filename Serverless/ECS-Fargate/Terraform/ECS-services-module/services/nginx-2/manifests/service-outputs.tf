# ECS Service Terraform Outputs

output "url" {
  description = "HTTP URL of the service"
  value       = module.service.url
}

output "service" {
  description = "Main attributes of the deployed service"
  value = {
    service_name        = module.service.service_name
    image               = local.container_image
    launch_type         = module.service.launch_type
    capacity_providers  = module.service.capacity_providers
    task_definition_arn = module.service.task_definition_arn
    target_group_arn    = module.service.target_group_arn
    listener_rule_arn   = module.service.listener_rule_arn
    security_group_id   = module.service.security_group_id
    log_group           = module.service.log_group
  }
}
