# ECS and PostgreSQL platform AI-DLC

마지막 확인일: 2026-10-01

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 최초 계획과 후속 Unit 5~9 및 11 범위 승인 |
| Inception | 최초 계획과 후속 Unit 5~9 및 11 요구사항 승인 |
| Construction | Unit 1~9 및 11 구현과 Review 완료. dev Task Definition과 Service는 CI/CD 소유 |
| 로컬 검증 | 최신 Unit 11 fmt, validate, dev mock 4개와 전체 Plan 점검 2개 통과. 기존 SPA 검증은 Unit 11에서 재실행하지 않음 |
| 실제 AWS Plan | Unit 11 Apply 전 SSM 대상 지정 1 add / 0 change / 0 destroy. Apply 후 전체 Plan 0 add / 1 change / 0 destroy. SSM 추가 변경 없이 기존 CloudFront Origin 표현 차이만 남음 |
| Apply와 배포 | Unit 11 Parameter 생성 Apply 완료, 1 added / 0 changed / 0 destroyed. 실제 접속값 등록과 앱 배포 미수행. 사용자 도메인 Unit 10은 별도 기록 참고 |
| 커밋과 푸시 | Unit 11 Apply 기록까지 반영한 커밋과 푸시 진행 중 |

초기 사용자의 `PLEASE IMPLEMENT THIS PLAN` 요청은 아래 최초 Ideation, Inception과 Unit 1~4의 Design 및 Implementation Plan 승인을 포함합니다. 후속 Unit의 승인은 각 변경 기록에 따로 적었습니다. AWS 작업은 `sbh-platform` 프로필을 사용하며 Apply는 명시적으로 승인된 해당 Unit 범위에서만 수행합니다.

아래 1~4절은 최초 구현 당시 기록입니다. 앱 Secrets Manager 구성에 관한 당시 설계와 검증은 후속 Unit 7이, Terraform의 Task Definition과 Service 소유는 Unit 8이 대체했습니다. Parameter 리소스 생성과 값 비저장 및 Provider 조회 경계는 Unit 11 기록을 따릅니다.

2026-10-01 후속 요청으로 `DATABASE_URL` Parameter 리소스 생성 방향과 Unit 11의 Inception, Design 및 Implementation Plan을 승인받아 구현, 로컬 검증과 실제 AWS Plan Review를 완료했습니다. 이후 사용자가 `apply하고 커밋 푸시`로 Parameter 생성 Apply와 커밋 및 푸시를 승인했습니다. 기존 CloudFront 변경을 제외한 새 SSM 대상 지정 Plan을 검토해 Parameter 하나를 생성했고, 메타데이터와 State의 값 비저장 및 적용 후 Plan을 확인했습니다. 사용자 도메인 Unit 10의 Apply는 [별도 AI-DLC](./dev-cloudfront-custom-domain.md)에 기록되어 있으므로 이번 Unit과 구분합니다.

## 1. Ideation

- 문제 정의: ECS 백엔드와 PostgreSQL의 AZ 장애 대응 기반, CloudFront와 S3 프론트엔드 배포 기반이 필요합니다.
- 사용자: 웹 서비스 사용자, Terraform 작성자와 운영자입니다.
- 성공 기준: dev 구성의 로컬 테스트와 실제 AWS Plan을 확인하고, 코드와 검증 기록을 함께 제공합니다. 배포 성공은 이번 완료 기준에 포함하지 않습니다.
- Scope: Network 확장, S3 출력 추가, ECS와 CloudFront 모듈, dev Root Module, ECR, IAM, Security Group, PostgreSQL Multi-AZ, 로그와 Runbook입니다.
- Non-goals: Apply, 리소스 배포, 파일과 이미지 업로드, DB 계정 생성, 스키마 변경, CI/CD, 사용자 도메인, 실제 장애 전환 테스트입니다.

## 2. Inception

### Functional Requirements

- 서울 리전 `ap-northeast-2a`와 `ap-northeast-2c`에 Public, App Private, DB Private Subnet을 하나씩 생성합니다.
- VPC 기본 CIDR은 `10.20.0.0/16`입니다. Public은 `10.20.0.0/24`와 `10.20.1.0/24`, App은 `10.20.10.0/24`와 `10.20.11.0/24`, DB는 `10.20.20.0/24`와 `10.20.21.0/24`입니다.
- AZ별 Zonal NAT를 생성하고 App만 같은 AZ의 NAT 기본 경로를 사용합니다. DB에는 인터넷 기본 경로가 없습니다.
- CloudFront는 OAC로 비공개 S3에 접근하며 `/api`와 `/api/*`는 VPC Origin으로 Internal ALB에 전달합니다.
- SPA의 확장자가 없는 프론트 경로는 `/index.html`로 변환하고 API 오류 응답은 보존합니다. HTML과 API는 캐싱하지 않고 `/assets/*`와 `/static/*`는 캐싱합니다.
- ECS는 Cluster와 로그 그룹을 항상 생성합니다. `service = null`이면 Task Definition과 Service는 생성하지 않습니다. 서비스 활성화 구성은 Linux X86_64, On-Demand Fargate, CPU 512, 메모리 1024 MiB, Task 2개, Public IP 비활성화와 AZ 재분산을 사용합니다.
- Internal ALB는 두 App Subnet, HTTP 80 Listener와 IP Target Group을 사용합니다. 후속 Unit 5에서 변경한 기본 앱 포트는 8000, 상태 확인 경로는 `/api/health`입니다.
- PostgreSQL은 17.11, db.t4g.small, gp3 20 GiB, Multi-AZ, 암호화, 백업 7일, 삭제 보호와 최종 스냅샷을 사용합니다. Read Replica는 생성하지 않습니다.
- 관리자 암호는 RDS에서 관리하고 앱 Secret은 메타데이터만 Terraform에서 관리합니다. Execution Role에는 ECR, 로그와 앱 Secret 권한만 연결합니다.
- AWS Provider와 S3 Backend는 `sbh-platform`을 사용합니다. Backend는 기존 별도 버킷, 암호화와 S3 잠금 파일을 사용하며 버킷과 State Key는 사용자 입력을 받습니다.

### Non-Functional Requirements

- Terraform 1.11 이상, AWS Provider 6.24 이상 7 미만입니다.
- 기존 Network 호출은 Subnet의 `enable_nat_route` 생략 시 기존 동작을 유지합니다.
- Secret 값을 읽거나 평문으로 입력, 출력, State에 저장하지 않습니다.
- AWS 자격 증명 없이 mock Plan 테스트가 실행되어야 합니다.
- 실제 AWS Plan과 mock 테스트, Apply와 배포, 커밋과 푸시 상태를 구분합니다.

### Architecture

```text
CloudFront -> OAC -> Private S3
           -> /api -> VPC Origin -> Internal ALB -> Fargate -> PostgreSQL
                                      App Private              DB Private
Public AZ a/c: NAT a/c           App NAT routes          No default route
```

### Acceptance Criteria

- Subnet 6개, NAT 2개와 App 경로 2개, DB의 기본 경로 부재를 확인합니다.
- ALB 인바운드는 CloudFront Prefix List의 80, 앱 인바운드는 ALB의 앱 포트, DB 인바운드는 앱의 5432입니다.
- 초기 서비스 생략과 활성화 시 Task 2개, IP Target Group 연결, 역할 및 Secret 참조를 테스트합니다.
- CloudFront Origin, Cache Policy, API 헤더 전달, SPA URI 변환과 API 오류 보존을 테스트합니다.
- RDS Multi-AZ, 암호화, 백업, 삭제 정책을 결합 테스트에서 확인합니다.
- 실제 Plan 전에 인증, Backend 접근, 엔진과 클래스의 Region 지원을 읽기 전용으로 확인합니다.

## 3. Construction

| Unit | Design과 Implementation Plan | 승인 | 현재 상태 |
|---|---|---|---|
| 1 | Network의 Private Subnet별 NAT 경로 선택, S3 Regional Domain 출력, README와 회귀 테스트 | 2026-10-01 | 구현, 테스트와 Review 완료 |
| 2 | Cluster와 선택적 단일 Fargate Service 모듈, 로그, IAM 참조, 입력 검증, mock 테스트 | 2026-10-01 | 구현, 테스트와 Review 완료 |
| 3 | S3와 ALB Origin, OAC, VPC Origin, 캐시 정책, SPA Function, mock 및 JavaScript 테스트 | 2026-10-01 | 구현, 테스트와 Review 완료 |
| 4 | dev 연결, 프로필과 Backend, IAM 최소 권한, DB 격리, 결합 테스트, AWS Plan, Runbook | 2026-10-01 | 구현, 테스트, 실제 Plan과 Review 완료 |

### 구현과 Review

