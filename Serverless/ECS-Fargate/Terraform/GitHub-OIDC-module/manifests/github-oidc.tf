# GitHub Actions OIDC: the pipeline gets TEMPORARY credentials by assuming IAM roles (no access keys)

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = merge(local.common_tags, { Name = "github-actions-oidc" })
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # OIDC "sub" claims (GitHub contexts) allowed for each role
  plan_subjects = [
    "repo:${local.github_repo}:pull_request",
    "repo:${local.github_repo}:ref:refs/heads/${var.github_main_branch}",
  ]
  apply_subjects = ["repo:${local.github_repo}:environment:${var.github_environment}"]

  state_bucket_arn = "arn:aws:s3:::${local.state_bucket}"
}

# Trust policies ------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.plan_subjects
    }
  }
}

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # ONLY jobs running in the protected GitHub environment (manual approval)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.apply_subjects
    }
  }
}

# Access to the Terraform state ---------------------------------------------------------------
data "aws_iam_policy_document" "state_read" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }
  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }
  # Native S3 locking: the lock file <key>.tflock is created and deleted on every plan
  statement {
    sid       = "StateLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }
}

data "aws_iam_policy_document" "state_write" {
  source_policy_documents = [data.aws_iam_policy_document.state_read.json]
  statement {
    sid       = "StateWrite"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }
}

# PLAN role: read only (pull requests and main branch) -------------------------------------
resource "aws_iam_role" "plan" {
  name                 = "${local.name_lower}-github-plan"
  description          = "GitHub Actions (${local.github_repo}): terraform plan - read only"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
  tags                 = local.common_tags
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_read.json
}

# APPLY role: only from the protected GitHub environment -----------------------------------
resource "aws_iam_role" "apply" {
  name                 = "${local.name_lower}-github-apply"
  description          = "GitHub Actions (${local.github_repo}): terraform apply - protected environment only"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
  tags                 = local.common_tags
}

# PowerUserAccess: everything except IAM, Organizations and account management
resource "aws_iam_role_policy_attachment" "apply_poweruser" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# Scoped IAM: only roles, policies and instance profiles named like the platform ones (*-<env>-*)
data "aws_iam_policy_document" "apply_iam" {
  statement {
    sid       = "IamRead"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }
  statement {
    sid = "IamManagePlatformRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:TagInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/*-${var.environment}-*",
      "arn:aws:iam::${local.account_id}:policy/*-${var.environment}-*",
      "arn:aws:iam::${local.account_id}:instance-profile/*-${var.environment}-*",
    ]
  }
  statement {
    sid       = "IamPassRoleToServices"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/*-${var.environment}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
  statement {
    sid       = "IamServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]
  }
  # The pipeline roles also match *-<env>-*: never let the pipeline change its own permissions
  statement {
    sid    = "DenyPipelineRolesChanges"
    effect = "Deny"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
      "iam:TagRole", "iam:UntagRole", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.name_lower}-github-*"]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  name   = "terraform-scoped-iam"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_iam.json
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state-write"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state_write.json
}
