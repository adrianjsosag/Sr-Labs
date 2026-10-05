# AWS EC2 Instance Terraform Variables

# AWS EC2 Instance Type
variable "instance_type" {
  description = "EC2 Instance Type"
  type        = string
  default     = "t3.micro"
}

# CIDR blocks allowed to connect to the Bastion Host via SSH
variable "bastion_ssh_allowed_cidrs" {
  description = "List of IPv4 CIDR blocks allowed to connect via SSH (port 22) to the Bastion Host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Path to the state file of the VPC project (relative to this manifests/ directory)
variable "vpc_state_path" {
  description = "Path to the terraform.tfstate of the VPC project"
  type        = string
  default     = "../../VPC-module/manifests/terraform.tfstate"
}
