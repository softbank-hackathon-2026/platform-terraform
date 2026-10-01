output "network" {
  description = "VPC, 계층별 Subnet과 NAT 식별 정보입니다."
  value = {
    vpc_id            = module.network.vpc_id
    public_subnet_ids = module.network.public_subnet_ids
    app_subnet_ids    = local.app_subnet_ids
    db_subnet_ids     = local.db_subnet_ids
    nat_gateway_ids   = module.network.nat_gateway_ids_by_az
  }
}

output "frontend" {
  description = "프론트엔드 버킷과 CloudFront HTTPS 주소입니다."
  value = {
    bucket_name     = module.frontend.bucket_name
    distribution_id = module.cloudfront.distribution_id
    url             = module.cloudfront.url
  }
}

output "backend" {
  description = "CI/CD가 Task Definition과 Service를 생성하는 데 필요한 ECR, ECS, ALB와 IAM 식별 정보입니다."
  value = {
    ecr_repository_url    = module.ecr.repository_url
    cluster_name          = module.ecs.cluster_name
    cluster_arn           = module.ecs.cluster_arn
    log_group_name        = module.ecs.log_group_name
    alb_arn               = module.alb.load_balancer_arn
    alb_dns_name          = module.alb.dns_name
    target_group_arn      = module.alb.target_group_arns["api"]
    ecs_security_group_id = module.ecs_security_group.security_group_id
    execution_role_arn    = module.execution_role.role_arn
    task_role_arn         = module.task_role.role_arn
    container_name        = "app"
    container_port        = var.container_port
  }
}

output "database" {
  description = "PostgreSQL 접속 주소, 관리자 Secret ARN과 앱 DATABASE_URL Parameter ARN입니다. 비밀값은 출력하지 않습니다."
  value = {
    identifier                 = module.database.db_instance_id
    address                    = module.database.writer_address
    port                       = module.database.port
    name                       = var.db_name
    master_secret_arn          = module.database.master_secret_arn
    database_url_parameter_arn = local.database_url_parameter_arn
  }
}
