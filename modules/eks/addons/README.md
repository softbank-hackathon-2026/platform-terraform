# EKS Add-On module

이미 생성된 EKS 클러스터에 명시한 Amazon EKS 관리형 Add-On만 설치·관리합니다. `addons = {}`이면 이 모듈의 관리 대상은 0개입니다. EKS 클러스터 생성 시 설치된 자체 관리형 `vpc-cni`, `kube-proxy`, CoreDNS는 이 설정만으로 제거되지 않습니다.

이 모듈은 AWS Provider만 사용합니다. 클러스터, 노드 그룹, Kubernetes/Helm 리소스, AWS Load Balancer Controller를 만들지 않습니다. 실제 환경에서 클러스터와 Add-On의 Terraform 상태를 분리하는 Root Module·Backend 예시는 후속 EKS Unit 5에서 구성합니다.

## 적용 순서와 버전 선택

1. 클러스터를 먼저 만들고 활성 상태를 확인합니다. 노드 기반 Add-On의 Pod 실행을 확인하려면 실행 가능한 Linux 노드도 필요합니다.
2. 클러스터 Kubernetes 버전에 호환되는 Add-On 버전을 `aws eks describe-addon-versions --addon-name <name> --kubernetes-version <version>`으로 조회합니다. 조회한 정확한 버전을 `addon_version`에 지정합니다. 모듈은 최신 버전을 자동 선택하지 않습니다.
3. 사용자 설정이 필요하면 `aws eks describe-addon-configuration --addon-name <name> --addon-version <version>`에서 해당 버전의 JSON 스키마를 확인합니다. IAM 권한이 필요한 Add-On은 서비스 계정 이름과 권장 정책도 확인하고, 필요한 Role·Policy·신뢰 정책을 먼저 준비합니다.
4. Terraform Plan에서 버전, 설정값, IAM 연결, 기존 자체 관리 Add-On과의 충돌 가능성을 검토한 뒤 적용합니다. 적용 후 AWS Add-On 상태와 실제 Pod 실행을 별도로 확인합니다.

기본 충돌 정책은 생성·갱신 모두 `NONE`입니다. 기존 자체 관리 구성과 충돌하면 자동 덮어쓰기 없이 적용이 실패합니다. 전환하기로 결정한 Add-On에서만 `resolve_conflicts_on_create = "OVERWRITE"`를 명시할 수 있습니다. 갱신 시에는 `PRESERVE`로 기존 Kubernetes 설정을 보존하거나 `OVERWRITE`를 명시할 수 있습니다. `OVERWRITE`는 기존 수정값에 영향을 줄 수 있습니다.

## 사용 예시

아래 예시의 버전 변수에는 조회해 확인한 정확한 버전을 넣습니다. `cluster_name`은 이미 생성된 클러스터의 이름입니다.

```hcl
module "eks_addons" {
  source = "../../modules/eks/addons"

  cluster_name = "sample-dev"
  addons = {
    coredns = {
      addon_version = var.coredns_addon_version
    }
    vpc-cni = {
      addon_version = var.vpc_cni_addon_version
    }
  }
}
```

Pod Identity를 선택했다면 Agent를 목록에 반드시 명시합니다. Agent가 사용할 `eks-auth:AssumeRoleForPodIdentity` 권한은 **노드 IAM Role**에 있어야 합니다. Agent 자체에는 IRSA Role이나 Pod Identity Association을 지정하지 않습니다. private 노드는 EKS Auth API용 VPC Endpoint와 ECR 이미지 접근 경로가 필요합니다. Add-On이 Pod Identity를 사용할 때는 해당 Add-On의 서비스 계정에 연결할 기존 IAM Role ARN을 `pod_identity_associations`에 지정합니다.

