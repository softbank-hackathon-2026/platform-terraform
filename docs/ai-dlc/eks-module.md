# EKS 및 클러스터 공통 구성 AI-DLC

마지막 확인일: 2026-09-24

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 2026-09-24 승인. Gateway API `HTTPRoute` 요구 포함 |
| Inception | 2026-09-24 승인 |
| Construction | Unit 1·2 구현·Test·Review 완료. Unit 3~5 미시작 |
| 로컬 검증 | Unit 1·2 포맷·`terraform validate` 통과, 각각 mock Plan 16개 통과 |
| 실제 AWS Plan과 Apply | 미수행 |
| 배포와 Operation | 미수행 |
| 커밋과 푸시 | Unit 1 `15fe220`, Unit 2 `4c6c680` 원격 main 확인 |

## 1. Ideation — 승인 완료

### 문제 정의

현재 저장소에는 EKS 클러스터와 관리형 노드 그룹을 재사용 가능한 방식으로 만드는 모듈이 없습니다. 클러스터의 인증 준비, AWS 관리형 Add-On, AWS Load Balancer Controller를 함께 고려해야 하지만, EKS 설정 변경만으로 Controller가 불필요하게 갱신되지 않도록 변경 주기를 분리해야 합니다. Kubernetes Gateway API의 `HTTPRoute`로 HTTP 서비스를 노출할 수 있어야 합니다.

### 사용자

- 환경별 EKS 클러스터와 공통 구성 요소를 만드는 Terraform 작성자
- 클러스터 접근, 노드 그룹, Add-On과 HTTP 라우팅을 운영하는 담당자

### 성공 기준

- EKS 클러스터 하나와 관리형 노드 그룹 0개 이상을 구성할 수 있습니다.
- IRSA용 OIDC 연결과 Pod Identity를 선택하거나 함께 준비하고, 워크로드별로 인증 방법을 선택할 수 있습니다.
- 필요한 AWS 관리형 Add-On만 명시적으로 관리합니다.
- 클러스터 생성 후 AWS Load Balancer Controller와 Gateway API CRD를 자동으로 설치할 수 있고, `HTTPRoute`가 ALB를 통해 백엔드 Service로 전달되는지 검증할 수 있습니다.
- 일반적인 EKS 설정 변경이 Controller 갱신으로 이어지지 않도록 독립적인 구성·상태 경계를 두고 검증할 수 있습니다.

### Scope

- 기존 Network, Security Group, IAM, KMS 모듈과 연결할 수 있는 EKS 클러스터 및 관리형 노드 그룹 모듈
- Kubernetes API 접근 설정, 제어 영역 로그, Access Entry, 선택적 고객 관리형 KMS 키, 선택적 IAM OIDC Provider
- Pod Identity Agent를 포함한 선택적 AWS 관리형 Add-On의 설치·버전 관리 방식
- 별도 Terraform 구성·상태에서 Load Balancer Controller의 IAM 연결, Gateway API CRD, 버전을 고정한 Helm 설치와 변경 관리
- `GatewayClass`·`Gateway`·`HTTPRoute`를 이용한 HTTP 연결 검증 방안

### Non-goals

- Fargate, EKS Auto Mode, 자체 관리 노드
- 애플리케이션별 Kubernetes 리소스와 Helm 차트 배포
- 기존 `modules/alb`가 관리하는 ALB를 Controller에서도 동시에 관리하기
- 현재 단계의 환경별 Root Module 구현과 실제 AWS 배포

2026-09-24 사용자가 수정된 Ideation을 승인했습니다. 사용자는 “HTTP API”가 Amazon API Gateway HTTP API가 아니라 Kubernetes Gateway API의 `HTTPRoute`임을 확인했습니다. 따라서 Controller 설치에는 Gateway API 지원을 포함합니다.

## 2. Inception — 승인 완료

### Functional Requirements

- EKS 모듈 호출당 클러스터 하나와 논리 키로 구분한 관리형 노드 그룹 0개 이상을 구성합니다. VPC, Subnet, Security Group, 클러스터 Role, 노드 Role, 선택적 KMS 키는 기존 구성에서 받습니다.
- Kubernetes 버전, API 엔드포인트의 public/private 접근, public 접근 CIDR, 제어 영역 로그 유형, 태그, 삭제 보호 여부를 설정할 수 있게 합니다. Access Entry와 관련 접근 정책 연결을 선택적으로 구성합니다.
- 인증 준비는 `none`, `irsa`, `pod_identity`, `both` 중 선택할 수 있게 합니다. IRSA를 선택하면 클러스터별 IAM OIDC Provider와 ARN·issuer 정보를 제공합니다. Pod Identity를 선택하면 후속 Add-On 단계에서 Agent를 설치할 수 있게 클러스터 정보를 제공합니다. 워크로드 IAM Role과 ServiceAccount 연결은 소유한 계층에서 관리합니다.
- AWS 관리형 Add-On은 별도 구성에서 명시적 목록으로 선택하고 호환 가능한 버전을 지정합니다. Pod Identity를 사용하는 구성은 `eks-pod-identity-agent`를 준비합니다. 기존 자체 관리 Add-On의 전환과 충돌 처리는 자동 덮어쓰지 않고 별도 결정을 요구합니다.
- AWS Load Balancer Controller는 클러스터가 활성화되고 실행 가능한 노드가 준비된 후 별도 Terraform 구성·상태에서 설치합니다. Controller 전용 IAM Policy·Role과 ServiceAccount 인증 연결은 IRSA 또는 Pod Identity 중 하나를 선택합니다.
- `HTTPRoute`를 위해 표준 Gateway API CRD와 Controller 전용 CRD를 Controller보다 먼저 설치하고 버전을 관리합니다. Controller와 차트 버전을 고정하며 ALB Gateway 기능을 활성화합니다. `GatewayClass`·`Gateway`·`HTTPRoute`의 소유 위치와 검증 절차를 문서화합니다.
- Controller가 만든 ALB·Target Group·Listener는 Controller가 소유합니다. 기존 `modules/alb`는 Controller가 생성하는 동일한 리소스를 관리하지 않습니다.

