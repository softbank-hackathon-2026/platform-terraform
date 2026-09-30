mock_provider "aws" {
  override_during = plan
}

variables {
  cluster_identifier    = "sample-aurora"
  writer_identifier     = "sample-aurora-one"
  engine                = "aurora-postgresql"
  engine_version        = "16.4"
  writer_instance_class = "db.r6g.large"
  master_username       = "dbadmin"
  subnet_ids            = ["subnet-11111111111111111", "subnet-22222222222222222"]
  security_group_ids    = ["sg-11111111111111111"]
}

run "postgres_defaults" {
  command = plan

  override_resource {
    target          = aws_rds_cluster.this
    override_during = plan
    values = {
      cluster_resource_id = "cluster-ABCDEFGHIJKL01234"
      endpoint            = "sample-aurora.cluster-example.rds.amazonaws.com"
      reader_endpoint     = "sample-aurora.cluster-ro-example.rds.amazonaws.com"
      port                = 5432
      master_user_secret = [{
        secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-aurora"
      }]
    }
  }

  assert {
    condition = (
      aws_db_subnet_group.this.subnet_ids == toset(var.subnet_ids) &&
      aws_rds_cluster.this.engine == "aurora-postgresql" &&
      aws_rds_cluster.this.engine_mode == "provisioned" &&
      aws_rds_cluster.this.port == 5432 &&
      aws_rds_cluster.this.storage_encrypted &&
      aws_rds_cluster.this.manage_master_user_password &&
      !aws_rds_cluster.this.iam_database_authentication_enabled &&
      aws_rds_cluster.this.backup_retention_period == 7 &&
      aws_rds_cluster.this.deletion_protection &&
      !aws_rds_cluster.this.skip_final_snapshot &&
      aws_rds_cluster.this.final_snapshot_identifier == "sample-aurora-final" &&
      !aws_rds_cluster_instance.initial_writer.publicly_accessible &&
      length(aws_rds_cluster_instance.reader) == 0
    )
    error_message = "기본 Aurora 클러스터의 Provisioned, 암호화, Secret, 백업, 삭제 또는 writer 정책이 올바르지 않습니다."
  }

  assert {
    condition = (
      output.cluster_resource_id == "cluster-ABCDEFGHIJKL01234" &&
      output.writer_endpoint == "sample-aurora.cluster-example.rds.amazonaws.com" &&
      output.master_secret_arn == "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-aurora" &&
      output.reader_endpoint == null &&
      output.reader_addresses == {}
    )
    error_message = "기본 클러스터의 접속 정보, IAM Resource ID 또는 빈 reader 출력이 올바르지 않습니다."
  }
}

run "readers_iam_and_kms" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
    kms_key_id                          = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    secret_kms_key_id                   = "arn:aws:kms:ap-northeast-2:123456789012:key/22345678-1234-1234-1234-123456789012"
    readers = {
      reporting = { identifier = "sample-aurora-reporting" }
      analytics = { identifier = "sample-aurora-analytics", instance_class = "db.r6g.xlarge", promotion_tier = 0 }
    }
  }

  override_resource {
    target          = aws_rds_cluster.this
    override_during = plan
    values = {
      reader_endpoint = "sample-aurora.cluster-ro-example.rds.amazonaws.com"
    }
  }

  assert {
    condition = (
      aws_rds_cluster.this.iam_database_authentication_enabled &&
      aws_rds_cluster.this.manage_master_user_password &&
      aws_rds_cluster.this.kms_key_id == var.kms_key_id &&
      aws_rds_cluster.this.master_user_secret_kms_key_id == var.secret_kms_key_id &&
      length(aws_rds_cluster_instance.reader) == 2 &&
      aws_rds_cluster_instance.reader["reporting"].instance_class == "db.r6g.large" &&
      aws_rds_cluster_instance.reader["reporting"].promotion_tier == 1 &&
      aws_rds_cluster_instance.reader["analytics"].instance_class == "db.r6g.xlarge" &&
      aws_rds_cluster_instance.reader["analytics"].promotion_tier == 0 &&
      alltrue([for reader in values(aws_rds_cluster_instance.reader) :
        reader.cluster_identifier == aws_rds_cluster.this.id &&
        reader.db_subnet_group_name == aws_db_subnet_group.this.name &&
        !reader.publicly_accessible
      ]) &&
      output.reader_endpoint == "sample-aurora.cluster-ro-example.rds.amazonaws.com" &&
      toset(keys(output.reader_addresses)) == toset(["reporting", "analytics"])
    )
    error_message = "IAM, KMS, reader 추가, 우선순위 또는 endpoint 출력이 올바르지 않습니다."
  }
}

run "mysql_and_delete_options" {
  command = plan

  variables {
    engine                   = "aurora-mysql"
    engine_version           = "8.0.mysql_aurora.3.06.0"
    extended_support_enabled = true
    skip_final_snapshot      = true
    deletion_protection      = false
  }

  assert {
    condition = (
      aws_rds_cluster.this.port == 3306 &&
      aws_rds_cluster.this.engine_lifecycle_support == "open-source-rds-extended-support" &&
      aws_rds_cluster.this.skip_final_snapshot &&
      aws_rds_cluster.this.final_snapshot_identifier == null &&
      !aws_rds_cluster.this.deletion_protection
    )
    error_message = "MySQL 기본 포트, Extended Support 또는 삭제 옵션이 올바르지 않습니다."
  }
}

run "rejects_invalid_engine" {
  command = plan
  variables { engine = "postgres" }
  expect_failures = [var.engine]
}

run "rejects_invalid_cluster_identifier" {
  command = plan
  variables { cluster_identifier = "bad--cluster" }
  expect_failures = [var.cluster_identifier]
}

run "rejects_empty_security_groups" {
  command = plan
  variables { security_group_ids = [] }
  expect_failures = [var.security_group_ids]
}

run "rejects_serverless_writer" {
  command = plan
  variables { writer_instance_class = "db.serverless" }
  expect_failures = [var.writer_instance_class]
}

run "rejects_serverless_reader" {
  command = plan
  variables { readers = { one = { identifier = "sample-reader", instance_class = "db.serverless" } } }
  expect_failures = [var.readers]
}

run "rejects_duplicate_subnets" {
  command = plan
  variables { subnet_ids = ["subnet-11111111111111111", "subnet-11111111111111111"] }
  expect_failures = [var.subnet_ids]
}

run "rejects_invalid_backup_period" {
  command = plan
  variables { backup_retention_period = 0 }
  expect_failures = [var.backup_retention_period]
}

run "rejects_duplicate_reader_identifiers" {
  command = plan
  variables {
    readers = {
      first  = { identifier = "sample-reader" }
      second = { identifier = "SAMPLE-READER" }
    }
  }
  expect_failures = [var.readers]
}

run "rejects_writer_reader_identifier_collision" {
  command = plan
  variables { readers = { copy = { identifier = "SAMPLE-AURORA-ONE" } } }
  expect_failures = [aws_rds_cluster.this]
}

run "rejects_invalid_promotion_tier" {
  command = plan
  variables { readers = { one = { identifier = "sample-reader", promotion_tier = 16 } } }
  expect_failures = [var.readers]
}

run "rejects_final_snapshot_conflict" {
  command = plan
  variables {
    skip_final_snapshot       = true
    final_snapshot_identifier = "sample-aurora-backup"
  }
  expect_failures = [aws_rds_cluster.this]
}
