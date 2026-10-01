# Project overview

마지막 확인일: 2026-10-01

이 저장소는 환경별 Terraform 실행기와 재사용 가능한 AWS Terraform 모듈을 제공합니다. `env/dev`에 ECS와 PostgreSQL Multi-AZ Root Module을 구현했습니다. Unit 9의 46개 생성 Plan은 당시 기록입니다. 2026-10-01 사용자 도메인 작업의 Apply 이후 S3 State는 serial 9, 관리 리소스 인스턴스 48개입니다. 기존 인프라를 처음 생성한 Apply 명령과 애플리케이션 배포 여부는 이번 조회로 확인하지 못했습니다. `env/stg`와 `env/prd`는 아직 Root Module이 없습니다.

## 새 세션에서 확인할 순서

1. [`AGENTS.md`](../AGENTS.md)에서 AI-DLC 절차와 문서화 규칙을 확인합니다.
2. 이 문서에서 전체 진행 상태와 다음 작업을 확인합니다.
3. 관련 AI-DLC 문서와 모듈 README를 확인합니다.
4. 현재 코드와 실제 검증 결과가 문서보다 우선합니다.

## 저장소 구조

```text
tf                         환경별 Terraform 실행기
env/dev                    dev Root Module 위치
env/stg                    stg Root Module 위치
env/prd                    prd Root Module 위치
modules/ec2                단일 EC2 인스턴스 모듈
modules/network            VPC와 Subnet, NAT Gateway 모듈
modules/s3                 단일 비공개 S3 버킷 모듈
modules/security-group     VPC Security Group과 규칙 모듈
modules/iam/policy         고객 관리 IAM Policy 모듈
modules/iam/role           IAM Role과 선택적 EC2 Instance Profile 모듈
modules/alb                단일 ALB와 0개 이상의 Target Group, Listener 모듈
modules/rds/instance       일반 RDS PostgreSQL/MySQL과 Read Replica 모듈
modules/rds/aurora         Provisioned Aurora PostgreSQL/MySQL과 reader 모듈
modules/ecr                비공개 ECR 저장소와 선택적 Lifecycle Policy 모듈
modules/ecs                Cluster와 선택적 단일 On-Demand Fargate Service 모듈
modules/cloudfront         S3 OAC, ALB VPC Origin과 SPA CloudFront 모듈
modules/kms                고객 관리형 대칭 KMS 키와 선택적 별칭 모듈
modules/eks                EKS 클러스터와 선택적 관리형 노드 그룹 모듈
modules/eks/addons         명시적으로 선택한 EKS 관리형 Add-On 모듈
tests/iam-composition      IAM Policy, Role, EC2 결합 mock 테스트 구성
docs/ai-dlc                작업 단위별 AI-DLC 기록
docs/runbooks              후속 배포, 모니터링과 복구 절차
```

## 진행 현황

아래 검증과 Plan 수치는 각 Unit을 완료한 시점의 기록입니다. 현재 dev Backend State에는 관리 리소스 인스턴스 48개가 있으며 실제 리소스별 상태와 드리프트는 새 Plan으로 확인해야 합니다.