- Unit 1: `enable_nat_route = optional(bool, true)`를 추가했습니다. NAT 경로 대상만 AZ 검증에 사용하며 DB Subnet이 다른 AZ에 있어도 NAT를 추가하지 않습니다. 기존 7개 시나리오와 DB 격리 3개 시나리오가 통과했습니다. S3 Regional Domain 출력과 기존 4개 테스트를 확인했습니다.
- Unit 2: `modules/ecs`를 추가했습니다. Cluster와 30일 로그 그룹, 선택적 Task/Service, Linux X86_64, On-Demand Fargate, AZ 재분산, 배포 Circuit Breaker를 구성했습니다. `log_region`을 지정하면 의존 리소스를 생성하기 전에도 로그 옵션과 컨테이너 JSON을 Plan에서 검토할 수 있습니다. Role과 Secret 참조를 입력받으며 평문 Secret 입력을 거부합니다.
- Unit 3: `modules/cloudfront`를 추가했습니다. S3 OAC와 ALB VPC Origin, `/api`와 `/api/*`, HTML 캐싱 비활성화와 정적 파일 캐싱을 구성했습니다. `/*.html`은 정적 폴더보다 먼저 처리하며 API Behavior는 그보다 먼저 적용합니다. 오류 캐시 TTL만 0으로 설정하고 응답 코드와 본문은 치환하지 않습니다. AWS 공식 관리형 정책 ID를 사용해 Plan에서 캐시 설정을 확인할 수 있습니다.
- Unit 4: `env/dev`에 기존 Network, S3, ECR, ALB, Security Group, IAM, RDS와 신규 모듈을 결합했습니다. ALB/VPC Origin은 Network와 접근 규칙을 기다리고 ECS Service는 Listener, IAM 연결과 NAT 경로를 기다립니다. Execution Role에는 ECR, 로그와 앱 Secret만 허용하고 Task Role에는 앱 요구가 없으므로 정책을 연결하지 않았습니다.
- DB 앱 Secret은 메타데이터 하나만 관리하고 Secret Version은 생성하거나 조회하지 않습니다. 관리자 암호는 RDS 관리형 모드이며 Read Replica는 없습니다. 최종 실제 Plan의 `password`와 `password_wo`는 null입니다.
- 앱 포트와 Health Check는 입력으로 연결됩니다. 배포 후 포트 변경은 기존 ALB 모듈의 고정 Target Group 이름과 교체 순서를 검토해야 합니다. Runbook에 기록했으며 실제 변경은 실행하지 않았습니다.
- README의 입력 30개와 출력 28개를 코드와 대조했고 복합 입력/출력의 내부 속성 표를 유지했습니다. Plan과 로컬 설정의 Git 제외 상태, dev Provider Lock 파일의 추적 가능 상태를 확인했습니다.

### 테스트 실행기 제약

Terraform 1.16.4 mock Provider는 기존 RDS 모듈의 ephemeral 선언을 지원하지 않아 dev 결합 테스트가 실패했습니다. 기존 `modules/rds/instance/tests-terraform-1.17` 방식에 맞춰 테스트를 분리하고 공식 Terraform 1.17.0-beta2 CLI의 SHA-256을 검증한 뒤 사용했습니다. AWS와 Random은 mock이며 실제 AWS 호출이나 Apply는 없습니다. 설치된 CLI를 교체하지 않았고 테스트 CLI는 `.local/`에만 있습니다. dev 구성과 실제 AWS Plan은 안정 버전 1.16.4로 검증했습니다.

### 실제 AWS Plan 검토

Backend 버킷은 사용자가 지정한 `sbh-platform-prod-s3-tf`, Key는 추가 승인한 `sbh-platform/dev/terraform.tfstate`입니다. 최초 조회는 NoSuchBucket이었지만 재조회에서 목록과 서울 리전을 확인했고 S3 Backend 초기화가 성공했습니다. 기존 State Key는 조회 시 없었습니다. 버킷을 생성하지 않았습니다.

최종 `AWS_PROFILE=sbh-platform ./tf dev plan`은 56개 생성, 변경과 삭제 0개입니다. `-detailed-exitcode`의 종료 코드 2는 변경이 있는 정상 Plan을 의미합니다. 생성 예정 수는 아래와 같습니다.

| 대상 | 생성 예정 |
|---|---|
| VPC / Subnet / NAT / EIP | 1 / 6 / 2 / 2 |
| Route Table / 연결 / 기본 경로 | 5 / 6 / 3, Public 1개와 App 2개이며 DB 경로 없음 |
| ALB / Target Group / Listener | 각 1개, Internal HTTP 80와 IP 대상 |
| Security Group / 인바운드 / 아웃바운드 | 3 / 3 / 3 |
| PostgreSQL / DB Subnet Group | 각 1개, Multi-AZ Primary/Standby를 단일 DB 리소스로 관리 |
| ECS Cluster / 로그 그룹 | 각 1개, Task Definition과 Service 0개 |
| IAM Role / Policy / 연결 | 2 / 1 / 1 |
| ECR / 앱 Secret 메타데이터 | 각 1개, Secret Version 0개 |
| S3 / 공개 접근 차단 / 버전 관리 / 버킷 정책 | 각 1개 |
| CloudFront Distribution / Function / OAC / VPC Origin | 각 1개 |

실제 Plan은 초기 인프라 구성을 검토했습니다. Task 2개 활성화는 mock Plan으로 확인했고 실제 서비스 생성은 하지 않았습니다. `.local/dev.tfplan`, `.local/dev.tfplan.json`, `.local/dev-plan.log`와 `env/dev/backend.local.hcl`은 Git에서 제외합니다. Plan 성공은 IAM 생성 권한, VPC Origin 트래픽, DB 접속이나 배포 성공을 증명하지 않습니다.

## 4. Operation

배포, 관측, 롤백과 장애 검증 절차를 [Runbook](../runbooks/ecs-postgresql-platform.md)에 작성했습니다. Apply, 파일과 이미지 업로드, DB 계정 생성, ECS 시작과 실제 장애 전환은 실행하지 않았습니다. 배포는 후속 수정과 Plan 검토를 마친 뒤 별도 요청을 받아 진행합니다.

## Git 반영과 후속 요청

2026-10-01 사용자의 현재 변경 커밋과 푸시 요청에 따라 `codex/ecs-postgresql-dev` 브랜치를 생성했습니다. 구현, 테스트와 검증 기록 47개 파일을 커밋 `c1a36ed4ba9093dc68dde5fbc71fb5808dbbadf0`으로 푸시하고 원격 SHA 일치를 확인했습니다. State, Plan, 로그와 로컬 Backend 설정은 Git에서 제외했습니다.

제공한 ADR의 네이밍과 태깅 수정 요청은 이 구현 커밋에 포함하지 않았습니다. 이후 `env/dev`와 연결 모듈에 적용한 내용과 로컬 검증, 변경 후 실제 AWS Plan 결과는 [dev 네이밍과 태깅 AI-DLC](./dev-naming-tagging.md)에 기록합니다. `sbh-platform`과 Apply 금지 조건, ADR의 팀 승인 상태는 그대로 유지합니다.

## 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform version -json` | Terraform 1.16.4, darwin_arm64 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 sts get-caller-identity` | 기본 Sandbox 연결 실패 후 허용된 네트워크에서 인증 성공 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 rds describe-db-engine-versions --engine postgres --engine-version 17.11` | PostgreSQL 17.11 지원 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 rds describe-orderable-db-instance-options --engine postgres --engine-version 17.11 --db-instance-class db.t4g.small` | gp3 최소 20 GiB, MultiAZCapable=true, a/c 포함 4개 AZ 지원 |
| 2026-10-01 | 같은 프로필로 `s3api list-buckets`, `get-bucket-location`, `head-object` | 지정 버킷 존재와 서울 리전 확인, 해당 State Key는 아직 없음 |
| 2026-10-01 | 같은 프로필로 `cloudfront get-cache-policy` 2회와 `get-origin-request-policy` | CachingDisabled TTL 모두 0, CachingOptimized, API allExcept Host 및 모든 쿠키/Query 전달 확인 |
| 2026-10-01 | `terraform fmt -check -recursive env/dev modules/network modules/s3 modules/ecs modules/cloudfront` | PASS |
| 2026-10-01 | Network, S3, ECS, CloudFront와 dev의 `terraform validate -no-color` | 다섯 구성 PASS, 최종 dev 1.16.4 검증 |
| 2026-10-01 | `terraform -chdir=modules/network test -no-color` | 10 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/s3 test -no-color` | 4 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/ecs test -no-color` | 6 PASS, 0 FAIL |
| 2026-10-01 | `terraform -chdir=modules/cloudfront test -no-color` | 3 PASS, 0 FAIL |
| 2026-10-01 | `node --test modules/cloudfront/tests/spa.test.cjs` | 14 PASS, 0 FAIL |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-tests.jsonl` | 3 PASS, 0 FAIL.모든 run은 mock Plan |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-tests.jsonl` | 초기 구성과 활성화 구성의 전체 Plan 점검 2개 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform ./tf dev init -reconfigure -backend-config=backend.local.hcl -input=false -no-color -lockfile=readonly` | S3 Backend 초기화 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform ./tf dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev.tfplan` | 최종 56 add, 0 change, 0 destroy, 종료 코드 2, Plan 저장 성공 |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev.tfplan > .local/dev.tfplan.json` 후 Python 점검 | 리소스 수, 서비스/Secret Version 생략, RDS 설정과 암호값 부재 확인 |
| 2026-10-01 | README 속성명 대조 Python 점검 | 입력 30개, 출력 28개 모두 문서화 |
| 2026-10-01 | `git diff --check`, 변경 파일 문자/공백/Markdown 표 점검 | PASS |
| 2026-10-01 | `git check-ignore`로 Plan, JSON, 로그와 로컬 Backend 점검 | 모두 Git 제외. dev Provider Lock 파일은 제외하지 않음 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform ./tf dev workspace show` | default workspace 확인 |
| 2026-10-01 | 같은 프로필의 `s3api list-objects-v2`로 승인 Key 접두사 조회 | 현재 State와 잠금 파일 객체 없음. Apply 미수행 상태 확인 |
| 2026-10-01 | 커밋 직전 `git diff --check`, `terraform fmt -check -recursive env/dev modules/network modules/s3 modules/ecs modules/cloudfront` | PASS |
| 2026-10-01 | 커밋 직전 `python3 scripts/check-dev-test-plan.py .local/dev-tests.jsonl` | 저장된 초기 구성과 활성화 구성의 전체 Plan 점검 2개 PASS |
| 2026-10-01 | 커밋 후보 47개 파일의 민감 정보 패턴과 제외 파일 점검 | 개인 키, AWS 키, GitHub 토큰 패턴 일치 없음. State와 로컬 설정 포함 없음 |
| 2026-10-01 | `git switch -c codex/ecs-postgresql-dev`, `git commit -m "feat: add ECS and PostgreSQL dev infrastructure"` | 구현 커밋 `c1a36ed` 생성 |
| 2026-10-01 | `git push -u origin codex/ecs-postgresql-dev` | 원격 브랜치 생성과 푸시 완료 |
| 2026-10-01 | `git ls-remote origin refs/heads/codex/ecs-postgresql-dev` | 원격 SHA `c1a36ed4ba9093dc68dde5fbc71fb5808dbbadf0`, 구현 커밋과 일치 |

