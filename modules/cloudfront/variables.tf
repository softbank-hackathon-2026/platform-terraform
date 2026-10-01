variable "name" {
  description = "CloudFront 리소스 이름의 접두사입니다."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 45
    error_message = "name은 1~45자의 소문자, 숫자, 단일 하이픈이어야 합니다."
  }
}

variable "s3_origin_domain_name" {
  description = "S3 버킷의 리전별 REST 도메인입니다. 웹사이트 엔드포인트가 아닙니다."
  type        = string

  validation {
    condition     = length(trimspace(var.s3_origin_domain_name)) > 0 && !strcontains(var.s3_origin_domain_name, "://")
    error_message = "s3_origin_domain_name은 URL 스킴 없는 비어 있지 않은 도메인이어야 합니다."
  }
}

variable "alb_arn" {
  description = "Active 상태의 Internal ALB ARN입니다."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:elasticloadbalancing:[^:]+:[0-9]{12}:loadbalancer/app/", var.alb_arn))
    error_message = "alb_arn은 Application Load Balancer ARN이어야 합니다."
  }
}

variable "alb_dns_name" {
  description = "Internal ALB의 DNS 이름입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.alb_dns_name)) > 0 && !strcontains(var.alb_dns_name, "://")
    error_message = "alb_dns_name은 URL 스킴 없는 비어 있지 않은 도메인이어야 합니다."
  }
}

variable "tags" {
  description = "CloudFront Distribution, VPC Origin과 Function에 적용할 추가 태그입니다."
  type        = map(string)
  default     = {}
}
