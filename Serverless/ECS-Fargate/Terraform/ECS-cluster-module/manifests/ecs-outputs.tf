# ECS Cluster Terraform Outputs

## cluster_name
output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.name
}

## cluster_arn
output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.arn
}

## cluster_id
output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.id
}

# >>> [FARGATE] enabled
## cluster_capacity_providers (FARGATE, FARGATE_SPOT)
output "cluster_capacity_providers" {
  description = "Capacity providers available in the ECS cluster"
  value       = ["FARGATE", "FARGATE_SPOT"]
}
# <<< [FARGATE]

# >>> [EC2] disabled
# ## capacity_providers
# output "capacity_providers" {
#   description = "Names of the capacity providers of the ECS cluster"
#   value       = [for cp in module.ecs_cluster.capacity_providers : cp.name]
# }
#
# ## autoscaling_group_name
# output "autoscaling_group_name" {
#   description = "Name of the Auto Scaling Group of the ECS container instances"
#   value       = module.autoscaling.autoscaling_group_name
# }
#
# ## autoscaling_group_arn
# output "autoscaling_group_arn" {
#   description = "ARN of the Auto Scaling Group of the ECS container instances"
#   value       = module.autoscaling.autoscaling_group_arn
# }
#
# ## ecs_instances_security_group_id
# output "ecs_instances_security_group_id" {
#   description = "ID of the Security Group of the ECS container instances"
#   value       = aws_security_group.ecs_instances.id
# }
#
# ## ecs_ssh_access_security_group_id
# output "ecs_ssh_access_security_group_id" {
#   description = "ID of the Security Group that allows SSH to the ECS container instances from the public subnets"
#   value       = aws_security_group.ecs_ssh_access.id
# }
#
# ## ecs_instance_iam_role_arn
# output "ecs_instance_iam_role_arn" {
#   description = "ARN of the IAM role of the ECS container instances"
#   value       = module.autoscaling.iam_role_arn
# }
#
# ## ecs_ami_id
# output "ecs_ami_id" {
#   description = "ECS-optimized Amazon Linux 2023 AMI ID used by the instances"
#   value       = nonsensitive(data.aws_ssm_parameter.ecs_optimized_ami.value)
# }
#
# ## ec2_key_pair_name
# output "ec2_key_pair_name" {
#   description = "Name of the Key Pair created for the ECS container instances"
#   value       = module.key_pair.key_pair_name
# }
#
# ## ec2_private_key_path
# output "ec2_private_key_path" {
#   description = "Local path of the private key (.pem) to connect to the ECS container instances"
#   value       = local_sensitive_file.ec2_private_key.filename
# }
# <<< [EC2]
