locals {
  ecs_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  ecs_log_stream_arn = "arn:${data.aws_partition.current.partition}:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:log-group:${local.name}-log-api:log-stream:*"
}

module "execution_policy" {
  source = "../../modules/iam/policy"
  name   = "${local.name}-policy-ecs-execution"
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
        Sid      = "ReadApplicationDatabaseUrl"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = local.database_url_parameter_arn
      },
      {
        Sid      = "ReadDeployCallbackSecret"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = "arn:aws:ssm:ap-northeast-2:723225040786:parameter/sbh/platform/demo/backend/DEPLOY_CALLBACK_SECRET"
      },
      {
        Sid      = "ReadGithubDeployToken"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = "arn:aws:ssm:ap-northeast-2:723225040786:parameter/sbh/platform/demo/backend/GITHUB_DEPLOY_TOKEN"
      },
    ]
  })
  tags = local.tags
}

module "execution_role" {
  source                  = "../../modules/iam/role"
  name                    = "${local.name}-role-ecs-execution"
  assume_role_policy_json = local.ecs_trust_policy
  managed_policy_arns     = { execution = module.execution_policy.policy_arn }
  tags                    = local.tags
}

module "task_role" {
  source                  = "../../modules/iam/role"
  name                    = "${local.name}-role-ecs-task"
  assume_role_policy_json = local.ecs_trust_policy
  tags                    = local.tags
}
