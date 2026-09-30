variable "project_name" {
  description = "dev 리소스 이름의 프로젝트 접두사입니다."
  type        = string
  default     = "sbh-platform"

  validation {
    condition = (
      length(var.project_name) <= 20 &&
      can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.project_name)) &&
      !startswith(var.project_name, "internal-")
    )
    error_message = "project_name은 영문 소문자로 시작하는 1~20자의 소문자, 숫자, 단일 하이픈이며 internal-로 시작할 수 없습니다."
  }
}

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
  default     = 8080

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

variable "backend_image_digest" {
  description = "같은 ECR 저장소의 배포할 이미지 Digest입니다. null이면 ECS 서비스는 생성하지 않습니다."
  type        = string
  default     = null

  validation {
    condition     = var.backend_image_digest == null ? true : can(regex("^sha256:[0-9a-f]{64}$", var.backend_image_digest))
    error_message = "backend_image_digest는 sha256: 뒤에 소문자 16진수 64자를 지정해야 합니다."
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
  default     = "sbhapp"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name은 영문자로 시작하는 1~63자의 영문자, 숫자, 밑줄이어야 합니다."
  }
}

variable "tags" {
  description = "dev 리소스에 추가할 태그입니다. Project, Environment와 ManagedBy는 Root Module 값이 우선합니다."
  type        = map(string)
  default     = {}
}