Provider 스키마와 mock 테스트의 로컬 통신은 Sandbox에서 차단되어 허용된 실행 환경에서 재시도했습니다. 최초 Network 테스트의 빈 NAT 대상 비교와 mock Plan의 unknown 비교를 수정한 뒤 관련 테스트를 다시 실행했습니다. 최종 결과만 PASS로 표시했으며 Apply와 배포 결과는 없습니다.

## 후속 변경: dev 백엔드 내부 포트 8000

### Ideation

- 문제 정의: 백엔드가 수신할 포트가 8000으로 예정되어 기존 dev 기본값 8080과 다릅니다.
- 사용자: 백엔드 배포 담당자와 dev 인프라 운영자입니다.
- 성공 기준: dev 기본 구성의 ALB Target Group, ALB와 ECS 사이 보안 그룹 규칙, ECS Task의 컨테이너 포트가 8000으로 일치합니다.
- Scope: dev Root Module 기본값, 결합 테스트와 관련 README, Runbook, AI-DLC 상태 기록입니다.
- Non-goals: 외부 ALB Listener 80 변경, 재사용 ECS 모듈의 기본값 변경, Apply와 실제 배포입니다.

### Inception

- Functional Requirements: `env/dev`의 `container_port` 기본값을 8000으로 설정합니다. 현재 `var.container_port`를 참조하는 Target Group, 보안 그룹 규칙과 ECS Service 입력은 그대로 사용합니다.
- Non-Functional Requirements: 별도 포트를 지정하는 호출자의 재정의 기능, `/api/health` 상태 확인 경로, CloudFront와 ALB의 외부 경로를 유지합니다.
- Architecture: CloudFront에서 Internal ALB HTTP 80까지는 기존 경로를 사용하고, ALB에서 Fargate 컨테이너까지 TCP 8000을 사용합니다.
- Unit of Work: 단일 Unit으로 기본값, 기본 포트와 재정의 포트의 mock 검증, 문서와 실제 AWS Plan 검토를 묶습니다.
- Acceptance Criteria: 기본 구성의 Target Group과 보안 그룹 규칙, 서비스 활성화 구성의 Task 포트가 8000입니다. 명시적 9090 재정의도 유지하고, 실제 AWS Plan의 변경과 교체 여부를 확인합니다.

### Construction Unit 5

- Design: 포트의 단일 원천인 dev `container_port` 기본값만 바꾸고 연결 모듈의 범용 기본값은 유지합니다.
- Implementation Plan: 기본값과 테스트 기대값을 바꾸고, 기본 포트로 서비스를 활성화한 mock Plan을 추가한 뒤 관련 문서를 갱신합니다. fmt, validate, dev mock, Plan 검사와 실제 AWS Plan을 실행합니다.
- Approval: 2026-10-01 사용자가 백엔드 내부 포트 8000과 이 변경 계획을 승인했습니다.
- Implementation: dev `container_port` 기본값을 8000으로 바꿨습니다. 기본 포트로 ECS 서비스를 활성화하는 mock run을 추가했고, 명시적 9090 재정의 run은 유지했습니다. dev README와 Runbook을 갱신했습니다.
- Test: Terraform fmt와 validate, dev mock 6개, 전체 Plan 점검 3개가 통과했습니다. 실제 AWS Plan은 56개 생성, 변경과 삭제 0개입니다.
- Review: 실제 Plan의 ALB Listener는 80, Target Group과 ALB/ECS 규칙은 8000이며 Health Check 포트는 `traffic-port`입니다. 초기 구성에 ECS Service와 Task Definition은 없고, 서비스 활성화 시 Task의 8000 포트는 mock Plan으로 확인했습니다.

### Operation과 Git 상태

- Deployment와 Observability: Apply와 배포는 미수행입니다. 서비스 활성화 후 앱이 `0.0.0.0:8000`에서 수신하고 `/api/health`에 응답하는지 확인해야 합니다.
- Rollback: Apply 전에는 기본값을 되돌릴 수 있습니다. Apply 이후에는 Target Group 이름과 교체 순서를 실제 State와 Plan으로 검토합니다.
- Git: 이번 포트 변경을 `main`에 커밋하고 원격 SHA 일치를 확인했습니다.

### 후속 변경 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform fmt -check -recursive env/dev` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-port-8000-tests.jsonl` | mock 6 PASS, 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-port-8000-tests.jsonl` | 초기 구성, 기본 포트 서비스, 9090 재정의의 전체 Plan 점검 3 PASS |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 sts get-caller-identity` | 계정 `723225040786` 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-port-8000.tfplan > .local/dev-port-8000-plan.log` | 종료 코드 2, 56 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-port-8000.tfplan > .local/dev-port-8000.tfplan.json` 후 Python 인라인 점검 | Listener 80, Target Group과 ALB/ECS 규칙 8000, Health Check `traffic-port`, 초기 ECS Service 생략 확인 |
| 2026-10-01 | `git diff --check` | PASS |
| 2026-10-01 | `git commit -m "fix: align dev backend port to 8000"` | dev 포트 변경과 문서 커밋 완료 |
| 2026-10-01 | `git push origin main`, `git ls-remote origin refs/heads/main` | 원격 `main` 푸시 및 SHA 일치 확인 |

## 후속 변경: dev Regional NAT와 private-only VPC

### Ideation: 승인됨

- 문제 정의: 기존 dev는 Public Subnet 2개에 Zonal NAT 2개를 배치했습니다. 배포 플랫폼 VPC에서 불필요한 Public Subnet을 없애고 Regional NAT로 외부 송신을 제공해야 합니다.
- 사용자: dev 배포 플랫폼 운영자와 CloudFront를 통해 서비스를 이용하는 사용자입니다.
- 성공 기준: dev VPC에 Public Subnet과 Public Route Table이 없고, App과 DB는 Private Subnet에 유지됩니다. App만 Regional NAT로 인터넷에 송신하고 DB에는 기본 경로가 없습니다. ALB는 Internal이며 ECS Task에는 Public IP를 할당하지 않습니다.
- Scope: `env/dev` Network 호출, 결합 mock Plan과 전체 Plan 점검, 관련 README, AI-DLC와 Runbook, 실제 AWS Plan 검토입니다.
- Non-goals: 재사용 Network 모듈의 인터페이스 변경, stg/prd 구성, VPC Endpoint와 새 보안 그룹 정책, Terraform Apply와 배포입니다. 커밋과 푸시는 후속 요청으로 범위에 추가됐습니다.
- 승인: 2026-10-01 사용자가 이 범위와 private-only의 의미를 승인했습니다. 여기서 private-only는 워크로드와 ALB에 Public Subnet 및 Public IP가 없다는 뜻입니다. Regional NAT의 인터넷 송신과 CloudFront VPC Origin을 위해 VPC에는 Internet Gateway가 연결됩니다.

### Inception: 승인됨

