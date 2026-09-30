variable "name" {
  description = "EKS 클러스터 이름입니다."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.name))
    error_message = "name은 영숫자로 시작하는 1~100자의 영숫자, 밑줄, 하이픈이어야 합니다."
  }
}

variable "kubernetes_version" {
  description = "생성할 EKS Kubernetes 버전입니다."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version은 1.33과 같은 major.minor 형식이어야 합니다."
  }
}

variable "cluster_role_arn" {
  description = "기존 EKS 클러스터 IAM Role ARN입니다."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.cluster_role_arn))
    error_message = "cluster_role_arn은 IAM Role ARN이어야 합니다."
  }
}

variable "cluster_subnet_ids" {
  description = "EKS 제어 영역이 사용할 Subnet ID 목록입니다. 서로 다른 AZ에 있어야 합니다."
  type        = list(string)

  validation {
    condition = (
      length(var.cluster_subnet_ids) >= 2 &&
      length(distinct(var.cluster_subnet_ids)) == length(var.cluster_subnet_ids) &&
      alltrue([for id in var.cluster_subnet_ids : can(regex("^subnet-[a-zA-Z0-9]+$", id))])
    )
    error_message = "cluster_subnet_ids에는 중복 없는 Subnet ID가 2개 이상 필요합니다."
  }
}

variable "cluster_security_group_ids" {
  description = "제어 영역 ENI에 추가할 기존 Security Group ID 목록입니다."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(distinct(var.cluster_security_group_ids)) == length(var.cluster_security_group_ids) &&
      alltrue([for id in var.cluster_security_group_ids : can(regex("^sg-[a-zA-Z0-9]+$", id))])
    )
    error_message = "cluster_security_group_ids는 중복 없는 Security Group ID 목록이어야 합니다."
  }
}

variable "endpoint_public_access" {
  description = "공개 EKS API 엔드포인트를 켤지 여부입니다."
  type        = bool
  default     = false
}

variable "endpoint_private_access" {
  description = "VPC 내부 EKS API 엔드포인트를 켤지 여부입니다."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "공개 API 엔드포인트 접근을 허용할 CIDR 목록입니다. 공개 접근 시 필수입니다."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(distinct(var.public_access_cidrs)) == length(var.public_access_cidrs) &&
      alltrue([for cidr in var.public_access_cidrs : can(cidrhost(cidr, 0))])
    )
    error_message = "public_access_cidrs는 중복 없는 유효한 CIDR 목록이어야 합니다."
  }
}

variable "enabled_cluster_log_types" {
  description = "활성화할 EKS 제어 영역 로그 유형입니다."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for log_type in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "지원하는 로그 유형은 api, audit, authenticator, controllerManager, scheduler입니다."
  }
}

variable "kms_key_arn" {
  description = "Kubernetes Secret 암호화에 사용할 기존 고객 관리형 KMS 키 ARN입니다."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn은 KMS 키 ARN이어야 합니다."
  }
}

variable "deletion_protection" {
  description = "EKS 클러스터 삭제 보호 활성화 여부입니다."
  type        = bool
  default     = true
}

variable "workload_identity_mode" {
  description = "IRSA용 OIDC Provider 및 후속 Pod Identity 준비 방식입니다."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "irsa", "pod_identity", "both"], var.workload_identity_mode)
    error_message = "workload_identity_mode는 none, irsa, pod_identity, both 중 하나여야 합니다."
  }
}

variable "access_entries" {
  description = "논리 키별 EKS API Access Entry입니다. STANDARD 유형만 생성합니다."
  type = map(object({
    principal_arn     = string
    kubernetes_groups = optional(set(string), [])
    username          = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, entry in var.access_entries :
      length(trimspace(key)) > 0 &&
      can(regex("^arn:[^:]+:iam::[0-9]{12}:(role|user)/.+$", entry.principal_arn)) &&
      alltrue([for group in entry.kubernetes_groups : length(trimspace(group)) > 0]) &&
      (entry.username == null ? true : length(trimspace(entry.username)) > 0)
    ])
    error_message = "Access Entry 키, IAM Role/User ARN, Kubernetes 그룹과 username은 유효해야 합니다."
  }
}

variable "access_policy_associations" {
  description = "논리 키별 Access Entry와 EKS 접근 정책 연결입니다."
  type = map(object({
    entry_key  = string
    policy_arn = string
    scope_type = string
    namespaces = optional(set(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, association in var.access_policy_associations :
      length(trimspace(key)) > 0 &&
      length(trimspace(association.entry_key)) > 0 &&
      can(regex("^arn:[^:]+:eks::aws:cluster-access-policy/.+$", association.policy_arn)) &&
      contains(["cluster", "namespace"], association.scope_type) &&
      (association.scope_type == "cluster" ? length(association.namespaces) == 0 : length(association.namespaces) > 0) &&
      alltrue([for namespace in association.namespaces : length(trimspace(namespace)) > 0])
    ])
    error_message = "접근 정책 연결에는 유효한 Entry 키·정책 ARN·범위와 해당 namespace 목록이 필요합니다."
  }
}

variable "node_groups" {
  description = "논리 키별 EKS 관리형 On-Demand 노드 그룹입니다."
  type = map(object({
    node_role_arn  = string
    subnet_ids     = optional(list(string))
    min_size       = number
    desired_size   = number
    max_size       = number
    instance_types = optional(list(string), ["t3.medium"])
    disk_size      = optional(number, 20)
    labels         = optional(map(string), {})
    tags           = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, group in var.node_groups :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", key)) &&
      can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", group.node_role_arn)) &&
      (group.subnet_ids == null ? true : (
        length(group.subnet_ids) >= 2 &&
        length(distinct(group.subnet_ids)) == length(group.subnet_ids) &&
        alltrue([for id in group.subnet_ids : can(regex("^subnet-[a-zA-Z0-9]+$", id))])
      )) &&
      group.min_size >= 0 &&
      group.min_size <= group.desired_size &&
      group.desired_size <= group.max_size &&
      group.max_size >= 1 &&
      floor(group.min_size) == group.min_size &&
      floor(group.desired_size) == group.desired_size &&
      floor(group.max_size) == group.max_size &&
      length(group.instance_types) >= 1 &&
      alltrue([for instance_type in group.instance_types : length(trimspace(instance_type)) > 0]) &&
      group.disk_size >= 20 &&
      floor(group.disk_size) == group.disk_size
    ])
    error_message = "노드 그룹 키·Role ARN·Subnet·인스턴스 유형·디스크 크기와 min <= desired <= max 크기를 확인하세요."
  }
}

variable "tags" {
  description = "클러스터, OIDC Provider, 노드 그룹에 적용할 공통 태그입니다."
  type        = map(string)
  default     = {}
}
