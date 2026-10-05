# ECS Service Terraform Variables

# Service definition (values in service.auto.tfvars)
variable "service" {
  description = "Definition of the ECS service deployed by this project"
  type = object({
    name                     = string                         # Service / container name (1-20 chars: a-z, 0-9, -)
    ecr_repository           = optional(string)               # Image from ECR-module: repository short name (e.g. "nginx-1")...
    image_tag                = optional(string)               # ...and its tag (e.g. "1.0.0"). Deployed pinned by digest
    image                    = optional(string)               # OR any other image URI (ECR Public, Docker Hub...)
    listener_rule_priority   = number                         # ALB rule priority (1-50000), UNIQUE among all the services
    launch_type              = optional(string, "FARGATE")    # FARGATE or EC2 (the ECS cluster must be in the same mode)
    fargate_spot_weight      = optional(number, 0)            # FARGATE only: > 0 also places tasks on FARGATE_SPOT
    container_port           = optional(number, 80)           # Port the application listens on
    cpu                      = optional(number, 256)          # Task CPU units (256 = 0.25 vCPU)
    memory                   = optional(number, 512)          # Task memory (MiB)
    desired_count            = optional(number, 1)            # Initial / minimum number of tasks
    autoscaling_max          = optional(number, 4)            # Maximum number of tasks
    path_patterns            = optional(list(string), ["/*"]) # ALB paths routed to this service
    health_check_path        = optional(string, "/")          # ALB health check path
    health_check_matcher     = optional(string, "200")        # Expected HTTP code(s) of the health check
    command                  = optional(list(string))         # Optional container command
    environment              = optional(map(string), {})      # Environment variables (no secrets)
    readonly_root_filesystem = optional(bool, false)          # nginx needs a writable root filesystem
  })

  validation {
    condition = (
      (var.service.image != null && var.service.ecr_repository == null && var.service.image_tag == null) ||
      (var.service.image == null && var.service.ecr_repository != null && var.service.image_tag != null)
    )
    error_message = "Define the image in ONE way: ecr_repository + image_tag (image from ECR-module) OR image (any other URI)."
  }
  validation {
    condition     = var.service.image_tag != "latest"
    error_message = "image_tag cannot be \"latest\": use a version (e.g. 1.0.0). ECR repositories are IMMUTABLE."
  }
}

# Name of the EC2 capacity provider of the ECS cluster (ECS-cluster-module, EC2 mode)
variable "ec2_capacity_provider_name" {
  description = "Name of the EC2 Auto Scaling Group capacity provider of the ECS cluster"
  type        = string
  default     = "ec2"
}

# Paths to the state files of the other projects (relative to services/<name>/manifests/)
variable "vpc_state_path" {
  description = "Path to the terraform.tfstate of the VPC project"
  type        = string
  default     = "../../../../VPC-module/manifests/terraform.tfstate"
}

variable "alb_state_path" {
  description = "Path to the terraform.tfstate of the ALB project"
  type        = string
  default     = "../../../../ALB-module/manifests/terraform.tfstate"
}

variable "ecs_cluster_state_path" {
  description = "Path to the terraform.tfstate of the ECS cluster project"
  type        = string
  default     = "../../../../ECS-cluster-module/manifests/terraform.tfstate"
}

variable "ecr_state_path" {
  description = "Path to the terraform.tfstate of the ECR project (only used with ecr_repository)"
  type        = string
  default     = "../../../../ECR-module/manifests/terraform.tfstate"
}