- Functional Requirements: dev의 `nat_gateway_mode`를 `regional`로 설정하고 Public Subnet과 Zonal NAT 배치 입력을 제거합니다. App Subnet 2개의 기본 경로는 같은 Regional NAT ID를 사용하고 DB Subnet 2개에는 인터넷 기본 경로를 만들지 않습니다. 기존 App, DB CIDR과 AZ를 유지합니다. `network.public_subnet_ids`는 빈 Map을 반환하고 `network.nat_gateway_ids`는 두 AZ 키가 같은 NAT ID를 가리킵니다.
- Non-Functional Requirements: 직접 인터넷 수신 경로를 만들지 않습니다. Regional NAT는 AWS가 AZ와 송신 IP를 관리하며, 한 리소스여도 활성 AZ별 시간 요금과 데이터 처리 요금이 발생합니다. 기존 모듈 기능을 재사용하고 새 추상화나 Provider 의존성을 추가하지 않습니다.
- Architecture: CloudFront VPC Origin → Internal ALB → App Private Subnet → DB Private Subnet입니다. App의 HTTPS 송신만 Regional NAT → Internet Gateway를 사용합니다. DB에는 기본 경로가 없습니다. CloudFront VPC Origin에는 Internet Gateway가 VPC에 연결되어 있어야 하지만 ALB 서브넷의 인터넷 경로로 사용하지 않습니다.
- Unit of Work: 단일 Unit으로 dev Network 호출, 검증과 문서 갱신을 묶습니다.
- Acceptance Criteria: mock Plan에서 Public Subnet, Public Route Table, Public 기본 경로, Public Route Table 연결과 Terraform 관리 EIP가 각각 0개입니다. Internet Gateway 1개, Regional NAT 1개, Private Subnet 4개, App의 Regional NAT 기본 경로 2개와 DB 기본 경로 0개를 확인합니다. NAT의 `availability_mode`는 `regional`이며 두 App 경로가 동일 NAT ID를 가리킵니다. Internal ALB, ECS Public IP 비활성화와 기존 접근 규칙을 유지합니다. fmt, validate, dev mock과 전체 Plan 점검을 실행하고 실제 AWS Plan에서 생성, 변경, 삭제 및 교체를 확인합니다.

### Construction Unit 6: 승인된 Design과 Implementation Plan

- Design: 이미 구현된 `modules/network`의 Regional NAT 경로를 사용합니다. `env/dev/main.tf`에서 `public_subnets`와 `zonal_nat_subnet_keys`를 제거하고 모드만 변경합니다. Network 모듈과 출력 구조는 유지하며 `public_subnet_ids`는 빈 Map으로 남깁니다. `env/dev/security.tf`의 NAT 경로 설명을 현재 구성에 맞춥니다.
- Implementation Plan: dev 결합 mock의 Zonal NAT override를 Regional NAT override로 바꾸고 `env/dev/tests-terraform-1.17/platform.tftest.hcl`과 `scripts/check-dev-test-plan.py`에서 Public 리소스 부재, Regional NAT와 App/DB 경로를 검증합니다. `env/dev/README.md`, 이 AI-DLC 문서, `docs/README.md`와 Runbook을 실제 구성과 검증 결과에 맞춰 갱신합니다. Terraform fmt, validate, dev mock, 전체 Plan 점검, 실제 AWS Plan을 차례로 실행한 뒤 diff와 Plan을 Review합니다.
- Approval: 2026-10-01 사용자가 Inception과 이 Unit의 Design 및 Implementation Plan을 승인했습니다.
- Implementation: dev Root Module에서 Public Subnet과 Zonal NAT 선택을 제거하고 Regional NAT를 선택했습니다. 결합 mock과 전체 Plan 점검을 Regional NAT, App 기본 경로 2개, DB 격리에 맞췄습니다. 기존 모듈의 코드는 변경하지 않았습니다.
- Test: `terraform fmt`, 허용된 환경의 `terraform validate`, dev mock 6개와 전체 Plan 점검 3개가 통과했습니다. 실제 AWS Plan은 47개 생성, 변경과 삭제 0개입니다.
- Review: 실제 Plan에는 Private Subnet 4개, Internet Gateway 1개, Regional NAT 1개, App의 Regional 기본 경로 2개가 있습니다. Public Subnet, Public Route Table과 경로, Terraform 관리 EIP, DB 기본 경로는 없습니다. ALB는 Internal, RDS는 비공개이며 초기 ECS Service와 Task Definition은 없습니다. mock Plan에서 활성화된 ECS Task의 Public IP 비활성화를 확인했습니다.
- Operation: Apply와 배포는 이 Unit에 포함하지 않습니다. 향후 기존 Zonal NAT에서 실제 전환한다면 연결 재설정과 송신 IP 변경 가능성을 검토하고, Plan에서 State 기준 삭제와 교체를 확인한 후 별도 승인으로 진행합니다.
- Git: 후속 요청에 따라 변경을 `main`에 커밋하고 푸시했습니다. 로컬 HEAD와 원격 main의 SHA 일치를 확인했습니다.

### Unit 6 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform fmt -check -recursive env/dev` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | Sandbox에서 Provider 기동 실패. 허용된 환경 재실행 PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-regional-nat-tests.jsonl` | mock 6 PASS, 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-regional-nat-tests.jsonl` | 초기 구성과 서비스 활성화 구성의 전체 Plan 점검 3 PASS |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json` | 계정 `723225040786` 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-regional-nat.tfplan > .local/dev-regional-nat-plan.log` | 종료 코드 2, 47 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-regional-nat.tfplan > .local/dev-regional-nat.tfplan.json` 후 Python 점검 | Public 리소스 부재, Regional NAT 1개, App 경로 2개, ALB/RDS 비공개와 초기 ECS Service 생략 확인 |
| 2026-10-01 | `git diff --check` | PASS |
| 2026-10-01 | `git commit -m "feat: switch dev to regional NAT"` | Unit 6 변경 커밋 완료 |
| 2026-10-01 | `git push origin main`, `git ls-remote origin refs/heads/main` | 원격 `main` 푸시 및 SHA 일치 확인 |

## 후속 변경: dev DATABASE_URL Parameter Store 연동

### Ideation: 승인됨

- 문제 정의: 현재 dev 백엔드는 DB 접속 정보를 일반 환경변수와 Secrets Manager의 앱 계정 Secret으로 나누어 받습니다. 백엔드가 요구하는 단일 `DATABASE_URL`을 ECS Task의 Secret으로 주입해야 합니다.
- 사용자: 인프라, 백엔드와 배포 파이프라인 담당자입니다.
- 성공 기준: 서비스 Task Definition이 `/sbh/platform/demo/backend/DATABASE_URL`의 SSM SecureString ARN을 `DATABASE_URL`로 참조하고, 실행 역할만 해당 Parameter를 읽을 수 있습니다. 값은 Terraform 변수, Plan과 State에 들어가지 않으며 mock Plan과 실제 AWS Plan에서 참조 및 권한을 검토합니다.
- Scope: dev Root Module의 ECS Secret 연결과 실행 역할, 기존 앱 Secret 참조 정리, 결합 검증, dev README, AI-DLC와 Runbook입니다.
- Non-goals: RDS 버전, 크기, DB 이름과 CloudFront 변경, 마이그레이션 Task 및 파이프라인 생성, 실제 Parameter 값 등록, Apply와 배포입니다.
- 승인: 2026-10-01 사용자가 Parameter Store 연동 중심의 범위와 실제 값의 별도 등록 방식을 선택하고 위 Ideation의 Inception 진행을 승인했습니다. 지정 경로는 같은 날 메타데이터 조회에서 발견되지 않았습니다.

### Inception: 승인됨

- Functional Requirements: dev의 기존 `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_SSLMODE`, `DB_USERNAME`, `DB_PASSWORD` 주입을 제거하고 ECS `secrets`에 `DATABASE_URL`의 전체 SSM ARN을 넣습니다. 실행 역할의 앱 Secret 읽기 권한을 해당 ARN에 한정된 `ssm:GetParameters`로 바꿉니다. RDS 관리형 관리자 Secret은 유지합니다. 쓰이지 않는 앱 Secrets Manager 메타데이터와 출력은 제거하고 비밀값을 담지 않는 Parameter ARN을 출력합니다.
- Non-Functional Requirements: Parameter는 승인된 운영 경로에서 기본 `aws/ssm` 키의 SecureString으로 등록합니다. Terraform은 Parameter 값을 생성하거나 조회하지 않습니다. 고객 관리 KMS 키를 쓰기로 변경한다면 배포 전에 실행 역할의 `kms:Decrypt` 정책을 별도 검토해야 합니다. 기존 ECS 모듈 인터페이스와 DB, 네트워크, CloudFront 구성을 유지합니다.
- Architecture: 운영 경로에서 SSM SecureString 등록 → ECS 실행 역할의 정확한 Parameter ARN 읽기 → Task Definition `secrets.valueFrom` → 컨테이너 `DATABASE_URL`입니다. 마이그레이션 Task도 동일한 실행 역할, Secret 참조와 App Subnet 및 ECS Security Group을 사용해야 하지만 해당 Task 생성은 별도 작업입니다.
- Unit of Work: 단일 Unit 7에서 dev Terraform 연결, 결합 mock 검사, 문서와 실제 AWS Plan 검토를 함께 처리합니다.
- Acceptance Criteria: 활성 서비스의 컨테이너 Secret은 정확히 `DATABASE_URL` 하나이고 전체 SSM ARN을 가리킵니다. 분리된 DB 환경변수와 앱 Secrets Manager 참조는 없습니다. 실행 정책은 해당 ARN에 `ssm:GetParameters`만 허용하며 Task Role에는 이 권한이 없습니다. 초기 이미지 Digest가 없을 때 ECS Service와 Task Definition은 생성하지 않습니다. fmt, validate, 결합 mock 및 전체 Plan 검사를 실제 실행하고 AWS Plan에서 생성, 변경, 삭제 및 비밀값 부재를 확인합니다. Parameter의 실재, 실제 주입과 DB 연결은 Apply 및 배포 전후 별도 확인 대상입니다.