| 작업 단위 | 구현 | 로컬 검증 | AWS Plan과 Apply | Git 상태 | 상세 기록 |
|---|---|---|---|---|---|
| `tf` 실행기 | 완료 | `bash -n` 통과, 자동 기능 테스트 없음 | 해당 없음 | 커밋 `d051afd` | [`tf`](../tf) |
| EC2 모듈 | 완료 | 포맷과 `terraform validate` 통과, 자동 테스트 없음 | 미수행 | 커밋 `776d3dd`, `3532c5f` | [EC2 AI-DLC](./ai-dlc/ec2-module.md) |
| Network 모듈 | Private Subnet별 NAT 경로 선택 확장 완료 | 2026-10-01 fmt, validate, mock 10개 통과 | dev 결합 실제 Plan 확인, Apply 미수행 | 확장 커밋 `c1a36ed`, 원격 `codex/ecs-postgresql-dev` 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md) |
| S3 모듈 | Regional Domain 출력 추가 완료 | 2026-10-01 fmt, validate, 회귀 mock 4개 통과 | dev 결합 실제 Plan 확인, Apply 미수행 | 확장 커밋 `c1a36ed`, 원격 `codex/ecs-postgresql-dev` 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md) |
| Security Group 모듈 | 완료 | 포맷과 `terraform validate` 통과, mock 테스트 8개 통과 | dev에 사용한 구성의 실제 Plan 확인, Apply 미수행. 기타 옵션은 기존 기록 범위 | 구현 커밋 `8949e16` 원격 main 확인 | [Security Group AI-DLC](./ai-dlc/security-group-module.md) |
| IAM Policy와 Role 모듈 | 완료, 결합 테스트 Root Provider 선언 보강 | 포맷과 세 구성의 `terraform validate` 통과, mock 테스트 9개 통과. 결합 테스트 2026-09-24 재검증 1개 통과 | dev에 사용한 구성의 실제 Plan 확인, Apply 미수행. 기타 옵션은 기존 기록 범위 | 기존 구현 `2190a91`, 테스트 보강 `df31fab` 원격 main 확인 | [IAM AI-DLC](./ai-dlc/iam-role-policy-modules.md) |
| 루트 `tests/` 조사 | 결합 테스트 고유 기능 확인 후 유지, 용도 문서화 | 결합 구성 `terraform validate` 통과, mock 테스트 1개 통과 | 해당 없음 | 커밋 `df31fab` 원격 main 확인 | [tests README](../tests/README.md) |
| ALB 모듈 | Listener 0개, 여러 개 확장까지 완료 | 포맷과 `terraform validate` 통과, 확장 mock 테스트 15개 통과 | dev에 사용한 구성의 실제 Plan 확인, Apply 미수행. 기타 옵션은 기존 기록 범위 | 구현 커밋 `50b854f` 원격 main 확인 | [ALB AI-DLC](./ai-dlc/alb-module.md) |
| RDS와 Aurora 모듈 | 세 Unit 로컬 구현, Review 완료. 일반 RDS RR은 별도 Secret 모드로 수정 | 일반 RDS 포맷, `terraform validate` 통과, mock 테스트 16개 통과. Aurora `terraform validate`와 회귀 mock 테스트 14개 통과 | dev에 사용한 구성의 실제 Plan 확인, Apply 미수행. 기타 옵션은 기존 기록 범위 | 구현 커밋 `aa26615` 원격 main 확인 | [RDS AI-DLC](./ai-dlc/rds-module.md) |
| ECR 모듈 | Unit 1 구현, Test, Review 완료 | 포맷, `terraform validate` 통과, mock 테스트 6개 통과 | dev에 사용한 구성의 실제 Plan 확인, Apply 미수행. 기타 옵션은 기존 기록 범위 | 구현 커밋 `3f6dbdd` 원격 main 확인 | [ECR AI-DLC](./ai-dlc/ecr-module.md) |
| KMS 모듈 | Unit 1 구현, Test, Review 완료 | 포맷, 구성 검증 통과, mock 테스트 10개 통과 | 실제 AWS 기준 미수행 | 구현 커밋 `2b1f850` 원격 main 확인 | [KMS AI-DLC](./ai-dlc/kms-module.md) |
| EKS 및 클러스터 공통 구성 | Unit 1, 2 구현, Test, Review 완료. Unit 3~5 미시작 | 두 Unit 포맷, 구성 검증 통과, 각 mock Plan 16개 통과 | 실제 AWS 기준 미수행 | Unit 1 `15fe220`, Unit 2 `4c6c680` 원격 main 확인 | [EKS AI-DLC](./ai-dlc/eks-module.md) |
| ECS와 CloudFront 모듈 | 구현과 Review 완료 | ECS mock 6개, CloudFront mock 3개, SPA 14개 통과 | dev 결합 실제 Plan 확인, Apply 미수행 | 커밋 `c1a36ed`, 원격 `codex/ecs-postgresql-dev` 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md) |
| 환경별 Root Module | dev ECS/PostgreSQL 기반과 `DATABASE_URL` SSM 참조 구현, Task Definition과 Service는 CI/CD 소유, stg/prd 미구현 | 최신 dev fmt, validate, mock 4개와 전체 Plan 점검 2개 통과 | sbh-platform dev 46 add / 0 change / 0 destroy, Apply 미수행 | Unit 7과 8 구현 커밋 `2886bd4` 원격 main 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md) |
| dev 네이밍과 태깅 | `env/dev`와 연결 모듈에 규칙 반영 | validate, 결합 mock 5개, 전체 Plan 점검 2개, ALB 15개, SG 8개, ECS 6개, IAM Role 5개 통과 | 56 add / 0 change / 0 destroy, 42개 리소스 계획 태그 확인. Apply 미수행 | `main` 커밋 및 원격 SHA 확인 | [네이밍과 태깅 AI-DLC](./ai-dlc/dev-naming-tagging.md) |
| dev 백엔드 내부 포트 | 기본값 8000 반영. ALB Listener 80 유지 | fmt, validate, dev mock 6개와 전체 Plan 점검 3개 통과 | 변경 후 56 add / 0 change / 0 destroy, Target Group과 ALB/ECS 규칙 8000 확인. Apply 미수행 | `main` 커밋 및 원격 SHA 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-백엔드-내부-포트-8000) |
| dev Regional NAT와 private-only VPC | Unit 6 구현, Test와 Review 완료 | fmt, validate, dev mock 6개와 전체 Plan 점검 3개 통과 | 47 add / 0 change / 0 destroy, Apply 미수행 | `main` 커밋과 푸시 완료, 원격 SHA 확인 | [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-regional-nat와-private-only-vpc) |
| dev `DATABASE_URL` Parameter Store | Unit 7 구현과 Review 완료. 값 등록은 별도 운영 작업 | fmt, validate, dev mock 6개와 전체 Plan 점검 3개 통과 | 46 add / 0 change / 0 destroy, Parameter 미등록, Apply 미수행 | 구현 커밋 `2886bd4` 원격 main 확인 | [Unit 7](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-database_url-parameter-store-연동) |
| dev ECS 배포 소유 경계 | Unit 8 구현과 Review 완료. Terraform은 기반 인프라, CI/CD는 Task Definition과 Service 소유 | fmt, validate, mock 4개와 전체 Plan 점검 2개 통과 | 46 add / 0 change / 0 destroy, Task Definition과 Service 없음, Apply 미수행 | 구현 커밋 `2886bd4` 원격 main 확인 | [Unit 8](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-ecs-배포-소유-경계) |
| dev 초기 DB 이름 `freesia` | Unit 9 구현과 Review 완료 | fmt, validate, mock 4개와 전체 Plan 점검 2개 통과 | 46 add / 0 change / 0 destroy, RDS 이름 `freesia`, Apply 미수행 | 구현 커밋 `c0df773` 원격 main 확인 | [Unit 9](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-초기-db-이름-freesia) |
| dev CloudFront 사용자 도메인 `sbh.howon.me` | Unit 10 구현, 인증서 발급과 기존 배포본 적용 완료. 사용자 외부 접속 정상 보고 | fmt, validate, CloudFront mock 4개, dev mock 4개, 전체 Plan 검사 2개 통과 | ACM 요청 1 add, 최종 1 add / 1 change / 0 destroy Apply 완료. CloudFront `Deployed`. 적용 후 Origin 표현 차이 1 change Plan 미적용 | 구현 커밋 `637e5bd` 원격 main 확인 | [사용자 도메인 AI-DLC](./ai-dlc/dev-cloudfront-custom-domain.md) |
| 지속 문서화 | RDS, ECR 진행 상태 반영, 기존 10개 모듈 README의 입력, 출력 속성 표 정리와 향후 유지 규칙 추가 | 입력 97개, 출력 49개 코드 대조 및 문서 공백 점검 완료 | 해당 없음 | ECR, README 표, 규칙 커밋 `3f6dbdd` 원격 main 확인 | 이 문서 |

