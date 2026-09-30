mock_provider "aws" {
  override_during = plan
}

variables {
  name               = "sample-dev"
  kubernetes_version = "1.33"
  cluster_role_arn   = "arn:aws:iam::123456789012:role/eks-cluster"
  cluster_subnet_ids = ["subnet-aaa111", "subnet-bbb222"]
}

run "private_cluster_without_nodes" {
  command = plan

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      !aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      aws_eks_cluster.this.access_config[0].authentication_mode == "API" &&
      aws_eks_cluster.this.deletion_protection &&
      aws_eks_cluster.this.bootstrap_self_managed_addons &&
      length(aws_eks_node_group.this) == 0 &&
      length(aws_iam_openid_connect_provider.this) == 0
    )
    error_message = "기본값은 private API, API Access Entry 인증, 삭제 보호와 노드 그룹 0개여야 합니다."
  }
}

run "both_api_endpoints" {
  command = plan

  variables {
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = ["203.0.113.0/24"]
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      aws_eks_cluster.this.vpc_config[0].endpoint_private_access &&
      contains(aws_eks_cluster.this.vpc_config[0].public_access_cidrs, "203.0.113.0/24")
    )
    error_message = "public과 private API 엔드포인트를 동시에 켤 수 있어야 합니다."
  }
}

run "public_only_api" {
  command = plan

  variables {
    endpoint_public_access  = true
    endpoint_private_access = false
    public_access_cidrs     = ["198.51.100.5/32"]
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access &&
      !aws_eks_cluster.this.vpc_config[0].endpoint_private_access
    )
    error_message = "public 전용 API 엔드포인트도 허용해야 합니다."
  }
}

run "multiple_on_demand_node_groups" {
  command = plan

  variables {
    node_groups = {
      app = {
        node_role_arn  = "arn:aws:iam::123456789012:role/eks-app-node"
        min_size       = 1
        desired_size   = 2
        max_size       = 4
        instance_types = ["m6i.large"]
        disk_size      = 50
        labels         = { workload = "app" }
        tags           = { Team = "app" }
      }
      system = {
        node_role_arn = "arn:aws:iam::123456789012:role/eks-system-node"
        subnet_ids    = ["subnet-ccc333", "subnet-ddd444"]
        min_size      = 1
        desired_size  = 1
        max_size      = 2
      }
    }
    tags = { Environment = "dev" }
  }

  assert {
    condition = (
      length(aws_eks_node_group.this) == 2 &&
      aws_eks_node_group.this["app"].node_group_name == "sample-dev-app" &&
      aws_eks_node_group.this["app"].capacity_type == "ON_DEMAND" &&
      aws_eks_node_group.this["app"].scaling_config[0].desired_size == 2 &&
      aws_eks_node_group.this["app"].disk_size == 50 &&
      join(",", aws_eks_node_group.this["app"].subnet_ids) == "subnet-aaa111,subnet-bbb222" &&
      join(",", aws_eks_node_group.this["system"].subnet_ids) == "subnet-ccc333,subnet-ddd444" &&
      aws_eks_node_group.this["app"].tags.Team == "app" &&
      aws_eks_node_group.this["app"].tags.Environment == "dev"
    )
    error_message = "두 그룹이 각각의 크기·Subnet·태그로 생성되고 이번 Unit에서는 On-Demand여야 합니다."
  }
}

run "irsa_oidc_provider" {
  command = plan

  variables {
    workload_identity_mode = "irsa"
  }

  assert {
    condition = (
      length(aws_iam_openid_connect_provider.this) == 1 &&
      contains(aws_iam_openid_connect_provider.this[0].client_id_list, "sts.amazonaws.com")
    )
    error_message = "IRSA 모드에서는 STS audience를 가진 OIDC Provider가 필요합니다."
  }
}

run "pod_identity_without_oidc_provider" {
  command = plan

  variables {
    workload_identity_mode = "pod_identity"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 0
    error_message = "Pod Identity 전용 모드에서 IAM OIDC Provider를 생성하면 안 됩니다."
  }
}

run "both_workload_identity_modes" {
  command = plan

  variables {
    workload_identity_mode = "both"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.this) == 1
    error_message = "both 모드에서는 IRSA용 OIDC Provider가 필요합니다."
  }
}

run "access_entries_and_scopes" {
  command = plan

  variables {
    access_entries = {
      admin = {
        principal_arn = "arn:aws:iam::123456789012:role/eks-admin"
      }
      reader = {
        principal_arn     = "arn:aws:iam::123456789012:role/eks-reader"
        kubernetes_groups = ["readers"]
      }
    }
    access_policy_associations = {
      admin = {
        entry_key  = "admin"
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        scope_type = "cluster"
      }
      reader = {
        entry_key  = "reader"
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        scope_type = "namespace"
        namespaces = ["apps"]
      }
    }
  }

  assert {
    condition = (
      length(aws_eks_access_entry.this) == 2 &&
      length(aws_eks_access_policy_association.this) == 2 &&
      aws_eks_access_policy_association.this["admin"].access_scope[0].type == "cluster" &&
      aws_eks_access_policy_association.this["reader"].access_scope[0].type == "namespace" &&
      contains(aws_eks_access_policy_association.this["reader"].access_scope[0].namespaces, "apps")
    )
    error_message = "Access Entry와 cluster/namespace 정책 범위가 각각 구성되어야 합니다."
  }
}

run "logs_and_secret_kms" {
  command = plan

  variables {
    enabled_cluster_log_types = ["api", "audit"]
    kms_key_arn               = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition = (
      length(aws_eks_cluster.this.encryption_config) == 1 &&
      aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"]) &&
      contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    )
    error_message = "KMS 키는 Secret 암호화에만 연결되고 선택한 로그가 켜져야 합니다."
  }
}

run "rejects_all_api_endpoints_disabled" {
  command = plan

  variables {
    endpoint_private_access = false
  }

  expect_failures = [aws_eks_cluster.this]
}

run "rejects_public_api_without_cidr" {
  command = plan

  variables {
    endpoint_public_access = true
  }

  expect_failures = [aws_eks_cluster.this]
}

run "rejects_cidr_when_public_api_disabled" {
  command = plan

  variables {
    public_access_cidrs = ["203.0.113.0/24"]
  }

  expect_failures = [aws_eks_cluster.this]
}

run "rejects_invalid_identity_mode" {
  command = plan

  variables {
    workload_identity_mode = "unknown"
  }

  expect_failures = [var.workload_identity_mode]
}

run "rejects_invalid_node_group_size" {
  command = plan

  variables {
    node_groups = {
      app = {
        node_role_arn = "arn:aws:iam::123456789012:role/eks-app-node"
        min_size      = 3
        desired_size  = 2
        max_size      = 4
      }
    }
  }

  expect_failures = [var.node_groups]
}

run "rejects_unknown_access_entry_key" {
  command = plan

  variables {
    access_policy_associations = {
      missing = {
        entry_key  = "unknown"
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        scope_type = "cluster"
      }
    }
  }

  expect_failures = [aws_eks_access_policy_association.this]
}

run "rejects_cluster_scope_with_namespaces" {
  command = plan

  variables {
    access_policy_associations = {
      bad = {
        entry_key  = "reader"
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
        scope_type = "cluster"
        namespaces = ["apps"]
      }
    }
  }

  expect_failures = [var.access_policy_associations]
}