### Non-Functional Requirements

- EKS 클러스터 구성과 클러스터 내부 구성 요소의 Terraform 상태를 분리합니다. Controller Helm 설정에는 필요한 안정적인 클러스터 출력만 전달하고 모듈 전체에 대한 포괄적 `depends_on`을 피합니다.
- Controller의 차트 또는 값이 바뀔 때만 의도된 Helm 갱신을 계획합니다. 강제 재생성·불필요한 Pod 재시작 옵션을 기본으로 켜지 않습니다. EKS 클러스터 자체가 교체되면 새 클러스터에 Controller를 다시 설치합니다.
- Kubernetes API 및 Helm Provider는 이미 존재하는 클러스터를 대상으로 구성합니다. 생성 전 클러스터 값을 Provider 설정에 요구하는 단일 단계 초기화는 사용하지 않습니다.
- 노드 그룹 0개인 클러스터는 핵심 EKS 모듈에서 유효하지만, Controller와 Pod Identity Agent의 정상 실행 검증에는 실행 가능한 Linux 노드가 필요합니다. Add-On 목록이 비어 있어도 EKS가 자체 관리형 기본 구성 요소를 만들 수 있으므로 이를 "Add-On 없음"으로 설명하지 않습니다.
- Controller와 Gateway API CRD의 호환 버전을 고정하고 CRD 업그레이드 절차를 별도로 정의합니다. Helm 차트 갱신이 기존 CRD를 자동 갱신한다고 가정하지 않습니다.
- `HTTPRoute`의 지원 범위는 선택한 Controller 버전의 공식 지원표와 대조합니다. 지원하지 않는 필터나 정책은 이번 범위에서 보장하지 않습니다.
- 모듈별 README에 모든 입력·출력 속성 표를 유지하고, 실제 실행한 검증과 미수행한 AWS 검증을 구분합니다.

### Architecture

```text
기존 Network / SG / IAM Role / KMS
                |
                v
클러스터 구성·상태
  modules/eks
    EKS Cluster, Managed Node Groups, Access Entries
    선택적 IAM OIDC Provider
                |
                | cluster name, endpoint, CA, OIDC 정보
                v
별도 공통 구성·상태 (클러스터 생성 후 실행)
  AWS 관리형 Add-On (선택 목록, Pod Identity Agent 포함)
  Gateway API 표준 CRD + Controller 전용 CRD
  Controller IAM Policy/Role + IRSA 또는 Pod Identity 연결
  AWS Load Balancer Controller Helm Release
                |
                v
애플리케이션 구성: GatewayClass / Gateway / HTTPRoute / Service
                |
                v
Controller 소유 ALB와 HTTP 라우팅
```

환경별 Root Module은 아직 없으므로 위 두 상태의 실제 Backend·실행 순서·권한은 이후 환경 구성 때 확정합니다. 이번 작업에서는 재사용 모듈과 사용법·검증 방법을 준비합니다.

### Unit of Work

1. EKS 클러스터, 0개 이상의 관리형 노드 그룹, 접근·로그·암호화·OIDC 옵션과 mock Plan 검증
2. 명시적으로 선택한 AWS 관리형 Add-On과 Pod Identity Agent의 재사용 구성 및 mock Plan 검증
3. Gateway API CRD, Controller IAM 연결, 독립 Helm 설치 구성과 설치·업그레이드 절차
4. 관리형 노드 그룹의 시작 템플릿 및 Spot 용량 선택 확장. Unit 1 기본 구성과 별도 Design·Implementation Plan 승인 후 구현
5. 독립 상태 결합 예시, `HTTPRoute` 검증 시나리오, 변경 영향 검토와 문서 Review

각 Unit은 별도의 Construction Design과 Implementation Plan을 제시하고 승인받은 뒤 구현합니다.

### Acceptance Criteria

