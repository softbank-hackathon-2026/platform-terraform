mock_provider "aws" {
  override_during = plan
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2" }
  }
  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-cloudfront" }
  }
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-platform" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      id                          = "sbh-platform-dev-s3-web-123456789012"
      arn                         = "arn:aws:s3:::sbh-platform-dev-s3-web-123456789012"
      bucket_regional_domain_name = "sbh-platform-dev-s3-web-123456789012.s3.ap-northeast-2.amazonaws.com"
    }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:ap-northeast-2:123456789012:repository/sbh-platform-dev-ecr-api"
      repository_url = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sbh-platform-dev-ecr-api"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/sbh-platform-dev-policy-ecs-execution" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:ap-northeast-2:123456789012:cluster/sbh-platform-dev-ecs-api" }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:function/sbh-platform-dev-cloudfront-spa" }
  }
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/ETESTPLATFORM"
      domain_name = "test-platform.cloudfront.net"
    }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address = "platform-postgres.internal"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds-master-AbCdEf"
        secret_status = "active"
        kms_key_id    = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
      }]
    }
  }
}

mock_provider "random" {
  override_during = plan
}

override_resource {
  target          = module.network.aws_subnet.private["app_a"]
  override_during = plan
  values          = { id = "subnet-app-a" }
}
override_resource {
  target          = module.network.aws_subnet.private["app_c"]
  override_during = plan
  values          = { id = "subnet-app-c" }
}
override_resource {
  target          = module.network.aws_subnet.private["db_a"]
  override_during = plan
  values          = { id = "subnet-db-a" }
}
override_resource {
  target          = module.network.aws_subnet.private["db_c"]
  override_during = plan
  values          = { id = "subnet-db-c" }
}
override_resource {
  target          = module.network.aws_nat_gateway.regional[0]
  override_during = plan
  values          = { id = "nat-regional" }
}
override_resource {
  target          = module.alb_security_group.aws_security_group.this
  override_during = plan
  values          = { id = "sg-alb" }
}
override_resource {
  target          = module.ecs_security_group.aws_security_group.this
  override_during = plan
  values          = { id = "sg-ecs" }
}
override_resource {
  target          = module.db_security_group.aws_security_group.this
  override_during = plan
  values          = { id = "sg-db" }
}
override_resource {
  target          = module.execution_role.aws_iam_role.this
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/sbh-platform-dev-role-ecs-execution" }
}
override_resource {
  target          = module.task_role.aws_iam_role.this
  override_during = plan
  values          = { arn = "arn:aws:iam::123456789012:role/sbh-platform-dev-role-ecs-task" }
}
override_resource {
  target          = module.alb.aws_lb.this
  override_during = plan
  values = {
    arn      = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/sbh-platform-dev-alb-api/1234567890123456"
    dns_name = "internal-platform.ap-northeast-2.elb.amazonaws.com"
  }
}
override_resource {
  target          = module.alb.aws_lb_target_group.this["api"]
  override_during = plan
  values          = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sbh-platform-dev-tg-api/1234567890123456" }
}

run "infrastructure_only" {
  command = plan

  assert {
    condition = (
      length(output.network.public_subnet_ids) == 0 &&
      output.network.app_subnet_ids == ["subnet-app-a", "subnet-app-c"] &&
      output.network.db_subnet_ids == ["subnet-db-a", "subnet-db-c"] &&
      output.network.nat_gateway_ids == {
        "ap-northeast-2a" = "nat-regional"
        "ap-northeast-2c" = "nat-regional"
      } &&
      output.backend.cluster_name == "sbh-platform-dev-ecs-api" &&
      output.backend.ecs_security_group_id == "sg-ecs" &&
      output.backend.target_group_arn == module.alb.target_group_arns["api"] &&
      output.backend.container_name == "app" && output.backend.container_port == 8000 &&
      output.database.database_url_parameter_arn == "arn:aws:ssm:ap-northeast-2:123456789012:parameter/sbh/platform/demo/backend/DATABASE_URL" &&
      output.database.master_secret_arn != null
    )
    error_message = "Private App/DB 계층, Regional NAT, CI/CD 인프라 출력과 SSM Parameter ARN이 필요합니다."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.cloudfront_to_alb.prefix_list_id == "pl-cloudfront" &&
      aws_vpc_security_group_ingress_rule.cloudfront_to_alb.from_port == 80 &&
      aws_vpc_security_group_ingress_rule.alb_to_ecs.referenced_security_group_id == "sg-alb" &&
      aws_vpc_security_group_ingress_rule.alb_to_ecs.from_port == 8000 &&
      aws_vpc_security_group_ingress_rule.ecs_to_db.referenced_security_group_id == "sg-ecs" &&
      aws_vpc_security_group_ingress_rule.ecs_to_db.from_port == 5432 &&
      aws_vpc_security_group_egress_rule.ecs_https.from_port == 443 &&
      aws_vpc_security_group_egress_rule.ecs_https.to_port == 443 &&
      output.backend.execution_role_arn != output.backend.task_role_arn &&
      jsondecode(aws_s3_bucket_policy.frontend.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == module.cloudfront.distribution_arn
    )
    error_message = "CloudFront -> ALB -> ECS -> RDS 접근 제한, HTTPS 송신과 S3 배포 ARN 제한을 확인해야 합니다."
  }
}

run "custom_port_handoff" {
  command = plan
  variables {
    container_port    = 9090
    health_check_path = "/api/ready"
  }
  assert {
    condition = (
      output.backend.container_port == 9090 &&
      module.alb.target_group_arns["api"] == output.backend.target_group_arn &&
      aws_vpc_security_group_ingress_rule.alb_to_ecs.from_port == 9090 &&
      aws_vpc_security_group_egress_rule.alb_to_ecs.to_port == 9090
    )
    error_message = "CI/CD에 전달하는 포트와 ALB, 보안 그룹 포트가 일치해야 합니다."
  }
}

run "reject_empty_tag_value" {
  command = plan
  variables { tags = { Team = "" } }
  expect_failures = [var.tags]
}

run "reject_global_application_id" {
  command = plan
  variables { tags = { ApplicationId = "app-1" } }
  expect_failures = [var.tags]
}
