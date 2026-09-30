output "policy_name" {
  description = "생성된 IAM Policy 이름입니다."
  value       = aws_iam_policy.this.name
}

output "policy_arn" {
  description = "다른 Role에 연결할 IAM Policy ARN입니다."
  value       = aws_iam_policy.this.arn
}
