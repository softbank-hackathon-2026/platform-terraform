variable "name" {
  description = "생성할 비공개 ECR 저장소 이름입니다."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name은 비어 있을 수 없습니다."
  }
}

variable "image_tag_mutability" {
  description = "이미지 태그 재사용 정책입니다. 기본값은 IMMUTABLE입니다."
  type        = string
  default     = "IMMUTABLE"
  nullable    = false

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability는 IMMUTABLE 또는 MUTABLE이어야 합니다."
  }
}

variable "kms_key_arn" {
  description = "기존 고객 관리 KMS 키 ARN입니다. null이면 AES256 암호화를 사용합니다."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn을 지정한다면 비어 있을 수 없습니다."
  }
}

variable "scan_on_push" {
  description = "저장소 수준의 기본 이미지 스캔을 push 시 요청할지 결정합니다. 실제 스캔은 Registry 설정에도 좌우됩니다."
  type        = bool
  default     = true
  nullable    = false
}

variable "lifecycle_policy_json" {
  description = "선택적 ECR Lifecycle Policy JSON 문서입니다. null이면 정책을 만들지 않습니다."
  type        = string
  default     = null

  validation {
    condition     = var.lifecycle_policy_json == null ? true : can(jsondecode(var.lifecycle_policy_json))
    error_message = "lifecycle_policy_json은 유효한 JSON 문서여야 합니다."
  }
}

variable "tags" {
  description = "ECR 저장소에 적용할 태그입니다."
  type        = map(string)
  default     = {}
  nullable    = false
}
