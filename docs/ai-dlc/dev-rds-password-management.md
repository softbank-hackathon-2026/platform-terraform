# dev RDS 관리자 비밀번호 관리 방식 전환

마지막 확인일: 2026-10-01

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 기존 DB를 유지하면서 RDS 관리형 암호를 해제하는 범위 승인 |
| Inception | 기존 `module_managed_secret` 모드와 콘솔 수동 변경 방식 승인 |
| Construction | Unit 12 전환 및 버전 정밀도 수정 구현과 Review 완료 |
| 로컬 검증 | fmt, dev 및 독립 RDS validate, RDS mock 16개, dev mock 4개와 전체 mock Plan 점검 2개 통과 |
| 실제 AWS Plan | 최종 0 add / 1 change / 0 destroy. RDS와 관리자 Secret/Version 및 출력은 no-op, 기존 CloudFront Origin 표현 차이만 남음 |
| Apply | 초기 전환 및 Version 정밀도 수정 완료. DB와 Secret 컨테이너 유지, State 출력 refresh-only 적용 완료. 최종 serial 15, 관리 인스턴스 51개 |
| DB 접속과 앱 배포 | 미수행, 별도 접근 경로와 앱 배포 범위 |
| 커밋과 푸시 | 구현 및 검증 커밋 `b995fa7` main 푸시 완료, 원격 SHA 일치 확인 |

사용자는 모드와 콘솔 변경 방법을 설명받은 뒤 `비관리형으로 바꾸고 적용해줘`라고 요청했습니다. 이 요청은 아래 Ideation, Inception, Unit 12 Construction과 Apply 승인으로 기록합니다. 초기 암호는 모듈이 생성해 새 Secret에 저장합니다. 사용자 지정 암호 입력은 포함하지 않습니다. 이후 2026-10-01 사용자가 `커밋 푸시`로 이번 코드와 문서의 main 반영을 추가 승인했습니다.

## 1. Ideation

- 문제 정의: RDS 관리형 암호를 운영자가 콘솔에서 직접 변경하는 방식으로 전환해야 합니다.
- 사용자: dev DB 관리자와 Terraform 운영자입니다.
- 성공 기준: DB Resource ID, 접속 주소와 `freesia`를 유지하고 관리형 암호를 해제합니다. 새 관리자 Secret과 DB에 같은 초기 암호를 설정하며 Plan, State와 출력에 암호를 저장하지 않습니다.
- Scope: dev 모드 선택, 기존 모듈의 Secret 생성 경로, 결합 검증, 실제 Plan과 Apply, 수동 변경 및 복구 절차입니다.
- Non-goals: DB 재생성, 앱 사용자와 SSM 값 갱신, 앱 배포, 자동 회전, Aurora/MySQL/RR 전환과 사용자 지정 암호 입력 계약입니다. 커밋과 푸시는 후속 요청으로 범위에 추가됐습니다.

## 2. Inception

- Functional Requirements: `env/dev`만 `module_managed_secret`로 바꿉니다. `<identifier>-master` Secret, Version과 기존 ephemeral/write-only 경로를 사용합니다. 출력 `database.master_secret_arn`은 새 Secret을 가리킵니다.
- Non-Functional Requirements: DB 교체와 평문 암호 저장을 금지합니다. 기존 Multi-AZ, 백업과 삭제 보호를 유지하고 Secret 이름 충돌을 확인합니다.
- Architecture: Secret 생성 → `username`, `password` JSON 저장 → 특정 Version의 ephemeral 조회 → 기존 DB 암호 수정 순서입니다. RDS 관리형 해제와 새 암호를 같은 DB 수정 요청으로 전달합니다. AWS는 이전 RDS 관리형 Secret을 삭제합니다.
- Unit of Work: Unit 12 하나로 dev 연결, 검증과 Operation을 처리합니다. 기존 모듈 경로에 문제가 발견되면 같은 범위에서 수정하고 다시 검증합니다.
- Acceptance Criteria: DB는 `update`이며 삭제와 교체가 없습니다. 새 Secret과 Version이 존재하고 DB의 RDS 관리형 Secret 연결이 없어야 합니다. Resource ID와 Writer 주소, State의 암호 비저장을 확인하고 적용 후 DB/Secret에 추가 변경이 없어야 합니다.

## 3. Construction

### Design, Implementation Plan과 Approval

2026-10-01 사용자의 `비관리형으로 바꾸고 적용해줘` 요청으로 아래 계획을 승인했습니다.

