variable "alias_name" {
  description = "선택적 KMS 별칭의 전체 이름입니다. 예: alias/app-key"
  type        = string
  default     = null

  validation {
    condition = var.alias_name == null ? true : (
      length(var.alias_name) <= 256 &&
      can(regex("^alias/[A-Za-z0-9/_-]+$", var.alias_name)) &&
      !startswith(var.alias_name, "alias/aws/")
    )
    error_message = "alias_name은 예약된 alias/aws/를 제외한 alias/<이름> 형식이어야 합니다."
  }
}

variable "description" {
  description = "KMS 키 설명입니다."
  type        = string
  default     = null
}

variable "kms_admin_arns" {
  description = "키 관리 권한을 직접 부여할 IAM Role/User ARN 집합입니다."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.kms_admin_arns :
      can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:(role|user)/[^[:space:]]+$", arn))
    ])
    error_message = "kms_admin_arns에는 IAM Role/User ARN만 지정할 수 있습니다."
  }
}

variable "key_user_arns" {
  description = "키 사용 권한을 직접 부여할 IAM Role/User ARN 집합입니다."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for arn in var.key_user_arns :
      can(regex("^arn:[a-z0-9-]+:iam::[0-9]{12}:(role|user)/[^[:space:]]+$", arn))
    ])
    error_message = "key_user_arns에는 IAM Role/User ARN만 지정할 수 있습니다."
  }
}

variable "policy_json" {
  description = "키 정책 전체를 대체할 JSON 문서입니다. 지정 시 관리자·사용자 ARN 집합은 비워야 합니다."
  type        = string
  default     = null

  validation {
    condition     = var.policy_json == null ? true : can(keys(jsondecode(var.policy_json)))
    error_message = "policy_json은 JSON 객체 형식이어야 합니다."
  }
}

variable "enable_key_rotation" {
  description = "AWS KMS 자동 키 재료 회전 활성화 여부입니다."
  type        = bool
  default     = true
  nullable    = false
}

variable "rotation_period_in_days" {
  description = "자동 키 재료 회전 주기입니다. 회전 활성화 시 적용합니다."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560 && floor(var.rotation_period_in_days) == var.rotation_period_in_days
    error_message = "rotation_period_in_days는 90~2560 사이의 정수여야 합니다."
  }
}

variable "deletion_window_in_days" {
  description = "키 삭제를 예약한 뒤 실제 삭제까지 기다리는 일수입니다."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30 && floor(var.deletion_window_in_days) == var.deletion_window_in_days
    error_message = "deletion_window_in_days는 7~30 사이의 정수여야 합니다."
  }
}

variable "tags" {
  description = "KMS 키에 적용할 태그입니다."
  type        = map(string)
  default     = {}
  nullable    = false
}
