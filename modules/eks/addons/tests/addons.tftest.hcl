mock_provider "aws" {
  override_during = plan
}

variables {
  cluster_name = "sample-dev"
}

run "empty_addon_selection" {
  command = plan

  assert {
    condition = (
      length(aws_eks_addon.pod_identity_agent) == 0 &&
      length(aws_eks_addon.other) == 0 &&
      length(output.addon_arns) == 0 &&
      output.pod_identity_agent_arn == null
    )
    error_message = "빈 목록은 이 모듈이 관리하는 Add-On을 생성하지 않아야 합니다."
  }
}

run "explicit_pinned_addons_only" {
  command = plan

  variables {
    addons = {
      coredns = { addon_version = "v1.0.0-eksbuild.1" }
      vpc-cni = { addon_version = "v1.1.0-eksbuild.1" }
    }
  }

  assert {
    condition = (
      length(aws_eks_addon.other) == 2 &&
      length(aws_eks_addon.pod_identity_agent) == 0 &&
      aws_eks_addon.other["coredns"].addon_version == "v1.0.0-eksbuild.1" &&
      aws_eks_addon.other["vpc-cni"].resolve_conflicts_on_create == "NONE" &&
      aws_eks_addon.other["vpc-cni"].resolve_conflicts_on_update == "NONE"
    )
    error_message = "명시한 두 Add-On만 지정 버전과 NONE 충돌 정책으로 계획되어야 합니다."
  }
}