IAM 구현 커밋 `2190a91`을 푸시한 직후 로컬 `HEAD`, `origin/main`, 원격 main의 SHA가 모두 `2190a91b4e6023492d71023f6c69a959d1a825b3`인 것을 확인했습니다.

## 구성 요소

### Terraform 실행기

[`tf`](../tf)는 실행 파일 위치를 기준으로 `env/<환경>`을 찾습니다. 명령 직접 실행, 번호 선택 TUI, Bash와 zsh 자동완성을 지원하며 `format`을 Terraform의 `fmt`로 변환합니다.

현재 자동 기능 테스트 파일은 없습니다. `bash -n tf`만 통과했습니다. 현재 `env/dev`에서 구현한 Root Module의 실제 Plan을 실행할 수 있습니다. `env/stg`와 `env/prd`는 `.gitkeep`만 있습니다.

### EC2 모듈

[`modules/ec2`](../modules/ec2/README.md)는 EC2 인스턴스 하나를 생성합니다. On-Demand와 Spot을 선택할 수 있고 암호화된 gp3 Root EBS와 IMDSv2를 기본으로 사용합니다.

VPC, Subnet, Security Group, IAM Role과 IAM Instance Profile은 생성하지 않습니다. 자세한 결정과 검증 상태는 [EC2 AI-DLC](./ai-dlc/ec2-module.md)에 기록합니다.

