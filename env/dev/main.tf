data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name = "sbh-platform-dev"
  tags = merge(var.tags, {
    Project     = "SBH"
    Scope       = "platform"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "정호원"
  })
  app_subnet_ids = [module.network.private_subnet_ids["app_a"], module.network.private_subnet_ids["app_c"]]
  db_subnet_ids  = [module.network.private_subnet_ids["db_a"], module.network.private_subnet_ids["db_c"]]
}

module "network" {
  source = "../../modules/network"

  name             = local.name
  vpc_cidr         = var.vpc_cidr
  nat_gateway_mode = "regional"
  private_subnets = {
    app_a = { availability_zone = "ap-northeast-2a", cidr_block = cidrsubnet(var.vpc_cidr, 8, 10) }
    app_c = { availability_zone = "ap-northeast-2c", cidr_block = cidrsubnet(var.vpc_cidr, 8, 11) }
    db_a  = { availability_zone = "ap-northeast-2a", cidr_block = cidrsubnet(var.vpc_cidr, 8, 20), enable_nat_route = false }
    db_c  = { availability_zone = "ap-northeast-2c", cidr_block = cidrsubnet(var.vpc_cidr, 8, 21), enable_nat_route = false }
  }
  tags = local.tags
}

module "frontend" {
  source = "../../modules/s3"

  bucket_name        = "${local.name}-s3-web-${data.aws_caller_identity.current.account_id}"
  versioning_enabled = true
  tags               = local.tags
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "${local.name}-ecr-api"
  tags   = local.tags
}

module "alb" {
  source = "../../modules/alb"

  name               = "${local.name}-alb-api"
  internal           = true
  vpc_id             = module.network.vpc_id
  subnet_ids         = local.app_subnet_ids
  security_group_ids = [module.alb_security_group.security_group_id]
  target_groups = {
    api = {
      name              = "${local.name}-tg-api"
      target_type       = "ip"
      protocol          = "HTTP"
      port              = var.container_port
      health_check_path = var.health_check_path
    }
  }
  listeners = {
    http = {
      port           = 80
      protocol       = "HTTP"
      default_action = { type = "forward", target_group_key = "api" }
    }
  }
  tags = local.tags
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name                  = local.name
  s3_origin_domain_name = module.frontend.bucket_regional_domain_name
  alb_arn               = module.alb.load_balancer_arn
  alb_dns_name          = module.alb.dns_name
  tags                  = local.tags

  depends_on = [module.network, module.alb, aws_vpc_security_group_ingress_rule.cloudfront_to_alb]
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = module.frontend.bucket_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontDistribution"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.frontend.bucket_arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = module.cloudfront.distribution_arn } }
    }]
  })
}

module "database" {
  source = "../../modules/rds/instance"

  identifier              = "${local.name}-rds-postgres"
  engine                  = "postgres"
  engine_version          = var.postgres_engine_version
  instance_class          = var.postgres_instance_class
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = var.db_name
  port                    = 5432
  subnet_ids              = local.db_subnet_ids
  security_group_ids      = [module.db_security_group.security_group_id]
  master_username         = "dbadmin"
  master_password_mode    = "rds_managed"
  multi_az                = true
  read_replicas           = {}
  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false
  tags                    = local.tags
}

resource "aws_secretsmanager_secret" "app_database" {
  name                    = "${local.name}-secret-db-app"
  description             = "Application PostgreSQL credentials: username and password JSON keys, provisioned outside Terraform"
  recovery_window_in_days = 30
  tags                    = merge(local.tags, { Name = "${local.name}-secret-db-app" })
}

module "ecs" {
  source = "../../modules/ecs"

  name               = "${local.name}-ecs-api"
  log_group_name     = "${local.name}-log-api"
  log_region         = "ap-northeast-2"
  log_retention_days = 30
  service = var.backend_image_digest == null ? null : {
    image              = "${module.ecr.repository_url}@${var.backend_image_digest}"
    container_port     = var.container_port
    cpu                = 512
    memory             = 1024
    desired_count      = 2
    subnet_ids         = local.app_subnet_ids
    security_group_ids = [module.ecs_security_group.security_group_id]
    target_group_arn   = module.alb.target_group_arns["api"]
    execution_role_arn = module.execution_role.role_arn
    task_role_arn      = module.task_role.role_arn
    environment = {
      DB_HOST    = module.database.writer_address
      DB_PORT    = tostring(module.database.port)
      DB_NAME    = var.db_name
      DB_SSLMODE = "verify-full"
    }
    secrets = {
      DB_USERNAME = "${aws_secretsmanager_secret.app_database.arn}:username::"
      DB_PASSWORD = "${aws_secretsmanager_secret.app_database.arn}:password::"
    }
  }
  tags = local.tags

  depends_on = [
    module.alb,
    module.execution_role,
    aws_vpc_security_group_ingress_rule.alb_to_ecs,
    aws_vpc_security_group_ingress_rule.ecs_to_db,
    aws_vpc_security_group_egress_rule.alb_to_ecs,
    aws_vpc_security_group_egress_rule.ecs_to_db,
    aws_vpc_security_group_egress_rule.ecs_https,
    module.network,
  ]
}
