# ECS and PostgreSQL platform AI-DLC

마지막 확인일: 2026-10-01

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 2026-10-01 전체 구현 계획 승인 |
| Inception | 같은 계획의 요구사항과 인터페이스 승인 |
| Construction | Unit 1~4 구현, Test와 Review 완료. 후속 Unit 5에서 dev 백엔드 기본 포트 8000 반영 |
| 로컬 검증 | 기존 mock Plan 26개와 SPA 14개 통과. 후속 Unit 5의 dev mock 6개, 전체 Plan 점검 3개 통과 |
| 실제 AWS Plan | 후속 포트 변경 후 `sbh-platform`, 서울, S3 Backend에서 56 add / 0 change / 0 destroy. Target Group과 ALB/ECS 규칙 8000 확인 |
| Apply와 배포 | 사용자 지시로 수행하지 않음 |
| 커밋과 푸시 | 기존 구현 커밋 `c1a36ed` 확인. 후속 Unit 5 변경은 `main`에 커밋하고 원격 SHA 확인 |

사용자의 `PLEASE IMPLEMENT THIS PLAN` 요청은 아래 Ideation, Inception과 각 Unit의 Design 및 Implementation Plan 승인을 포함합니다. AWS 작업은 `sbh-platform` 프로필을 사용하며 실제 Terraform Plan까지만 수행합니다.

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