1. 현재 AWS 프로필, Backend, DB 메타데이터와 Secret 이름 충돌을 확인합니다.
2. 기존 모드를 선택하고 결합 mock과 Plan 점검에서 관리자 Secret만 허용합니다. 앱 Secret과 ECS 배포 리소스 생성 금지는 유지합니다.
3. fmt, validate, dev mock과 전체 mock Plan 점검을 실행합니다. 모듈 구현을 바꾸면 해당 모듈의 테스트도 실행합니다.
4. 전체 Plan과 DB 대상 지정 Plan에서 기존 `manage_master_user_password = true` 해제, 새 암호 전달과 DB `update`를 확인합니다. 기존 CloudFront Origin 표현 차이를 제외한 저장 Plan만 적용합니다.
5. AWS 메타데이터, State와 적용 후 전체 Plan으로 검증하고 문서 색인과 Runbook을 실제 결과로 갱신합니다. DB 로그인은 별도 접근 경로가 있어야 검증할 수 있습니다.

### 검증 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-10-01 | `git status --short --branch` | `main` 작업 트리 깨끗함 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 sts get-caller-identity` (Account만 조회) | 현재 프로필 계정 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 rds describe-db-instances --db-instance-identifier sbh-platform-dev-rds-postgres` (메타데이터만 저장) | 기존 DB 메타데이터를 Git 제외 파일에 저장, 암호 조회 안 함 |
| 2026-10-01 | `aws --profile sbh-platform --region ap-northeast-2 secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values=sbh-platform-dev-rds-postgres-master` | 이름 충돌과 삭제 대기 Secret 없음 |
| 2026-10-01 | `python3` Backend와 테스트 CLI 경로 확인 | 기존 dev S3 Backend, 서울 Region, State 잠금과 Terraform 1.17 beta 테스트 CLI 확인 |
| 2026-10-01 | `python3` 전환 전 DB 메타데이터 검사 | `available`, 관리형 Secret `active`, 대기 변경 없음. `freesia`, Multi-AZ와 삭제 보호 확인 |
| 2026-10-01 | `terraform fmt -check -recursive env/dev modules/rds/instance` | PASS |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color` | PASS |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-rds-password-tests.jsonl` | 4 PASS, 0 FAIL. 입력 거부 테스트의 오류 진단 2개는 예상된 검증 결과 |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-rds-password-tests.jsonl` | 두 전체 mock Plan PASS. 관리자 Secret/Version, 암호 버전 연결, 값 비저장과 기존 앱 배포 경계 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-rds-password-full.tfplan` | exit 2, 2 add / 2 change / 0 destroy. Secret과 Version 생성, DB 및 기존 CloudFront 수정 |
| 2026-10-01 | `terraform -chdir=env/dev show -json ../../.local/dev-rds-password-full.tfplan` 및 `python3` Plan 검토 | DB는 `update`, 기존 관리형 true 해제 및 새 암호 write-only 버전 예약. Resource ID, 주소와 DB 설정 유지, 암호 및 Secret 본문 비저장 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -target=module.database -input=false -no-color -detailed-exitcode -out=../../.local/dev-rds-password-apply.tfplan` | exit 2, 2 add / 1 change / 0 destroy. 새 관리자 Secret/Version과 기존 DB 수정만 포함 |
| 2026-10-01 | 대상 지정 저장 Plan의 JSON 변환 및 `python3` 최종 검토 | 기존 DB의 Resource ID 및 주소 대조, 삭제와 교체 없음, 평문 암호 없음, CloudFront 제외 확인 |
| 2026-10-01 | `git diff --check` 및 `git check-ignore` | 공백 오류 없음, Plan과 조회 메타데이터 Git 제외 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-rds-password-apply.tfplan` | 초기 전환 완료, 2 added / 1 changed / 0 destroyed. 대상 지정 Apply 경고는 이후 전체 Plan으로 검증 |
| 2026-10-01 | RDS 및 새 Secret 메타데이터 조회, 이전 Secret `describe-secret` | DB available, 관리형 연결 해제, 이전 Secret ResourceNotFoundException. 새 Secret의 RDS 소유 및 자동 회전 없음 |
| 2026-10-01 | 초기 Apply 후 전체 Plan과 State 검토 | Secret Version 번호 반올림으로 반복 교체 계획 발견. Root Secret ARN 출력도 이전 값으로 남아 수정 필요 |
| 2026-10-01 | 수정 후 dev `validate`, 1.17 beta mock 및 전체 mock Plan 점검 | validate PASS, mock 4 PASS, Plan 점검 2 PASS. 52비트 번호의 float 변환 정밀도 확인 |
| 2026-10-01 | `.local/rds-password-module-test`에 수정 모듈과 dev Lock 파일 복사, 기존 Provider 경로로 `init -backend=false -lockfile=readonly`, `validate` | 초기화와 독립 모듈 validate PASS, AWS 6.66.0 및 Random 3.9.1 재사용 |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=.local/rds-password-module-test test -test-directory=tests-terraform-1.17 -no-color -json` | 최종 16 PASS, 0 FAIL. 첫 범위 검증의 unknown condition은 Plan 시점 Version ID mock을 추가해 해결 |
| 2026-10-01 | `terraform fmt -check -recursive env/dev modules/rds/instance` | 정밀도 수정 후 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -target=module.database -input=false -no-color -detailed-exitcode -out=../../.local/dev-rds-password-fixed-apply.tfplan`, JSON 검토 | exit 2, Secret Version만 교체하는 1 add / 1 change / 1 destroy. DB update, Secret 컨테이너 no-op, 값 비저장과 안전한 버전 범위 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-rds-password-fixed-apply.tfplan` | 정밀도 수정 완료, 1 added / 1 changed / 1 destroyed. 교체는 Secret Version뿐이며 DB와 Secret 컨테이너 유지 |
| 2026-10-01 | 최종 RDS/Secret 메타데이터 조회 및 `terraform -chdir=env/dev state pull`, `python3` 검사 | DB available, 관리형 연결과 대기 변경 없음. 기존 Resource ID 및 주소 유지. 새 Version AWSCURRENT, 자동 회전 없음. 두 52비트 번호가 계산값과 정확히 일치하며 암호 본문 비저장. State serial 14, 관리 인스턴스 51개 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -refresh-only -input=false -no-color -detailed-exitcode -out=../../.local/dev-rds-password-final-refresh.tfplan` 및 JSON 검토 | exit 2. AWS 리소스 작업 없음, `database.master_secret_arn` 출력만 새 ARN으로 갱신 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-rds-password-final-refresh.tfplan` | refresh-only 적용 완료, AWS 리소스 변경 없음 |
| 2026-10-01 | 최종 `terraform -chdir=env/dev state pull` 및 `python3` 검사 | serial 15, 관리 인스턴스 51개. 새 Secret ARN 출력 일치, 정확한 버전 번호와 암호 비저장 재확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-rds-password-final.tfplan` 및 JSON 검사 | exit 2, 0 add / 1 change / 0 destroy. RDS, Secret, Version과 database 출력 no-op, 이전 CloudFront Origin 표현 차이만 남음 |
| 2026-10-01 | `python3` 모듈 README 입력/출력 표 점검 | 전체 입력 23개와 출력 9개 누락 없음. 복합 입력 표와 기존 계약 유지 |
| 2026-10-01 | `python3` 변경 파일의 상대 링크 및 앵커, 금지 문자 검사 | 변경 파일 13개, 상대 링크 및 앵커 97개 통과. 검사기의 식별자 underscore 처리 수정 후 확인 |
| 2026-10-01 | `git diff --check`, 최종 `terraform fmt -check -recursive env/dev modules/rds/instance` | PASS |
| 2026-10-01 | `git status --short --branch` | Git 승인 전 이번 코드와 문서의 로컬 변경 13개. 커밋 및 푸시 미수행 |
| 2026-10-01 | 사용자 요청 `커밋 푸시` | 이번 코드와 문서의 main 커밋 및 푸시 승인 |
| 2026-10-01 | `git diff --check`, `python3` 변경 문서 링크 및 앵커와 금지 문자 검사 | 공백 오류와 금지 문자 없음, 변경 파일 13개 및 상대 링크와 앵커 97개 확인 |
| 2026-10-01 | 검토한 13개 파일 `git add`, `git diff --cached --check`, `git diff --cached --name-only`, `git commit -m 'feat: switch dev RDS to unmanaged credentials'` | 코드와 문서 13개만 커밋. 구현 및 검증 커밋 `b995fa7ff251ef52978e1ed4cb7d90be5486bc89` 생성 |
| 2026-10-01 | `git push origin main`, `git ls-remote origin refs/heads/main`, `git rev-parse HEAD`, `git status --short --branch` | 원격 main과 로컬 HEAD SHA가 `b995fa7ff251ef52978e1ed4cb7d90be5486bc89`로 일치, 구현 푸시 직후 작업 트리 변경 없음 |