### Construction Unit 7: 승인된 Design과 Implementation Plan

- Design: `env/dev`에 경로와 계정 및 리전으로 계산한 SSM ARN을 한 번 정의하고 ECS Secret, IAM 정책과 비밀값 없는 출력에서 재사용합니다. 재사용 ECS 모듈의 기존 `secrets` 입력을 사용합니다. 기존 앱 Secret 메타데이터는 구성에서 제거하고 실제 State에 존재해 삭제가 계획되면 Apply 전에 별도 검토합니다.
- Implementation Plan: `env/dev/main.tf`, `iam.tf`, `outputs.tf`를 수정하고 `platform.tftest.hcl`과 `check-dev-test-plan.py`에서 정확한 ARN, 최소 권한과 이전 참조 부재를 확인합니다. dev README와 Runbook에는 실제 DB 엔드포인트 및 `db_name`을 사용해 URL을 등록하는 절차, 예약 문자 URL 인코딩, Parameter 메타데이터 사전 확인, Task 재시작 시점과 마이그레이션 Task의 선행 조건을 기록합니다. AI-DLC와 `docs/README.md`의 상태를 동기화합니다. 그 뒤 fmt, validate, 결합 mock, 전체 Plan 검사, 실제 AWS Plan과 diff를 Review합니다.
- Approval: 2026-10-01 사용자가 이 Inception과 Unit 7의 Design 및 Implementation Plan을 승인했습니다. 실제 AWS Plan까지 승인했으며 Apply, 값 등록, 커밋과 푸시는 포함하지 않았습니다.
- Implementation: dev Root Module에 비밀값 없는 SSM ARN을 정의해 ECS `DATABASE_URL` Secret, 실행 정책과 출력에 연결했습니다. 기존 앱 Secrets Manager 메타데이터, 분리된 DB 환경변수와 앱 Secret 읽기 권한을 제거했습니다. 재사용 ECS 모듈은 변경하지 않았습니다.
- Test: `terraform fmt`와 허용된 환경의 `terraform validate`가 통과했습니다. dev 결합 mock 6개와 전체 Plan 점검 3개가 통과했고, 활성 구성에서 정확한 Secret ARN과 실행 역할의 `ssm:GetParameters`, 이전 앱 Secret 부재를 확인했습니다.
- Review: 실제 AWS Plan은 46개 생성, 변경과 삭제 0개입니다. Backend State 파일은 존재하지만 `state list`의 관리 리소스는 비어 있습니다. Plan JSON에는 SSM ARN 출력만 있고 Parameter 값, 앱 Secret 리소스와 평문 DB URL은 없습니다. 초기 구성이라 ECS Task Definition과 Service가 없으며 실행 IAM 정책 본문도 ECR ARN이 미정이어서 실제 Plan에서는 확정되지 않습니다. 활성 Task 참조와 정책의 정확한 ARN은 mock Plan으로 확인했습니다.
- Operation: Runbook에 앱 계정 생성 뒤 외부 SecureString 등록, 메타데이터 사전 확인, 별도 마이그레이션 Task의 선행 조건, 값 교체 후 Task 재시작을 기록했습니다. 2026-10-01 조회 시 Parameter는 아직 존재하지 않았습니다. Apply, 값 등록, 배포와 DB 접속 검증은 수행하지 않았습니다.
- Git: 후속 요청으로 Unit 7과 8의 구현 변경을 커밋 `2886bd4`로 `main`에 푸시하고 원격 SHA 일치를 확인했습니다.

### Unit 7 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters`에서 지정 Name 메타데이터 조회 | 결과 빈 배열. 값은 조회하지 않음 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 s3api head-object --bucket sbh-platform-prod-s3-tf --key sbh-platform/dev/terraform.tfstate` | Sandbox 네트워크 연결 실패. State 존재 여부는 이번 조회로 판정하지 않음 |
| 2026-10-01 | 같은 `s3api head-object` 명령을 허용된 환경에서 재실행 | State 객체 존재 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev state list` | 관리 리소스 목록 빈 결과 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL --query 'Parameters[].[Name,Type,KeyId]' --output json` | 빈 배열. 비밀값은 조회하지 않음 |
| 2026-10-01 | `terraform fmt -check -recursive env/dev`, Python AST 구문 검사, `git diff --check` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | Sandbox에서 Provider 시작 실패 후 허용된 환경 재실행 PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-parameter-store-tests.jsonl` | Sandbox에서 Provider 시작 실패 후 허용된 환경 재실행, mock 6 PASS / 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-parameter-store-tests.jsonl` | 초기 구성과 활성 구성 전체 Plan 검사 3 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-parameter-store.tfplan > .local/dev-parameter-store-plan.log` | 종료 코드 2, 46 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-parameter-store.tfplan > .local/dev-parameter-store.tfplan.json` 및 Python 인라인 검사 | Sandbox에서 Provider 시작 실패 후 허용된 환경 재실행. 생성 46개, 삭제 없음, SSM ARN 출력, 값과 앱 Secret 리소스 부재 확인 |

## 후속 변경: dev ECS 배포 소유 경계

### Ideation: 승인됨

- 문제 정의: 현재 dev는 이미지 Digest를 지정하면 Terraform이 Task Definition과 Service를 함께 소유합니다. CI/CD가 새 Task Definition revision을 Service에 배포한 뒤 Terraform Apply를 실행하면 Service가 Terraform의 이전 revision으로 돌아갈 수 있습니다.
- 사용자: 인프라 운영자, 백엔드와 CI/CD 담당자입니다.
- 성공 기준: dev Terraform State와 Plan이 Task Definition 및 Service를 관리하지 않고, CI/CD가 두 리소스를 생성하고 갱신할 수 있도록 인프라 식별자와 런타임 계약을 제공합니다. 이후 인프라 Apply가 CI/CD의 Task Definition revision을 되돌리지 않습니다.
- Scope: dev Root Module의 ECS 호출과 입력 및 출력, 결합 검증, dev README, AI-DLC, 프로젝트 README와 Runbook의 배포 소유 경계입니다. Unit 7의 Parameter Store ARN과 실행 역할 권한은 유지합니다.
- Non-goals: CI/CD 워크플로와 배포용 IAM 주체 생성, 실제 Task Definition 및 Service 등록, Parameter 값 등록, Terraform Apply, 배포, 커밋과 푸시입니다.
- 승인: 2026-10-01 사용자가 CI/CD가 Task Definition과 Service를 소유하는 방향으로 Ideation을 승인했습니다. 현재 저장소에는 배포 워크플로가 없고, 이전 확인 시 dev Terraform State의 관리 리소스 목록은 비어 있었습니다. 새 Plan에서 삭제와 교체 여부를 다시 확인합니다.

### Inception: 승인됨

- Functional Requirements: dev `module.ecs`는 Cluster와 로그 그룹만 생성합니다. `backend_image_digest` 입력과 dev의 Terraform 관리 Task Definition 및 Service 활성화 경로를 제거합니다. `backend` 출력은 ECR 저장소, Cluster, 로그 그룹, 실행 및 Task Role, ECS Security Group, ALB Target Group, 컨테이너 이름과 포트를 CI/CD에 제공합니다. `network.app_subnet_ids`와 `database.database_url_parameter_arn`도 CI/CD 입력 계약에 포함합니다. Service와 Task Definition ARN 출력은 제거합니다.
- Non-Functional Requirements: 기존 범용 ECS 모듈 인터페이스는 유지하고 dev에서 `service`를 전달하지 않습니다. 비밀값은 Terraform에 입력하거나 조회하지 않습니다. Terraform이 관리하는 Cluster, ALB, 보안 그룹과 역할의 변경은 서비스에 영향을 줄 수 있으므로 계속 Plan을 검토합니다.
- Architecture: Terraform → ECR, ECS Cluster, 로그 그룹, IAM Role과 SSM 읽기 권한, App Subnet 및 Security Group, ALB Target Group을 제공합니다. CI/CD → 이미지 Digest로 Task Definition revision 등록, 동일 네트워크에서 마이그레이션 Task 실행, ECS Service 생성 또는 새 revision으로 갱신을 수행합니다. 컨테이너는 `app`, 기본 포트 8000, Fargate Linux X86_64, CPU 512, 메모리 1024 MiB, `DATABASE_URL` SSM Secret 참조를 사용합니다.
- Unit of Work: 단일 Unit 8에서 dev의 소유 경계, 결합 검증, 문서와 실제 AWS Plan 검토를 처리합니다.
- Acceptance Criteria: 기본 dev mock Plan과 실제 AWS Plan에 `aws_ecs_task_definition`, `aws_ecs_service`가 없습니다. dev에는 이미지 Digest 입력이 없고 출력에는 CI/CD가 필요한 ARN, ID, 포트와 이름이 있습니다. Parameter ARN 및 실행 역할의 `ssm:GetParameters` 권한은 유지됩니다. 기존 Network, RDS, ALB와 CloudFront 구성을 유지하고 fmt, validate, 결합 mock 및 Plan 검사를 실행합니다. 실제 AWS Plan에 의도하지 않은 삭제나 교체가 없는지 확인합니다.