### Network 모듈

[`modules/network`](../modules/network/README.md)는 VPC, Public과 Private Subnet, Route Table, 선택적 NAT Gateway를 생성합니다. NAT 모드는 `none`, `regional`, `zonal`을 지원합니다.

Zonal NAT는 AZ별 Public Subnet 키를 직접 선택하고 Regional NAT는 Subnet을 입력받지 않습니다. 자세한 결정과 검증 상태는 [Network AI-DLC](./ai-dlc/network-module.md)에 기록합니다.

### S3 모듈

[`modules/s3`](../modules/s3/README.md)는 일반 목적 S3 버킷 하나와 공개 접근 차단을 생성합니다. 버전 관리와 고객 관리 KMS 키는 선택할 수 있습니다. 로컬 검증과 실제 AWS 미검증 범위는 [S3 AI-DLC](./ai-dlc/s3-module.md)에 기록합니다.

### Security Group 모듈

[`modules/security-group`](../modules/security-group/README.md)는 VPC Security Group 하나와 명시한 IPv4 또는 Security Group 참조 규칙을 생성합니다. 기본 인바운드와 아웃바운드 규칙은 없습니다. 로컬 검증과 실제 AWS 미검증 범위는 [Security Group AI-DLC](./ai-dlc/security-group-module.md)에 기록합니다.

### IAM Policy와 Role 모듈

[`modules/iam/policy`](../modules/iam/policy/README.md)는 고객 관리 IAM Policy를 독립적으로 생성합니다. [`modules/iam/role`](../modules/iam/role/README.md)은 서비스별 신뢰 정책으로 Role을 만들고 관리형 Policy를 연결하며, EC2용 Instance Profile을 선택적으로 생성합니다. 결합 mock Plan과 실제 AWS 미검증 범위는 [IAM AI-DLC](./ai-dlc/iam-role-policy-modules.md)에 기록합니다.

### ALB 모듈

