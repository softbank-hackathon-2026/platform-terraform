output "key_id" {
  description = "생성된 KMS 키 ID입니다."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "생성된 KMS 키 ARN입니다."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "생성된 별칭 이름입니다. 별칭이 없으면 null입니다."
  value       = one(aws_kms_alias.this[*].name)
}

output "alias_arn" {
  description = "생성된 별칭 ARN입니다. 별칭이 없으면 null입니다."
  value       = one(aws_kms_alias.this[*].arn)
}
