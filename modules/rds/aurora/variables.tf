variable "cluster_identifier" {
  description = "Aurora 클러스터 식별자입니다."
  type        = string

  validation {
    condition = (
      length(var.cluster_identifier) >= 1 && length(var.cluster_identifier) <= 63 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", var.cluster_identifier)) &&
      !strcontains(var.cluster_identifier, "--")
    )
    error_message = "cluster_identifier는 영문자로 시작하고 영문자 또는 숫자로 끝나는 1~63자의 영문자, 숫자, 하이픈이어야 하며 연속 하이픈은 사용할 수 없습니다."
  }
}

variable "writer_identifier" {
  description = "최초 Aurora 인스턴스 식별자입니다. 장애 조치 후 역할은 바뀔 수 있습니다."
  type        = string

  validation {
    condition = (
      length(var.writer_identifier) >= 1 && length(var.writer_identifier) <= 63 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", var.writer_identifier)) &&
      !strcontains(var.writer_identifier, "--")
    )
    error_message = "writer_identifier는 영문자로 시작하고 영문자 또는 숫자로 끝나는 1~63자의 영문자, 숫자, 하이픈이어야 합니다."
  }
}

variable "engine" {
  description = "Aurora 엔진입니다. aurora-postgresql 또는 aurora-mysql입니다."
  type        = string

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine은 aurora-postgresql 또는 aurora-mysql이어야 합니다."
  }
}

variable "engine_version" {
  description = "AWS Region에서 지원하는 Aurora 엔진 버전입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.engine_version)) > 0
    error_message = "engine_version은 비어 있을 수 없습니다."
  }
}

variable "writer_instance_class" {
  description = "최초 Aurora 인스턴스 클래스입니다. db.serverless는 지원하지 않습니다."
  type        = string

  validation {
    condition     = length(trimspace(var.writer_instance_class)) > 0 && lower(trimspace(var.writer_instance_class)) != "db.serverless"
    error_message = "writer_instance_class는 비어 있지 않은 Provisioned 클래스여야 하며 db.serverless는 사용할 수 없습니다."
  }
}

variable "database_name" {
  description = "선택적으로 생성할 초기 DB 이름입니다."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null ? true : length(var.database_name) >= 1 && length(var.database_name) <= 64 && can(regex("^[A-Za-z][A-Za-z0-9_]*$", var.database_name))
    error_message = "database_name은 영문자로 시작하는 1~64자의 영문자, 숫자, 밑줄이어야 합니다."
  }
}

variable "port" {
  description = "DB 접속 포트입니다. 생략하면 PostgreSQL 5432, MySQL 3306을 사용합니다."
  type        = number
  default     = null

  validation {
    condition     = var.port == null ? true : var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port는 1~65535의 정수여야 합니다."
  }
}

variable "subnet_ids" {
  description = "서로 다른 AZ의 Private Subnet ID 두 개 이상입니다."
  type        = list(string)

  validation {
    condition = (
      length(var.subnet_ids) >= 2 &&
      length(distinct(var.subnet_ids)) == length(var.subnet_ids) &&
      alltrue([for id in var.subnet_ids : length(trimspace(id)) > 0])
    )
    error_message = "subnet_ids에는 중복 없는 비어 있지 않은 Private Subnet ID 두 개 이상이 필요합니다."
  }
}

variable "security_group_ids" {
  description = "DB 접속 규칙을 가진 기존 Security Group ID입니다."
  type        = list(string)

  validation {
    condition = (
      length(var.security_group_ids) >= 1 &&
      length(distinct(var.security_group_ids)) == length(var.security_group_ids) &&
      alltrue([for id in var.security_group_ids : length(trimspace(id)) > 0])
    )
    error_message = "security_group_ids에는 중복 없는 비어 있지 않은 Security Group ID가 하나 이상 필요합니다."
  }
}

variable "master_username" {
  description = "Secrets Manager에서 암호를 관리할 관리자 계정 이름입니다."
  type        = string

  validation {
    condition     = length(var.master_username) >= 1 && length(var.master_username) <= 16 && can(regex("^[A-Za-z][A-Za-z0-9_]*$", var.master_username))
    error_message = "master_username은 영문자로 시작하는 1~16자의 영문자, 숫자, 밑줄이어야 합니다."
  }
}

variable "kms_key_id" {
  description = "스토리지 암호화에 사용할 기존 KMS 키 ID 또는 ARN입니다."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null ? true : length(trimspace(var.kms_key_id)) > 0
    error_message = "kms_key_id를 지정한다면 비어 있을 수 없습니다."
  }
}

variable "secret_kms_key_id" {
  description = "관리자 Secret 암호화에 사용할 기존 KMS 키 ID 또는 ARN입니다."
  type        = string
  default     = null

  validation {
    condition     = var.secret_kms_key_id == null ? true : length(trimspace(var.secret_kms_key_id)) > 0
    error_message = "secret_kms_key_id를 지정한다면 비어 있을 수 없습니다."
  }
}

variable "iam_database_authentication_enabled" {
  description = "일반 DB 사용자용 IAM 데이터베이스 인증을 활성화합니다. 관리자 암호는 계속 Secrets Manager에서 관리합니다."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "자동 백업 보존 기간(일)입니다."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period는 1~35일의 정수여야 합니다."
  }
}

variable "deletion_protection" {
  description = "Aurora 클러스터 삭제 보호 활성화 여부입니다."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "클러스터 삭제 시 최종 스냅샷 생성을 생략할지 여부입니다."
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "최종 스냅샷 식별자입니다. 기본값은 <cluster_identifier>-final입니다."
  type        = string
  default     = null

  validation {
    condition = var.final_snapshot_identifier == null ? true : (
      length(var.final_snapshot_identifier) >= 1 && length(var.final_snapshot_identifier) <= 255 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", var.final_snapshot_identifier)) &&
      !strcontains(var.final_snapshot_identifier, "--")
    )
    error_message = "final_snapshot_identifier는 영문자로 시작하고 영문자 또는 숫자로 끝나는 1~255자의 영문자, 숫자, 하이픈이어야 합니다."
  }
}

variable "extended_support_enabled" {
  description = "RDS Extended Support 등록 여부입니다. 기본값은 비활성화입니다."
  type        = bool
  default     = false
}

variable "readers" {
  description = "논리 키별 Aurora reader 인스턴스 설정입니다."
  type = map(object({
    identifier     = string
    instance_class = optional(string)
    promotion_tier = optional(number, 1)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, reader in var.readers :
      length(trimspace(key)) > 0 &&
      length(reader.identifier) >= 1 && length(reader.identifier) <= 63 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", reader.identifier)) &&
      !strcontains(reader.identifier, "--") &&
      (reader.instance_class == null ? true : length(trimspace(reader.instance_class)) > 0 && lower(trimspace(reader.instance_class)) != "db.serverless") &&
      reader.promotion_tier >= 0 && reader.promotion_tier <= 15 && floor(reader.promotion_tier) == reader.promotion_tier
    ])
    error_message = "readers의 논리 키, 식별자, Provisioned 인스턴스 클래스 또는 0~15 정수 promotion_tier를 확인하세요."
  }

  validation {
    condition     = length(distinct([for reader in values(var.readers) : lower(reader.identifier)])) == length(var.readers)
    error_message = "readers의 DB 식별자는 대소문자 구분 없이 서로 달라야 합니다."
  }
}

variable "tags" {
  description = "DB Subnet Group, 클러스터와 인스턴스에 적용할 태그입니다. Name은 각 리소스 식별자가 우선합니다."
  type        = map(string)
  default     = {}
}
