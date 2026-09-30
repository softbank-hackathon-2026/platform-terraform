# EKS module

EKS 클러스터 하나와 선택적인 관리형 On-Demand 노드 그룹, Access Entry, IRSA용 IAM OIDC Provider를 구성합니다. VPC/Subnet, Security Group, 클러스터·노드 IAM Role, KMS 키는 기존 리소스를 입력받습니다.

이 모듈은 AWS 관리형 Add-On, Pod Identity Agent/Association, Kubernetes 리소스, AWS Load Balancer Controller를 설치하지 않습니다. 이들은 클러스터 생성 후 별도 Terraform 구성·상태에서 관리할 계획입니다. Gateway API `HTTPRoute`를 위한 Controller와 CRD도 후속 Unit 범위입니다.

## 기본 사용 예시

```hcl
module "eks" {
  source = "../../modules/eks"

  name               = "sample-dev"
  kubernetes_version = "1.33"
  cluster_role_arn   = module.eks_cluster_role.role_arn
  cluster_subnet_ids = values(module.network.private_subnet_ids)

  tags = {
    Environment = "dev"
  }
}
```

기본값은 private API 엔드포인트만 활성화하며 노드 그룹을 만들지 않습니다. 클러스터 생성자의 관리자 권한과 EKS 기본 자체 관리 Add-On 설치는 활성화합니다. private API를 사용하는 Terraform 실행기와 운영자는 VPC 내부 경로, VPN 또는 적절한 연결이 필요합니다. 실제 AWS 생성 시에는 클러스터 Role에 필요한 IAM 정책이 연결되어 있어야 합니다.

## API 엔드포인트

public·private 엔드포인트를 동시에 켜려면 다음처럼 설정합니다. public만 켜려면 `endpoint_private_access = false`로 바꿉니다. 두 엔드포인트를 모두 끄는 값은 거부합니다.

```hcl
module "eks" {
  source = "../../modules/eks"

  name                    = "sample-dev"
  kubernetes_version      = "1.33"
  cluster_role_arn        = module.eks_cluster_role.role_arn
  cluster_subnet_ids      = values(module.network.private_subnet_ids)
  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = ["203.0.113.0/24"]
}
```

public API를 켜면 `public_access_cidrs`를 반드시 지정합니다. 실제 운영자의 출발지 CIDR로 바꾸세요. public API를 끄면 이 목록은 비워야 합니다. `endpoint_private_access = true`여도 public API 접근은 지정한 CIDR의 영향을 받습니다.

## 관리형 노드 그룹

`node_groups`는 논리 키로 구분합니다. 그룹별 Subnet을 생략하면 클러스터 Subnet을 사용합니다. 현재 Unit은 `ON_DEMAND`만 구성하며, 시작 템플릿과 Spot 선택은 후속 Unit에서 추가할 계획입니다.

```hcl
module "eks" {
  source = "../../modules/eks"

  name               = "sample-dev"
  kubernetes_version = "1.33"
  cluster_role_arn   = module.eks_cluster_role.role_arn
  cluster_subnet_ids = values(module.network.private_subnet_ids)

  node_groups = {
    system = {
      node_role_arn = module.eks_node_role.role_arn
      min_size      = 1
      desired_size  = 2
      max_size      = 3
    }
    app = {
      node_role_arn  = module.eks_node_role.role_arn
      subnet_ids     = values(module.network.private_subnet_ids)
      min_size       = 1
      desired_size   = 2
      max_size       = 5
      instance_types = ["m6i.large"]
      disk_size      = 50
      labels         = { workload = "app" }
    }
  }
}
```

노드 Role의 필수 정책 연결, Subnet의 서로 다른 AZ 배치와 라우팅, 제어 영역과 노드 간 Security Group 통신은 호출자가 준비합니다. 클러스터와 노드 Role 정책 연결이 완료된 뒤 EKS가 생성되도록 Root Module의 의존 관계를 확인하세요. private Subnet에서 이미지 다운로드나 AWS API 접근이 필요하면 NAT 또는 해당 VPC Endpoint도 준비해야 합니다. 이 모듈은 `desired_size`를 Terraform에서 관리하므로 외부 오토스케일러가 같은 값을 바꾸면 다음 Plan에서 차이가 나타날 수 있습니다.

