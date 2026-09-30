variable "name" {
  description = "생성할 고객 관리 IAM Policy 이름입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "policy_json" {
  description = "호출자가 작성한 IAM 권한 정책 JSON 문자열입니다."
  type        = string

  validation {
    condition     = can(jsondecode(var.policy_json))
    error_message = "policy_json은 유효한 JSON이어야 합니다."
  }
}

variable "description" {
  description = "선택적 IAM Policy 설명입니다."
  type        = string
  default     = null
}

variable "tags" {
  description = "IAM Policy에 적용할 태그입니다."
  type        = map(string)
  default     = {}
}
