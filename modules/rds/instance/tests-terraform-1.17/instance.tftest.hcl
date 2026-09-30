mock_provider "aws" {
  override_during = plan

  mock_ephemeral "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"dbadmin\",\"password\":\"test-only-password\"}"
    }
  }
}

variables {
  identifier         = "sample-db"
  engine             = "postgres"
  engine_version     = "16.4"
  instance_class     = "db.t4g.medium"
  allocated_storage  = 100
  master_username    = "dbadmin"
  subnet_ids         = ["subnet-11111111111111111", "subnet-22222222222222222"]
  security_group_ids = ["sg-11111111111111111"]
}

run "postgres_defaults" {
  command = plan

  override_resource {
    target          = aws_db_instance.primary
    override_during = plan
    values = {
      arn         = "arn:aws:rds:ap-northeast-2:123456789012:db:sample-db"
      resource_id = "db-ABCDEFGHIJKL01234"
      address     = "sample-db.example.rds.amazonaws.com"
      port        = 5432
      master_user_secret = [{
        secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-db"
      }]
    }
  }

  assert {
    condition = (
      aws_db_subnet_group.this.subnet_ids == toset(var.subnet_ids) &&
      aws_db_instance.primary.engine == "postgres" &&
      aws_db_instance.primary.port == 5432 &&
      aws_db_instance.primary.storage_type == "gp3" &&
      aws_db_instance.primary.storage_encrypted &&
      !aws_db_instance.primary.publicly_accessible &&
      aws_db_instance.primary.manage_master_user_password &&
      !aws_db_instance.primary.iam_database_authentication_enabled &&
      aws_db_instance.primary.backup_retention_period == 7 &&
      aws_db_instance.primary.deletion_protection &&
      !aws_db_instance.primary.skip_final_snapshot &&
      aws_db_instance.primary.final_snapshot_identifier == "sample-db-final" &&
      !aws_db_instance.primary.multi_az &&
      length(aws_secretsmanager_secret.master) == 0 &&
      length(aws_secretsmanager_secret_version.master) == 0 &&
      length(aws_db_instance.replica) == 0
    )
    error_message = "기본 PostgreSQL DB의 비공개, 암호화, Secret, 백업, 삭제 정책 또는 복제본 수가 올바르지 않습니다."
  }

  assert {
    condition = (
      output.db_instance_id == "sample-db" &&
      output.db_resource_id == "db-ABCDEFGHIJKL01234" &&
      output.writer_address == "sample-db.example.rds.amazonaws.com" &&
      output.master_secret_arn == "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-db" &&
      output.read_replica_ids == {} &&
      output.read_replica_resource_ids == {} &&
      output.read_replica_addresses == {}
    )
    error_message = "기본 DB의 접속 정보, IAM Resource ID 또는 빈 복제본 출력이 올바르지 않습니다."
  }
}

run "replicas_multi_az_and_iam" {
  command = plan

  variables {
    master_password_mode                = "module_managed_secret"
    multi_az                            = true
    iam_database_authentication_enabled = true
    kms_key_id                          = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    secret_kms_key_id                   = "arn:aws:kms:ap-northeast-2:123456789012:key/22345678-1234-1234-1234-123456789012"
    read_replicas = {
      reporting = { identifier = "sample-db-reporting" }
      analytics = { identifier = "sample-db-analytics", instance_class = "db.t4g.large", deletion_protection = false }
    }
  }

  override_resource {
    target          = aws_db_instance.primary
    override_during = plan
    values = {
      arn = "arn:aws:rds:ap-northeast-2:123456789012:db:sample-db"
    }
  }

  override_resource {
    target          = aws_secretsmanager_secret.master[0]
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-db-master"
    }
  }

  assert {
    condition = (
      aws_db_instance.primary.multi_az &&
      aws_db_instance.primary.iam_database_authentication_enabled &&
      aws_db_instance.primary.manage_master_user_password == null &&
      aws_db_instance.primary.kms_key_id == var.kms_key_id &&
      length(aws_secretsmanager_secret.master) == 1 &&
      aws_secretsmanager_secret.master[0].kms_key_id == var.secret_kms_key_id &&
      aws_secretsmanager_secret.master[0].name == "sample-db-master" &&
      length(aws_secretsmanager_secret_version.master) == 1 &&
      aws_secretsmanager_secret_version.master[0].secret_string_wo_version == parseint(substr(sha256(var.master_username), 0, 15), 16) &&
      length(aws_db_instance.replica) == 2 &&
      aws_db_instance.replica["reporting"].instance_class == "db.t4g.medium" &&
      aws_db_instance.replica["reporting"].deletion_protection &&
      aws_db_instance.replica["analytics"].instance_class == "db.t4g.large" &&
      !aws_db_instance.replica["analytics"].deletion_protection &&
      alltrue([for replica in values(aws_db_instance.replica) :
        replica.replicate_source_db == aws_db_instance.primary.arn &&
        replica.iam_database_authentication_enabled &&
        !replica.publicly_accessible &&
        replica.skip_final_snapshot
      ]) &&
      toset(keys(output.read_replica_resource_ids)) == toset(["reporting", "analytics"]) &&
      output.read_replica_ids["reporting"] == "sample-db-reporting" &&
      output.read_replica_ids["analytics"] == "sample-db-analytics" &&
      output.master_secret_arn == "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-db-master"
    )
    error_message = "Multi-AZ, IAM 인증, KMS 또는 두 Read Replica의 구성이 올바르지 않습니다."
  }
}

