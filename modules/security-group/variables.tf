variable "name" {
  description = "Security Group 이름입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "vpc_id" {
  description = "Security Group을 생성할 VPC ID입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id는 비어 있을 수 없습니다."
  }
}

variable "ingress_rules" {
  description = "논리 키를 사용하는 인바운드 규칙입니다. 기본값은 규칙 없음입니다."
  type = map(object({
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
    description                  = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, rule in var.ingress_rules :
      length(trimspace(key)) > 0 &&
      contains(["tcp", "udp", "-1"], rule.ip_protocol) &&
      (
        (rule.cidr_ipv4 != null && rule.referenced_security_group_id == null && can(cidrnetmask(rule.cidr_ipv4))) ||
        (rule.cidr_ipv4 == null && rule.referenced_security_group_id != null && length(trimspace(rule.referenced_security_group_id)) > 0)
      ) &&
      (rule.ip_protocol == "-1" ?
        rule.from_port == null && rule.to_port == null :
        (rule.from_port != null && rule.to_port != null ?
          rule.from_port >= 0 && rule.to_port <= 65535 && rule.from_port <= rule.to_port &&
          floor(rule.from_port) == rule.from_port && floor(rule.to_port) == rule.to_port : false
        )
      )
    ])
    error_message = "ingress_rules는 비어 있지 않은 키, tcp/udp/-1 프로토콜, IPv4 CIDR 또는 Security Group ID 하나, 올바른 포트 조합이 필요합니다."
  }
}

variable "egress_rules" {
  description = "논리 키를 사용하는 아웃바운드 규칙입니다. 기본값은 규칙 없음입니다."
  type = map(object({
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
    description                  = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, rule in var.egress_rules :
      length(trimspace(key)) > 0 &&
      contains(["tcp", "udp", "-1"], rule.ip_protocol) &&
      (
        (rule.cidr_ipv4 != null && rule.referenced_security_group_id == null && can(cidrnetmask(rule.cidr_ipv4))) ||
        (rule.cidr_ipv4 == null && rule.referenced_security_group_id != null && length(trimspace(rule.referenced_security_group_id)) > 0)
      ) &&
      (rule.ip_protocol == "-1" ?
        rule.from_port == null && rule.to_port == null :
        (rule.from_port != null && rule.to_port != null ?
          rule.from_port >= 0 && rule.to_port <= 65535 && rule.from_port <= rule.to_port &&
          floor(rule.from_port) == rule.from_port && floor(rule.to_port) == rule.to_port : false
        )
      )
    ])
    error_message = "egress_rules는 비어 있지 않은 키, tcp/udp/-1 프로토콜, IPv4 CIDR 또는 Security Group ID 하나, 올바른 포트 조합이 필요합니다."
  }
}

variable "tags" {
  description = "Security Group에 적용할 추가 태그입니다. Name은 name 값이 우선합니다."
  type        = map(string)
  default     = {}
}
