variable "identifier" {
  description = "기본 RDS DB 인스턴스 식별자입니다."
  type        = string

  validation {
    condition = (
      length(var.identifier) >= 1 && length(var.identifier) <= 63 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", var.identifier)) &&
      !strcontains(var.identifier, "--")
    )
    error_message = "identifier는 영문자로 시작하고 영문자 또는 숫자로 끝나는 1~63자의 영문자, 숫자, 하이픈이어야 하며 연속 하이픈은 사용할 수 없습니다."
  }
}

variable "engine" {
  description = "일반 RDS 엔진입니다. postgres 또는 mysql입니다."
  type        = string

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine은 postgres 또는 mysql이어야 합니다."
  }
}

variable "engine_version" {
  description = "AWS Region에서 지원하는 DB 엔진 버전입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.engine_version)) > 0
    error_message = "engine_version은 비어 있을 수 없습니다."
  }
}

variable "instance_class" {
  description = "기본 DB 인스턴스 클래스입니다."
  type        = string

  validation {
    condition     = length(trimspace(var.instance_class)) > 0
    error_message = "instance_class는 비어 있을 수 없습니다."
  }
}

variable "allocated_storage" {
  description = "기본 DB에 할당할 스토리지 용량(GiB)입니다."
  type        = number

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536 && floor(var.allocated_storage) == var.allocated_storage
    error_message = "allocated_storage는 20~65536 GiB의 정수여야 합니다."
  }
}

variable "storage_type" {
  description = "DB 스토리지 유형입니다."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2"], var.storage_type)
    error_message = "storage_type은 gp3 또는 gp2여야 합니다."
  }
}

variable "db_name" {
  description = "선택적으로 생성할 초기 DB 이름입니다."
  type        = string
  default     = null

  validation {
    condition     = var.db_name == null ? true : length(var.db_name) >= 1 && length(var.db_name) <= 64 && can(regex("^[A-Za-z][A-Za-z0-9_]*$", var.db_name))
    error_message = "db_name은 영문자로 시작하는 1~64자의 영문자, 숫자, 밑줄이어야 합니다."
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

variable "master_password_mode" {
  description = "관리자 암호 관리 방식입니다. Read Replica가 있으면 module_managed_secret을 선택해야 합니다."
  type        = string
  default     = "rds_managed"

  validation {
    condition     = contains(["rds_managed", "module_managed_secret"], var.master_password_mode)
    error_message = "master_password_mode는 rds_managed 또는 module_managed_secret이어야 합니다."
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
  description = "기본 DB의 삭제 보호 활성화 여부입니다."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "기본 DB 삭제 시 최종 스냅샷 생성을 생략할지 여부입니다."
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "최종 스냅샷 식별자입니다. 기본값은 <identifier>-final입니다."
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

variable "multi_az" {
  description = "기본 DB의 Multi-AZ 대기 인스턴스 사용 여부입니다. Read Replica와 별도입니다."
  type        = bool
  default     = false
}

variable "read_replicas" {
  description = "논리 키별 같은 Region의 Read Replica 설정입니다."
  type = map(object({
    identifier          = string
    instance_class      = optional(string)
    deletion_protection = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, replica in var.read_replicas :
      length(trimspace(key)) > 0 &&
      length(replica.identifier) >= 1 && length(replica.identifier) <= 63 &&
      can(regex("^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z]$", replica.identifier)) &&
      !strcontains(replica.identifier, "--") &&
      (replica.instance_class == null ? true : length(trimspace(replica.instance_class)) > 0)
    ])
    error_message = "read_replicas의 논리 키, 식별자 또는 인스턴스 클래스를 확인하세요."
  }

  validation {
    condition     = length(distinct([for replica in values(var.read_replicas) : lower(replica.identifier)])) == length(var.read_replicas)
    error_message = "read_replicas의 DB 식별자는 대소문자 구분 없이 서로 달라야 합니다."
  }
}

variable "tags" {
  description = "DB Subnet Group과 DB 인스턴스에 적용할 태그입니다. Name은 각 리소스 식별자가 우선합니다."
  type        = map(string)
  default     = {}
}
