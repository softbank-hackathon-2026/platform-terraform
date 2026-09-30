mock_provider "aws" {
  override_during = plan
}

variables {
  name = "sample/dev/app"
}

run "repository_defaults" {
  command = plan

  override_resource {
    target          = aws_ecr_repository.this
    override_during = plan
    values = {
      arn            = "arn:aws:ecr:ap-northeast-2:123456789012:repository/sample/dev/app"
      repository_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sample/dev/app"
    }
  }

  assert {
    condition = (
      aws_ecr_repository.this.name == var.name &&
      aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE" &&
      !aws_ecr_repository.this.force_delete &&
      one(aws_ecr_repository.this.encryption_configuration).encryption_type == "AES256" &&
      one(aws_ecr_repository.this.image_scanning_configuration).scan_on_push &&
      length(aws_ecr_lifecycle_policy.this) == 0
    )
    error_message = "기본 저장소의 태그, 암호화, 스캔, 삭제 또는 보존 정책 설정이 올바르지 않습니다."
  }

  assert {
    condition = (
      output.repository_name == var.name &&
      output.repository_arn == "arn:aws:ecr:ap-northeast-2:123456789012:repository/sample/dev/app" &&
      output.repository_url == "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sample/dev/app"
    )
    error_message = "저장소 이름, ARN, URL 출력이 올바르지 않습니다."
  }
}

run "kms_mutable_and_lifecycle_policy" {
  command = plan

  variables {
    image_tag_mutability = "MUTABLE"
    kms_key_arn          = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    scan_on_push         = false
    lifecycle_policy_json = jsonencode({
      rules = [{
        rulePriority = 1
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      }]
    })
    tags = { Environment = "dev" }
  }

  assert {
    condition = (
      aws_ecr_repository.this.image_tag_mutability == "MUTABLE" &&
      one(aws_ecr_repository.this.encryption_configuration).encryption_type == "KMS" &&
      one(aws_ecr_repository.this.encryption_configuration).kms_key == var.kms_key_arn &&
      !one(aws_ecr_repository.this.image_scanning_configuration).scan_on_push &&
      aws_ecr_repository.this.tags["Environment"] == "dev" &&
      length(aws_ecr_lifecycle_policy.this) == 1 &&
      aws_ecr_lifecycle_policy.this[0].repository == var.name &&
      jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 14
    )
    error_message = "선택한 KMS, 태그 변경, 스캔, 태그 또는 보존 정책 설정이 올바르지 않습니다."
  }
}

run "rejects_empty_name" {
  command = plan
  variables { name = " " }
  expect_failures = [var.name]
}

run "rejects_unknown_mutability" {
  command = plan
  variables { image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION" }
  expect_failures = [var.image_tag_mutability]
}

run "rejects_empty_kms_key" {
  command = plan
  variables { kms_key_arn = " " }
  expect_failures = [var.kms_key_arn]
}

run "rejects_invalid_lifecycle_json" {
  command = plan
  variables { lifecycle_policy_json = "{invalid" }
  expect_failures = [var.lifecycle_policy_json]
}
