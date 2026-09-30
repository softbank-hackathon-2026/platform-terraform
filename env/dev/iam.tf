locals {
  ecs_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  ecs_log_stream_arn = "arn:${data.aws_partition.current.partition}:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name}-backend:log-stream:*"
}

module "execution_policy" {
  source = "../../modules/iam/policy"
  name   = "${local.name}-ecs-execution"
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid      = "PullBackendImage"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = module.ecr.repository_arn
      },
      {
        Sid      = "WriteTaskLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.ecs_log_stream_arn
      },
      {
        Sid      = "ReadApplicationDatabaseSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.app_database.arn
      },
    ]
  })
  tags = local.tags
}

module "execution_role" {
  source                  = "../../modules/iam/role"
  name                    = "${local.name}-ecs-execution"
  assume_role_policy_json = local.ecs_trust_policy
  managed_policy_arns     = { execution = module.execution_policy.policy_arn }
  tags                    = local.tags
}

module "task_role" {
  source                  = "../../modules/iam/role"
  name                    = "${local.name}-ecs-task"
  assume_role_policy_json = local.ecs_trust_policy
  tags                    = local.tags
}