[`modules/alb`](../modules/alb/README.md)는 ALB 하나와 논리 키로 구분한 0개 이상의 Target Group, Listener를 생성합니다. Listener별로 같은 Target Group을 공유하거나 다른 Target Group을 선택할 수 있고, HTTP→HTTPS 리디렉션도 설정할 수 있습니다. 공개형 HTTP Listener는 리디렉션만 허용합니다. 검증 범위는 [ALB AI-DLC](./ai-dlc/alb-module.md)에 기록합니다.

### RDS와 Aurora 모듈

[`modules/rds/instance`](../modules/rds/instance/README.md)는 PostgreSQL/MySQL 기본 인스턴스와 선택적 Multi-AZ를 구성합니다. Read Replica를 사용하면 모듈 소유 관리자 Secret 모드를 명시해야 하며, RDS 관리형 관리자 Secret과 RR의 조합은 Plan에서 거부합니다. [`modules/rds/aurora`](../modules/rds/aurora/README.md)는 Provisioned Aurora PostgreSQL/MySQL 클러스터와 reader를 만듭니다. 두 모듈 모두 Private DB Subnet Group, 암호화, 백업, 삭제 보호를 사용합니다. 일반 DB 사용자용 IAM 인증은 기본 비활성화이며 선택적으로 켤 수 있습니다. 관리자 계정은 IAM 대상에서 제외합니다. 모듈 소유 Secret의 자동 회전은 구현하지 않았고 실제 AWS 생성은 검증하지 않았습니다. 자세한 범위는 [RDS AI-DLC](./ai-dlc/rds-module.md)에 기록합니다.

### ECR 모듈

[`modules/ecr`](../modules/ecr/README.md)는 비공개 ECR 저장소 하나를 만듭니다. 태그 불변성, AES256 암호화, 저장소 수준 push 시 스캔 설정이 기본이며, 기존 KMS 키와 Lifecycle Policy를 선택할 수 있습니다. 로컬 mock 검증과 dev에 사용한 구성의 실제 AWS Plan을 확인했습니다. Apply와 이미지 동작은 확인하지 않았습니다. 자세한 범위는 [ECR AI-DLC](./ai-dlc/ecr-module.md)에 기록합니다.

### KMS 모듈

[`modules/kms`](../modules/kms/README.md)는 고객 관리형 대칭 KMS 키 하나와 선택적 별칭을 만듭니다. `kms_admin_arns`와 `key_user_arns`로 키 정책에 관리자, 사용자 권한을 추가하거나, `policy_json`으로 전체 정책을 지정합니다. 자동 키 재료 회전은 기본 활성화합니다. mock Plan 테스트는 완료했고 실제 AWS 권한과 키 사용은 검증하지 않았습니다. 자세한 범위는 [KMS AI-DLC](./ai-dlc/kms-module.md)에 기록합니다.

### EKS 모듈

[`modules/eks`](../modules/eks/README.md)는 EKS 클러스터 하나와 선택적인 On-Demand 관리형 노드 그룹, Access Entry, IRSA용 IAM OIDC Provider를 구성합니다. private/public API를 각각 또는 함께 켤 수 있습니다. [`modules/eks/addons`](../modules/eks/addons/README.md)는 버전을 명시한 EKS 관리형 Add-On과 선택적 Pod Identity Agent를 관리합니다. 두 모듈은 각각 mock Plan 16개가 통과했으며 실제 AWS Plan, Apply와 Add-On 실행은 확인하지 않았습니다. 시작 템플릿과 Spot 선택은 Unit 4, Gateway API `HTTPRoute`용 Load Balancer Controller는 Unit 3 범위입니다. 자세한 상태는 [EKS AI-DLC](./ai-dlc/eks-module.md)에 기록합니다.

## ECS와 PostgreSQL dev 구성

[dev README](../env/dev/README.md)에 입력, 출력, Backend와 실행 방법을 정리했습니다. 두 AZ의 App/DB Private Subnet, Regional NAT 1개, Internal ALB, ECS Cluster와 로그 그룹, PostgreSQL Multi-AZ, CloudFront/S3를 연결했습니다. Public Subnet은 만들지 않습니다. Terraform은 Task Definition과 Service를 관리하지 않으며 CI/CD가 이미지 Digest, 앱 DB 계정과 `DATABASE_URL` SecureString을 준비한 뒤 배포합니다. [Runbook](./runbooks/ecs-postgresql-platform.md)에 CI/CD 인수인계와 장애 검증 절차를 기록했습니다.

