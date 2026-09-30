variable "cluster_name" {
  description = "이미 생성된 EKS 클러스터 이름입니다."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name은 영숫자로 시작하는 1~100자의 EKS 클러스터 이름이어야 합니다."
  }
}

variable "workload_identity_mode" {
  description = "클러스터에서 선택한 워크로드 IAM 인증 방식입니다."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "irsa", "pod_identity", "both"], var.workload_identity_mode)
    error_message = "workload_identity_mode는 none, irsa, pod_identity, both 중 하나여야 합니다."
  }
}

variable "addons" {
  description = "이 모듈이 관리할 Add-On 이름별 명시적 버전과 설정입니다."
  type = map(object({
    addon_version               = string
    configuration_values_json   = optional(string)
    service_account_role_arn    = optional(string)
    pod_identity_associations   = optional(map(string), {})
    resolve_conflicts_on_create = optional(string, "NONE")
    resolve_conflicts_on_update = optional(string, "NONE")
    tags                        = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, addon in var.addons :
      length(trimspace(name)) > 0 &&
      length(trimspace(addon.addon_version)) > 0 &&
      (addon.configuration_values_json == null ? true : can(jsondecode(addon.configuration_values_json))) &&
      (addon.service_account_role_arn == null ? true : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", addon.service_account_role_arn))) &&
      alltrue([
        for service_account, role_arn in addon.pod_identity_associations :
        length(trimspace(service_account)) > 0 &&
        can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", role_arn))
      ]) &&
      contains(["NONE", "OVERWRITE"], addon.resolve_conflicts_on_create) &&
      contains(["NONE", "PRESERVE", "OVERWRITE"], addon.resolve_conflicts_on_update)
    ])
    error_message = "Add-On 이름·버전·JSON·IAM Role ARN·충돌 정책 입력을 확인하세요."
  }
}

variable "tags" {
  description = "모든 Add-On에 적용할 공통 태그입니다."
  type        = map(string)
  default     = {}
}