## 4. Operation

### 적용 후 발견한 문제와 수정 계획

초기 Apply 후 기존 DB `available`, 관리형 Secret 연결 해제와 이전 Secret 삭제, 새 관리자 Secret 생성을 확인했습니다. 이후 전체 Plan에서는 Secret Version의 반복 교체를 발견했습니다. 해시 앞 15자리로 만든 60비트 버전 번호가 Provider/State 경로에서 반올림됐습니다. `dbadmin`의 설정 번호 `907288694771894316`은 State에서 `907288694771894300`이 됐습니다. mock은 실제 State 저장을 실행하지 않아 이 문제를 확인하지 못했습니다.

승인된 기존 모듈 경로 수정 범위 안에서 두 write-only 버전 번호를 해시 앞 13자리의 52비트 정수로 줄입니다. 기존 Secret 컨테이너와 DB는 유지하며 Secret Version만 한 번 교체하고 DB 암호를 새 Version과 맞춥니다. 수정 적용의 Version 교체는 초기 전환의 삭제 0개 기록과 구분합니다. 숫자 범위 검증, 일반 RDS mock 16개와 dev 결합 검증을 실행하고, 실제 Plan과 Apply 후 State에서 정확한 버전 번호 및 반복 변경 해소를 확인합니다.

대상 지정 Apply에서 Root 출력 `database.master_secret_arn`이 이전 ARN으로 남은 점도 확인했습니다. 최종적으로 AWS 리소스를 수정하지 않는 refresh-only Plan을 검토하고 적용해 출력을 새 ARN으로 갱신했습니다.

