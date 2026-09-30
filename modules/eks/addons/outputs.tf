output "addon_arns" {
  description = "관리하는 Add-On 이름별 ARN입니다."
  value = merge(
    { for name, addon in aws_eks_addon.pod_identity_agent : name => addon.arn },
    { for name, addon in aws_eks_addon.other : name => addon.arn }
  )

  precondition {
    condition = (
      contains(["pod_identity", "both"], var.workload_identity_mode) ==
      contains(keys(var.addons), "eks-pod-identity-agent")
    )
    error_message = "pod_identity 또는 both 모드에서는 eks-pod-identity-agent를 명시해야 하고, 다른 모드에서는 지정할 수 없습니다."
  }

  precondition {
    condition = alltrue([
      for name, addon in var.addons :
      name == "eks-pod-identity-agent" ? (
        addon.service_account_role_arn == null && length(addon.pod_identity_associations) == 0
        ) : (
        !(addon.service_account_role_arn != null && length(addon.pod_identity_associations) > 0) &&
        (addon.service_account_role_arn == null || contains(["irsa", "both"], var.workload_identity_mode)) &&
        (length(addon.pod_identity_associations) == 0 || contains(["pod_identity", "both"], var.workload_identity_mode))
      )
    ])
    error_message = "Agent에는 IAM 연결을 지정할 수 없고, 다른 Add-On에는 선택한 모드에 맞는 IRSA 또는 Pod Identity 연결 하나만 지정할 수 있습니다."
  }
}

output "addon_versions" {
  description = "관리하는 Add-On 이름별 지정 버전입니다."
  value = merge(
    { for name, addon in aws_eks_addon.pod_identity_agent : name => addon.addon_version },
    { for name, addon in aws_eks_addon.other : name => addon.addon_version }
  )
}

output "pod_identity_agent_arn" {
  description = "Pod Identity Agent Add-On ARN입니다. 미설치면 null입니다."
  value       = try(aws_eks_addon.pod_identity_agent["eks-pod-identity-agent"].arn, null)
}
