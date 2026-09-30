resource "aws_eks_cluster" "this" {
  name                          = var.name
  role_arn                      = var.cluster_role_arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = true
  deletion_protection           = var.deletion_protection
  enabled_cluster_log_types     = var.enabled_cluster_log_types
  tags                          = var.tags

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    security_group_ids      = var.cluster_security_group_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  dynamic "encryption_config" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]

    content {
      resources = ["secrets"]

      provider {
        key_arn = encryption_config.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.endpoint_public_access || var.endpoint_private_access
      error_message = "public 또는 private API 엔드포인트를 하나 이상 활성화해야 합니다."
    }

    precondition {
      condition     = var.endpoint_public_access ? length(var.public_access_cidrs) > 0 : length(var.public_access_cidrs) == 0
      error_message = "public API를 켜면 public_access_cidrs가 필요하고, 끄면 비워야 합니다."
    }
  }
}

resource "aws_iam_openid_connect_provider" "this" {
  count = contains(["irsa", "both"], var.workload_identity_mode) ? 1 : 0

  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = "STANDARD"
  kubernetes_groups = each.value.kubernetes_groups
  user_name         = each.value.username
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_policy_associations

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = try(aws_eks_access_entry.this[each.value.entry_key].principal_arn, "")
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.scope_type == "namespace" ? tolist(each.value.namespaces) : null
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.access_entries), each.value.entry_key)
      error_message = "access_policy_associations의 entry_key는 access_entries의 키여야 합니다."
    }
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-${each.key}"
  node_role_arn   = each.value.node_role_arn
  subnet_ids      = each.value.subnet_ids == null ? var.cluster_subnet_ids : each.value.subnet_ids
  capacity_type   = "ON_DEMAND"
  instance_types  = each.value.instance_types
  disk_size       = each.value.disk_size
  labels          = each.value.labels
  tags            = merge(var.tags, each.value.tags)

  scaling_config {
    min_size     = each.value.min_size
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
  }

  lifecycle {
    precondition {
      condition     = length("${var.name}-${each.key}") <= 63
      error_message = "클러스터 이름과 노드 그룹 키를 합친 이름은 63자 이하여야 합니다."
    }
  }
}