### 운영과 복구

자동 회전은 추가하지 않습니다. 콘솔에서 Secret 값만 바꿔도 DB 암호는 자동 변경되지 않습니다. RDS와 Secret 값을 함께 수정해야 하며, Terraform이 최초 생성한 특정 Secret Version을 참조하는 제한도 [Runbook](../runbooks/ecs-postgresql-platform.md)에 기록합니다.

전환 실패 시 Secret을 먼저 삭제하지 않습니다. 실제 RDS 관리 상태, 대기 변경과 State를 확인해 새 Secret을 유지한 채 DB 수정을 복구합니다. RDS 관리형으로 되돌릴 때는 별도 Plan에서 DB 수정과 새 RDS 관리형 Secret 발급을 확인하고 모듈 소유 Secret의 제거를 검토합니다. 이전 암호와 Secret ARN이 자동 복원된다고 가정하지 않습니다.

## 근거

- [AWS ModifyDBInstance](https://docs.aws.amazon.com/cli/latest/reference/rds/modify-db-instance.html)
- [AWS RDS 관리자 암호 관리](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [AWS Provider 6.66.0 RDS 구현](https://github.com/hashicorp/terraform-provider-aws/blob/v6.66.0/internal/service/rds/instance.go)
- [Secrets Manager 값 수정](https://docs.aws.amazon.com/secretsmanager/latest/userguide/manage_update-secret-value.html)
- [기존 RDS 모듈 설계](./rds-module.md)

## 최종 Review

기존 RDS Resource ID와 Writer 주소 및 DB 이름을 유지하고 비관리형 전환을 완료했습니다. 현재 DB는 `available`, 관리형 Secret 연결과 대기 변경이 없으며 새 관리자 Secret은 자동 회전 없이 활성 Version을 가집니다. Secret 컨테이너는 정밀도 수정 중에도 유지됐습니다. 두 write-only 버전 번호의 실제 State 정밀도와 출력 ARN을 확인했고, 최종 전체 Plan에서 DB와 Secret 반복 변경이 사라졌습니다. 이전 CloudFront 차이는 적용하지 않았습니다.

비밀번호 본문을 직접 조회해 출력하거나 실제 DB에 로그인한 검증은 수행하지 않았습니다. 동일 초기 암호 전달은 모듈의 특정 Version 참조, DB 수정 Apply와 State의 Version 연결로 확인했습니다. VPC 내부 로그인, 콘솔 수동 변경, 앱 사용자 및 Parameter 값 등록과 앱 배포는 후속 운영 범위입니다. 이번 코드와 문서는 커밋 `b995fa7ff251ef52978e1ed4cb7d90be5486bc89`으로 main에 푸시했고 원격 SHA 일치를 확인했습니다. Backend, State, Plan과 로컬 검증 산출물은 Git 제외 경로에 유지했습니다.
