data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

module "alb_security_group" {
  source = "../../modules/security-group"
  name   = "${local.name}-alb"
  vpc_id = module.network.vpc_id
  tags   = local.tags
}

module "ecs_security_group" {
  source = "../../modules/security-group"
  name   = "${local.name}-ecs"
  vpc_id = module.network.vpc_id
  tags   = local.tags
}

module "db_security_group" {
  source = "../../modules/security-group"
  name   = "${local.name}-db"
  vpc_id = module.network.vpc_id
  tags   = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront_to_alb" {
  security_group_id = module.alb_security_group.security_group_id
  description       = "CloudFront origin-facing traffic only"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = module.alb_security_group.security_group_id
  referenced_security_group_id = module.ecs_security_group.security_group_id
  description                  = "API and health checks to Fargate"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_ingress_rule" "alb_to_ecs" {
  security_group_id            = module.ecs_security_group.security_group_id
  referenced_security_group_id = module.alb_security_group.security_group_id
  description                  = "API from internal ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_db" {
  security_group_id            = module.ecs_security_group.security_group_id
  referenced_security_group_id = module.db_security_group.security_group_id
  description                  = "PostgreSQL to database only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "ecs_to_db" {
  security_group_id            = module.db_security_group.security_group_id
  referenced_security_group_id = module.ecs_security_group.security_group_id
  description                  = "PostgreSQL from Fargate only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = module.ecs_security_group.security_group_id
  description       = "External HTTPS APIs and AWS APIs through same-AZ NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