- 로컬 mock Plan에서 클러스터 1개, 노드 그룹 0개·여러 개, 엔드포인트·로그·Access Entry·KMS·OIDC 선택 구성을 확인합니다. 잘못된 인증 모드와 상충하는 입력을 거부합니다.
- 선택한 AWS 관리형 Add-On만 Terraform 관리 대상으로 나타납니다. Pod Identity 선택 시 Agent가 구성되고, Add-On별 버전과 충돌 처리 정책이 명시됩니다.
- 노드 그룹 0개 구성의 클러스터 생성과, 노드가 준비된 뒤의 Controller·Agent 설치를 구분해 문서화합니다.
- Gateway API 표준 및 Controller 전용 CRD의 소유·버전·설치 순서가 명확하며, Controller Helm 버전과 ALB Gateway 활성화 설정이 고정됩니다. IRSA와 Pod Identity 두 경로의 Controller IAM 연결을 검증합니다.
- `GatewayClass`·`Gateway`·`HTTPRoute`에서 Service로 이어지는 HTTP 검증 시나리오와 지원하지 않는 기능의 경계가 문서에 있습니다.
- EKS 일반 설정 변경 시 Controller Terraform 상태의 변경 계획이 없어야 합니다. 실제 AWS 환경이 없는 현재 단계에서는 구조와 입력 의존성까지만 로컬 검토하고, 실제 무변경 Plan과 HTTP 요청 성공은 환경별 Root Module 및 배포가 준비된 뒤 별도로 검증합니다.
- 실제 수행한 Terraform 포맷·구성 검증·mock 테스트의 날짜, 명령, 결과를 기록합니다. 수행하지 않은 실제 AWS Plan·Apply 및 HTTP 요청 검증은 PASS로 적지 않습니다.
- 후속 Unit에서 관리형 노드 그룹별 시작 템플릿과 `SPOT`/`ON_DEMAND` 용량 선택을 설계·검증합니다. Spot 중단 대응, 템플릿 버전 고정 및 기존 노드 그룹 교체 위험을 별도로 검토합니다.

2026-09-24 사용자가 위 Inception을 승인했습니다. 이 승인은 Unit 1 구현 승인이 아니며, 아래 Construction 설계와 구현 계획을 별도로 검토합니다.

## 3. Construction

### Unit 1: EKS 클러스터와 관리형 노드 그룹

#### Design — 수정안 승인 완료

| 결정 | 설계 |
|---|---|
| 모듈 경계 | `modules/eks`가 클러스터 하나, 관리형 노드 그룹 0개 이상, Access Entry·접근 정책 연결, 선택적 IAM OIDC Provider를 소유합니다. 기존 VPC/Subnet, Security Group, IAM Role/KMS 키와 해당 IAM 정책 연결은 호출자가 소유합니다. Add-On, Pod Identity Association, Controller, Kubernetes/Helm 리소스는 후속 Unit에서 별도 상태로 관리합니다. |
| 클러스터 기본값 | Kubernetes 버전은 호출자가 명시합니다. API 인증은 `API` 모드로 고정하고 생성자 관리자 권한 부트스트랩은 기본 활성화합니다. 기본 자체 관리 Add-On 설치도 활성화합니다. 클러스터에는 관리형 노드 그룹이 없어도 됩니다. |
| 네트워크 | 클러스터 Subnet ID는 2개 이상 받되 서로 다른 AZ 여부는 AWS에서 최종 확인합니다. API 엔드포인트는 기본적으로 private만 켜고, public만 또는 public·private를 동시에 켤 수도 있습니다. public을 켤 때는 공개 CIDR을 명시해야 합니다. 두 엔드포인트를 모두 끄는 설정은 거부합니다. 클러스터 보안 그룹 ID 목록은 선택 입력이고, EKS가 생성한 기본 클러스터 보안 그룹 ID를 별도 출력합니다. Private 엔드포인트에 접속할 Terraform 실행기·운영자 네트워크 경로는 호출자가 준비합니다. |
| 로그·암호화·삭제 | 제어 영역 로그 유형은 EKS 지원 유형에서 선택합니다. 고객 관리형 KMS ARN이 있으면 Kubernetes Secret용 `encryption_config`를 추가합니다. 삭제 보호는 기본 활성화하고 실제 삭제 전 명시적으로 꺼야 합니다. EKS 제어 영역 로그 그룹의 보존 정책은 이 Unit에서 관리하지 않습니다. |
| 접근 권한 | Access Entry는 논리 키별 IAM principal ARN을 받으며 `STANDARD` 유형만 다룹니다. 접근 정책 연결은 별도 논리 키로 관리하고 Entry 키, 정책 ARN, `cluster` 또는 `namespace` 범위 및 namespace 목록을 받습니다. 존재하지 않는 Entry 참조와 범위·namespace 불일치는 거부합니다. 생성자 부트스트랩 권한은 Terraform 상태에 Access Entry로 나타나지 않을 수 있으므로 README에서 따로 설명합니다. |
| 워크로드 인증 준비 | `workload_identity_mode`는 `none`, `irsa`, `pod_identity`, `both` 중 하나입니다. `irsa`/`both`에서만 클러스터 issuer와 audience `sts.amazonaws.com`으로 IAM OIDC Provider를 만듭니다. Provider가 인증서 thumbprint를 조회하는 기본 방식을 사용하고 고정 thumbprint를 입력받지 않습니다. `pod_identity`/`both`는 클러스터 이름만 후속 Unit에 제공하며 Agent·Association을 여기서 만들지 않습니다. 클러스터 API 인증 모드와 워크로드 IAM 인증 모드를 구분합니다. |
| 노드 그룹 | `node_groups`는 논리 키 Map입니다. 각 그룹은 기존 노드 IAM Role ARN, Subnet ID 목록(생략 시 클러스터 Subnet), `min_size`·`desired_size`·`max_size`, 선택적 인스턴스 유형·디스크 크기·레이블·태그를 받습니다. 이름은 클러스터 이름과 논리 키로 안정적으로 구성합니다. 이 Unit은 `ON_DEMAND`만 설정합니다. 시작 템플릿과 `SPOT` 선택은 후속 Unit 4에서 다루고, SSH 원격 접근·자체 AMI·Fargate는 현재 범위에서 다루지 않습니다. `desired_size`는 Terraform이 관리하며 외부 오토스케일러가 변경하는 구성은 후속 설계가 필요합니다. |
| 출력 | 클러스터 이름·ARN·엔드포인트·CA 데이터·OIDC issuer·기본 클러스터 보안 그룹 ID, 노드 그룹 이름/ARN Map, 선택적 IAM OIDC Provider ARN을 제공합니다. CA 데이터와 엔드포인트는 후속 별도 구성에서 이미 생성된 클러스터에 연결할 때 사용합니다. |
| 버전·소유권 | 기존 모듈과 같이 Terraform `>= 1.5.0`, AWS Provider `>= 6.24`를 요구합니다. Node Role의 필수 관리형 IAM 정책, KMS 키 정책, Subnet 라우팅/태그와 Security Group 통신 규칙은 호출자가 준비하고 실제 AWS Plan에서 확인합니다. |

