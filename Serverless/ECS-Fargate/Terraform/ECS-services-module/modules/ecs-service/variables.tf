# ECS Service module - Input Variables

# --- Naming -------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix of the resource names (<business_divsion>-<environment>)"
  type        = string
}

variable "environment" {
  description = "Environment name, used in the target group name"
  type        = string
}

variable "service_name" {
  description = "Name of the service (also the container name). 1-20 chars: lowercase letters, numbers or '-'"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.service_name))
    error_message = "service_name must have 1-20 characters: lowercase letters, numbers or '-'."
  }
}

variable "tags" {
  description = "Tags applied to all the resources"
  type        = map(string)
  default     = {}
}

# --- Container ----------------------------------------------------------------
variable "image" {
  description = "Container image (ECR, ECR Public, Docker Hub...). Prefer an immutable tag or a digest"
  type        = string
}

variable "container_port" {
  description = "Port the application listens on"
  type        = number
  default     = 80
}

variable "command" {
  description = "Optional container command (overrides the image CMD)"
  type        = list(string)
  default     = null
}

variable "environment_variables" {
  description = "Environment variables of the container (do NOT put secrets here)"
  type        = map(string)
  default     = {}
}

variable "readonly_root_filesystem" {
  description = "Mount the container root filesystem as read-only (nginx needs it writable)"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Retention of the container CloudWatch log group"
  type        = number
  default     = 7
}

# --- Task size, count and autoscaling -------------------------------------------
variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a valid Fargate value: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory (MiB)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Initial / minimum number of tasks"
  type        = number
  default     = 1
  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be >= 1."
  }
}

variable "autoscaling_max" {
  description = "Maximum number of tasks (CPU / memory autoscaling)"
  type        = number
  default     = 4
}

# --- Launch type --------------------------------------------------------------
variable "launch_type" {
  description = "FARGATE or EC2 (the ECS cluster must be in the same mode)"
  type        = string
  default     = "FARGATE"
  validation {
    condition     = contains(["FARGATE", "EC2"], var.launch_type)
    error_message = "launch_type must be \"FARGATE\" or \"EC2\"."
  }
}

variable "fargate_spot_weight" {
  description = "FARGATE only: > 0 also places tasks on FARGATE_SPOT with this weight"
  type        = number
  default     = 0
  validation {
    condition     = var.fargate_spot_weight >= 0
    error_message = "fargate_spot_weight must be >= 0."
  }
}

variable "ec2_capacity_provider_name" {
  description = "Name of the EC2 Auto Scaling Group capacity provider of the ECS cluster"
  type        = string
  default     = "ec2"
}

# --- ALB routing and health check -----------------------------------------------
variable "path_patterns" {
  description = "ALB paths routed to this service"
  type        = list(string)
  default     = ["/*"]
}

variable "listener_rule_priority" {
  description = "ALB listener rule priority (1-50000). Must be unique among ALL the services of the ALB"
  type        = number
  validation {
    condition     = var.listener_rule_priority >= 1 && var.listener_rule_priority <= 50000
    error_message = "listener_rule_priority must be between 1 and 50000."
  }
}

variable "health_check_path" {
  description = "ALB health check path"
  type        = string
  default     = "/"
}

variable "health_check_matcher" {
  description = "Expected HTTP code(s) of the health check"
  type        = string
  default     = "200"
}

# --- Platform (values read from the other projects' states) ---------------------
variable "vpc_id" {
  description = "VPC ID (VPC-module)"
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs for the tasks (VPC-module)"
  type        = list(string)
}

variable "listener_arn" {
  description = "ARN of the ALB HTTP listener (ALB-module)"
  type        = string
}

variable "alb_security_group_id" {
  description = "ID of the ALB Security Group (ALB-module)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB (ALB-module), used to build the service URL"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster (ECS-cluster-module)"
  type        = string
}

variable "cluster_capacity_providers" {
  description = "Capacity providers associated to the ECS cluster (ECS-cluster-module)"
  type        = list(string)
}
