# Application Load Balancer Terraform Variables

# IPv4 CIDR blocks allowed to reach the ALB over HTTP (port 80)
variable "alb_allowed_cidrs" {
  description = "List of IPv4 CIDR blocks allowed to connect to the ALB over HTTP (port 80)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Deletion protection (keep false in the lab so terraform destroy works)
variable "alb_enable_deletion_protection" {
  description = "If true, the ALB cannot be deleted via the AWS API (terraform destroy fails)"
  type        = bool
  default     = false
}

# Idle timeout in seconds
variable "alb_idle_timeout" {
  description = "Time in seconds that a connection is allowed to be idle"
  type        = number
  default     = 60
}

# Path to the state file of the VPC project (relative to this manifests/ directory)
variable "vpc_state_path" {
  description = "Path to the terraform.tfstate of the VPC project"
  type        = string
  default     = "../../VPC-module/manifests/terraform.tfstate"
}
