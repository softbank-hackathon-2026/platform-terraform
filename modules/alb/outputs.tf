output "load_balancer_arn" {
  description = "ALB ARN입니다."
  value       = aws_lb.this.arn
}

output "dns_name" {
  description = "ALB DNS 이름입니다."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "ALB의 Route 53 Hosted Zone ID입니다."
  value       = aws_lb.this.zone_id
}

output "target_group_arns" {
  description = "논리 키별 Target Group ARN Map입니다."
  value = {
    for key, target_group in aws_lb_target_group.this : key => target_group.arn
  }
}

output "listener_arns" {
  description = "논리 키별 Listener ARN Map입니다."
  value = merge(
    { for key, listener in aws_lb_listener.forward : key => listener.arn },
    { for key, listener in aws_lb_listener.redirect : key => listener.arn }
  )
}
