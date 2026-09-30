output "id" {
  description = "생성된 EC2 인스턴스 ID입니다."
  value       = aws_instance.this.id
}

output "arn" {
  description = "생성된 EC2 인스턴스 ARN입니다."
  value       = aws_instance.this.arn
}

output "availability_zone" {
  description = "생성된 EC2 인스턴스의 Availability Zone입니다."
  value       = aws_instance.this.availability_zone
}

output "private_ip" {
  description = "생성된 EC2 인스턴스의 Private IP 주소입니다."
  value       = aws_instance.this.private_ip
}

output "private_dns" {
  description = "생성된 EC2 인스턴스의 Private DNS 이름입니다."
  value       = aws_instance.this.private_dns
}

output "public_ip" {
  description = "생성된 EC2 인스턴스의 Public IP 주소입니다. Public IP가 없으면 비어 있습니다."
  value       = aws_instance.this.public_ip
}

output "public_dns" {
  description = "생성된 EC2 인스턴스의 Public DNS 이름입니다. Public IP가 없으면 비어 있습니다."
  value       = aws_instance.this.public_dns
}
