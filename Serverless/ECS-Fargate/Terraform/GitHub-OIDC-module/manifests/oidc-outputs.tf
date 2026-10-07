# GitHub OIDC Outputs

output "plan_role_arn" {
  description = "GitHub repository variable AWS_PLAN_ROLE_ARN"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub repository variable AWS_APPLY_ROLE_ARN"
  value       = aws_iam_role.apply.arn
}

output "aws_region" {
  description = "GitHub repository variable AWS_REGION"
  value       = var.aws_region
}

output "github_oidc_subjects" {
  description = "OIDC subjects (GitHub contexts) allowed for each role"
  value = {
    plan  = local.plan_subjects
    apply = local.apply_subjects
  }
}
