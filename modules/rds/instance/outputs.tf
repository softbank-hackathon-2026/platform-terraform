output "db_instance_id" {
  description = "기본 DB 인스턴스 식별자입니다."
  value       = aws_db_instance.primary.identifier
}

output "db_instance_arn" {
  description = "기본 DB 인스턴스 ARN입니다."
  value       = aws_db_instance.primary.arn
}

output "db_resource_id" {
  description = "기본 DB의 IAM rds-db:connect 정책에 사용할 Resource ID입니다."
  value       = aws_db_instance.primary.resource_id
}

output "writer_address" {
  description = "기본 DB의 쓰기 접속 주소입니다."
  value       = aws_db_instance.primary.address
}

output "port" {
  description = "DB 접속 포트입니다."
  value       = aws_db_instance.primary.port
}

output "master_secret_arn" {
  description = "선택한 관리자 암호 관리 방식의 Secret ARN입니다."
  value       = local.module_managed_secret ? aws_secretsmanager_secret.master[0].arn : try(one(aws_db_instance.primary.master_user_secret).secret_arn, null)
}

output "read_replica_ids" {
  description = "논리 키별 Read Replica 식별자입니다."
  value       = { for key, replica in aws_db_instance.replica : key => replica.identifier }
}

output "read_replica_resource_ids" {
  description = "논리 키별 Read Replica IAM 접속 권한용 Resource ID입니다."
  value       = { for key, replica in aws_db_instance.replica : key => replica.resource_id }
}

output "read_replica_addresses" {
  description = "논리 키별 Read Replica의 읽기 접속 주소입니다."
  value       = { for key, replica in aws_db_instance.replica : key => replica.address }
}
