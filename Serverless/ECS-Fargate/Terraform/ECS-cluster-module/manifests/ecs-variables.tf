# ECS Cluster Terraform Variables

# CloudWatch Container Insights
variable "ecs_container_insights" {
  description = "Enable or disable CloudWatch Container Insights on the cluster"
  type        = string
  default     = "disabled"
  validation {
    condition     = contains(["enabled", "disabled"], var.ecs_container_insights)
    error_message = "ecs_container_insights must be \"enabled\" or \"disabled\"."
  }
}

# >>> [EC2] disabled
# # EC2 Instance Type for the ECS container instances
# variable "ecs_instance_type" {
#   description = "EC2 Instance Type of the ECS container instances"
#   type        = string
#   default     = "t3.medium"
# }
#
# # Auto Scaling Group - Minimum number of instances
# variable "ecs_asg_min_size" {
#   description = "Minimum number of EC2 instances in the Auto Scaling Group"
#   type        = number
#   default     = 1
# }
#
# # Auto Scaling Group - Maximum number of instances
# variable "ecs_asg_max_size" {
#   description = "Maximum number of EC2 instances in the Auto Scaling Group"
#   type        = number
#   default     = 3
# }
#
# # Auto Scaling Group - Initial number of instances
# variable "ecs_asg_desired_capacity" {
#   description = "Initial number of EC2 instances in the Auto Scaling Group (afterwards managed by ECS)"
#   type        = number
#   default     = 2
# }
#
# # Root volume size of the ECS container instances
# variable "ecs_root_volume_size" {
#   description = "Root EBS volume size (GiB) of the ECS container instances"
#   type        = number
#   default     = 30
# }
#
# # Capacity Provider - Managed Scaling target capacity
# variable "ecs_target_capacity" {
#   description = "Target utilization (%) of the instances for the ECS managed scaling"
#   type        = number
#   default     = 80
#   validation {
#     condition     = var.ecs_target_capacity >= 1 && var.ecs_target_capacity <= 100
#     error_message = "ecs_target_capacity must be between 1 and 100."
#   }
# }
#
# # S3 bucket with the Terraform states (S3-tfstate-backend-module). Default: <division>-<environment>-tfstate-<account_id>
# variable "state_bucket" {
#   description = "S3 bucket of the Terraform states (null = name derived like S3-tfstate-backend-module)"
#   type        = string
#   default     = null
# }
#
# # TESTS ONLY: directory with local <project>.tfstate files used instead of the S3 bucket
# variable "remote_state_local_dir" {
#   description = "Tests only: directory with local <project>.tfstate files (e.g. VPC-module.tfstate) instead of S3"
#   type        = string
#   default     = null
# }
# <<< [EC2]
