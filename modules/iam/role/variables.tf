variable "name" {
  description = "생성할 IAM Role 이름이며, 선택적 Instance Profile 이름에도 사용합니다."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "assume_role_policy_json" {
  description = "호출자가 작성한 IAM Role 신뢰 정책 JSON 문자열입니다."
  type        = string

  validation {
    condition     = can(jsondecode(var.assume_role_policy_json))
    error_message = "assume_role_policy_json은 유효한 JSON이어야 합니다."
  }
}

variable "managed_policy_arns" {
  description = "논리 키를 사용하는 IAM 관리형 Policy ARN Map입니다."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, arn in var.managed_policy_arns :
      length(trimspace(key)) > 0 && length(trimspace(arn)) > 0
    ])
    error_message = "managed_policy_arns의 키와 ARN은 비어 있을 수 없습니다."
  }
}

variable "create_instance_profile" {
  description = "EC2 연결을 위한 IAM Instance Profile 생성 여부입니다."
  type        = bool
  default     = false
}

variable "tags" {
  description = "IAM Role과 선택적 Instance Profile에 적용할 태그입니다."
  type        = map(string)
  default     = {}
}
