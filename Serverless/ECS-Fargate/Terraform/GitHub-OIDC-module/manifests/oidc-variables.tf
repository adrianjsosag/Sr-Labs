# GitHub OIDC Terraform Variables

# GitHub repository allowed to assume the pipeline roles
variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,39}$", var.github_owner))
    error_message = "github_owner must be a valid GitHub user or organization name."
  }
}

variable "github_repository" {
  description = "Name of the GitHub repository"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository must be a valid GitHub repository name."
  }
}

# Branch whose pushes (merges) run the plan of the pipeline
variable "github_main_branch" {
  description = "Main branch of the repository"
  type        = string
  default     = "main"
}

# GitHub environment (with required reviewers) whose jobs can assume the apply role
variable "github_environment" {
  description = "GitHub environment allowed to assume the apply role"
  type        = string
  default     = "production"
}

# Create the GitHub OIDC provider (false if the AWS account already has it: only one per account)
variable "create_github_oidc_provider" {
  description = "Create the token.actions.githubusercontent.com OIDC provider"
  type        = bool
  default     = true
}

# S3 bucket with the Terraform states (S3-tfstate-backend-module). Default: <division>-<environment>-tfstate-<account_id>
variable "state_bucket" {
  description = "S3 bucket of the Terraform states (null = name derived like S3-tfstate-backend-module)"
  type        = string
  default     = null
}
