# KMS module AI-DLC

마지막 확인일: 2026-09-24

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 2026-09-24 승인 |
| Inception | 2026-09-24 관리자·사용자 입력과 정책 모드 수정안 승인 |
| Construction | Unit 1 Design·Implementation Plan 승인, 구현·Test·Review 완료 |
| 로컬 검증 | 포맷·구성 검증 통과, mock Plan 테스트 10개 통과 |
| Terraform Plan과 Apply | mock provider Plan 테스트만 수행, 실제 AWS Plan·Apply 미수행 |
| 배포와 Operation | 미수행 |
| 커밋과 푸시 | 구현 커밋 `2b1f850` 원격 main 확인 |

## 1. Ideation — 승인 완료

### 문제 정의

S3, ECR, RDS 모듈은 기존 고객 관리형 KMS 키를 입력받지만, 이 저장소에는 키를 생성하는 재사용 모듈이 없습니다.

### 사용자

- 환경에서 서비스별 암호화 키를 구성하는 Terraform 작성자
- 키 정책, 회전, 삭제를 관리하는 운영자

### 성공 기준

- 고객 관리형 대칭 암호화 키를 생성하고 선택적으로 별칭을 붙일 수 있습니다.
- 출력한 키 ARN을 기존 S3, ECR, RDS 모듈의 KMS 입력에 전달할 수 있습니다.
- 키 접근과 회전·삭제 설정을 문서화하고 로컬에서 검증할 수 있습니다.

### Scope

- 고객 관리형 대칭 KMS 키 하나와 선택적 별칭
- 키 정책, 회전 설정, 삭제 대기 기간
- 입력·출력 속성 표, 연결 예시, 로컬 검증

### Non-goals

- 비대칭 키, HMAC 키, 외부 키 저장소, 다중 Region 복제
- 환경별 Root Module 또는 실제 AWS 배포

2026-09-24 사용자가 위 Ideation 범위를 승인했습니다. KMS 다음에는 루트 `tests/` 디렉터리의 용도와 삭제 가능 여부를 조사하고, 이어서 EKS, ECS, Lambda 모듈을 진행합니다.

## 2. Inception — 수정안 승인 완료

### Functional Requirements

- 모듈 호출당 `aws_kms_key` 하나를 만듭니다. 키는 단일 Region, `SYMMETRIC_DEFAULT`, `ENCRYPT_DECRYPT`, AWS 생성 키 재료를 사용합니다.
- 선택적 `alias_name`을 지정하면 `aws_kms_alias` 하나를 만듭니다. 값은 `alias/`로 시작해야 하고 예약된 `alias/aws/`는 거부합니다. 생략하면 별칭을 만들지 않습니다.
- 선택적 `description`과 `tags`를 키에 적용합니다.
- `kms_admin_arns`와 `key_user_arns`에 관리자 및 키 사용자 IAM Role/User ARN 집합을 각각 지정할 수 있습니다. 기본값은 빈 집합입니다. IAM Group은 키 정책의 Principal로 사용할 수 없습니다.
- `policy_json`이 없으면 계정의 IAM 권한 위임 문장을 기본으로 만들고, 지정한 관리자와 사용자에게 별도의 키 정책 문장을 추가합니다. 관리자는 키 관리 작업, 사용자는 암호화 작업과 AWS 서비스 연동에 필요한 조건부 Grant 작업을 허용합니다.
- `policy_json`을 지정하면 호출자가 제공한 JSON이 키 정책 전체를 대체합니다. 이 경우 관리자·사용자 ARN 입력은 허용하지 않습니다. 사용자 정책에서 관리 권한과 키 사용 권한을 직접 작성합니다. 모듈은 서비스별 사용 주체를 추측해 정책에 추가하지 않습니다.
- 자동 키 재료 회전은 기본 활성화하며, 회전 주기는 기본 365일입니다. `enable_key_rotation`과 `rotation_period_in_days`로 변경할 수 있습니다.
- 삭제 대기 기간은 기본 30일이며 `deletion_window_in_days`로 7~30일 내에서 변경할 수 있습니다.
- 키 ID, 키 ARN, 별칭 이름, 별칭 ARN을 출력합니다. 별칭을 만들지 않으면 별칭 출력은 `null`입니다.

### Non-Functional Requirements

