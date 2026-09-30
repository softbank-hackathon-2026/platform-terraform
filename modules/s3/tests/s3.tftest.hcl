mock_provider "aws" {
  override_during = plan
}

variables {
  bucket_name = "sample-test-data"
}

run "private_bucket_defaults" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket.this.bucket == "sample-test-data" &&
      aws_s3_bucket.this.force_destroy == false &&
      aws_s3_bucket.this.tags["Name"] == "sample-test-data"
    )
    error_message = "버킷 이름, 삭제 보호, Name 태그의 기본값이 올바르지 않습니다."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "버킷의 공개 접근 차단 설정 네 가지가 모두 켜져 있어야 합니다."
  }

  assert {
    condition = (
      length(aws_s3_bucket_versioning.this) == 0 &&
      length(aws_s3_bucket_server_side_encryption_configuration.this) == 0
    )
    error_message = "기본 구성은 버전 관리와 KMS 암호화 설정을 만들지 않아야 합니다."
  }
}

run "versioning_and_kms" {
  command = plan

  variables {
    versioning_enabled = true
    kms_key_arn        = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition = (
      length(aws_s3_bucket_versioning.this) == 1 &&
      aws_s3_bucket_versioning.this[0].versioning_configuration[0].status == "Enabled"
    )
    error_message = "요청한 버전 관리가 활성화되어야 합니다."
  }

  assert {
    condition = (
      length(aws_s3_bucket_server_side_encryption_configuration.this) == 1 &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn &&
      one(aws_s3_bucket_server_side_encryption_configuration.this[0].rule).bucket_key_enabled
    )
    error_message = "요청한 KMS 키와 S3 Bucket Key가 적용되어야 합니다."
  }
}

run "rejects_empty_bucket_name" {
  command = plan

  variables {
    bucket_name = ""
  }

  expect_failures = [var.bucket_name]
}

run "rejects_empty_kms_key" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [var.kms_key_arn]
}
