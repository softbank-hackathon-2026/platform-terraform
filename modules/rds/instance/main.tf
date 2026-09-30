locals {
  port                  = var.port == null ? (var.engine == "postgres" ? 5432 : 3306) : var.port
  module_managed_secret = var.master_password_mode == "module_managed_secret"
  master_password       = local.module_managed_secret ? jsondecode(ephemeral.aws_secretsmanager_secret_version.master[0].secret_string).password : null
  master_password_version = local.module_managed_secret ? parseint(
    substr(sha256(aws_secretsmanager_secret_version.master[0].version_id), 0, 15),
    16
  ) : null
}

ephemeral "random_password" "master" {
  count = local.module_managed_secret ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "aws_secretsmanager_secret" "master" {
  count = local.module_managed_secret ? 1 : 0

  name       = "${var.identifier}-master"
  kms_key_id = var.secret_kms_key_id
  tags       = merge(var.tags, { Name = "${var.identifier}-master" })
}

resource "aws_secretsmanager_secret_version" "master" {
  count = local.module_managed_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.master[0].id
  secret_string_wo = jsonencode({
    username = var.master_username
    password = ephemeral.random_password.master[0].result
  })
  secret_string_wo_version = parseint(substr(sha256(var.master_username), 0, 15), 16)
}

ephemeral "aws_secretsmanager_secret_version" "master" {
  count = local.module_managed_secret ? 1 : 0

  secret_id  = aws_secretsmanager_secret.master[0].id
  version_id = aws_secretsmanager_secret_version.master[0].version_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.identifier}-subnets" })
}

resource "aws_db_instance" "primary" {
  identifier                          = var.identifier
  engine                              = var.engine
  engine_version                      = var.engine_version
  engine_lifecycle_support            = var.extended_support_enabled ? "open-source-rds-extended-support" : "open-source-rds-extended-support-disabled"
  instance_class                      = var.instance_class
  allocated_storage                   = var.allocated_storage
  storage_type                        = var.storage_type
  db_name                             = var.db_name
  port                                = local.port
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = var.security_group_ids
  publicly_accessible                 = false
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_id
  username                            = var.master_username
  manage_master_user_password         = local.module_managed_secret ? null : true
  master_user_secret_kms_key_id       = local.module_managed_secret ? null : var.secret_kms_key_id
  password_wo                         = local.master_password
  password_wo_version                 = local.master_password_version
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  backup_retention_period             = var.backup_retention_period
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.identifier}-final")
  multi_az                            = var.multi_az
  apply_immediately                   = false
  tags                                = merge(var.tags, { Name = var.identifier })

  lifecycle {
    precondition {
      condition     = local.module_managed_secret || length(var.read_replicas) == 0
      error_message = "Read Replica를 사용하려면 master_password_mode를 module_managed_secret으로 설정해야 합니다."
    }

    precondition {
      condition     = !(var.skip_final_snapshot && var.final_snapshot_identifier != null)
      error_message = "skip_final_snapshot이 true이면 final_snapshot_identifier를 지정할 수 없습니다."
    }

    precondition {
      condition     = alltrue([for replica in values(var.read_replicas) : lower(replica.identifier) != lower(var.identifier)])
      error_message = "Read Replica 식별자는 기본 DB 식별자와 달라야 합니다."
    }
  }
}

resource "aws_db_instance" "replica" {
  for_each = var.read_replicas

  identifier                          = each.value.identifier
  instance_class                      = coalesce(each.value.instance_class, var.instance_class)
  replicate_source_db                 = aws_db_instance.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = var.security_group_ids
  publicly_accessible                 = false
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  deletion_protection                 = each.value.deletion_protection
  skip_final_snapshot                 = true
  apply_immediately                   = false
  tags                                = merge(var.tags, { Name = each.value.identifier })
}