### Construction Unit 8: 승인된 Design과 Implementation Plan

- Design: 범용 `modules/ecs`의 선택적 `service` 인터페이스는 그대로 두고 dev 호출에서 서비스 입력을 제거합니다. Cluster와 로그 그룹은 다른 인프라와 직접 의존하지 않으므로 dev ECS 모듈의 `depends_on`도 제거합니다. CI/CD 인수인계에 필요한 비밀값 없는 출력만 추가합니다.
- Implementation Plan: `env/dev/main.tf`에서 `service`와 관련 의존성을, `variables.tf`에서 이미지 Digest 입력을 제거합니다. `outputs.tf`의 배포 리소스 ARN을 CI/CD 인프라 출력으로 교체합니다. dev 결합 mock과 `check-dev-test-plan.py`를 서비스 생성 테스트 대신 인프라 및 출력 계약 검사로 바꾸고 포트 재정의 검증을 유지합니다. dev README, AI-DLC, 프로젝트 README와 Runbook에 CI/CD의 Task Definition 등록, 마이그레이션, Service 생성 및 후속 revision 배포 순서를 기록합니다. fmt, validate, 결합 mock, 전체 Plan 검사와 실제 AWS Plan을 실행하고 diff 및 삭제 여부를 Review합니다.
- Approval: 2026-10-01 사용자가 Inception과 Unit 8의 Design 및 Implementation Plan을 승인했습니다. mock 검증과 실제 AWS Plan까지 포함하며 Apply, CI/CD 워크플로 구현, 커밋과 푸시는 포함하지 않았습니다.
- Implementation: dev ECS 모듈 호출에서 `service`와 불필요한 전체 모듈 의존성을 제거하고 이미지 Digest 입력을 삭제했습니다. CI/CD에 필요한 Cluster, ECR, 로그 그룹, Role, ECS Security Group, ALB Target Group, 컨테이너 이름과 포트를 출력합니다. 범용 ECS 모듈은 변경하지 않았고 Unit 7의 SSM 권한 및 ARN은 유지했습니다.
- Test: `terraform fmt`와 허용된 환경의 `terraform validate`, dev mock 4개와 전체 Plan 점검 2개가 통과했습니다. 기본 포트 8000과 재정의 포트 9090에서 ALB 및 보안 그룹 연결, CI/CD 출력 계약과 Task Definition 및 Service 부재를 확인했습니다.
- Review: 실제 AWS Plan은 46개 생성, 변경과 삭제 0개입니다. Plan JSON에 Terraform 관리 Task Definition, Service, 앱 Secret과 SSM 값 리소스가 없고 이미지 Digest 입력도 없습니다. CI/CD 인수인계 출력과 비밀값 없는 SSM ARN을 확인했습니다. Parameter 값의 존재, CI/CD 동작과 실제 서비스 배포는 검증하지 않았습니다.
- Operation: Runbook에 Terraform 인프라 Apply 이후 CI/CD의 Task Definition 등록, 마이그레이션 Task, Service 생성 및 후속 revision 갱신 순서와 AZ 재분산 및 배포 Circuit Breaker 설정을 기록했습니다. Apply와 배포는 수행하지 않았습니다.
- Git: 후속 요청으로 Unit 7과 8의 구현 변경을 커밋 `2886bd4`로 `main`에 푸시하고 원격 SHA 일치를 확인했습니다.

### Unit 8 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform fmt -check -recursive env/dev`, Python AST 구문 검사, `git diff --check` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | 허용된 환경에서 PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-cicd-ownership-tests.jsonl` | mock 4 PASS / 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-cicd-ownership-tests.jsonl` | 기본 포트와 재정의 포트 전체 Plan 검사 2 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-cicd-ownership.tfplan > .local/dev-cicd-ownership-plan.log` | 종료 코드 2, 46 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-cicd-ownership.tfplan > .local/dev-cicd-ownership.tfplan.json` 후 Python 인라인 검사 | 허용된 환경에서 JSON 변환, Terraform 관리 Task Definition과 Service 부재, CI/CD 출력, 삭제 및 평문 DB URL 부재 확인 |
| 2026-10-01 | `git diff --cached --check`, `git diff --cached --name-only` | 공백 오류 없음, 검토한 10개 파일만 스테이징 확인 |
| 2026-10-01 | `git commit -m 'feat: hand off dev ECS deployment and use SSM DATABASE_URL'`, `git push origin main` | 구현 커밋 `2886bd4292bbe18bbe1ba1daea5107e74af04b10` 푸시 완료 |
| 2026-10-01 | `git ls-remote origin refs/heads/main` | 원격 SHA `2886bd4292bbe18bbe1ba1daea5107e74af04b10`으로 로컬 구현 커밋과 일치 |

## 후속 변경: dev 초기 DB 이름 freesia

### Ideation: 승인됨

- 문제 정의: dev PostgreSQL의 초기 DB 이름 기본값은 `sbhapp`이고 사용자가 요청한 이름은 `freesia`입니다. dev README와 Runbook에도 이전 기본값이 적혀 있습니다.
- 사용자: dev 인프라와 백엔드 담당자입니다.
- 성공 기준: dev 기본값이 `freesia`이고 RDS 입력과 `database.name` 출력 및 운영 문서가 일치합니다. 실제 AWS Plan에서 의도하지 않은 삭제나 교체가 없어야 합니다.
- Scope: dev Root Module의 기본값, 기존 결합 Plan 검사, dev README와 Runbook, AI-DLC 및 프로젝트 진행 상태입니다.
- Non-goals: 재사용 RDS 모듈의 기본값 변경, 기존 DB 데이터나 이름의 직접 변경, `DATABASE_URL` 값 등록, Terraform Apply와 배포, 커밋과 푸시입니다.
- 승인: 2026-10-01 사용자가 위 dev DB 이름 변경 범위에 `ㄱㄱ`로 답해 Ideation 진행을 승인했습니다.

### Inception: 승인됨

- Functional Requirements: `env/dev`의 `db_name` 기본값을 `freesia`로 설정합니다. 기존 `module.database.db_name = var.db_name`과 `database.name = var.db_name` 경로를 유지하고, 문서에 표시된 기본값을 맞춥니다.
- Non-Functional Requirements: `db_name` 재정의 기능과 검증 규칙을 유지합니다. 비밀값을 Terraform이나 검증 기록에 넣지 않습니다. 현재 인프라와 배포 소유 경계를 바꾸지 않습니다.
- Architecture: dev 변수 → 재사용 RDS 모듈의 `aws_db_instance.primary.db_name`; 같은 변수 → `database.name` 출력입니다. DB 접속 URL은 Terraform 밖의 SSM SecureString 값으로 관리합니다.
- Unit of Work: 단일 Unit 9에서 기본값, 기존 결합 검사, 관련 문서와 실제 AWS Plan 검토를 처리합니다.
- Acceptance Criteria: 기본 dev mock Plan의 RDS `db_name`과 `database.name` 출력이 `freesia`이고 fmt, validate 및 결합 Plan 검사가 통과합니다. 실제 AWS Plan의 생성, 변경, 삭제와 교체 여부를 확인합니다. 기존 리소스의 삭제나 교체가 보이면 구현을 멈추고 별도 검토합니다. Apply와 배포는 수행하지 않습니다.

### Construction Unit 9: Design과 Implementation Plan 승인됨

- Design: `env/dev/variables.tf`의 기본값만 변경하고 기존 전달 경로를 재사용합니다. 새 추상화나 재사용 모듈 변경은 필요하지 않습니다. 기존 `scripts/check-dev-test-plan.py`에서 RDS 계획값과 dev 출력값을 확인합니다.
- Implementation Plan: 변수 기본값, 결합 Plan 검사, dev README와 Runbook의 기본 이름을 갱신합니다. fmt, validate, dev mock과 전체 Plan 검사 후 `sbh-platform` 실제 AWS Plan을 실행하고 삭제 및 교체를 검토합니다. 승인된 단계와 검증 결과를 이 문서 및 `docs/README.md`에 기록합니다.
- Approval: 2026-10-01 사용자가 `ㄱㄱ`로 Inception과 Unit 9의 Design 및 Implementation Plan을 승인했습니다. 실제 AWS Plan까지 포함하며 Apply, 배포, 커밋과 푸시는 포함하지 않습니다.
- Implementation: `env/dev/variables.tf`의 `db_name` 기본값을 `freesia`로 변경했습니다. 기존 RDS 입력과 출력 연결은 유지하고 전체 Plan 검사에 두 값의 일치 확인을 추가했습니다. dev README와 Runbook의 기본 이름을 갱신했습니다.
- Test: fmt, validate와 Python 구문 검사가 통과했습니다. dev mock 4개와 기본 및 재정의 포트의 전체 Plan 검사 2개가 통과했고 RDS 입력과 출력이 모두 `freesia`임을 확인했습니다.
- Review: 실제 AWS Plan은 46개 생성, 변경과 삭제 0개입니다. 계획된 RDS의 `db_name`과 `database.name` 출력이 `freesia`이며 교체, Terraform 관리 ECS Service 및 Task Definition, SSM Parameter 생성이 없습니다. 현재 Terraform State의 관리 리소스 목록은 비어 있습니다.
- Operation: Runbook에 새 기본 이름을 반영했습니다. 실제 DB 생성, 기존 데이터 변경, `DATABASE_URL` 값 등록, Apply와 배포는 수행하지 않았습니다.
- Git: 후속 요청으로 Unit 9 구현 변경을 커밋 `c0df773`으로 `main`에 푸시하고 원격 SHA 일치를 확인했습니다.

