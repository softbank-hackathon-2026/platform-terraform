# ECR module AI-DLC

마지막 확인일: 2026-09-24

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 2026-09-24 승인 |
| Inception | 2026-09-24 요구사항 승인 |
| Construction | Unit 1 승인·구현·Test·Review 완료 |
| 구현과 테스트 | 완료, 포맷·구성 검증 통과, mock 테스트 6개 통과 |
| Terraform Plan과 Apply | mock provider Plan 테스트만 수행, 실제 AWS Plan·Apply 미수행 |
| 배포와 Operation | 미수행 |
| 커밋과 푸시 | 구현·테스트·README·AI-DLC·문서 규칙 커밋 `3f6dbdd` 원격 main 확인 |

## 1. Ideation

### 문제 정의

환경별 서비스의 컨테이너 이미지를 저장할 비공개 ECR 저장소가 필요합니다. 현재 저장소에는 ECR을 재사용 가능한 방식으로 만드는 모듈이 없습니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 이미지 저장소를 구성하는 Terraform 작성자
- 이미지 태그, 암호화, 스캔, 보존 정책을 관리하는 운영자

### 성공 기준

- 모듈 호출당 비공개 ECR 저장소 하나를 만들 수 있습니다.
- 저장소 이름, ARN, 이미지 주소를 다른 구성이나 배포 작업에서 사용할 수 있습니다.
- 기본 구성에서 태그 재사용을 막고, 저장소 단위의 push 시 기본 이미지 스캔을 요청합니다.
- 선택적으로 기존 KMS 키와 이미지 보존 정책을 적용할 수 있습니다.

### Scope

- 비공개 ECR 저장소 하나와 태그
- 기본 태그 불변성, AES256 암호화, 저장소 수준의 push 시 기본 이미지 스캔
- 선택적 KMS 암호화와 이미지 보존 정책
- 저장소 이름, ARN, 이미지 주소 출력

### Non-goals

- Public ECR, 이미지 빌드·업로드
- IAM 권한 정책, 저장소 정책, 복제
- 레지스트리 수준의 스캔 설정과 향상된 스캔
- 실제 AWS 배포

2026-09-24 사용자가 위 Ideation 범위를 승인했습니다.

## 2. Inception — 승인 완료

### Functional Requirements

- 필수 입력 `name`으로 비공개 ECR 저장소 하나를 생성합니다. 빈 이름은 거부하고, AWS의 세부 이름 규칙과 계정·Region 내 중복 여부는 AWS가 최종 확인합니다.
- 선택적 `tags`를 저장소에 적용합니다.
- `image_tag_mutability`의 기본값은 `IMMUTABLE`입니다. 필요한 경우 `MUTABLE`을 명시할 수 있으며, 제외 패턴 모드는 이번 범위에 포함하지 않습니다.
- `kms_key_arn`이 없으면 AES256 암호화를 사용합니다. 지정하면 기존 고객 관리 KMS 키로 KMS 암호화를 구성합니다. 모듈은 키를 만들지 않습니다.
- `scan_on_push`의 기본값은 `true`입니다. 이 값은 저장소의 기본 이미지 스캔 설정에 적용되며, 레지스트리 수준의 스캔 설정이 실제 스캔 주기와 범위를 결정할 수 있습니다.
- `lifecycle_policy_json`의 기본값은 `null`이고, 지정했을 때만 해당 JSON 문서를 ECR Lifecycle Policy로 연결합니다. JSON 문법을 검증하며 정책의 규칙과 이미지 삭제 대상은 적용 전에 운영자가 ECR Preview로 확인합니다.
- 저장소 이름, ARN, `repository_url`을 출력합니다.

### Non-Functional Requirements

- `force_delete = false`를 유지해 이미지가 든 저장소의 강제 삭제를 막습니다.
- 기본 구성에는 이미지를 만료시키는 Lifecycle Policy를 만들지 않습니다.
- Terraform과 AWS Provider 버전 조건은 기존 모듈과 호환되게 설정합니다.
- 잘못된 열거값, 빈 KMS 키 ARN, 잘못된 JSON 문서는 가능한 한 Plan 전에 거부합니다.
- AWS 자격 증명 없이 mock provider로 기본 구성과 선택 구성을 검증할 수 있어야 합니다. 이 검증을 실제 AWS 스캔 실행 또는 이미지 삭제 검증으로 해석하지 않습니다.

### Architecture

```text
Root Module
  name, tags, image_tag_mutability, kms_key_arn,
  scan_on_push, lifecycle_policy_json
        |
        v
  modules/ecr
    aws_ecr_repository
    aws_ecr_lifecycle_policy (JSON 지정 시)
        |
        v
  repository name, ARN, repository_url

AWS private registry scanning configuration (모듈 외부)
  → 해당 저장소의 실제 스캔 유형·주기에 영향
```

### Unit of Work

1. 비공개 ECR 저장소, 선택적 Lifecycle Policy, 사용법 및 mock Plan 검증

### Acceptance Criteria

