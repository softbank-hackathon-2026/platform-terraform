output "security_group_id" {
  description = "생성된 Security Group ID입니다."
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "생성된 Security Group ARN입니다."
  value       = aws_security_group.this.arn
}
