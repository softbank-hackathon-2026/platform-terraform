output "cluster_name" {
  description = "ECS Cluster 이름입니다."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN입니다."
  value       = aws_ecs_cluster.this.arn
}

output "log_group_name" {
  description = "Task 로그 그룹 이름입니다."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "Task 로그 그룹 ARN입니다."
  value       = aws_cloudwatch_log_group.this.arn
}

output "service_name" {
  description = "ECS Service 이름입니다. service = null이면 null입니다."
  value       = try(aws_ecs_service.this["this"].name, null)
}

output "service_arn" {
  description = "ECS Service ARN입니다. service = null이면 null입니다."
  value       = try(aws_ecs_service.this["this"].id, null)
}

output "task_definition_arn" {
  description = "Task Definition ARN입니다. service = null이면 null입니다."
  value       = try(aws_ecs_task_definition.this["this"].arn, null)
}
