resource "aws_eks_addon" "pod_identity_agent" {
  for_each = {
    for name, addon in var.addons : name => addon
    if name == "eks-pod-identity-agent"
  }

  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  configuration_values        = each.value.configuration_values_json
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  tags                        = merge(var.tags, each.value.tags)
}

resource "aws_eks_addon" "other" {
  for_each = {
    for name, addon in var.addons : name => addon
    if name != "eks-pod-identity-agent"
  }

  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  configuration_values        = each.value.configuration_values_json
  service_account_role_arn    = each.value.service_account_role_arn
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  tags                        = merge(var.tags, each.value.tags)

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_associations

    content {
      service_account = pod_identity_association.key
      role_arn        = pod_identity_association.value
    }
  }

  depends_on = [aws_eks_addon.pod_identity_agent]
}
