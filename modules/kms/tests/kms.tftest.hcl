mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }
}

run "key_defaults" {
  command = plan

  override_resource {
    target          = aws_kms_key.this
    override_during = plan
    values = {
      key_id = "12345678-1234-1234-1234-123456789012"
      arn    = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  }

  assert {
    condition = (
      aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT" &&
      aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT" &&
      !aws_kms_key.this.multi_region &&
      aws_kms_key.this.enable_key_rotation &&
      aws_kms_key.this.rotation_period_in_days == 365 &&
      aws_kms_key.this.deletion_window_in_days == 30 &&
      !aws_kms_key.this.bypass_policy_lockout_safety_check &&
      length(aws_kms_alias.this) == 0
    )
    error_message = "기본 키 유형, 회전, 삭제 대기 또는 별칭 설정이 올바르지 않습니다."
  }

  assert {
    condition = (
      length(jsondecode(aws_kms_key.this.policy).Statement) == 1 &&
      jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:root" &&
      jsondecode(aws_kms_key.this.policy).Statement[0].Action == "kms:*"
    )
    error_message = "기본 키 정책에 계정 IAM 권한 위임 문장이 있어야 합니다."
  }

  assert {
    condition = (
      output.key_id == "12345678-1234-1234-1234-123456789012" &&
      output.key_arn == "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012" &&
      output.alias_name == null &&
      output.alias_arn == null
    )
    error_message = "기본 키 또는 별칭 출력이 올바르지 않습니다."
  }
}

run "admin_user_and_service_grant" {
  command = plan

  variables {
    kms_admin_arns = ["arn:aws:iam::123456789012:role/KmsAdmin"]
    key_user_arns  = ["arn:aws:iam::123456789012:role/AppRole"]
  }

  assert {
    condition = (
      length(jsondecode(aws_kms_key.this.policy).Statement) == 4 &&
      jsondecode(aws_kms_key.this.policy).Statement[1].Principal.AWS[0] == "arn:aws:iam::123456789012:role/KmsAdmin" &&
      contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:Put*") &&
      !contains(jsondecode(aws_kms_key.this.policy).Statement[1].Action, "kms:Encrypt") &&
      jsondecode(aws_kms_key.this.policy).Statement[2].Principal.AWS[0] == "arn:aws:iam::123456789012:role/AppRole" &&
      contains(jsondecode(aws_kms_key.this.policy).Statement[2].Action, "kms:Decrypt") &&
      jsondecode(aws_kms_key.this.policy).Statement[3].Condition.Bool["kms:GrantIsForAWSResource"] == true
    )
    error_message = "관리자, 사용자 또는 AWS 서비스용 조건부 Grant 정책이 올바르지 않습니다."
  }
}

run "custom_policy_and_alias" {
  command = plan

  variables {
    alias_name  = "alias/dev/app"
    description = "Application encryption"
    policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "ExplicitAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::123456789012:role/CustomAdmin" }
        Action    = "kms:*"
        Resource  = "*"
      }]
    })
    enable_key_rotation     = false
    deletion_window_in_days = 14
    tags = {
      Environment = "dev"
    }
  }

  override_resource {
    target          = aws_kms_key.this
    override_during = plan
    values = {
      key_id = "12345678-1234-1234-1234-123456789012"
    }
  }

  override_resource {
    target          = aws_kms_alias.this[0]
    override_during = plan
    values = {
      arn = "arn:aws:kms:ap-northeast-2:123456789012:alias/dev/app"
    }
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.this.policy).Statement[0].Sid == "ExplicitAdmin" &&
      length(jsondecode(aws_kms_key.this.policy).Statement) == 1 &&
      !aws_kms_key.this.enable_key_rotation &&
      aws_kms_key.this.deletion_window_in_days == 14 &&
      aws_kms_key.this.description == "Application encryption" &&
      aws_kms_key.this.tags["Environment"] == "dev" &&
      length(aws_kms_alias.this) == 1 &&
      aws_kms_alias.this[0].target_key_id == aws_kms_key.this.key_id &&
      output.alias_name == "alias/dev/app" &&
      output.alias_arn == "arn:aws:kms:ap-northeast-2:123456789012:alias/dev/app"
    )
    error_message = "사용자 정책, 별칭 또는 선택적 키 설정이 올바르지 않습니다."
  }
}

run "rejects_reserved_alias" {
  command = plan
  variables {
    alias_name = "alias/aws/example"
  }
  expect_failures = [var.alias_name]
}

run "rejects_invalid_policy_json" {
  command = plan
  variables {
    policy_json = "{invalid"
  }
  expect_failures = [var.policy_json]
}

run "rejects_custom_policy_with_admin_list" {
  command = plan
  variables {
    policy_json    = jsonencode({ Version = "2012-10-17", Statement = [] })
    kms_admin_arns = ["arn:aws:iam::123456789012:role/KmsAdmin"]
  }
  expect_failures = [aws_kms_key.this]
}

run "rejects_invalid_admin_arn" {
  command = plan
  variables {
    kms_admin_arns = ["arn:aws:iam::123456789012:group/Admins"]
  }
  expect_failures = [var.kms_admin_arns]
}

run "rejects_invalid_user_arn" {
  command = plan
  variables {
    key_user_arns = [" "]
  }
  expect_failures = [var.key_user_arns]
}

run "rejects_rotation_period" {
  command = plan
  variables {
    rotation_period_in_days = 89
  }
  expect_failures = [var.rotation_period_in_days]
}

run "rejects_deletion_window" {
  command = plan
  variables {
    deletion_window_in_days = 31
  }
  expect_failures = [var.deletion_window_in_days]
}
