variable "name" {
  description = "Application Load Balancer 이름입니다."
  type        = string

  validation {
    condition = (
      length(var.name) <= 32 &&
      can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", var.name)) &&
      !startswith(lower(var.name), "internal-")
    )
    error_message = "name은 1~32자의 영문자, 숫자, 하이픈만 사용하고 영문자나 숫자로 시작하고 끝나야 하며 internal-로 시작할 수 없습니다."
  }
}

variable "vpc_id" {
  description = "Target Group이 속할 VPC ID입니다. Target Group이 없으면 생략할 수 있습니다."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id를 지정한다면 비어 있을 수 없습니다."
  }
}

variable "subnet_ids" {
  description = "서로 다른 Availability Zone의 ALB Subnet ID입니다."
  type        = list(string)

  validation {
    condition = (
      length(var.subnet_ids) >= 2 &&
      length(distinct(var.subnet_ids)) == length(var.subnet_ids) &&
      alltrue([for id in var.subnet_ids : length(trimspace(id)) > 0])
    )
    error_message = "subnet_ids에는 중복되지 않는 비어 있지 않은 Subnet ID가 두 개 이상 필요합니다."
  }
}

variable "security_group_ids" {
  description = "ALB에 연결할 Security Group ID입니다."
  type        = list(string)

  validation {
    condition = (
      length(var.security_group_ids) > 0 &&
      alltrue([for id in var.security_group_ids : length(trimspace(id)) > 0])
    )
    error_message = "security_group_ids에는 비어 있지 않은 Security Group ID가 하나 이상 필요합니다."
  }
}

variable "internal" {
  description = "내부형 ALB 여부입니다. 공개형의 HTTP Listener는 HTTPS로 리디렉션해야 합니다."
  type        = bool
  default     = true
}

variable "target_groups" {
  description = "논리 키별 Target Group 정의입니다. 기본값은 빈 Map입니다."
  type = map(object({
    name                 = string
    target_type          = optional(string, "instance")
    protocol             = optional(string, "HTTP")
    port                 = optional(number, 80)
    health_check_path    = optional(string, "/")
    health_check_matcher = optional(string, "200")
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, target_group in var.target_groups :
      length(trimspace(key)) > 0 &&
      length(target_group.name) <= 32 &&
      can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", target_group.name)) &&
      contains(["instance", "ip"], target_group.target_type) &&
      contains(["HTTP", "HTTPS"], target_group.protocol) &&
      target_group.port >= 1 && target_group.port <= 65535 && floor(target_group.port) == target_group.port &&
      startswith(target_group.health_check_path, "/") &&
      length(trimspace(target_group.health_check_matcher)) > 0
    ])
    error_message = "target_groups의 키, 이름, 대상 유형, 프로토콜, 포트, 상태 확인 경로와 성공 코드를 확인하세요."
  }

  validation {
    condition     = length(distinct([for target_group in values(var.target_groups) : target_group.name])) == length(var.target_groups)
    error_message = "target_groups의 AWS 이름은 서로 달라야 합니다."
  }
}

variable "listeners" {
  description = "논리 키별 Listener 정의입니다. 기본값은 빈 Map입니다."
  type = map(object({
    port            = number
    protocol        = string
    certificate_arn = optional(string)
    tls_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    default_action = object({
      type                     = string
      target_group_key         = optional(string)
      redirect_to_listener_key = optional(string)
    })
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, listener in var.listeners :
      length(trimspace(key)) > 0 &&
      listener.port >= 1 && listener.port <= 65535 && floor(listener.port) == listener.port &&
      contains(["HTTP", "HTTPS"], listener.protocol) &&
      (listener.protocol == "HTTPS" ? listener.certificate_arn != null : listener.certificate_arn == null) &&
      (listener.certificate_arn == null ? true : length(trimspace(listener.certificate_arn)) > 0) &&
      length(trimspace(listener.tls_policy)) > 0 &&
      contains(["forward", "redirect"], listener.default_action.type) &&
      (listener.default_action.type == "forward" ? (
        listener.default_action.target_group_key != null &&
        listener.default_action.redirect_to_listener_key == null
        ) : (
        listener.protocol == "HTTP" &&
        listener.default_action.target_group_key == null &&
        listener.default_action.redirect_to_listener_key != null
      ))
    ])
    error_message = "listeners의 키, 포트, 프로토콜, 인증서 및 forward 또는 redirect 동작 조합을 확인하세요."
  }

  validation {
    condition     = length(distinct([for listener in values(var.listeners) : listener.port])) == length(var.listeners)
    error_message = "listeners의 포트는 ALB 안에서 서로 달라야 합니다."
  }
}

variable "enable_deletion_protection" {
  description = "ALB 삭제 보호 활성화 여부입니다."
  type        = bool
  default     = false
}

variable "tags" {
  description = "ALB와 Target Group에 적용할 태그입니다. Name 태그는 모듈 이름이 우선합니다."
  type        = map(string)
  default     = {}
}