### Unit 9 사전 확인 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `rg -n 'sbhapp|freesia|db_name' --glob '!*.tfplan*' .` | 문서 제안 추가 전 `sbhapp`은 dev 변수 기본값과 dev README, Runbook에만 사용. RDS 모듈은 입력값을 그대로 전달 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev state list` | 현재 State의 관리 리소스 목록 빈 결과. 실제 AWS Plan은 아직 실행하지 않음 |
| 2026-10-01 | `git status --short` | 문서 제안 추가 전 작업 트리 변경 없음. Unit 9 구현 미시작 |
| 2026-10-01 | `terraform fmt -check -recursive env/dev`, Python AST 구문 검사, `git diff --check` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | 허용된 환경에서 PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-db-name-tests.jsonl` | mock 4 PASS / 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-db-name-tests.jsonl` | 기본 및 재정의 포트의 전체 Plan 검사 2개 PASS, RDS 입력과 출력 이름 `freesia` 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-db-name.tfplan > .local/dev-db-name-plan.log` | 종료 코드 2, 46 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-db-name.tfplan > .local/dev-db-name.tfplan.json` 및 Python 인라인 검사 | RDS `db_name`과 출력 `database.name`이 `freesia`, 생성 46개, 변경과 삭제 및 교체 없음 |
| 2026-10-01 | `git diff --cached --check`, `git diff --cached --name-only` | 공백 오류 없음, 검토한 6개 파일만 스테이징 확인 |
| 2026-10-01 | `git commit -m 'fix: set dev database name to freesia'`, `git push origin main` | 구현 커밋 `c0df773501058de4b09291b3ce134b9b6d9e0a3d` 푸시 완료 |
| 2026-10-01 | `git ls-remote origin refs/heads/main` | 원격 SHA `c0df773501058de4b09291b3ce134b9b6d9e0a3d`로 구현 커밋과 일치 |

## 후속 변경: dev DATABASE_URL Parameter 리소스 생성

### Ideation: 승인됨

- 문제 정의: dev Terraform은 Parameter ARN과 실행 역할의 읽기 권한만 제공하며 `/sbh/platform/demo/backend/DATABASE_URL` 리소스를 생성하지 않습니다.
- 사용자: dev 인프라와 백엔드 운영 담당자입니다.
- 성공 기준: Terraform이 실제 접속 정보를 넣지 않고 SecureString Parameter 리소스를 생성할 수 있어야 합니다. 운영자가 이후 등록한 값은 Terraform이 초기값으로 되돌리지 않아야 합니다.
- Scope: dev의 Parameter 리소스 하나, 기존 ARN 및 IAM 계약 유지, 결합 검증과 관련 운영 문서입니다.
- Non-goals: 앱 DB 계정 생성, 실제 `DATABASE_URL` 등록, 앱 배포, ECS Task Definition과 Service 생성입니다. 최초 제안은 코드 변경과 검증까지였으며 Parameter 생성 Apply와 커밋 및 푸시는 이후 별도 요청으로 승인받았습니다.
- 승인: 2026-10-01 사용자가 `그러면 일단 리소스 생성만 하게 ㄱㄱ`로 리소스 생성 방향을 승인했습니다. 초기값과 생성 이후 관리 방식은 아래 Inception 및 Design의 승인 대상입니다.

### Inception: 승인됨

- Functional Requirements: 기존 경로에 Standard 등급의 SecureString을 만들고 기본 `alias/aws/ssm` 키를 사용합니다. 생성 시 필요한 초기값은 접속 URL이 아닌 `NOT_CONFIGURED`입니다. 기존 ARN 출력과 실행 역할의 `ssm:GetParameters` 정책을 유지합니다. 실제 값은 운영 경로에서 이후 갱신합니다.
- Non-Functional Requirements: 초기값은 `value_wo`로 전달하고 갱신 번호는 1로 고정합니다. 실제 접속 정보가 Terraform 변수, 출력, Plan과 State에 저장되지 않게 합니다. AWS Provider 6.66.0은 write-only 모드에서도 refresh 시 `GetParameter`를 복호화 옵션으로 호출하므로, Unit 7의 "Terraform이 실제 값을 조회하지 않는다" 조건을 대체합니다. 사용자는 값 비저장과 Provider의 refresh 조회를 구분하는 이 제약까지 승인했습니다.
- Architecture: Terraform이 비밀이 아닌 초기값으로 Parameter를 생성하고 메타데이터 및 태그를 State에 관리합니다. 운영자가 실제 값을 갱신하며 CI/CD는 기존 ARN으로 Task Definition의 Secret 참조를 구성합니다. 초기값이 남아 있는 동안에는 DB 접속 준비가 완료된 상태가 아닙니다.
- Unit of Work: Unit 11 하나로 생성 구성, 기존 결합 검증 변경, 문서와 실제 AWS Plan 검토를 처리합니다.
- Acceptance Criteria: dev mock Plan에 정확한 경로의 SecureString Parameter가 하나 있고 일반 `value`와 `insecure_value`가 비어 있어야 합니다. 기존 ARN 출력 및 최소 읽기 권한이 일치해야 합니다. Terraform 관리 앱 Secret, Task Definition과 Service는 계속 없어야 합니다. fmt, validate, dev mock 및 전체 Plan 검사를 실제 실행합니다. AWS 인증이 가능한 경우 새 Plan에서 생성과 변경, 삭제 및 교체를 검토하고 다른 리소스 변경을 구분합니다.

### Construction Unit 11: Design과 Implementation Plan 승인됨

- Design: `env/dev`에 `aws_ssm_parameter.database_url`을 추가합니다. 경로를 Local 값 하나로 정의하고 기존 ARN은 같은 경로로 계산해 IAM 및 출력의 계획값을 유지합니다. `value_wo = "NOT_CONFIGURED"`, `value_wo_version = 1`, `overwrite = false`, 공통 태그를 사용합니다. `prevent_destroy = true`로 삭제 및 이름 변경에 따른 교체를 막습니다.
- 생성 이후 관리: `ignore_changes`에 `value_wo_version`, `allowed_pattern`, `data_type`, `description`, `key_id`, `tier`, `type`을 지정합니다. 현 Provider에서 이러한 속성 변경은 값을 다시 쓰는 API를 호출하므로 생성 이후 Terraform은 태그 변경만 관리합니다. `overwrite = false`는 기존 외부 Parameter가 있거나 잘못된 값 갱신이 계획됐을 때 덮어쓰기 대신 실패하게 하는 추가 제약입니다. 새 경로, 키 및 유형 변경은 별도 설계 대상입니다.
- Implementation Plan: 경로 Local과 Parameter 구성 파일을 추가합니다. 결합 mock에 고정 ARN을 제공하고 기존 전체 Plan 검사에서 SSM 리소스 금지 조건을 정확한 리소스 하나 및 값 비저장 조건으로 바꿉니다. dev README, 루트 README와 Runbook에 초기값, 운영자의 값 갱신, Provider의 refresh 조회 및 생성 이후 관리 범위를 반영합니다. AI-DLC와 `docs/README.md`를 같은 작업에서 갱신합니다. fmt, validate, 기존 dev mock과 전체 Plan 검사 후 SSO 인증이 복구되면 실제 AWS Plan을 Review합니다.
- Approval: 2026-10-01 사용자가 제시한 설계에 `ㄱㄱ`로 답해 Inception, Unit 11 Design과 Implementation Plan 및 코드 변경과 검증을 승인했습니다. 초기값, write-only 값 비저장, Provider의 refresh 조회와 생성 이후 갱신 방지 방식을 포함합니다. 이후 `apply하고 커밋 푸시`로 Parameter 리소스 생성 Apply와 커밋 및 푸시를 추가 승인했습니다. 실제 접속값 등록과 앱 배포는 포함하지 않습니다.
- Implementation: `env/dev/parameter-store.tf`에 Standard SecureString 리소스를 추가하고 경로 Local을 기존 ARN 계산과 공유했습니다. 승인한 `value_wo`, 고정 갱신 번호, 생성 이후 메타데이터 무시, 덮어쓰기 및 삭제 방지, 공통 태그를 적용했습니다. 기존 IAM과 출력 계약은 유지하고 결합 mock 및 전체 Plan 검사, 루트 및 dev README와 Runbook을 갱신했습니다. 모듈 입력과 출력은 변경하지 않았습니다.
- Test: fmt, validate 및 Python 구문 검사가 통과했습니다. dev mock 4개와 기본 및 재정의 포트의 전체 Plan 검사 2개가 통과했고 Parameter 리소스 하나, Standard SecureString, 기본 SSM 키, 값 비저장, ARN 및 IAM 계약을 확인했습니다. 최초 샌드박스 실행의 Provider handshake 실패는 허용된 환경에서 재실행해 해결했습니다. SPA 테스트는 이번 변경에서 재실행하지 않았습니다.
- Review: Apply 전 지정 Parameter가 없음을 확인하고 새 SSM 대상 지정 Plan 1 add / 0 change / 0 destroy를 검토했습니다. Apply 결과는 1 added / 0 changed / 0 destroyed이며 AWS 메타데이터는 지정 경로, SecureString, Standard, `alias/aws/ssm`, 버전 1입니다. 적용 후 State serial 10, 관리 리소스 인스턴스 49개이며 Parameter의 `has_value_wo = true`, `value = ""`, `insecure_value = null`, `value_wo = null`로 비밀값이 저장되지 않았습니다. 실제 ARN과 출력 및 실행 정책도 일치합니다. 적용 후 전체 Plan은 0 add / 1 change / 0 destroy이고 Parameter는 no-op, 기존 CloudFront Origin 표현 차이만 남습니다. 운영자의 실제 접속값 갱신 이후 동작과 DB 접속은 미검증입니다.
- Operation: 사용자 승인 후 검토한 저장 Plan으로 Parameter 리소스만 Apply했습니다. CloudFront와 기타 리소스는 변경하지 않았으며 대상 지정 경고에 따라 적용 후 전체 Plan을 확인했습니다. 실제 접속값 등록과 앱 배포는 미수행입니다. Runbook에 초기값 상태와 운영자의 값 갱신을 기록했습니다. CLI에서 비밀값을 출력하지 않았으며 Provider가 자체적으로 수행하는 refresh 조회는 별도 제약으로 기록했습니다.
- Git: 구현과 Apply 검증 기록의 커밋 및 푸시를 진행합니다. Backend 설정과 State, Plan, Provider 및 테스트 CLI는 Git 제외 경로에 보관했습니다.

