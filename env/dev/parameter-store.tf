resource "aws_ssm_parameter" "database_url" {
  name             = local.database_url_parameter_name
  description      = "백엔드 DATABASE_URL입니다. 운영자가 실제 접속값을 등록합니다."
  type             = "SecureString"
  tier             = "Standard"
  data_type        = "text"
  key_id           = "alias/aws/ssm"
  value_wo         = "NOT_CONFIGURED"
  value_wo_version = 1
  overwrite        = false
  tags             = merge(local.tags, { Name = "${local.name}-ssm-database-url" })

  lifecycle {
    prevent_destroy = true

    # AWS Provider 6.66.0 rewrites the value when these metadata fields change.
    # Keep value ownership with the operator; Terraform only updates tags.
    ignore_changes = [
      value_wo_version,
      allowed_pattern,
      data_type,
      description,
      key_id,
      tier,
      type,
    ]
  }
}