핵심 입력은 `name`, `kubernetes_version`, `cluster_role_arn`, `cluster_subnet_ids`, `cluster_security_group_ids`, `endpoint_public_access`, `endpoint_private_access`, `public_access_cidrs`, `enabled_cluster_log_types`, `kms_key_arn`, `deletion_protection`, `workload_identity_mode`, `access_entries`, `access_policy_associations`, `node_groups`, `tags`로 계획합니다. 복합 입력의 내부 속성, 기본값, 검증 조건은 구현 시 README 표에 빠짐없이 기록합니다.

#### Implementation Plan — 수정안 승인 완료

1. `modules/eks/versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`를 만들고 클러스터, 선택적 OIDC Provider, Access Entry/정책 연결, 논리 키별 관리형 노드 그룹을 구성합니다. 클러스터 IAM Role/노드 Role과 권한 연결은 기존 IAM 모듈을 호출하는 측에서 준비합니다.
2. 입력 검증으로 빈 이름/ARN/Subnet, 유효하지 않은 워크로드 인증 모드·로그 유형·크기 범위, 꺼진 두 API 엔드포인트, CIDR 없는 public 엔드포인트, 접근 정책 연결의 Entry 키·범위 불일치를 거부합니다. public·private 동시 활성화 Plan을 확인합니다. AZ 분산, IAM/KMS 권한, Kubernetes 버전과 AMI/인스턴스 호환성은 AWS Plan·Apply 전까지 미검증으로 표시합니다.
3. `modules/eks/README.md`에 전체 입력·출력과 `map(object)` 내부 속성 표, 0개 및 복수 노드 그룹 예시, Private API 접속 요건, `API` Access Entry와 IRSA/Pod Identity 차이, IAM/KMS/네트워크 사전 요건, 삭제 보호의 해제 절차를 기록합니다.
4. `modules/eks/tests/eks.tftest.hcl`에서 AWS mock provider Plan으로 기본 0개 노드 그룹, 복수 그룹, public/private API와 로그·KMS, Access Entry/정책 범위, 네 가지 인증 모드와 OIDC Provider 생성 여부, 잘못된 입력 거부를 검증합니다. 모의 Plan은 실제 AWS 권한·노드 Ready·API 접속을 증명하지 않습니다.
5. `terraform fmt -check`, `terraform validate`, `terraform test`를 실제 실행합니다. Provider 설치나 실행 환경의 제약이 있으면 결과를 구분해 기록하고, 테스트 파일 및 README 속성 표를 코드와 대조합니다.
6. 구현·검증 후 Review하고 이 문서와 `docs/README.md`의 상태를 갱신합니다. AWS Plan·Apply, Controller 무변경 Plan, HTTP 요청, 배포, 커밋, 푸시는 실행했을 때만 기록합니다. Unit 2는 별도 Design·Implementation Plan 승인 후 시작합니다.

#### Approval