## 접근 권한과 워크로드 인증

클러스터 접근은 EKS `API` 인증 모드와 Access Entry로 관리합니다. `access_policy_associations`는 `access_entries`의 논리 키를 참조합니다. `scope_type = "cluster"`이면 `namespaces`는 비워야 하며, `namespace`이면 하나 이상 지정해야 합니다. `kubernetes_groups`를 사용하면 해당 그룹에 대한 Kubernetes RBAC도 별도로 구성해야 합니다. 생성자에게 EKS가 부여한 관리자 권한은 이 모듈의 `access_entries`에 나타나지 않을 수 있습니다.

```hcl
access_entries = {
  operator = {
    principal_arn = module.operator_role.role_arn
  }
}

access_policy_associations = {
  operator = {
    entry_key  = "operator"
    policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
    scope_type = "namespace"
    namespaces = ["apps"]
  }
}
```

`workload_identity_mode`는 클러스터 접근 인증과 별개입니다. `irsa` 또는 `both`를 선택하면 이 모듈이 IAM OIDC Provider를 만들고 `oidc_provider_arn`을 출력합니다. `pod_identity` 또는 `both`를 선택해도 이 Unit은 Agent와 Association을 생성하지 않습니다. Pod Identity Agent는 후속 Add-On 구성에서 준비하고, 워크로드별 IAM Role과 ServiceAccount 연결은 해당 워크로드의 소유자가 구성해야 합니다. IRSA용 IAM OIDC Provider를 만들 때 IAM이 OIDC 서버 인증서 thumbprint를 조회하므로 실행 환경에서 issuer 접근이 가능해야 합니다.

## 암호화·로그·삭제

`kms_key_arn`을 지정하면 Kubernetes Secret의 고객 관리형 키 암호화 설정을 추가합니다. KMS 키 정책과 실행 주체의 권한은 별도로 확인해야 합니다. `enabled_cluster_log_types`로 `api`, `audit`, `authenticator`, `controllerManager`, `scheduler` 로그를 선택할 수 있습니다. 이 모듈은 CloudWatch 로그 그룹 보존 기간을 설정하지 않습니다.

`deletion_protection`은 기본 `true`입니다. 클러스터를 실제로 삭제하려면 먼저 `false`로 변경해 적용한 뒤 삭제 작업을 진행해야 합니다. 이 모듈의 로컬 mock 테스트는 실제 AWS의 삭제 보호, IAM 권한, 네트워크 접속, 노드 Ready 상태를 확인하지 않습니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | EKS 클러스터 이름과 노드 그룹 이름의 접두사입니다. |
| `kubernetes_version` | `string` | 필수 | 원하는 Kubernetes major.minor 버전입니다. |
| `cluster_role_arn` | `string` | 필수 | 기존 EKS 클러스터 IAM Role ARN입니다. |
| `cluster_subnet_ids` | `list(string)` | 필수 | 제어 영역용 Subnet ID 2개 이상입니다. 서로 다른 AZ여야 합니다. |
| `cluster_security_group_ids` | `list(string)` | `[]` | 제어 영역 ENI에 추가할 기존 Security Group ID입니다. |
| `endpoint_public_access` | `bool` | `false` | 공개 Kubernetes API 엔드포인트 활성화 여부입니다. |
| `endpoint_private_access` | `bool` | `true` | VPC 내부 Kubernetes API 엔드포인트 활성화 여부입니다. |
| `public_access_cidrs` | `list(string)` | `[]` | 공개 API 접근을 허용할 CIDR입니다. 공개 API를 켜면 필수입니다. |
| `enabled_cluster_log_types` | `set(string)` | `[]` | 켤 제어 영역 로그 유형 목록입니다. |
| `kms_key_arn` | `string` | `null` | Kubernetes Secret 암호화에 사용할 기존 KMS 키 ARN입니다. |
| `deletion_protection` | `bool` | `true` | EKS 클러스터 삭제 보호 여부입니다. |
| `workload_identity_mode` | `string` | `"none"` | `none`, `irsa`, `pod_identity`, `both` 중 선택합니다. |
| `access_entries` | `map(object)` | `{}` | 논리 키별 EKS Access Entry입니다. |
| `access_policy_associations` | `map(object)` | `{}` | 논리 키별 Access Entry와 EKS 접근 정책 연결입니다. |
| `node_groups` | `map(object)` | `{}` | 논리 키별 관리형 On-Demand 노드 그룹입니다. |
| `tags` | `map(string)` | `{}` | 클러스터·OIDC Provider·노드 그룹의 공통 태그입니다. |