- `bypass_policy_lockout_safety_check`는 활성화하지 않습니다. 사용자 정책은 유효한 JSON인지 검사하며 실제 권한 효과와 관리 주체의 잔존 여부는 AWS 검증 및 운영자 Review 대상입니다.
- 기본 생성 정책의 계정 권한 위임 문장은 IAM 정책으로 KMS 권한을 부여할 수 있게 합니다. 따라서 관리자·사용자 ARN 목록은 유일한 허용 목록이 아니며, 계정의 다른 IAM 정책도 키 접근을 허용할 수 있음을 README에 설명합니다. 키 ARN을 다른 모듈에 전달하는 것만으로 해당 서비스에 키 사용 권한이 생기지는 않습니다.
- 관리자에게는 암호화 작업을 직접 허용하지 않습니다. 다만 관리자는 정책 변경이나 Grant 생성으로 자기 권한을 바꿀 수 있으므로 보안 경계로 오해하지 않도록 설명합니다.
- AWS 서비스가 사용자 대신 키를 사용하기 위한 Grant 권한은 `kms:GrantIsForAWSResource` 조건을 적용합니다. 서비스별 추가 권한과 교차 계정 IAM 권한은 호출자가 확인합니다.
- 별칭 형식, 회전 주기 90~2560일, 삭제 대기 기간 7~30일, 잘못된 JSON, 빈 주체 ARN, 사용자 정책과 관리자·사용자 ARN의 동시 입력을 가능한 한 Plan 전에 거부합니다.
- 키 삭제를 예약하면 대기 기간 동안 암호화 작업에 사용할 수 없고, 기간 종료 후 키 재료가 삭제됩니다. README에 사용 중인 데이터와 서비스 영향을 설명합니다.
- 기존 모듈과 호환되는 Terraform 및 AWS Provider 버전 조건을 사용합니다.
- AWS 자격 증명 없이 mock provider로 기본·선택 구성과 입력 오류를 검증합니다. mock 결과를 실제 AWS 권한·키 사용·회전·삭제 검증으로 해석하지 않습니다.

### Architecture

```text
Root Module
  description, tags, alias_name,
  kms_admin_arns, key_user_arns 또는 policy_json,
  enable_key_rotation, rotation_period_in_days,
  deletion_window_in_days
         |
         v
  modules/kms
    aws_caller_identity, aws_partition (기본 생성 정책)
    aws_kms_key
    aws_kms_alias (alias_name 지정 시)
         |
         +-- key_arn -> S3/ECR kms_key_arn
         +-- key_arn -> RDS/Aurora kms_key_id 또는 secret_kms_key_id
```

### Unit of Work

1. 고객 관리형 대칭 키, 선택적 별칭, README와 mock Plan 검증

### Acceptance Criteria

- 기본 mock Plan에 대칭 KMS 키 하나와 계정 권한 위임 정책이 포함되고 별칭은 없으며, 자동 회전 365일과 삭제 대기 30일이 설정됩니다.
- 관리자·사용자 ARN을 지정하면 생성 정책에 각각 관리 작업, 암호화 작업과 조건부 Grant 작업이 포함됩니다. 관리자 문장에는 직접 암호화 작업이 없습니다.
- 사용자 정책 JSON을 지정하면 생성 정책을 대체하고, 별칭·설명·태그·회전·삭제 설정도 선택값에 맞게 반영됩니다.
- 잘못된 별칭, JSON 정책, 회전 주기, 삭제 대기 기간, 빈 주체 ARN, 사용자 정책과 관리자·사용자 ARN의 동시 입력을 거부합니다.
- 별칭 유무에 따른 키·별칭 출력이 정의되고, README에는 모든 입력·출력 속성 표와 기존 S3/ECR/RDS 모듈 연결 예시가 있습니다.
- README는 생성 정책의 IAM 위임과 ARN 목록의 비독점성, 관리자와 사용자의 권한 차이, 직접 지정한 전체 정책의 잠금 위험, 키 삭제의 데이터 영향 및 실제 서비스별 권한 설정 책임을 설명합니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행하고 날짜·명령·결과를 기록합니다. 실제 AWS Plan·Apply는 별도 상태로 유지합니다.

2026-09-24 사용자가 최초 Inception 요구사항과 Unit 1을 승인했습니다. 이후 관리자 입력명을 `kms_admin_arns`로 정정하고, 관리자·사용자 지정 방식과 정책 선택 규칙을 추가한 수정안을 승인했습니다.

## 3. Construction

### Unit 1: 고객 관리형 대칭 키와 선택적 별칭

#### Design — 승인 완료