현재 dev 기본 포트는 ALB Listener 80에서 백엔드 Target Group과 ECS 컨테이너 8000으로 전달합니다. 초기 구성에는 ECS Service가 없으며, 활성화 시 컨테이너 포트는 mock Plan으로 검증했습니다.

## 이전 작업 기록

- AI-DLC 인수인계 문서와 `AGENTS.md` 지속 문서화 규칙 구현, 검증, Review 완료
- 자주 사용하는 AWS 리소스 모듈을 S3, Security Group, IAM Role과 Policy, ALB, RDS, ECR 순서로 추가하기로 결정
- S3 모듈 구현, 로컬 검증, Review 완료. 실제 AWS Plan과 Apply는 미수행
- Security Group 모듈 구현, 로컬 검증, Review 완료. 실제 AWS Plan과 Apply는 미수행
- IAM Policy와 Role 모듈 구현, 로컬 검증, Review 완료. 실제 AWS Plan과 Apply는 미수행
- ALB 모듈의 Listener 0개, 여러 개 및 Listener별 Target Group 선택 확장 구현, 로컬 검증, Review 완료. 실제 AWS Plan과 Apply는 미수행
- ALB 구현 커밋 `50b854f`를 원격 main에 푸시하고 원격 SHA `50b854fa2beb72160dabe0df83f363c6209bae1d` 확인
- RDS 기존 Ideation과 Inception 승인: 일반 RDS, Provisioned Aurora, 읽기 복제본 포함. Serverless v2는 이번 범위에서 제외
- RDS/Aurora 일반 DB 사용자용 IAM 접근 옵션 및 관리자 계정 제외 범위 확정. 최초 두 Unit의 로컬 검증 완료
- 일반 RDS RR을 위한 별도 관리자 Secret 모드의 Ideation, 수정 Inception, Unit 3 Construction 승인. 구현과 로컬 mock 테스트 16개, Aurora 회귀 테스트 14개 완료. 실제 AWS Plan, Apply는 미수행하고 자동 회전은 구현하지 않음
- ECR 모듈 Unit 1 승인, 구현, 로컬 Test, Review 완료. 기본 태그 불변성, AES256, 저장소 수준 push 스캔, 선택적 KMS, Lifecycle Policy를 mock Plan 6개로 확인. 실제 AWS Plan, Apply 미수행
- 기존 10개 모듈 README의 입력, 출력 속성을 표로 정리하고, 새 모듈 및 기존 모듈 변경 시 표를 유지하도록 `AGENTS.md` 규칙 추가
- KMS 모듈 수정 Inception과 Unit 1 Design, Implementation Plan 승인. `kms_admin_arns` 명칭으로 구현, 로컬 테스트 10개, Review 완료. 구현 커밋 `2b1f850` 원격 main 확인. 실제 AWS Plan, Apply 미수행
- 루트 `tests/` 조사 완료: `iam-composition`은 개별 모듈 테스트에 없는 결합 검증이므로 유지. 현재 Provider에서 mock 테스트가 실행되도록 Provider 요구 선언 추가, `terraform validate`와 mock 테스트 1개 통과. 커밋 `df31fab` 원격 main 확인
- EKS Unit 1, 2 구현, 로컬 mock Plan 각 16개, Review 완료. Unit 1 public, private API 동시 활성화와 Unit 2 명시적 Add-On, Pod Identity Agent, IAM 연결 검증. 커밋 `15fe220`, `4c6c680` 원격 main 확인. Load Balancer Controller와 Gateway API `HTTPRoute`는 Unit 3, 시작 템플릿과 Spot 선택은 Unit 4 범위. 실제 AWS Plan, Apply 미수행