- 기본 mock Plan에 ECR 저장소 하나가 포함되고, 태그 불변성·AES256·`scan_on_push = true`·`force_delete = false`가 설정됩니다. Lifecycle Policy는 생성되지 않습니다.
- 선택 입력을 주면 기존 KMS 키 ARN과 태그, `MUTABLE` 설정, Lifecycle Policy JSON이 해당 리소스에 반영됩니다.
- 빈 이름, 허용하지 않는 태그 변경 모드, 빈 KMS 키 ARN, 잘못된 JSON을 거부합니다.
- 저장소 이름, ARN, URL 출력이 정의됩니다.
- README에 저장소 수준과 레지스트리 수준 스캔 설정의 관계, 이미지가 있는 저장소 삭제 제한, 보존 정책의 삭제 효과와 AWS Preview 필요성을 설명합니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행하고 날짜·명령·결과를 기록합니다. 실제 AWS Plan·Apply는 별도 상태로 유지합니다.

2026-09-24 사용자가 이 Inception 요구사항과 작업 단위를 승인했습니다.

### 문서 점검 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git diff --check` | PASS, 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/ai-dlc/ecr-module.md docs/README.md` | 일치 항목 없음, 두 문서에 줄 끝 공백 없음 |

## 3. Construction

### Unit 1: 비공개 ECR 저장소와 선택적 Lifecycle Policy

#### Design

| 결정 | 내용 |
|---|---|
| 리소스 경계 | 모듈 호출당 `aws_ecr_repository` 한 개를 소유합니다. Public Registry나 계정 전체 Registry 설정은 관리하지 않습니다. |
| 태그 변경 | `image_tag_mutability`는 `IMMUTABLE` 기본값과 명시적 `MUTABLE`만 허용합니다. 기존 태그 재사용이 필요한 배포 흐름은 호출자가 `MUTABLE`을 선택합니다. |
| 암호화 | `encryption_configuration`을 항상 설정합니다. `kms_key_arn = null`이면 `AES256`, 지정하면 `KMS`와 기존 키 ARN을 사용합니다. 키 생성·권한 부여는 모듈 밖에서 처리합니다. ECR은 생성 후 암호화 설정을 바꾸지 못하므로 키 선택을 최초 생성 전에 확정합니다. |
| 이미지 스캔 | `image_scanning_configuration.scan_on_push`에 입력값을 전달하고 기본값은 `true`입니다. 실제 스캔 방식은 Registry 설정과 필터에도 좌우되므로 이 모듈 출력이나 mock 테스트로 스캔 완료를 보장하지 않습니다. |
| 보존 정책 | `lifecycle_policy_json`이 `null`이면 정책 리소스가 없고, 값이 있으면 `aws_ecr_lifecycle_policy` 한 개를 저장소 이름에 연결합니다. JSON 문법만 모듈에서 검사하며 AWS 규칙의 유효성과 영향받을 이미지는 AWS에서 확인합니다. |
| 삭제 | `force_delete = false`를 고정합니다. 이미지가 남은 저장소 삭제는 실패하며, 보존 정책이 있다면 그 규칙에 따라 이미지가 자동 만료·보관될 수 있습니다. |
| 태그와 출력 | 입력 `tags`를 저장소에 적용하고 이름, ARN, `repository_url`을 출력합니다. |
| 버전 | 기존 모듈과 동일하게 Terraform `>= 1.5.0`, AWS Provider `>= 6.24`를 요구합니다. |

저장소 수준 `scan_on_push` 설정은 [AWS가 권장하는 레지스트리 수준 설정](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)과 별개입니다. 이 Unit은 승인된 저장소 모듈 범위에 맞춰 저장소 설정만 관리하고, 실제 계정의 Registry 설정을 배포 전 점검 항목으로 남깁니다. 보존 정책은 이미지 만료가 시작될 수 있으므로 기본으로 만들지 않고, 운영자가 AWS의 Lifecycle Policy Preview로 대상 이미지를 확인한 뒤 적용합니다.

#### Implementation Plan

1. `modules/ecr/versions.tf`, `main.tf`, `variables.tf`, `outputs.tf`를 작성합니다. 저장소의 암호화·태그 변경·스캔·삭제 기본값을 명시하고, JSON 지정 여부로 Lifecycle Policy 리소스를 조건부 생성합니다.
2. 변수 검증으로 빈 이름, 허용하지 않는 태그 변경 모드, 빈 KMS 키 ARN, JSON 문법 오류를 거부합니다. AWS 이름 규칙과 정책 내용의 최종 검증은 AWS에 맡깁니다.
3. `modules/ecr/README.md`에 기본 호출, KMS와 보존 정책 예시, 출력값, Registry 스캔 설정의 영향, 태그 재사용·암호화 설정 변경 시 저장소 교체 가능성·저장소 삭제·이미지 만료 주의 사항을 작성합니다.
4. `modules/ecr/tests/ecr.tftest.hcl`의 mock provider Plan으로 기본 설정, KMS·태그·`MUTABLE`·선택 정책, `scan_on_push = false`, 잘못된 입력을 확인합니다. mock 결과는 이미지 push, 취약점 스캔, 정책의 실제 이미지 만료를 증명하지 않습니다.
5. Terraform 포맷, `terraform validate`, `terraform test`를 실제 실행하고 날짜·명령·결과를 기록합니다. 공급자 설치가 불가능하면 그 제약과 수행한 범위만 기록합니다.
6. 코드와 문서의 일치 여부를 Review하고 `docs/README.md` 상태를 갱신합니다. 실제 AWS Plan·Apply와 배포는 수행 여부를 별도로 기록합니다.

