mock_provider "aws" {
  override_during = plan
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:ap-northeast-2:123456789012:cluster/sample-dev-backend" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:ap-northeast-2:123456789012:task-definition/sample-dev-backend:1" }
  }
}

variables {
  name = "sample-dev-backend"
}

run "cluster_only" {
  command = plan

  assert {
    condition = (
      length(aws_ecs_task_definition.this) == 0 && length(aws_ecs_service.this) == 0 &&
      output.service_name == null && output.service_arn == null && output.task_definition_arn == null &&
      aws_cloudwatch_log_group.this.retention_in_days == 30
    )
    error_message = "초기 구성은 Cluster와 30일 로그 그룹만 만들고 Task와 Service를 생략해야 합니다."
  }
}

run "fargate_service" {
  command = plan

  variables {
    service = {
      image              = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/sample@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      subnet_ids         = ["subnet-app-a", "subnet-app-c"]
      security_group_ids = ["sg-app"]
      target_group_arn   = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample/1234567890123456"
      execution_role_arn = "arn:aws:iam::123456789012:role/sample-execution"
      task_role_arn      = "arn:aws:iam::123456789012:role/sample-task"
      environment        = { DB_HOST = "database.internal" }
      secrets            = { DB_PASSWORD = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-app-AbCdEf:password::" }
    }
  }

  assert {
    condition = (
      aws_ecs_service.this["this"].launch_type == "FARGATE" &&
      aws_ecs_service.this["this"].desired_count == 2 &&
      aws_ecs_service.this["this"].availability_zone_rebalancing == "ENABLED" &&
      !aws_ecs_service.this["this"].network_configuration[0].assign_public_ip &&
      length(aws_ecs_service.this["this"].network_configuration[0].subnets) == 2 &&
      aws_ecs_service.this["this"].deployment_minimum_healthy_percent == 100 &&
      aws_ecs_service.this["this"].deployment_maximum_percent == 200 &&
      aws_ecs_service.this["this"].deployment_circuit_breaker[0].enable &&
      aws_ecs_service.this["this"].deployment_circuit_breaker[0].rollback
    )
    error_message = "Task 2개, AZ 재분산, Public IP 비활성화와 배포 복구 설정을 유지해야 합니다."
  }

  assert {
    condition = (
      aws_ecs_task_definition.this["this"].cpu == "512" &&
      aws_ecs_task_definition.this["this"].memory == "1024" &&
      aws_ecs_task_definition.this["this"].network_mode == "awsvpc" &&
      aws_ecs_task_definition.this["this"].runtime_platform[0].cpu_architecture == "X86_64" &&
      aws_ecs_task_definition.this["this"].runtime_platform[0].operating_system_family == "LINUX" &&
      aws_ecs_task_definition.this["this"].execution_role_arn != aws_ecs_task_definition.this["this"].task_role_arn &&
      jsondecode(aws_ecs_task_definition.this["this"].container_definitions)[0].secrets[0].valueFrom == var.service.secrets.DB_PASSWORD &&
      jsondecode(aws_ecs_task_definition.this["this"].container_definitions)[0].logConfiguration.options["awslogs-region"] == "ap-northeast-2"
    )
    error_message = "Task 자원, Linux X86_64, 분리한 Role과 Secret ARN 참조가 반영되어야 합니다."
  }
}

run "reject_invalid_cpu_memory" {
  command = plan
  variables {
    service = {
      image              = "example.invalid/app:sample"
      cpu                = 512
      memory             = 512
      subnet_ids         = ["subnet-app-a", "subnet-app-c"]
      security_group_ids = ["sg-app"]
      target_group_arn   = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample/1234567890123456"
      execution_role_arn = "arn:aws:iam::123456789012:role/sample-execution"
      task_role_arn      = "arn:aws:iam::123456789012:role/sample-task"
    }
  }
  expect_failures = [var.service]
}

run "reject_single_subnet" {
  command = plan
  variables {
    service = {
      image              = "example.invalid/app:sample"
      subnet_ids         = ["subnet-app-a"]
      security_group_ids = ["sg-app"]
      target_group_arn   = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample/1234567890123456"
      execution_role_arn = "arn:aws:iam::123456789012:role/sample-execution"
      task_role_arn      = "arn:aws:iam::123456789012:role/sample-task"
    }
  }
  expect_failures = [var.service]
}

run "reject_duplicate_environment_secret" {
  command = plan
  variables {
    service = {
      image              = "example.invalid/app:sample"
      subnet_ids         = ["subnet-app-a", "subnet-app-c"]
      security_group_ids = ["sg-app"]
      target_group_arn   = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample/1234567890123456"
      execution_role_arn = "arn:aws:iam::123456789012:role/sample-execution"
      task_role_arn      = "arn:aws:iam::123456789012:role/sample-task"
      environment        = { DB_PASSWORD = "not-a-secret" }
      secrets            = { DB_PASSWORD = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:sample-app-AbCdEf:password::" }
    }
  }
  expect_failures = [var.service]
}

run "reject_plaintext_secret" {
  command = plan
  variables {
    service = {
      image              = "example.invalid/app:sample"
      subnet_ids         = ["subnet-app-a", "subnet-app-c"]
      security_group_ids = ["sg-app"]
      target_group_arn   = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample/1234567890123456"
      execution_role_arn = "arn:aws:iam::123456789012:role/sample-execution"
      task_role_arn      = "arn:aws:iam::123456789012:role/sample-task"
      secrets            = { DB_PASSWORD = "plain-text" }
    }
  }
  expect_failures = [var.service]
}
