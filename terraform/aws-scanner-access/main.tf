# Read-only IAM role for the weekly scan, assumable ONLY by GitHub Actions OIDC tokens issued to the
# main branch of one repository. No access keys are created. The permission policy is loaded from
# permissions/aws/cost-guardian-readonly-policy.json so the documented JSON and the deployed policy
# can never drift apart.

terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

variable "region" {
  description = "Any region; IAM is global."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "owner/repo allowed to assume the role."
  type        = string
  default     = "rsk071216-stack/cloud-cost-guardian"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/repo."
  }
}

variable "github_branch" {
  description = "Branch whose workflow runs may assume the role."
  type        = string
  default     = "main"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if the account already has one."
  type        = bool
  default     = true
}

variable "role_name" {
  description = "Name of the read-only scanner role."
  type        = string
  default     = "cloud-cost-guardian-readonly"
}

variable "tags" {
  description = "Default tags."
  type        = map(string)
  default = {
    owner         = "platform-team"
    "cost-center" = "finops"
    environment   = "shared"
    "managed-by"  = "terraform"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_role" "scanner" {
  name                 = var.role_name
  description          = "Read-only role for the cloud-cost-guardian weekly scan (GitHub OIDC, ${var.github_repository}@${var.github_branch})"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOidc"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "scanner_readonly" {
  name        = "${var.role_name}-policy"
  description = "Describe/Get-only permissions used by cloud-cost-guardian rules"
  policy      = file("${path.module}/../../permissions/aws/cost-guardian-readonly-policy.json")
}

resource "aws_iam_role_policy_attachment" "scanner_readonly" {
  role       = aws_iam_role.scanner.name
  policy_arn = aws_iam_policy.scanner_readonly.arn
}

output "role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable."
  value       = aws_iam_role.scanner.arn
}