run "module_secret_without_replicas" {
  command = plan

  variables {
    master_password_mode = "module_managed_secret"
  }

  assert {
    condition = (
      length(aws_secretsmanager_secret.master) == 1 &&
      length(aws_secretsmanager_secret_version.master) == 1 &&
      aws_db_instance.primary.manage_master_user_password == null &&
      aws_db_instance.primary.password_wo_version != null &&
      length(aws_db_instance.replica) == 0
    )
    error_message = "복제본이 없어도 모듈 소유 Secret 모드를 선택할 수 있어야 합니다."
  }
}

run "module_secret_tracks_master_username" {
  command = plan

  variables {
    master_username      = "otheradmin"
    master_password_mode = "module_managed_secret"
  }

  assert {
    condition = (
      aws_db_instance.primary.username == "otheradmin" &&
      aws_secretsmanager_secret_version.master[0].secret_string_wo_version == parseint(substr(sha256("otheradmin"), 0, 15), 16) &&
      aws_secretsmanager_secret_version.master[0].secret_string_wo_version != parseint(substr(sha256("dbadmin"), 0, 15), 16)
    )
    error_message = "관리자 사용자 이름이 바뀌면 Secret Version 갱신도 계획돼야 합니다."
  }
}

run "mysql_replica_with_module_secret" {
  command = plan

  variables {
    engine               = "mysql"
    engine_version       = "8.0.40"
    master_password_mode = "module_managed_secret"
    read_replicas = {
      reporting = { identifier = "sample-db-reporting" }
    }
  }

  override_resource {
    target          = aws_db_instance.primary
    override_during = plan
    values = {
      arn = "arn:aws:rds:ap-northeast-2:123456789012:db:sample-db"
    }
  }

  assert {
    condition = (
      aws_db_instance.primary.engine == "mysql" &&
      aws_db_instance.primary.port == 3306 &&
      aws_db_instance.primary.manage_master_user_password == null &&
      length(aws_secretsmanager_secret.master) == 1 &&
      length(aws_db_instance.replica) == 1 &&
      aws_db_instance.replica["reporting"].replicate_source_db == aws_db_instance.primary.arn
    )
    error_message = "MySQL Read Replica는 모듈 소유 관리자 Secret 모드에서 생성돼야 합니다."
  }
}

run "rejects_replicas_with_rds_managed_password" {
  command = plan

  variables {
    read_replicas = {
      reporting = { identifier = "sample-db-reporting" }
    }
  }

  expect_failures = [aws_db_instance.primary]
}

run "rejects_invalid_master_password_mode" {
  command = plan

  variables {
    master_password_mode = "unknown"
  }

  expect_failures = [var.master_password_mode]
}

run "mysql_and_extended_support" {
  command = plan

  variables {
    engine                   = "mysql"
    engine_version           = "8.0.40"
    extended_support_enabled = true
    skip_final_snapshot      = true
    secret_kms_key_id        = "arn:aws:kms:ap-northeast-2:123456789012:key/22345678-1234-1234-1234-123456789012"
  }

  assert {
    condition = (
      aws_db_instance.primary.port == 3306 &&
      aws_db_instance.primary.engine_lifecycle_support == "open-source-rds-extended-support" &&
      aws_db_instance.primary.skip_final_snapshot &&
      aws_db_instance.primary.final_snapshot_identifier == null &&
      aws_db_instance.primary.master_user_secret_kms_key_id == var.secret_kms_key_id
    )
    error_message = "MySQL 기본 포트, Extended Support 또는 최종 스냅샷 옵션이 올바르지 않습니다."
  }
}

run "rejects_invalid_engine" {
  command = plan
  variables { engine = "mariadb" }
  expect_failures = [var.engine]
}

run "rejects_invalid_identifier" {
  command = plan
  variables { identifier = "bad--db" }
  expect_failures = [var.identifier]
}

run "rejects_empty_security_groups" {
  command = plan
  variables { security_group_ids = [] }
  expect_failures = [var.security_group_ids]
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

run "rejects_duplicate_replica_identifiers" {
  command = plan
  variables {
    master_password_mode = "module_managed_secret"
    read_replicas = {
      first  = { identifier = "sample-replica" }
      second = { identifier = "SAMPLE-REPLICA" }
    }
  }
  expect_failures = [var.read_replicas]
}

run "rejects_primary_replica_identifier_collision" {
  command = plan
  variables {
    master_password_mode = "module_managed_secret"
    read_replicas        = { copy = { identifier = "SAMPLE-DB" } }
  }
  expect_failures = [aws_db_instance.primary]
}

run "rejects_final_snapshot_conflict" {
  command = plan
  variables {
    skip_final_snapshot       = true
    final_snapshot_identifier = "sample-db-backup"
  }
  expect_failures = [aws_db_instance.primary]
}