run "pod_identity_agent_and_association" {
  command = plan

  variables {
    workload_identity_mode = "pod_identity"
    addons = {
      eks-pod-identity-agent = { addon_version = "v1.0.0-eksbuild.1" }
      aws-ebs-csi-driver = {
        addon_version = "v1.1.0-eksbuild.1"
        pod_identity_associations = {
          ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/ebs-csi"
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_eks_addon.pod_identity_agent) == 1 &&
      length(aws_eks_addon.other) == 1 &&
      aws_eks_addon.pod_identity_agent["eks-pod-identity-agent"].service_account_role_arn == null &&
      length(aws_eks_addon.other["aws-ebs-csi-driver"].pod_identity_association) == 1 &&
      anytrue([
        for association in aws_eks_addon.other["aws-ebs-csi-driver"].pod_identity_association :
        association.service_account == "ebs-csi-controller-sa" &&
        association.role_arn == "arn:aws:iam::123456789012:role/ebs-csi"
      ])
    )
    error_message = "Pod Identity 모드에서 Agent와 Add-On 소유 Association이 계획되어야 합니다."
  }
}

run "irsa_without_agent" {
  command = plan

  variables {
    workload_identity_mode = "irsa"
    addons = {
      vpc-cni = {
        addon_version            = "v1.1.0-eksbuild.1"
        service_account_role_arn = "arn:aws:iam::123456789012:role/vpc-cni"
      }
    }
  }

  assert {
    condition = (
      length(aws_eks_addon.pod_identity_agent) == 0 &&
      aws_eks_addon.other["vpc-cni"].service_account_role_arn == "arn:aws:iam::123456789012:role/vpc-cni" &&
      length(aws_eks_addon.other["vpc-cni"].pod_identity_association) == 0
    )
    error_message = "IRSA Add-On은 Agent와 Pod Identity Association 없이 Role ARN을 사용해야 합니다."
  }
}

run "both_modes_with_separate_addon_roles" {
  command = plan

  variables {
    workload_identity_mode = "both"
    addons = {
      eks-pod-identity-agent = { addon_version = "v1.0.0-eksbuild.1" }
      vpc-cni = {
        addon_version            = "v1.1.0-eksbuild.1"
        service_account_role_arn = "arn:aws:iam::123456789012:role/vpc-cni"
      }
      aws-ebs-csi-driver = {
        addon_version = "v1.1.0-eksbuild.1"
        pod_identity_associations = {
          ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/ebs-csi"
        }
      }
    }
  }

  assert {
    condition = (
      length(aws_eks_addon.pod_identity_agent) == 1 &&
      length(aws_eks_addon.other) == 2 &&
      aws_eks_addon.other["vpc-cni"].service_account_role_arn != null &&
      length(aws_eks_addon.other["aws-ebs-csi-driver"].pod_identity_association) == 1
    )
    error_message = "both 모드는 Add-On별로 IRSA 또는 Pod Identity를 각각 선택할 수 있어야 합니다."
  }
}

run "custom_config_tags_and_explicit_conflict_policy" {
  command = plan

  variables {
    tags = { Environment = "dev", Team = "platform" }
    addons = {
      coredns = {
        addon_version               = "v1.0.0-eksbuild.1"
        configuration_values_json   = jsonencode({ replicaCount = 2 })
        resolve_conflicts_on_create = "OVERWRITE"
        resolve_conflicts_on_update = "PRESERVE"
        tags                        = { Team = "dns" }
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_eks_addon.other["coredns"].configuration_values).replicaCount == 2 &&
      aws_eks_addon.other["coredns"].resolve_conflicts_on_create == "OVERWRITE" &&
      aws_eks_addon.other["coredns"].resolve_conflicts_on_update == "PRESERVE" &&
      aws_eks_addon.other["coredns"].tags.Team == "dns" &&
      aws_eks_addon.other["coredns"].tags.Environment == "dev"
    )
    error_message = "선택한 설정 JSON, 충돌 정책과 Add-On별 태그 덮어쓰기가 반영되어야 합니다."
  }
}

run "rejects_missing_agent_for_pod_identity" {
  command = plan

  variables {
    workload_identity_mode = "pod_identity"
  }

  expect_failures = [output.addon_arns]
}

run "rejects_agent_in_irsa_mode" {
  command = plan

  variables {
    workload_identity_mode = "irsa"
    addons = {
      eks-pod-identity-agent = { addon_version = "v1.0.0-eksbuild.1" }
    }
  }

  expect_failures = [output.addon_arns]
}

run "rejects_agent_iam_role" {
  command = plan

  variables {
    workload_identity_mode = "pod_identity"
    addons = {
      eks-pod-identity-agent = {
        addon_version            = "v1.0.0-eksbuild.1"
        service_account_role_arn = "arn:aws:iam::123456789012:role/incorrect"
      }
    }
  }

  expect_failures = [output.addon_arns]
}

run "rejects_irsa_role_without_irsa_mode" {
  command = plan

  variables {
    addons = {
      vpc-cni = {
        addon_version            = "v1.1.0-eksbuild.1"
        service_account_role_arn = "arn:aws:iam::123456789012:role/vpc-cni"
      }
    }
  }

  expect_failures = [output.addon_arns]
}

run "rejects_pod_identity_association_without_mode" {
  command = plan

  variables {
    workload_identity_mode = "irsa"
    addons = {
      aws-ebs-csi-driver = {
        addon_version = "v1.1.0-eksbuild.1"
        pod_identity_associations = {
          ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/ebs-csi"
        }
      }
    }
  }

  expect_failures = [output.addon_arns]
}

run "rejects_two_identity_bindings_on_one_addon" {
  command = plan

  variables {
    workload_identity_mode = "both"
    addons = {
      eks-pod-identity-agent = { addon_version = "v1.0.0-eksbuild.1" }
      aws-ebs-csi-driver = {
        addon_version            = "v1.1.0-eksbuild.1"
        service_account_role_arn = "arn:aws:iam::123456789012:role/ebs-csi-irsa"
        pod_identity_associations = {
          ebs-csi-controller-sa = "arn:aws:iam::123456789012:role/ebs-csi-pod-identity"
        }
      }
    }
  }

  expect_failures = [output.addon_arns]
}

run "rejects_empty_version" {
  command = plan

  variables {
    addons = { coredns = { addon_version = "" } }
  }

  expect_failures = [var.addons]
}

run "rejects_invalid_configuration_json" {
  command = plan

  variables {
    addons = {
      coredns = {
        addon_version             = "v1.0.0-eksbuild.1"
        configuration_values_json = "{invalid"
      }
    }
  }

  expect_failures = [var.addons]
}

run "rejects_invalid_create_conflict_policy" {
  command = plan

  variables {
    addons = {
      coredns = {
        addon_version               = "v1.0.0-eksbuild.1"
        resolve_conflicts_on_create = "PRESERVE"
      }
    }
  }

  expect_failures = [var.addons]
}

run "rejects_invalid_update_conflict_policy" {
  command = plan

  variables {
    addons = {
      coredns = {
        addon_version               = "v1.0.0-eksbuild.1"
        resolve_conflicts_on_update = "INVALID"
      }
    }
  }

  expect_failures = [var.addons]
}