### `access_entries` 내부 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `principal_arn` | `string` | 필수 | 접근을 허용할 IAM Role 또는 User ARN입니다. |
| `kubernetes_groups` | `set(string)` | `[]` | 별도 RBAC에 연결할 Kubernetes 그룹 이름입니다. |
| `username` | `string` | `null` | 선택적 Kubernetes 사용자 이름입니다. |

### `access_policy_associations` 내부 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `entry_key` | `string` | 필수 | 연결할 `access_entries`의 논리 키입니다. |
| `policy_arn` | `string` | 필수 | EKS 클러스터 접근 정책 ARN입니다. |
| `scope_type` | `string` | 필수 | `cluster` 또는 `namespace`입니다. |
| `namespaces` | `set(string)` | `[]` | `namespace` 범위에서 허용할 네임스페이스입니다. |

### `node_groups` 내부 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `node_role_arn` | `string` | 필수 | 기존 노드 IAM Role ARN입니다. |
| `subnet_ids` | `list(string)` | `null` | 그룹별 Subnet ID입니다. 생략하면 클러스터 Subnet을 사용합니다. |
| `min_size` | `number` | 필수 | 노드 수 하한입니다. |
| `desired_size` | `number` | 필수 | Terraform이 관리할 희망 노드 수입니다. |
| `max_size` | `number` | 필수 | 노드 수 상한입니다. |
| `instance_types` | `list(string)` | `["t3.medium"]` | 관리형 노드 그룹의 EC2 인스턴스 유형입니다. |
| `disk_size` | `number` | `20` | 노드 루트 디스크 크기(GiB)입니다. |
| `labels` | `map(string)` | `{}` | 노드에 적용할 Kubernetes 레이블입니다. |
| `tags` | `map(string)` | `{}` | 이 노드 그룹에 적용할 태그입니다. 공통 태그와 같은 키면 덮어씁니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `cluster_name` | 클러스터 이름입니다. 후속 Add-On과 Controller 구성에 사용합니다. |
| `cluster_arn` | 클러스터 ARN입니다. |
| `cluster_endpoint` | Kubernetes API 엔드포인트입니다. |
| `cluster_certificate_authority_data` | Kubernetes API CA 인증서의 Base64 데이터입니다. |
| `cluster_oidc_issuer_url` | 클러스터 OIDC issuer URL입니다. IAM OIDC Provider를 만들지 않아도 출력합니다. |
| `cluster_primary_security_group_id` | EKS가 생성한 기본 클러스터 Security Group ID입니다. |
| `node_group_names` | 논리 키별 노드 그룹 이름 Map입니다. |
| `node_group_arns` | 논리 키별 노드 그룹 ARN Map입니다. |
| `oidc_provider_arn` | IRSA용 IAM OIDC Provider ARN입니다. 없으면 `null`입니다. |

## 로컬 검증

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```

mock Plan 테스트는 Terraform 구성과 선택 리소스만 확인합니다. 실제 AWS Plan·Apply, 클러스터 API 연결, 노드 Ready, Add-On 및 `HTTPRoute` 동작은 아직 검증하지 않았습니다.
