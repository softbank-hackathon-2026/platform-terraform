locals {
  port = var.port == null ? (var.engine == "aurora-postgresql" ? 5432 : 3306) : var.port
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.cluster_identifier}-subnets" })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = var.cluster_identifier
  engine                              = var.engine
  engine_mode                         = "provisioned"
  engine_version                      = var.engine_version
  engine_lifecycle_support            = var.extended_support_enabled ? "open-source-rds-extended-support" : "open-source-rds-extended-support-disabled"
  database_name                       = var.database_name
  port                                = local.port
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = var.security_group_ids
  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_id
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.secret_kms_key_id
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  backup_retention_period             = var.backup_retention_period
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.cluster_identifier}-final")
  apply_immediately                   = false
  tags                                = merge(var.tags, { Name = var.cluster_identifier })

  lifecycle {
    precondition {
      condition     = !(var.skip_final_snapshot && var.final_snapshot_identifier != null)
      error_message = "skip_final_snapshot이 true이면 final_snapshot_identifier를 지정할 수 없습니다."
    }

    precondition {
      condition     = alltrue([for reader in values(var.readers) : lower(reader.identifier) != lower(var.writer_identifier)])
      error_message = "reader 식별자는 최초 인스턴스 식별자와 달라야 합니다."
    }
  }
}

resource "aws_rds_cluster_instance" "initial_writer" {
  identifier           = var.writer_identifier
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = var.writer_instance_class
  engine               = var.engine
  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  apply_immediately    = false
  tags                 = merge(var.tags, { Name = var.writer_identifier })
}

resource "aws_rds_cluster_instance" "reader" {
  for_each = var.readers

  identifier           = each.value.identifier
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = coalesce(each.value.instance_class, var.writer_instance_class)
  engine               = var.engine
  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  promotion_tier       = each.value.promotion_tier
  apply_immediately    = false
  tags                 = merge(var.tags, { Name = each.value.identifier })

  depends_on = [aws_rds_cluster_instance.initial_writer]
}