2026-09-24 사용자가 두 API 엔드포인트의 동시 활성화를 명시하고, 시작 템플릿·Spot 선택을 후속 작업에 추가한 수정안을 승인했습니다.

#### Implementation

- [versions.tf](../../modules/eks/versions.tf): Terraform `>= 1.5.0`, AWS Provider `>= 6.24`
- [variables.tf](../../modules/eks/variables.tf): 클러스터, 네트워크, 인증, 접근 권한, 관리형 노드 그룹 입력과 검증
- [main.tf](../../modules/eks/main.tf): EKS 클러스터, 선택적 IAM OIDC Provider, Access Entry·정책 연결, On-Demand 관리형 노드 그룹
- [outputs.tf](../../modules/eks/outputs.tf): 후속 구성이 사용할 클러스터와 노드 그룹·OIDC 출력
- [README.md](../../modules/eks/README.md): 전체 입력·출력 및 복합 입력 내부 속성 표와 사용 예시, 사전 요건, 검증 경계
- [eks.tftest.hcl](../../modules/eks/tests/eks.tftest.hcl): API 엔드포인트 세 조합, 노드 그룹, 인증, 접근 정책, KMS·로그 및 잘못된 입력의 mock Plan 검증

#### Test

검증은 `/tmp/template-eks.hDWTT0/eks`에 모듈을 복사하고 Terraform 1.13.3과 로컬 AWS Provider 6.66.0으로 실행했습니다. 임시 디렉터리의 플랫폼별 Provider lock file은 저장소에 복사하지 않았습니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `terraform fmt -recursive modules/eks` | 실행 완료, 변경 없음 |
| 2026-09-24 | `terraform init -backend=false -plugin-dir=/tmp/terraform-plugin-cache -no-color` (임시 복사본) | Provider 6.66.0 설치, 초기화 성공. 로컬 설치에 따른 플랫폼별 체크섬 경고 |
| 2026-09-24 | `terraform validate -no-color` (임시 복사본, 기본 샌드박스) | Provider 프로세스 시작 실패. 구성 오류로 판정하지 않음 |
| 2026-09-24 | `terraform validate -no-color` (임시 복사본, Provider 실행 권한 확대) | PASS. 최종 소스 복사 후 재검증도 PASS |
| 2026-09-24 | `terraform test -no-color` (임시 복사본, 최초) | 14 pass, 2 fail. 목록 타입을 잘못 비교한 테스트 단언식 수정 |
| 2026-09-24 | `terraform test -no-color` (임시 복사본, 수정 후) | 16 pass, 0 fail. 양쪽 API 엔드포인트 동시 활성화 포함 |
| 2026-09-24 | `terraform fmt -check -recursive modules/eks` | PASS |
| 2026-09-24 | `python3` 인라인 점검: Terraform 변수·출력과 README 표 및 복합 입력 내부 속성 대조 | 입력 16개·출력 9개, 내부 속성 3+4+9개 일치 |
| 2026-09-24 | `git diff --check` 및 `rg -n '[[:blank:]]+$' modules/eks docs/ai-dlc/eks-module.md docs/README.md` | 추적 변경에 공백 오류 없고 줄 끝 공백 검색 결과 없음 |

mock Plan은 Provider 구성과 계획의 리소스 속성만 확인합니다. 실제 AWS IAM/KMS 권한, Subnet의 AZ 분산과 네트워크 연결, Kubernetes 버전·인스턴스 호환성, 노드 Ready, 삭제 보호, Add-On과 Controller 동작은 검증하지 않았습니다.

#### Review

- 기본 private 전용과 public 전용, public·private 동시 활성화를 모두 Plan에서 확인했습니다. public API는 CIDR 목록이 있어야 하며 두 엔드포인트를 끄면 Plan을 거부합니다.
- 노드 그룹 0개와 복수 그룹을 확인했고, Unit 1에서는 `ON_DEMAND`만 생성합니다. 시작 템플릿·Spot 선택은 승인된 후속 Unit 4에서 설계합니다.
- `API` Access Entry는 클러스터 접속용이며 워크로드용 IRSA/Pod Identity와 분리됩니다. `irsa`·`both`에서만 IAM OIDC Provider를 생성합니다. Pod Identity Agent는 후속 Unit에서 설치합니다.
- README 입력 16개·출력 9개와 복합 입력 속성 표가 코드와 일치합니다. 실제 AWS Plan·Apply와 배포는 하지 않았습니다. 커밋·푸시는 아래 기록을 따릅니다.

### 커밋과 푸시 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'feat(eks): add core cluster module and mock tests'` | 구현 커밋 `15fe220d2eeb2dd07c88da6b54094bea32c5320d` 생성 |
| 2026-09-24 | `git push origin main` | EKS Unit 1 구현 커밋 푸시 완료 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main의 SHA가 `15fe220d2eeb2dd07c88da6b54094bea32c5320d`임을 확인 |

### 문서 점검 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git diff --check` | 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/ai-dlc/eks-module.md docs/README.md` | 일치 항목 없음 |

