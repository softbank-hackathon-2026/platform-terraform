# dev 리소스 네이밍과 태깅 AI-DLC

마지막 확인일: 2026-10-01

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation, Inception, Construction 계획 | 2026-10-01 사용자 승인 |
| 구현 | `env/dev`와 여기서 호출하는 모듈에 반영 |
| 로컬 검증 | Terraform validate, dev mock 5개, 전체 Plan 점검 2개, 연결 모듈 회귀 테스트 통과 |
| 실제 AWS Plan | `sbh-platform`, 서울 리전, dev S3 Backend에서 56 add / 0 change / 0 destroy. 태그 지원 리소스 42개의 `tags_all` 확인 |
| Apply, 배포 | 미수행 |
| 커밋, 푸시 | 2026-10-01 `main` 커밋 및 원격 SHA 확인 |

## 1. Ideation

- 문제 정의: 기존 dev 구성은 `Project=sbh-platform`, `ManagedBy=Terraform`을 사용하며 `Scope`, `Owner`가 없습니다. VPC와 일부 리소스의 이름에는 유형이 빠지고, 태그를 지원하는 일부 하위 리소스에는 `Name`이 없습니다.
- 사용자: Terraform 작성자, 플랫폼 운영자, 비용 집계 담당자입니다.
- 성공 기준: 직접 관리하는 태그 지원 리소스에 `Name`, `Project=SBH`, `Scope=platform`, `Environment=dev`, `ManagedBy=terraform`, `Owner=정호원`을 적용합니다. 이름은 `sbh-platform-dev-<type>-<purpose>` 형식과 서비스 제한을 지키고, mock Plan과 실제 AWS Plan을 구분해 검증합니다.
- Scope: `env/dev`, 여기서 호출하는 Network, S3, ECR, ALB, CloudFront, ECS, RDS Instance, Security Group, IAM Policy와 Role 모듈, 관련 테스트와 문서입니다.
- Non-goals: 미사용 모듈, AWS Apply, Cost Allocation Tag 활성화, 실제 앱 배포, 식별자가 아직 없는 `InfraId`, `ApplicationId`, `DeploymentId` 부여입니다.

## 2. Inception

### Functional Requirements

- 프로젝트, Scope, 환경과 리소스 유형 및 용도를 이름에 사용합니다. S3 버킷은 계정 ID를 덧붙입니다.
- AWS Provider `default_tags`와 기존 모듈 `tags` 입력에 동일한 공통 태그를 사용합니다. 각 태그 지원 리소스의 `Name`은 모듈 또는 Root Module에서 개별 설정합니다.
- 빈 추가 태그 값, 필수 태그와 `Name`의 재정의, 전체 공유 리소스에 대한 `ApplicationId`와 `DeploymentId` 일괄 적용을 거부합니다.
- ALB Listener, Security Group Rule, CloudFront Function 등 태그를 지원하지만 `Name`이 누락된 리소스를 보완합니다.
- RDS 인스턴스 태그를 스냅샷에 복사하도록 설정합니다. AWS가 직접 만드는 RDS 관리형 Secret 등은 Apply 후 태그를 별도로 확인합니다.

### Non-Functional Requirements와 Architecture