```hcl
module "eks_addons" {
  source = "../../modules/eks/addons"

  cluster_name           = "sample-dev"
  workload_identity_mode = "pod_identity"

  addons = {
    eks-pod-identity-agent = {
      addon_version = var.pod_identity_agent_version
    }
    aws-ebs-csi-driver = {
      addon_version = var.ebs_csi_addon_version
      pod_identity_associations = {
        ebs-csi-controller-sa = module.ebs_csi_role.role_arn
      }
    }
  }
}
```

`workload_identity_mode = "irsa"`이면 Agent 없이 Add-On별 `service_account_role_arn`을 사용할 수 있습니다. 이때 클러스터의 IAM OIDC Provider와 ServiceAccount를 신뢰하는 Role이 이미 필요합니다. `both`이면 Add-On마다 IRSA 또는 Pod Identity를 하나씩 선택할 수 있습니다. **한 Add-On에 두 IAM 연결을 동시에 지정하는 설정은 거부합니다.** IAM 연결을 생략한 Add-On은 필요한 AWS 권한을 노드 Role에서 가져올 수 있으므로 해당 Add-On의 권한 모델을 검토하세요.

Add-On의 Pod Identity Association은 Add-On 리소스가 소유합니다. 같은 ServiceAccount를 별도의 `aws_eks_pod_identity_association`으로 함께 관리하지 마세요. Add-On의 Association 목록을 갱신할 때 기존 항목을 누락하면 제거될 수 있고, 변경 시 Add-On Pod가 재시작될 수 있습니다. Add-On을 Terraform에서 삭제하면 관련 워크로드와 Add-On 소유 Association에 영향이 있으므로 삭제 계획을 확인하세요. 이 모듈은 삭제 시 리소스 보존 옵션을 노출하지 않습니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `cluster_name` | `string` | 필수 | 이미 생성된 EKS 클러스터 이름입니다. |
| `workload_identity_mode` | `string` | `"none"` | `none`, `irsa`, `pod_identity`, `both` 중 선택합니다. Pod Identity를 선택하면 Agent가 필수입니다. |
| `addons` | `map(object)` | `{}` | Add-On 이름을 키로 하는 명시적 관리 대상과 버전·설정입니다. |
| `tags` | `map(string)` | `{}` | 모든 Add-On에 적용하는 공통 태그입니다. |

### `addons` 내부 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `addon_version` | `string` | 필수 | 클러스터와 호환되는 정확한 Add-On 버전입니다. |
| `configuration_values_json` | `string` | `null` | 버전별 설정 스키마에 맞는 선택적 JSON 문자열입니다. |
| `service_account_role_arn` | `string` | `null` | IRSA 방식으로 Add-On 서비스 계정에 연결할 기존 IAM Role ARN입니다. |
| `pod_identity_associations` | `map(string)` | `{}` | Add-On 서비스 계정 이름을 키, 기존 Pod Identity IAM Role ARN을 값으로 하는 Map입니다. |
| `resolve_conflicts_on_create` | `string` | `"NONE"` | 생성 시 `NONE` 또는 명시적 `OVERWRITE`입니다. |
| `resolve_conflicts_on_update` | `string` | `"NONE"` | 갱신 시 `NONE`, `PRESERVE`, `OVERWRITE` 중 선택합니다. |
| `tags` | `map(string)` | `{}` | Add-On별 태그입니다. 공통 태그와 키가 같으면 덮어씁니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `addon_arns` | Add-On 이름별 ARN Map입니다. 모드와 IAM 연결 입력도 이 출력의 사전 조건에서 검사합니다. |
| `addon_versions` | Add-On 이름별 지정 버전 Map입니다. |
| `pod_identity_agent_arn` | Agent Add-On ARN입니다. 설치하지 않으면 `null`입니다. |

## 검증 범위

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```

로컬 mock Plan은 선택 리소스, 입력 검증, 설정 전달을 확인합니다. 실제 Add-On 지원 여부와 버전 호환성, 설정 JSON 스키마, IAM 권한, 기존 자체 관리 Add-On 전환, Pod Ready, 변경 시 재시작, AWS Plan·Apply는 검증하지 않았습니다.