## README 속성 표 점검

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `python3` 인라인 점검: 모듈별 `variables.tf`, `outputs.tf`와 README 표의 속성명 대조 | 10개 모듈의 입력 97개, 출력 49개 모두 일치 |
| 2026-09-24 | `python3` 인라인 점검: 입력 타입, 기본값 및 `map(object)` 내부 속성 대조 | 일치, 누락 없음 |
| 2026-09-24 | `python3` 인라인 점검: Markdown 표 열 개수 대조 | 10개 README 모두 일치 |
| 2026-09-24 | `git diff --check` | PASS |
| 2026-09-24 | `rg -n '[[:blank:]]+$' AGENTS.md docs/README.md modules` | 일치 항목 없음, 신규 ECR README 포함 줄 끝 공백 없음 |

## 현재 작업과 다음 단계

현재 작업은 [dev CloudFront 사용자 도메인](./ai-dlc/dev-cloudfront-custom-domain.md) 연결입니다. Ideation, Inception과 Unit 10 계획을 승인받아 Terraform 구현, 로컬 검증, ACM `ISSUED`와 기존 배포본 `ECSDZ4JA6Z85U`의 Apply를 완료했습니다. AWS에서는 `Deployed`, 별칭 `sbh.howon.me`, 비내보내기 인증서와 SNI 정책을 확인했고 State의 `frontend.url`도 사용자 도메인입니다. 사용자는 외부에서 정상 접속됐다고 확인했습니다. 이 컴퓨터의 DNS가 도메인을 보안 차단 주소로 바꿔 서비스용 CNAME의 정확한 대상과 응답 코드는 독립 확인하지 못했습니다. 적용 후 Plan의 CloudFront Origin 표현 차이 1건은 추가 적용하지 않았습니다. 후속 요청에 따라 구현 커밋 `637e5bd`를 `main`에 푸시하고 원격 SHA 일치를 확인했습니다.

2026-10-01 사용자 도메인 Apply 전 S3 Backend State 조회에서는 관리 리소스 인스턴스 46개와 기존 CloudFront 배포본을 확인했고, 이번 두 단계 Apply 후에는 48개입니다. 아래의 “Apply 미수행” 문구는 각 과거 Unit을 기록한 당시 결과이며 현재 AWS에 리소스가 없다는 뜻은 아닙니다. 기존 인프라 생성 Apply 명령은 확인하지 못했고 애플리케이션 배포 상태도 별도로 검증해야 합니다.

dev 초기 DB 이름을 `sbhapp`에서 `freesia`로 바꾸는 Unit 9 구현과 Review를 마쳤습니다. [AI-DLC 기록](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-초기-db-이름-freesia)에 dev 기본값, 문서와 당시 검증 결과를 남겼습니다. fmt, validate, dev mock 4개와 전체 Plan 점검 2개가 통과했고 당시 실제 AWS Plan은 46 add / 0 change / 0 destroy, DB 이름 `freesia`였습니다. 당시 State의 관리 리소스 목록은 비어 있었습니다. 후속 요청으로 구현 커밋 `c0df773`를 `main`에 푸시해 원격 SHA 일치를 확인했습니다. 해당 작업에서 Apply와 배포는 수행하지 않았습니다.

CI/CD가 dev Task Definition과 Service를 소유하고 Terraform은 ECS 기반 인프라만 관리하도록 [Unit 8 변경](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-ecs-배포-소유-경계)을 구현했습니다. 이미지 Digest 입력과 Terraform의 Task Definition 및 Service 생성 경로를 제거하고 인프라 출력 계약을 추가했습니다. mock 4개와 전체 Plan 점검 2개가 통과했고 실제 AWS Plan은 46 add / 0 change / 0 destroy입니다. 후속 요청으로 Unit 7과 8의 구현 커밋 `2886bd4`를 `main`에 푸시해 원격 SHA 일치를 확인했습니다. Apply와 CI/CD 배포는 수행하지 않았습니다.

