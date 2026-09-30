output "role_name" {
  description = "생성된 IAM Role 이름입니다."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "다른 서비스에 전달할 IAM Role ARN입니다."
  value       = aws_iam_role.this.arn
}

output "instance_profile_name" {
  description = "EC2 모듈에 전달할 IAM Instance Profile 이름입니다. 생성하지 않으면 null입니다."
  value       = try(aws_iam_instance_profile.this[0].name, null)
}

output "instance_profile_arn" {
  description = "IAM Instance Profile ARN입니다. 생성하지 않으면 null입니다."
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}
