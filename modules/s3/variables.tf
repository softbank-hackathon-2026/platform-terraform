variable "bucket_name" {
  description = "생성할 일반 목적 S3 버킷 이름입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.bucket_name)) > 0
    error_message = "bucket_name은 비어 있을 수 없습니다."
  }
}

variable "versioning_enabled" {
  description = "버킷 버전 관리 활성화 여부입니다."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "SSE-KMS 기본 암호화에 사용할 선택적 KMS 키 ARN입니다. null이면 AWS의 기본 SSE-S3를 사용합니다."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn을 지정한다면 비어 있을 수 없습니다."
  }
}

variable "tags" {
  description = "버킷에 적용할 추가 태그입니다. Name 태그는 버킷 이름으로 설정됩니다."
  type        = map(string)
  default     = {}
}
