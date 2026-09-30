output "repository_name" {
  description = "생성된 ECR 저장소 이름입니다."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "생성된 ECR 저장소 ARN입니다."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "이미지 태그를 붙여 사용할 ECR 저장소 URL입니다."
  value       = aws_ecr_repository.this.repository_url
}