- 기존 VPC CIDR, 네트워크 경로, IAM 권한, 암호 처리, 서비스 설정은 유지합니다.
- AWS Provider 6.66.0과 Terraform 1.15.4에서 구성 검증을 수행하고, 기존 RDS ephemeral mock이 필요한 dev 결합 테스트는 공식 Terraform 1.17.0-beta2로 실행합니다.
- Root Module의 `local.tags`가 모듈 입력과 Provider `default_tags`의 단일 태그 원천입니다. `Name`은 리소스별 `merge`로 설정합니다. Provider 공통 태그가 모듈 하위 리소스에도 적용되는지 실제 Plan의 `tags_all`로 확인했습니다. [HashiCorp default tags 설명](https://developer.hashicorp.com/terraform/tutorials/aws/aws-default-tags)
- CloudFront OAC와 S3 버킷 정책처럼 태그 입력이 없는 Terraform 리소스에는 태그를 강제로 넣지 않습니다. OAC는 규칙에 맞는 고유 이름을 사용합니다.

### Acceptance Criteria

- dev 초기 구성과 ECS 활성화 mock Plan의 모든 직접 관리 태그 지원 리소스에 여섯 필수 태그가 있고 빈 값이 없습니다.
- VPC, Subnet, ALB, Target Group, S3, ECR, ECS, RDS, IAM의 이름이 지정한 형식에 맞으며 ALB와 Target Group은 32자, S3는 63자 제한 이내입니다. [ALB 이름 제한](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-application-load-balancer.html), [Target Group 이름 제한](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-target-group.html), [S3 버킷 규칙](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)
- 실제 AWS Plan에서 리소스 교체나 삭제가 있는지 검토하고, Apply 여부는 별도로 결정합니다.

## 3. Construction

| Unit | Design과 Implementation Plan | 승인 | 현재 상태 |
|---|---|---|---|
| 1 | dev Root Module의 이름, 공통 태그, 추가 태그 검증과 직접 관리 규칙 `Name` 설정 | 2026-10-01 | 구현, mock 검증 완료 |
| 2 | 연결 모듈의 네트워크 `Name`, 누락된 태그 지원 리소스 `Name`, ECS 로그 이름 입력, RDS 스냅샷 태그 복사 | 2026-10-01 | 구현, 연결 모듈 회귀 검증 완료 |
| 3 | dev mock 전체 Plan 점검, README와 Runbook, AI-DLC 및 프로젝트 상태 갱신, 실제 AWS Plan | 2026-10-01 | 문서 갱신, 로컬 검증, 실제 AWS Plan 검토 완료 |

### Review

- `default_tags`와 모듈 `tags`는 같은 `local.tags`를 사용합니다. Terraform mock Provider는 Provider의 `default_tags`를 `tags_all`에 반영하지 않아 mock 점검은 각 리소스의 명시적 `tags`를 검사합니다. 실제 AWS Provider의 Plan에서는 태그 지원 리소스 42개의 `tags_all`에 여섯 필수 태그가 있고 빈 값이 없음을 확인했습니다. AWS 측 태그는 Apply 후 별도 확인이 필요합니다.
- ECS Service의 `propagate_tags = "SERVICE"`와 `enable_ecs_managed_tags = true`는 유지했습니다. 실제 Task의 태그는 서비스 활성화 후 확인해야 합니다. [AWS ECS 태그 전파](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-using-tags.html)
- CloudFront OAC는 현재 AWS Provider 리소스에 `tags` 인수가 없습니다. RDS 관리형 관리자 Secret은 Terraform이 직접 관리하지 않습니다.
- `sbh-platform` 계정 `723225040786`과 서울 리전의 기존 Backend를 확인했습니다. dev State Key의 객체는 없으며 변경 후 실제 Plan은 56개 생성, 변경과 삭제 0개입니다. 계획된 S3 버킷 이름은 `sbh-platform-dev-s3-web-723225040786`입니다. Plan은 Apply 성공이나 AWS 측 태그 생성을 증명하지 않습니다.

## 4. Operation

- Deployment: 미수행. 실제 AWS Plan과 교체, 삭제 여부를 검토했습니다. Apply는 별도 배포 요청 후 진행합니다.
- Observability: Apply 후 직접 관리 리소스의 AWS 태그와 RDS 관리형 Secret, CloudFront VPC Origin 하위 리소스, ECS Task 태그를 별도로 조회합니다.
- Rollback: Apply 전에는 코드 변경을 되돌릴 수 있습니다. Apply 이후 이름 변경으로 생성된 리소스의 복구는 실제 Plan과 State를 기준으로 검토합니다.
- Runbook: [dev ECS와 PostgreSQL 운영 절차](../runbooks/ecs-postgresql-platform.md)를 사용합니다.

## 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform -chdir=env/dev init -backend=false -reconfigure -input=false -lockfile=readonly -no-color` | AWS 6.66.0, Random 3.9.1 Provider 설치 및 초기화 성공. 기본 Sandbox 네트워크 실패 후 허용된 실행 환경에서 성공 |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | PASS |
| 2026-10-01 | `terraform fmt -check -recursive env/dev modules/network modules/alb modules/cloudfront modules/ecr modules/ecs modules/iam modules/rds/instance modules/security-group` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color` | Terraform 1.15.4의 ephemeral mock 미지원으로 1 fail, 2 skip. 이후 전용 실행기로 재실행 |
| 2026-10-01 | 공식 1.17.0-beta2 darwin_arm64 ZIP과 SHA256SUMS 대조 | SHA-256 `353b17a245e6857830d9bdcc81a2ef78b4bf246ed80303dd5673675f07667dde` 일치 |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-tests.jsonl` | mock Plan 5 PASS, 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-tests.jsonl` | 초기와 ECS 활성화 구성의 전체 Plan 점검 2 PASS |
| 2026-10-01 | `terraform -chdir=modules/alb test -no-color` | 15 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/security-group test -no-color` | 8 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/ecs test -no-color` | 6 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/iam/role test -no-color` | 5 PASS, 0 FAIL |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 sts get-caller-identity` | 초기에는 프로필 부재, 이후 동일 명령 재실행으로 계정 `723225040786` 인증 성공 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 s3api get-bucket-location --bucket sbh-platform-prod-s3-tf` | 기존 Backend 버킷 서울 리전 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 s3api head-object --bucket sbh-platform-prod-s3-tf --key sbh-platform/dev/terraform.tfstate` | 404, dev State 객체 없음 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev init -reconfigure -backend-config=backend.local.hcl -input=false -no-color -lockfile=readonly` | S3 Backend 초기화 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-naming.tfplan` | Terraform 1.15.4, 종료 코드 2, 56 add / 0 change / 0 destroy. Plan 저장 성공 |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-naming.tfplan > .local/dev-naming.tfplan.json` | JSON 변환 성공. 첫 Sandbox 시도는 Provider 실행 제한으로 실패했고 허용된 환경에서 재실행 |
| 2026-10-01 | `python3` 인라인 점검: Plan JSON과 AWS Provider Schema의 태그 지원 속성 비교 | 42개 태그 지원 리소스 전체의 `tags_all`, 필수 태그와 `Name` 검사 PASS. RDS 스냅샷 태그 복사, ALB, Target Group, S3 이름 길이 PASS |
| 2026-10-01 | `git diff --check` | PASS |
| 2026-10-01 | `git commit -m "feat: apply dev resource naming and required tags"` | `main`에 구현과 문서 커밋 완료 |
| 2026-10-01 | `git push origin main`, `git ls-remote origin refs/heads/main` | 원격 `main` 푸시 및 SHA 일치 확인 |

Apply와 배포는 실행하지 않았습니다.
