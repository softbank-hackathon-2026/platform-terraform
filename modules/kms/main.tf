data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_principal_arn = format(
    "arn:%s:iam::%s:root",
    data.aws_partition.current.partition,
    data.aws_caller_identity.current.account_id
  )

  account_policy_statement = {
    Sid       = "EnableAccountIAMPermissions"
    Effect    = "Allow"
    Principal = { AWS = local.account_principal_arn }
    Action    = "kms:*"
    Resource  = "*"
  }

  admin_policy_statements = [for statement in [{
    Sid       = "AllowKeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = sort(tolist(var.kms_admin_arns)) }
    Action = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:RotateKeyOnDemand"
    ]
    Resource = "*"
  }] : statement if length(var.kms_admin_arns) > 0]

  user_policy_statements = [for statement in [
    {
      Sid       = "AllowKeyUse"
      Effect    = "Allow"
      Principal = { AWS = sort(tolist(var.key_user_arns)) }
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      Resource = "*"
    },
    {
      Sid       = "AllowAWSResourceGrants"
      Effect    = "Allow"
      Principal = { AWS = sort(tolist(var.key_user_arns)) }
      Action = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ]
      Resource = "*"
      Condition = {
        Bool = {
          "kms:GrantIsForAWSResource" = true
        }
      }
    }
  ] : statement if length(var.key_user_arns) > 0]

  generated_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.account_policy_statement],
      local.admin_policy_statements,
      local.user_policy_statements
    )
  })
}

resource "aws_kms_key" "this" {
  description                        = var.description
  key_usage                          = "ENCRYPT_DECRYPT"
  customer_master_key_spec           = "SYMMETRIC_DEFAULT"
  multi_region                       = false
  enable_key_rotation                = var.enable_key_rotation
  rotation_period_in_days            = var.enable_key_rotation ? var.rotation_period_in_days : null
  deletion_window_in_days            = var.deletion_window_in_days
  policy                             = var.policy_json != null ? var.policy_json : local.generated_policy_json
  bypass_policy_lockout_safety_check = false
  tags                               = var.tags

  lifecycle {
    precondition {
      condition = var.policy_json == null || (
        length(var.kms_admin_arns) == 0 &&
        length(var.key_user_arns) == 0
      )
      error_message = "policy_json을 지정하면 kms_admin_arns와 key_user_arns는 비워야 합니다."
    }
  }
}

resource "aws_kms_alias" "this" {
  count = var.alias_name == null ? 0 : 1

  name          = var.alias_name
  target_key_id = aws_kms_key.this.key_id
}
