variable "vpc_cidr" {
  description = "두 AZ의 세 Subnet 계층을 나눌 IPv4 /16 CIDR입니다."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(split("/", var.vpc_cidr)[1] == "16" && cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false)
    error_message = "vpc_cidr은 네트워크 주소로 정렬된 IPv4 /16 CIDR이어야 합니다."
  }
}

variable "container_port" {
  description = "ALB Target Group과 Fargate 앱의 TCP 포트입니다."
  type        = number
  default     = 8000

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port는 1~65535의 정수여야 합니다."
  }
}

variable "health_check_path" {
  description = "인증 없이 HTTP 200을 반환할 ALB 상태 확인 경로입니다."
  type        = string
  default     = "/api/health"

  validation {
    condition     = startswith(var.health_check_path, "/") && !strcontains(var.health_check_path, "?")
    error_message = "health_check_path는 /로 시작하고 Query String이 없는 경로여야 합니다."
  }
}

variable "postgres_engine_version" {
  description = "서울 리전에서 지원하는 PostgreSQL 엔진 버전입니다."
  type        = string
  default     = "17.11"

  validation {
    condition     = length(trimspace(var.postgres_engine_version)) > 0
    error_message = "postgres_engine_version은 비어 있을 수 없습니다."
  }
}

variable "postgres_instance_class" {
  description = "Multi-AZ PostgreSQL 인스턴스 클래스입니다."
  type        = string
  default     = "db.t4g.small"

  validation {
    condition     = startswith(var.postgres_instance_class, "db.")
    error_message = "postgres_instance_class는 db.로 시작하는 RDS 인스턴스 클래스여야 합니다."
  }
}

variable "db_name" {
  description = "초기 PostgreSQL 데이터베이스 이름입니다."
  type        = string
  default     = "freesia"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name은 영문자로 시작하는 1~63자의 영문자, 숫자, 밑줄이어야 합니다."
  }
}

variable "tags" {
  description = "dev 리소스에 추가할 태그입니다. 필수 태그와 Name은 Root Module과 각 리소스에서 설정합니다."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.tags :
      length(trimspace(key)) > 0 &&
      length(trimspace(value)) > 0 &&
      !contains(["name", "project", "scope", "environment", "managedby", "owner", "applicationid", "deploymentid"], lower(key)) &&
      (lower(key) != "infraid" || key == "InfraId")
    ])
    error_message = "추가 태그는 빈 값, 필수 태그와 Name의 재정의 또는 공통 ApplicationId와 DeploymentId를 허용하지 않습니다. InfraId는 정확한 대소문자를 사용하세요."
  }
}
