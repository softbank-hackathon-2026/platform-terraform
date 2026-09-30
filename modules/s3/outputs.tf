output "bucket_name" {
  description = "생성된 S3 버킷 이름입니다."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "생성된 S3 버킷 ARN입니다."
  value       = aws_s3_bucket.this.arn
}
