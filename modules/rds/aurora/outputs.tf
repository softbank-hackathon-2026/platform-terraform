output "cluster_id" {
  description = "Aurora 클러스터 ID입니다."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Aurora 클러스터 ARN입니다."
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "IAM rds-db:connect 정책에 사용할 클러스터 Resource ID입니다."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  description = "현재 writer를 가리키는 클러스터 접속 주소입니다."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "reader가 설정되어 있으면 클러스터 reader 접속 주소이고, 없으면 null입니다."
  value       = length(var.readers) > 0 ? aws_rds_cluster.this.reader_endpoint : null
}

output "port" {
  description = "DB 접속 포트입니다."
  value       = aws_rds_cluster.this.port
}

output "master_secret_arn" {
  description = "RDS가 관리하는 관리자 암호 Secret ARN입니다."
  value       = try(one(aws_rds_cluster.this.master_user_secret).secret_arn, null)
}

output "reader_addresses" {
  description = "논리 키별 reader 인스턴스 주소입니다. 장애 조치 후 실제 역할이 바뀔 수 있습니다."
  value       = { for key, reader in aws_rds_cluster_instance.reader : key => reader.endpoint }
}
