data "aws_region" "current" {
  count = var.log_region == null ? 1 : 0
}

locals {
  services   = var.service == null ? {} : { this = var.service }
  log_region = var.log_region == null ? data.aws_region.current[0].region : var.log_region
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  tags = merge(var.tags, { Name = var.name })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = merge(var.tags, { Name = var.name })
}

resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = each.value.execution_role_arn
  task_role_arn            = each.value.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = each.value.container_name
      image     = each.value.image
      essential = true
      portMappings = [{
        containerPort = each.value.container_port
        hostPort      = each.value.container_port
        protocol      = "tcp"
      }]
      environment = [for name, value in each.value.environment : { name = name, value = value }]
      secrets     = [for name, ref in each.value.secrets : { name = name, valueFrom = ref }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = local.log_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ecs_service" "this" {
  for_each = local.services

  name                               = var.name
  cluster                            = aws_ecs_cluster.this.arn
  task_definition                    = aws_ecs_task_definition.this[each.key].arn
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  scheduling_strategy                = "REPLICA"
  desired_count                      = each.value.desired_count
  availability_zone_rebalancing      = "ENABLED"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds
  wait_for_steady_state              = true
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = each.value.subnet_ids
    security_groups  = each.value.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = each.value.target_group_arn
    container_name   = each.value.container_name
    container_port   = each.value.container_port
  }

  tags = merge(var.tags, { Name = var.name })
}