### Unit 11 사전 확인 기록

| 날짜 | 명령 또는 자료 | 결과 |
|---|---|---|
| 2026-10-01 | `git status --short --branch`, `rg -n 'aws_ssm\|ssm:\|database_url'`로 dev 코드 및 관련 문서 확인 | 작업 시작 시 main 작업 트리 변경 없음. 생성 리소스 없이 ARN 및 읽기 권한만 확인 |
| 2026-10-01 | `env/dev/.terraform.lock.hcl`, [AWS PutParameter API](https://docs.aws.amazon.com/systems-manager/latest/APIReference/API_PutParameter.html), [AWS Provider 6.66.0 SSM 문서](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/website/docs/r/ssm_parameter.html.markdown), [동일 버전 구현](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/ssm/parameter.go) | 고정 AWS Provider 6.66.0. 생성 시 Value 필수. `value_wo` 비저장 지원, refresh 복호화 조회와 메타데이터 변경의 값 쓰기 경로 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL --query 'Parameters[].[Name,Type,KeyId]' --output json` | 기본 환경에서는 OIDC endpoint 연결 실패. 허용된 네트워크에서 재시도 시 `Token has expired and refresh failed`. 현재 존재 여부 미확인, 비밀값 조회 없음 |
| 2026-10-01 | `git diff --check`, Python 인라인 문서 금지 문자 검사, `git diff --stat` | 문서 공백 오류와 금지 문자 없음. 변경 파일은 AI-DLC와 문서 인덱스 2개이며 Terraform 코드 변경 없음 |

### Unit 11 구현 및 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `terraform -chdir=env/dev init -backend=false -lockfile=readonly -input=false -no-color` | AWS Provider 6.66.0과 Random 3.9.1 초기화 완료. 잠금 파일 변경 없음 |
| 2026-10-01 | 공식 HashiCorp Releases의 1.17.0-beta2 Darwin ARM64 ZIP과 SHA256SUMS 다운로드 및 Python SHA-256 대조 | 일치: `353b17a245e6857830d9bdcc81a2ef78b4bf246ed80303dd5673675f07667dde`. 기존 ephemeral mock 제약 때문에 테스트에만 사용 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL --query 'Parameters[].[Name,Type,KeyId]' --output json` | SSO 재인증 후 빈 배열. 지정 Parameter 없음, 비밀값 조회 없음 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 s3api head-object --bucket sbh-platform-prod-s3-tf --key sbh-platform/dev/terraform.tfstate --query '{LastModified:LastModified,ContentLength:ContentLength}' --output json` | 기록된 기존 dev Backend 파일 확인. 이후 전체 Plan의 prior_state에서 관리 리소스 인스턴스 48개 확인 |
| 2026-10-01 | `terraform -chdir=env/dev init -reconfigure -backend-config=backend.local.hcl -lockfile=readonly -input=false -no-color` | 기존 S3 Backend 연결 완료. State 이전 및 Apply 없음. 실제 Backend 설정은 Git 제외 파일에 작성 |
| 2026-10-01 | `terraform fmt env/dev/main.tf env/dev/parameter-store.tf env/dev/tests-terraform-1.17/platform.tftest.hcl`, `terraform fmt -check -recursive env/dev`, Python AST 검사 | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color`, dev mock 테스트 최초 기본 샌드박스 실행 | Provider handshake 실패. 구성 검증 및 테스트 완료로 표시하지 않음 |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | 허용된 환경에서 재실행 PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-ssm-parameter-tests.jsonl` | 허용된 환경에서 mock 4 PASS / 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-ssm-parameter-tests.jsonl` | 기본 포트와 재정의 포트의 전체 Plan 검사 2 PASS |
| 2026-10-01 | `terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-ssm-parameter.tfplan > .local/dev-ssm-parameter-plan.log` | 안정 버전 1.16.4, 종료 코드 2. 1 add / 1 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-ssm-parameter.tfplan > .local/dev-ssm-parameter.tfplan.json` 및 Python 검사 | Parameter 생성 하나, 값 필드 부재, 기존 CloudFront `origin` 표현 차이만 갱신, 삭제와 교체 없음 |
| 2026-10-01 | `terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -target=aws_ssm_parameter.database_url -out=../../.local/dev-ssm-parameter-only.tfplan > .local/dev-ssm-parameter-only-plan.log` | 종료 코드 2. 1 add / 0 change / 0 destroy. 대상 지정 경고는 이 보조 Plan에 예상된 결과 |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-ssm-parameter-only.tfplan > .local/dev-ssm-parameter-only.tfplan.json` 및 Python 검사 | 변경 리소스는 Parameter 생성 하나이며 실제 값 필드 부재 확인 |
| 2026-10-01 | `git check-ignore env/dev/backend.local.hcl .local/dev-ssm-parameter.tfplan .local/dev-ssm-parameter-tests.jsonl`, `git diff` 및 신규 리소스 파일 Review | Backend, Plan과 검증 산출물 Git 제외 확인. 승인한 생성 범위와 기존 계약 유지 확인 |
| 2026-10-01 | `git diff --check`, Python 인라인 문서 상대 링크 및 앵커와 금지 문자 검사 | PASS. 상대 링크 및 앵커 79개 확인, 신규 Parameter 파일을 포함한 변경 파일 9개의 금지 문자 없음 |

### Unit 11 Apply 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | 사용자 요청 `apply하고 커밋 푸시` | Parameter 생성 Apply와 커밋 및 푸시 승인. 실제 접속값 등록과 앱 배포 제외 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL --query 'Parameters[].[Name,Type,KeyId]' --output json` | Apply 전 빈 배열, 기존 Parameter 없음 |
| 2026-10-01 | `terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -target=aws_ssm_parameter.database_url -out=../../.local/dev-ssm-parameter-apply.tfplan > .local/dev-ssm-parameter-apply-plan.log` | 종료 코드 2. 최신 Plan 1 add / 0 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-ssm-parameter-apply.tfplan > .local/dev-ssm-parameter-apply.tfplan.json` 및 Python 검사 | 변경 항목은 정확히 Parameter 생성 하나. 경로, 유형, 키와 값 필드 비저장 확인 |
| 2026-10-01 | `terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-ssm-parameter-apply.tfplan > .local/dev-ssm-parameter-apply.log` | 종료 코드 0. 1 added / 0 changed / 0 destroyed. 대상 지정의 불완전 적용 경고는 이후 전체 Plan으로 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters --parameter-filters Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL --query 'Parameters[].{Name:Name,Type:Type,Tier:Tier,KeyId:KeyId,Version:Version}' --output json` | 경로 일치, SecureString, Standard, `alias/aws/ssm`, 버전 1. 비밀값 조회 없음 |
| 2026-10-01 | `terraform -chdir=env/dev state pull > .local/dev-ssm-parameter-postapply.tfstate` 및 Python 검사 | serial 10, 관리 인스턴스 49개. SDK가 `value`를 null 대신 빈 문자열로 저장하는 점을 반영해 미저장 판별을 보정. 값 없음, write-only 플래그와 ARN 및 IAM 계약 일치 |
| 2026-10-01 | `terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-ssm-parameter-postapply.tfplan > .local/dev-ssm-parameter-postapply-plan.log` | 종료 코드 2. 0 add / 1 change / 0 destroy |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-ssm-parameter-postapply.tfplan > .local/dev-ssm-parameter-postapply.tfplan.json` 및 Python 검사 | Parameter no-op 및 값 비저장. 기존 CloudFront Origin 표현 차이만 남으며 삭제와 교체 없음 |