dev 백엔드의 `DATABASE_URL` Parameter Store 연동은 2026-10-01 Ideation, Inception과 Unit 7 계획을 승인받았습니다. dev Terraform 변경, 로컬 mock 6개와 전체 Plan 점검 3개, 실제 AWS Plan 46 add / 0 change / 0 destroy까지 [Unit 7 기록](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-database_url-parameter-store-연동)에 남겼습니다. 실제 값은 승인된 운영 경로에서 별도 등록하기로 했고 현재 Parameter는 조회되지 않았습니다. 후속 요청으로 구현을 커밋하고 푸시했습니다. Apply와 배포는 수행하지 않았습니다.

dev Regional NAT와 private-only VPC 전환의 Ideation, Inception과 단일 Unit 계획을 2026-10-01 승인받았습니다. Public Subnet을 없애고 App의 송신만 Regional NAT로 보내는 구현, 로컬 mock 검증과 실제 AWS Plan 검토를 마쳤습니다. Plan은 47개 생성, 변경과 삭제 0개입니다. 후속 요청에 따라 변경을 `main`에 커밋하고 푸시해 원격 SHA를 확인했습니다. Apply는 수행하지 않았습니다. [검증 기록](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-regional-nat와-private-only-vpc)을 확인하세요.

기존 ECS/PostgreSQL dev 구축 당시 mock Plan 26개, SPA 14개와 결합 Plan 점검 2개가 통과했습니다. dev 결합 mock은 기존 RDS의 ephemeral 선언 때문에 공식 Terraform 1.17.0-beta2로 실행했고 당시 실제 Plan은 안정 버전 1.16.4로 실행했습니다. 상세 날짜와 명령은 [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md)에 있습니다.

이전 ECS/PostgreSQL 구현 커밋 `c1a36ed4ba9093dc68dde5fbc71fb5808dbbadf0`은 `codex/ecs-postgresql-dev`에 푸시됐습니다. 이후 제공한 네이밍과 태깅 규칙을 `env/dev`와 연결 모듈에 적용해 로컬 검증과 실제 AWS Plan 검토를 마쳤습니다. 이 변경은 `main`에 커밋하고 원격 SHA 일치를 확인했습니다. 이번 백엔드 내부 포트 8000 변경도 로컬 검증과 실제 AWS Plan 검토를 마치고 `main`에 커밋해 원격 SHA 일치를 확인했습니다. 상세 범위와 검증은 [Platform AI-DLC](./ai-dlc/ecs-postgresql-platform.md#후속-변경-dev-백엔드-내부-포트-8000)에 기록했습니다.

1. ADR의 팀 승인 상태는 별도로 확인합니다.
2. 사용자 도메인은 AWS 적용과 사용자 접속 확인을 완료했습니다. 서비스용 CNAME 대상과 HTTP 상태 코드의 독립 검증이 필요하면 차단되지 않은 네트워크에서 확인합니다. 적용 후 Origin 블록 표현 차이가 보이는 Plan은 별도 원인 검토 전 추가 적용하지 않습니다.
3. 앱 이미지, DB 사용자와 `DATABASE_URL` SecureString, 프론트 빌드를 준비한 뒤 CI/CD가 Task Definition과 Service를 배포합니다. 그 전에 마이그레이션 Task를 실행하고, 배포 후 두 AZ 배치와 API/DB 접속을 검증합니다. 배포 주체와 워크플로는 아직 이 저장소에서 구현하지 않았습니다.
4. EKS의 미완료 Unit 3~5와 stg/prd Root Module은 기존 후속 작업으로 남깁니다. 일반 RDS RR의 모듈 소유 Secret 회전/복구도 별도 운영 작업입니다.
5. 계획, 로컬 테스트, AWS Plan, Apply, 배포, 커밋과 푸시를 계속 구분합니다.
