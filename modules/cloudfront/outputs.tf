output "distribution_id" {
  description = "CloudFront Distribution ID입니다."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "S3 버킷 정책의 SourceArn에 사용할 Distribution ARN입니다."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "CloudFront 기본 도메인입니다."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "url" {
  description = "프론트엔드와 API의 HTTPS 주소입니다. 사용자 도메인이 있으면 해당 도메인을 사용합니다."
  value       = "https://${var.alternate_domain_name == null ? aws_cloudfront_distribution.this.domain_name : var.alternate_domain_name}"
}

output "vpc_origin_id" {
  description = "Internal ALB VPC Origin ID입니다."
  value       = aws_cloudfront_vpc_origin.api.id
}

output "origin_access_control_id" {
  description = "S3 Origin Access Control ID입니다."
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "spa_function_arn" {
  description = "SPA viewer-request Function ARN입니다."
  value       = aws_cloudfront_function.spa.arn
}
