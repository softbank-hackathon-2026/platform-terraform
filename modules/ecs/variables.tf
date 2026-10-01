variable "name" {
  description = "Cluster, Task Definition, Service와 로그 그룹 이름의 접두사입니다."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,64}$", var.name))
    error_message = "name은 1~64자의 영문자, 숫자, 밑줄, 하이픈이어야 합니다."
  }
}

variable "log_group_name" {
  description = "Task 로그 그룹 이름입니다. 생략하면 /ecs/<name>을 사용합니다."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_name == null ? true : length(trimspace(var.log_group_name)) > 0
    error_message = "log_group_name을 지정하면 비어 있을 수 없습니다."
  }
}

variable "log_region" {
  description = "로그 그룹과 호출 AWS Provider의 Region입니다. 생략하면 Provider Region을 조회합니다. 명시하면 의존 리소스 생성 전에도 로그 설정을 Plan에서 확인할 수 있습니다."
  type        = string
  default     = null

  validation {
    condition     = var.log_region == null ? true : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.log_region))
    error_message = "log_region은 호출 AWS Provider와 같은 AWS Region 이름이어야 합니다."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs 보존 기간입니다."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days는 CloudWatch Logs에서 지원하는 보존 기간이어야 합니다."
  }
}

variable "service" {
  description = "선택적 On-Demand Fargate 서비스입니다. null이면 Task Definition과 Service를 만들지 않습니다."
  type = object({
    image                             = string
    container_name                    = optional(string, "app")
    container_port                    = optional(number, 8080)
    cpu                               = optional(number, 512)
    memory                            = optional(number, 1024)
    desired_count                     = optional(number, 2)
    subnet_ids                        = list(string)
    security_group_ids                = list(string)
    target_group_arn                  = string
    execution_role_arn                = string
    task_role_arn                     = string
    environment                       = optional(map(string), {})
    secrets                           = optional(map(string), {})
    health_check_grace_period_seconds = optional(number, 60)
  })
  default = null

  validation {
    condition = var.service == null ? true : (
      length(trimspace(var.service.image)) > 0 &&
      can(regex("^[A-Za-z0-9_-]{1,255}$", var.service.container_name)) &&
      var.service.container_port >= 1 && var.service.container_port <= 65535 && floor(var.service.container_port) == var.service.container_port &&
      var.service.desired_count >= 1 && floor(var.service.desired_count) == var.service.desired_count &&
      var.service.health_check_grace_period_seconds >= 0 && floor(var.service.health_check_grace_period_seconds) == var.service.health_check_grace_period_seconds
    )
    error_message = "service의 이미지, 컨테이너 이름, 포트, Task 수와 상태 확인 유예 시간을 확인하세요."
  }

  validation {
    condition = var.service == null ? true : (
      length(var.service.subnet_ids) >= 2 &&
      length(distinct(var.service.subnet_ids)) == length(var.service.subnet_ids) &&
      alltrue([for id in var.service.subnet_ids : length(trimspace(id)) > 0]) &&
      length(var.service.security_group_ids) >= 1 &&
      length(distinct(var.service.security_group_ids)) == length(var.service.security_group_ids) &&
      alltrue([for id in var.service.security_group_ids : length(trimspace(id)) > 0]) &&
      length(trimspace(var.service.target_group_arn)) > 0 &&
      length(trimspace(var.service.execution_role_arn)) > 0 &&
      length(trimspace(var.service.task_role_arn)) > 0
    )
    error_message = "service에는 서로 다른 AZ의 Private Subnet 두 개 이상, Security Group, IP Target Group과 Execution/Task Role ARN이 필요합니다."
  }

  validation {
    condition = var.service == null ? true : anytrue([
      var.service.cpu == 256 && contains([512, 1024, 2048], var.service.memory),
      var.service.cpu == 512 && contains([1024, 2048, 3072, 4096], var.service.memory),
      var.service.cpu == 1024 && var.service.memory >= 2048 && var.service.memory <= 8192 && var.service.memory % 1024 == 0,
      var.service.cpu == 2048 && var.service.memory >= 4096 && var.service.memory <= 16384 && var.service.memory % 1024 == 0,
      var.service.cpu == 4096 && var.service.memory >= 8192 && var.service.memory <= 30720 && var.service.memory % 1024 == 0,
      var.service.cpu == 8192 && var.service.memory >= 16384 && var.service.memory <= 61440 && var.service.memory % 4096 == 0,
      var.service.cpu == 16384 && var.service.memory >= 32768 && var.service.memory <= 122880 && var.service.memory % 8192 == 0,
    ])
    error_message = "service.cpu와 service.memory는 Linux Fargate에서 지원하는 CPU/메모리 조합이어야 합니다."
  }

  validation {
    condition = var.service == null ? true : (
      alltrue([for key in keys(var.service.environment) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key))]) &&
      alltrue([for key, ref in var.service.secrets : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", key)) && startswith(ref, "arn:")]) &&
      length(setintersection(toset(keys(var.service.environment)), toset(keys(var.service.secrets)))) == 0
    )
    error_message = "환경변수 이름은 유효하고 중복되지 않아야 합니다. secrets에는 평문 대신 Secrets Manager 또는 SSM ARN 참조를 전달하세요."
  }
}

variable "tags" {
  description = "ECS와 로그 그룹에 적용할 추가 태그입니다."
  type        = map(string)
  default     = {}
}
