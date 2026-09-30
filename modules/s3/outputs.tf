output "bucket_name" {
  description = "생성된 S3 버킷 이름입니다."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "생성된 S3 버킷 ARN입니다."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "CloudFront S3 Origin에 사용할 버킷의 리전별 도메인입니다."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
