# Terraform state in the S3 bucket created by S3-tfstate-backend-module (one key per project).
# Backends cannot use variables: if the AWS account, division or environment change, update "bucket"
# here and in the other projects (see the README of S3-tfstate-backend-module).
# This project is ALWAYS applied by hand: the pipeline must never change its own permissions.
terraform {
  backend "s3" {
    bucket       = "cloudengineering-stag-tfstate-373716886058"
    key          = "GitHub-OIDC-module/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