#### Approval

2026-09-24 사용자가 Unit 1 Design과 Implementation Plan을 승인했습니다.

#### Implementation

- [`main.tf`](../../modules/ecr/main.tf): 저장소의 태그 변경·암호화·스캔·삭제 정책과 선택적 Lifecycle Policy
- [`variables.tf`](../../modules/ecr/variables.tf): 이름, KMS 키, 스캔, 정책 JSON, 태그 입력과 검증
- [`outputs.tf`](../../modules/ecr/outputs.tf): 저장소 이름, ARN, URL
- [`versions.tf`](../../modules/ecr/versions.tf): Terraform과 AWS Provider 버전 조건
- [`README.md`](../../modules/ecr/README.md): 기본 사용법, 선택 설정, Registry 스캔과 삭제·암호화 제한
- [`ecr.tftest.hcl`](../../modules/ecr/tests/ecr.tftest.hcl): 기본값, 선택 설정, 출력, 입력 오류 mock Plan 테스트

#### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform fmt -recursive modules/ecr` | PASS, 테스트 파일 포맷 적용 |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform init -backend=false -input=false -no-color -plugin-dir=/tmp/terraform-plugin-cache` (임시 모듈 복사본) | PASS, 로컬 AWS Provider v6.66.0 설치 |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform validate -no-color` (임시 복사본, 최초 샌드박스 실행) | 실패, Provider 프로세스의 로컬 플러그인 통신을 시작하지 못함 |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform validate -no-color` (임시 복사본, 승인된 실행 권한) | PASS, configuration is valid |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform test -no-color` (임시 복사본, 최초 실행) | 5 pass, 1 fail. mock Provider가 AES256 구성의 미지정 `kms_key`에 임의 값을 채워 기본값 단언 실패 |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform test -no-color` (수정한 테스트를 복사한 임시 복사본) | PASS, 6 passed and 0 failed |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform fmt -check -recursive modules/ecr` | PASS |
| 2026-09-24 | `git diff --check` | PASS |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/README.md docs/ai-dlc/ecr-module.md modules/ecr` | 일치 항목 없음, 신규 파일 포함 줄 끝 공백 없음 |

검증 경로는 `/tmp/template-ecr.7aKY5s/ecr`입니다. 기본 AES256 설정에서 `kms_key = null`은 모듈의 설정 값이지만, mock Provider가 선택·계산 필드에 임의 값을 채웁니다. 이 값은 실제 KMS 키가 생성되었다는 뜻이 아니므로 테스트는 암호화 유형을 검사하도록 수정했습니다. `terraform test`는 mock provider의 Plan이며 AWS 호출, 이미지 push, 취약점 스캔, Lifecycle Policy의 실제 이미지 만료·보관을 확인하지 않습니다.

#### Review

- 기본 저장소 하나와 선택적 정책 한 개만 생성되며 `force_delete = false`와 기본 정책 없음이 확인되었습니다.
- AES256과 KMS 전환은 설정으로 분기하며, 선택한 KMS 키 ARN은 Provider 리소스에 전달됩니다. 기존 저장소의 암호화 설정 변경과 키 접근 권한은 실제 AWS에서 검증하지 않았습니다.
- `scan_on_push`는 저장소 설정이며 실제 스캔 빈도와 유형은 Registry 설정의 영향을 받습니다.
- 정책 JSON은 문법만 로컬에서 검증합니다. 규칙 내용과 만료·보관 대상은 AWS의 Lifecycle Policy Preview로 적용 전에 확인해야 합니다.
- 환경별 Root Module이 없어 실제 AWS Plan·Apply, 배포 및 이미지 동작 검증은 수행하지 않았습니다.

### Git 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'feat(ecr): add repository module and document module inputs'` | ECR 구현·테스트, 10개 모듈 README 표, 문서 규칙 커밋 `3f6dbddf79693bdf185071a2aa777e047876b093` 생성 |
| 2026-09-24 | `git push origin main` | 구현 커밋 `3f6dbdd` 푸시 완료 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main이 `3f6dbddf79693bdf185071a2aa777e047876b093`인 것을 확인 |

## 4. Operation

Deployment, Observability, Rollback, Runbook은 시작하지 않았습니다. 환경별 Root Module과 AWS 계정이 준비된 뒤 별도 작업에서 다룹니다.

## 근거

- [Terraform AWS Provider ECR Repository](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ecr_repository.html.markdown)
- [Terraform AWS Provider ECR Lifecycle Policy](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ecr_lifecycle_policy.html.markdown)
- [AWS ECR 이미지 스캔](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html)
- [AWS ECR 레지스트리 스캔 필터](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-filters.html)
- [AWS ECR 저장소 암호화](https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html)
- [AWS ECR Lifecycle Policy](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)