| 결정 | 내용 |
|---|---|
| 모듈 경계 | `modules/kms` 호출당 `aws_kms_key` 하나를 소유하고, `alias_name`이 있을 때만 `aws_kms_alias` 하나를 만듭니다. 기존 S3/ECR/RDS 모듈은 변경하지 않습니다. |
| 키 유형 | `SYMMETRIC_DEFAULT`, `ENCRYPT_DECRYPT`, 단일 Region, AWS 생성 키 재료로 고정합니다. |
| 정책 | `policy_json = null`이면 `aws_caller_identity`와 `aws_partition`으로 계정 주체 ARN을 구성해 IAM 위임 문장을 만들고, 비어 있지 않은 관리자·사용자 집합에 한해 해당 문장을 추가합니다. `policy_json`을 지정하면 그 문서만 적용하고 관리자·사용자 입력은 거부합니다. 잠금 방지 검사는 우회하지 않습니다. |
| 관리자와 사용자 | 관리자 문장은 AWS KMS의 관리 작업 예시를 따르되 직접 `Encrypt`·`Decrypt`·`GenerateDataKey`를 허용하지 않습니다. 사용자 문장은 해당 암호화 작업과 `DescribeKey`, AWS 서비스용 조건부 Grant 작업을 허용합니다. |
| 별칭 | 입력은 Terraform/API 형식의 전체 이름 `alias/<name>`입니다. 빈 접미사와 예약된 `alias/aws/`를 거부하고, 없으면 별칭 리소스는 만들지 않으며 별칭 출력값은 `null`입니다. |
| 회전 | `enable_key_rotation = true`, `rotation_period_in_days = 365`가 기본입니다. 회전을 끄면 Provider의 회전 주기 인수는 `null`로 두고, 다시 켜면 지정한 주기를 적용합니다. |
| 삭제 | `deletion_window_in_days = 30`을 기본으로 하고 7~30일만 허용합니다. `terraform destroy`가 키 삭제를 예약할 수 있으므로 README에 서비스 영향과 삭제 취소 절차를 설명합니다. |
| 출력 | `key_id`, `key_arn`, `alias_name`, `alias_arn`을 내보냅니다. 별칭이 없을 때 두 별칭 출력은 `null`입니다. |
| 버전 | 기존 모듈과 같이 Terraform `>= 1.5.0`, AWS Provider `>= 6.24`를 요구합니다. |

#### Implementation Plan — 승인 완료

1. `modules/kms/versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`에 키·조건부 별칭, 기본값, 출력과 입력 검증을 정의합니다.
2. `alias_name`의 형식과 예약 접두사, 정책 JSON 문법, 관리자·사용자 ARN, 정책 입력 모드의 상호 배제, 회전 주기와 삭제 대기 기간을 검사합니다. AWS 계정·Region 내 별칭 중복과 정책의 실제 의미는 AWS가 최종 검증합니다.
3. `modules/kms/README.md`에 기본·관리자/사용자·사용자 정책·별칭 예시, 모든 입력·출력 속성 표, S3/ECR/RDS 연결 예시, IAM 및 키 정책 책임, 키 삭제·회전 영향과 삭제 취소 절차를 기록합니다.
4. `modules/kms/tests/kms.tftest.hcl`에서 mock Plan으로 기본값, 관리자/사용자 정책, 전체 사용자 정책, 별칭 유무와 출력, 잘못된 입력을 확인합니다. mock 테스트는 실제 서비스의 암호화 성공이나 IAM 권한을 증명하지 않습니다.
5. Terraform 포맷·`terraform validate`·`terraform test`를 실제 실행하고 날짜·명령·결과를 기록합니다. 실행하지 못한 검증은 PASS로 표시하지 않습니다.
6. 구현과 README 속성 표를 대조하고 Review한 뒤 `docs/README.md`의 상태를 갱신합니다. AWS Plan·Apply, 배포, 커밋, 푸시는 각각 실제 수행 여부로 기록합니다.

#### Approval

2026-09-24 사용자가 `kms_admin_arns` 명칭을 지정하고 수정된 Unit 1 설계와 구현 계획을 승인했습니다.

#### Implementation

- [main.tf](../../modules/kms/main.tf): 계정 IAM 위임 정책, 관리자·사용자 정책 문장, 전체 정책 교체, 대칭 키와 선택적 별칭
- [variables.tf](../../modules/kms/variables.tf): `kms_admin_arns` 등 입력과 형식·범위·정책 모드 검증
- [outputs.tf](../../modules/kms/outputs.tf): 키 ID·ARN과 선택적 별칭 이름·ARN
- [README.md](../../modules/kms/README.md): 입력·출력 속성 표, 정책 모드와 기존 모듈 연결, 회전·삭제 영향
- [kms.tftest.hcl](../../modules/kms/tests/kms.tftest.hcl): 기본·관리자·사용자·전체 정책과 잘못된 입력의 mock Plan 테스트