### Unit 1 설계 참고 자료

- [Terraform AWS Provider EKS Cluster](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/eks_cluster.html.markdown)
- [Terraform AWS Provider EKS Node Group](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/eks_node_group.html.markdown)
- [Terraform AWS Provider IAM OIDC Provider](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/iam_openid_connect_provider.html.markdown)
- [AWS EKS IAM OIDC Provider 생성](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

### 참고 자료

- [AWS EKS 서비스 계정 인증 방식](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html)
- [AWS EKS Add-On](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [AWS Load Balancer Controller Helm 설치](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [Controller의 Gateway API 요구 사항과 설치 순서](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/)
- [Controller의 HTTPRoute 지원 범위](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/l7gateway/)
- [Terraform의 클러스터·Kubernetes 구성 분리 권장](https://developer.hashicorp.com/terraform/tutorials/kubernetes/eks)
- [Terraform `depends_on` 계획 영향](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)

### Unit 2: Amazon EKS 관리형 Add-On과 Pod Identity Agent

#### Design — 승인 완료

| 결정 | 설계 |
|---|---|
| 모듈과 상태 경계 | `modules/eks/addons`를 별도 재사용 모듈로 만들고, 이미 생성된 클러스터 이름을 입력받습니다. `modules/eks`는 변경 주기가 다른 클러스터 리소스를 계속 소유합니다. 실제 환경별 Root Module과 Backend가 없으므로 두 모듈을 독립 상태로 실행하는 구성은 Unit 5에서 예시와 함께 완성합니다. 현재 Unit은 별도 상태에 배치할 수 있는 Add-On 모듈만 제공합니다. |
| 선택과 버전 | `addons`는 Add-On 이름을 키로 하는 Map이고 기본값은 빈 Map입니다. Add-On별 `addon_version`은 필수이며 정확한 버전 문자열을 입력합니다. `most_recent` 조회나 자동 버전 선택은 사용하지 않습니다. 빈 Map은 이 모듈이 관리하는 Add-On이 0개라는 뜻이며, Unit 1이 설치한 기본 자체 관리 Add-On을 제거하지 않습니다. |
| Pod Identity Agent | `workload_identity_mode`가 `pod_identity` 또는 `both`이면 `addons`에 `eks-pod-identity-agent`와 호환 버전을 명시해야 합니다. `none` 또는 `irsa`에서는 Agent 항목을 허용하지 않습니다. Agent는 별도 `aws_eks_addon` 리소스로 먼저 구성하고, 다른 Add-On의 Pod Identity Association은 Agent 이후 생성되도록 연결합니다. Agent 자체에는 IRSA Role이나 Pod Identity Association을 지정하지 않으며 노드 IAM Role에 `eks-auth:AssumeRoleForPodIdentity` 권한이 필요합니다. |
| Add-On별 IAM | 각 Add-On은 선택적으로 `service_account_role_arn`(IRSA) 또는 `pod_identity_associations`(ServiceAccount 이름별 IAM Role ARN)를 받습니다. 두 방식을 같은 Add-On에 동시에 지정하지 않도록 검사합니다. IRSA 입력은 `irsa`/`both`, Pod Identity 입력은 `pod_identity`/`both` 모드에서만 허용합니다. Add-On의 Pod Identity Association은 Add-On 리소스 내부에서 관리하며 별도 `aws_eks_pod_identity_association`으로 중복 소유하지 않습니다. 필요한 IAM Role·Policy·신뢰 정책은 호출자가 준비합니다. |
| 충돌 처리 | `resolve_conflicts_on_create`와 `resolve_conflicts_on_update`의 기본값은 각각 `NONE`입니다. 기존 자체 관리 Add-On과 충돌하면 적용이 실패하여 전환 결정을 드러냅니다. 호출자는 해당 Add-On에서만 create에 `OVERWRITE`, update에 `PRESERVE` 또는 `OVERWRITE`를 명시할 수 있습니다. `OVERWRITE`는 기존 수정값에 영향을 줄 수 있으므로 변경 계획과 Add-On 설정을 먼저 검토합니다. |
| 설정·태그 | 선택적 `configuration_values_json`은 JSON 문법을 로컬에서 검사하고, 버전별 실제 설정 스키마는 AWS에서 확인합니다. 공통 `tags`와 Add-On별 `tags`를 합치며 후자가 같은 키를 덮어씁니다. Add-On의 사용자 지정 namespace와 삭제 시 리소스 보존 옵션은 이 Unit에서 입력으로 노출하지 않습니다. |
| 출력 | Add-On 이름을 키로 하는 ARN·버전 Map과 Pod Identity Agent ARN(미설치 시 `null`)을 제공합니다. 설치 상태와 Pod 실행 여부는 AWS API 및 Kubernetes에서 별도로 확인합니다. 설치된 AWS Provider 6.66.0의 `aws_eks_addon` 리소스에는 계획 당시 예상한 `status` 출력 속성이 없어 설계를 수정했습니다. |
| 실행 전제와 영향 | 클러스터가 활성화되고 Add-On이 사용할 Linux 노드가 준비되어야 Agent와 노드 기반 Add-On의 Pod 실행을 검증할 수 있습니다. private 노드는 EKS Auth API와 ECR에 접근할 경로, 노드 Role 권한이 필요합니다. Add-On 버전·설정·Pod Identity Association 변경은 Add-On Pod 재시작을 일으킬 수 있습니다. Add-On이 소유한 Association 목록을 갱신할 때 빠진 항목은 제거될 수 있으므로 목록 전체와 Controller 변경 영향을 검토합니다. |

입력은 `cluster_name`, `workload_identity_mode`, `addons`, `tags`로 계획합니다. `addons` 내부에는 `addon_version`, 선택적 `configuration_values_json`, `service_account_role_arn`, `pod_identity_associations`, `resolve_conflicts_on_create`, `resolve_conflicts_on_update`, `tags`를 둡니다. Add-On별 실제 지원 여부, 버전 호환성, IAM 권한과 설정 JSON 스키마는 AWS 조회와 실제 Plan·Apply에서 확인합니다.

#### Implementation Plan — 승인 완료

1. `modules/eks/addons`에 `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`를 만듭니다. Agent와 나머지 Add-On 리소스를 나눠, Pod Identity Association이 있는 Add-On이 Agent 생성에 의존하도록 구성합니다. Kubernetes·Helm Provider는 이 Unit에서 사용하지 않습니다.
2. 빈 클러스터 이름, Add-On 이름·버전 누락, 잘못된 JSON·충돌 정책, Agent 필수 조건, Agent 자체 IAM 연결, Add-On별 IRSA/Pod Identity 동시 입력과 모드 불일치를 로컬에서 거부합니다. Provider 스키마와 AWS API가 확인해야 하는 버전 호환성·JSON 스키마는 로컬 mock 검증의 범위 밖으로 남깁니다.
3. README에 전체 입력·출력과 `addons` 내부 속성 표, Add-On 0개·기본 Add-On·Pod Identity Agent 및 Add-On별 IAM 연결 예시를 적습니다. `aws eks describe-addon-versions --addon-name ... --kubernetes-version ...`로 호환 버전을 선택하고 `describe-addon-configuration`으로 설정 스키마·필요 IAM 정책을 확인하는 절차를 기록합니다. 자체 관리 Add-On 전환과 `NONE`/`PRESERVE`/`OVERWRITE`의 차이, 노드·EKS Auth·ECR 전제, Add-On 삭제 영향을 설명합니다.
4. AWS mock provider Plan 테스트에서 빈 Map, 명시한 Add-On만 생성, Agent 필수 조건과 생성 순서, 버전·설정·태그, IRSA/Pod Identity 단일 선택, 충돌 정책과 잘못된 입력 거부를 검증합니다. 실제 Agent Pod Ready나 API 인증 성공으로 해석하지 않습니다.
5. Terraform 포맷·구성 검증·mock 테스트를 실제 실행해 날짜·명령·결과를 기록하고 README 표를 코드와 대조합니다. 실제 AWS Plan·Apply, 자체 관리 Add-On 전환, Pod 재시작, Controller 무변경 Plan은 환경 구성 후 별도로 검증합니다.
6. 구현·Test·Review 후 AI-DLC 및 프로젝트 진행 문서를 갱신합니다. Unit 3은 Gateway API CRD와 Load Balancer Controller의 별도 Design·Implementation Plan 승인 후 시작합니다.

#### Approval

2026-09-24 사용자가 Unit 2 Design·Implementation Plan을 승인했습니다. Unit 2 구현을 진행합니다.

#### Implementation

- [versions.tf](../../modules/eks/addons/versions.tf): 기존 모듈과 같은 Terraform·AWS Provider 요구 버전
- [variables.tf](../../modules/eks/addons/variables.tf): 클러스터 이름, 인증 모드, 명시적 Add-On 버전·설정·IAM 연결·충돌 정책과 입력 검증
- [main.tf](../../modules/eks/addons/main.tf): Agent와 다른 Add-On을 분리한 `aws_eks_addon` 리소스, Agent 선행 의존성, Add-On 소유 Pod Identity Association
- [outputs.tf](../../modules/eks/addons/outputs.tf): Add-On ARN·지정 버전과 선택적 Agent ARN, 인증 모드와 Add-On IAM 연결의 사전 조건
- [README.md](../../modules/eks/addons/README.md): 입력·출력·중첩 속성 표, 적용 순서, 버전·설정 스키마 확인, IAM·네트워크·전환·삭제 영향
- [addons.tftest.hcl](../../modules/eks/addons/tests/addons.tftest.hcl): 명시적 선택, Agent·IAM 모드, 설정·태그·충돌 정책과 잘못된 입력의 mock Plan 검증

#### Test

검증은 `/tmp/template-eks-addons.RiuGVn/addons`에 모듈을 복사하고 Terraform 1.13.3과 로컬 AWS Provider 6.66.0으로 실행했습니다. 임시 디렉터리의 플랫폼별 Provider lock file은 저장소에 복사하지 않았습니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `terraform fmt -recursive modules/eks/addons` | 파일 포맷 적용. 최종 재실행에서 변경 없음 |
| 2026-09-24 | `terraform init -backend=false -plugin-dir=/tmp/terraform-plugin-cache -no-color` (임시 복사본) | Provider 6.66.0 초기화 성공. 로컬 설치로 플랫폼별 체크섬 경고 |
| 2026-09-24 | `terraform validate -no-color` (임시 복사본, Provider 실행 권한 확대) | PASS. 최종 소스 재검증도 PASS |
| 2026-09-24 | `terraform test -no-color` (최초) | 1 pass, 1 fail, 14 skip. 설치된 Provider의 Add-On 리소스에 `status` 속성이 없어 출력 설계를 수정 |
| 2026-09-24 | `terraform providers schema -json` (임시 복사본) | AWS Provider 6.66.0의 `aws_eks_addon` 속성 목록 확인, `status` 없음 |
| 2026-09-24 | `terraform test -no-color` (두 번째) | 2 pass, 1 fail, 13 skip. Pod Identity Association은 Set이므로 인덱스 접근을 순회 단언식으로 수정 |
| 2026-09-24 | `terraform test -no-color` (수정 후 및 최종 소스 재검증) | 16 pass, 0 fail |
| 2026-09-24 | `terraform graph -type=plan` (임시 복사본, Provider 실행 권한 확대) | `aws_eks_addon.other`가 `aws_eks_addon.pod_identity_agent`에 의존하는 그래프 확인 |
| 2026-09-24 | `terraform fmt -check -recursive modules/eks/addons` | PASS |
| 2026-09-24 | `python3` 인라인 점검: 변수·출력과 README 표 및 `addons` 내부 속성 대조 | 입력 4개·출력 3개·내부 속성 7개 일치 |
| 2026-09-24 | `git diff --check` 및 `rg -n '[[:blank:]]+$' modules/eks/addons docs/ai-dlc/eks-module.md docs/README.md` | 추적 변경 공백 오류 없고 줄 끝 공백 일치 항목 없음 |

mock Plan은 리소스 수와 전달 설정, 입력 거부를 확인합니다. 실제 AWS의 Add-On 지원·버전 호환성·JSON 설정 스키마·IAM 권한, 자체 관리 Add-On 전환, Pod Ready, 업데이트에 따른 재시작은 검증하지 않았습니다.

#### Review

- `addons = {}`는 AWS 관리형 Add-On 리소스 0개를 계획합니다. Unit 1의 기본 자체 관리 Add-On과는 별개입니다.
- Pod Identity를 선택하면 Agent를 명시해야 하며, Agent에는 IAM 연결을 허용하지 않습니다. Add-On마다 IRSA 또는 Pod Identity 연결 하나만 허용합니다. Terraform 그래프에서 Agent가 다른 Add-On보다 선행합니다.
- 생성·갱신 충돌 정책의 기본값은 `NONE`입니다. `OVERWRITE`와 갱신 시 `PRESERVE`는 Add-On별로 명시해야 합니다. Add-On 소유 Pod Identity Association은 별도 리소스로 중복 관리하지 않습니다.
- 설치된 Provider의 `aws_eks_addon`에 `status` 출력이 없어 계획에서 제거했습니다. 상태와 Pod 실행은 AWS·Kubernetes에서 확인하도록 README에 적었습니다.
- README 입력 4개·출력 3개, 복합 입력 7개 속성이 코드와 일치합니다. 실제 AWS Plan·Apply와 배포는 수행하지 않았습니다. 커밋·푸시는 아래 기록을 따릅니다.

#### Unit 2 커밋과 푸시

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'feat(eks): add managed addons module and mock tests'` | 구현 커밋 `4c6c68021174bd82d9fa7e15217bf63b45ba1b94` 생성 |
| 2026-09-24 | `git push origin main` | EKS Unit 2 구현 커밋 푸시 완료 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main의 SHA가 `4c6c68021174bd82d9fa7e15217bf63b45ba1b94`임을 확인 |

#### Unit 2 참고 자료

- [Terraform AWS Provider `aws_eks_addon`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/eks_addon.html.markdown)
- [Amazon EKS Add-On과 기본 자체 관리 Add-On](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [Add-On 버전 호환성 확인](https://docs.aws.amazon.com/eks/latest/userguide/addon-compat.html)
- [Add-On IAM Role과 Pod Identity Association](https://docs.aws.amazon.com/eks/latest/userguide/add-ons-iam.html)
- [Pod Identity Agent 사전 조건](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)

#### Unit 2 문서 점검

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git diff --check` | 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/ai-dlc/eks-module.md docs/README.md` | 일치 항목 없음 |

Unit 2의 계획 문서 점검은 위와 같으며, 구현·로컬 검증 결과는 Unit 2 Test와 Review에 기록했습니다. 실제 AWS Plan·Apply는 수행하지 않았습니다.