#### Test

검증은 `/tmp/template-kms.Ii1FLq/kms`에 모듈을 복사하고 로컬 AWS Provider 6.66.0으로 실행했습니다. Terraform 실행 파일은 `/tmp/terraform-1.13.3/terraform`입니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `terraform fmt -recursive modules/kms` | 테스트 파일 포맷 수정 |
| 2026-09-24 | `terraform init -backend=false -plugin-dir=/tmp/terraform-plugin-cache -no-color` (임시 복사본) | Provider 6.66.0 설치, 초기화 성공. 로컬 설치로 인한 플랫폼별 체크섬 경고 |
| 2026-09-24 | `terraform validate -no-color` 및 `terraform test -no-color` (임시 복사본, 제한된 실행 환경) | Provider 프로세스 시작 실패, 구성·테스트 결과로 판정하지 않음 |
| 2026-09-24 | `terraform validate -no-color` (실행 권한을 높인 임시 복사본, 최초) | 조건부 목록 타입 불일치 발견. 관리자·사용자 정책 문장 목록 구성 수정 |
| 2026-09-24 | `terraform validate -no-color` (실행 권한을 높인 임시 복사본, 재실행) | PASS |
| 2026-09-24 | `terraform test -no-color` (실행 권한을 높인 임시 복사본, 최초) | 2 pass, 1 fail, 7 skip. mock Plan에서 키 ID가 미확정이라 별칭 연결 단언 실패 |
| 2026-09-24 | `terraform test -no-color` (실행 권한을 높인 임시 복사본, 수정 후 재실행) | 10 pass, 0 fail |
| 2026-09-24 | `terraform fmt -check -recursive modules/kms` | PASS |
| 2026-09-24 | `python3` 인라인 점검: `variables.tf`·`outputs.tf`와 README 속성 표 대조 | 입력 9개·출력 4개 모두 일치 |
| 2026-09-24 | `git diff --check` | 추적 중인 변경에 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' modules/kms docs/ai-dlc/kms-module.md docs/README.md` | 일치 항목 없음 |

mock Plan은 Terraform 구성과 정책 JSON 형태만 확인합니다. 실제 AWS 권한, 서비스별 키 사용, 키 재료 회전, 삭제 예약 및 데이터 복호화는 검증하지 않았습니다.

#### Review

- 관리자 입력명은 요청대로 `kms_admin_arns`이며, 별도 사용자 입력은 `key_user_arns`입니다. 정책 JSON을 지정하면 두 ARN 집합은 비워야 합니다.
- 생성 정책의 관리자 문장에는 직접 암호화 작업이 없고, 사용자 Grant 문장에는 `kms:GrantIsForAWSResource` 조건이 있습니다. 계정 IAM 위임 문장 때문에 ARN 집합만으로 접근이 제한되는 것은 아님을 README에 명시했습니다.
- README 입력 9개·출력 4개가 코드와 일치합니다. 키 ARN은 기존 S3/ECR/RDS 입력에 연결할 수 있습니다.
- 실제 AWS Plan·Apply와 배포는 하지 않았으며, 교차 계정과 서비스별 최종 권한은 배포 시 검증이 필요합니다.

### 문서 점검 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git diff --check` | 추적 중인 `docs/README.md` 변경에 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/ai-dlc/kms-module.md docs/README.md` | 일치 항목 없음 |

### 커밋과 푸시 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'feat(kms): add customer managed key module and tests'` | 구현·테스트·README·AI-DLC 커밋 `2b1f85040e1de8bb9d94f935f4c2108a764dfa18` 생성 |
| 2026-09-24 | `git push origin main` | 구현 커밋 푸시 완료 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main의 SHA가 `2b1f85040e1de8bb9d94f935f4c2108a764dfa18`임을 확인 |

## 4. Operation

Deployment, Observability, Rollback, Runbook은 시작하지 않았습니다. 실제 AWS 키를 배포하기 전 키 관리자·사용자, 서비스별 권한, 삭제 예약과 복구 절차를 확인해야 합니다.

### 참고 자료

- [AWS KMS 기본 키 정책](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html)
- [AWS KMS 키 정책과 권한](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
- [AWS KMS 키 회전](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)
- [AWS KMS 키 삭제](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html)
- [AWS KMS 별칭 생성](https://docs.aws.amazon.com/kms/latest/developerguide/alias-create.html)
- [Terraform AWS Provider `aws_kms_key`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key)
- [Terraform AWS Provider `aws_kms_alias`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias)
