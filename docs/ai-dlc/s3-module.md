# S3 module AI-DLC

마지막 확인일: 2026-09-23

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 모듈 종류와 작업 순서 승인 |
| Inception | 요구사항 승인 |
| Construction | 구현, Test, Review 완료 |
| 구현과 테스트 | 완료, 포맷과 구성 검증 및 mock 테스트 4개 통과 |
| Terraform Plan과 Apply | mock provider Plan만 수행, 실제 AWS 기준 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋과 푸시 | S3 구현 커밋 `e2cf4ef` 푸시 완료, 원격 main SHA 일치 확인 |
| Operation | 시작하지 않음 |

## 1. Ideation

### 문제 정의

현재 저장소에는 Network와 EC2 모듈만 있습니다. 기존 모듈의 기능을 늘리는 것보다 자주 사용하는 AWS 리소스 종류를 추가할 필요가 있습니다. 첫 작업은 여러 환경에서 재사용할 수 있는 비공개 S3 버킷 모듈입니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 버킷을 구성하는 작성자
- 버킷의 공개 접근과 암호화 상태를 관리하는 운영자

### 성공 기준

- Root Module이 이름과 태그를 전달해 일반 목적 S3 버킷 하나를 생성할 수 있습니다.
- 버킷 수준의 공개 접근 차단 네 가지 설정을 명시적으로 관리합니다.
- 버전 관리와 고객 관리 KMS 키를 선택할 수 있습니다.
- 다른 모듈과 연결할 버킷 이름과 ARN을 출력합니다.

### Scope

- 일반 목적 S3 버킷 하나와 태그
- 버킷 수준의 공개 접근 차단
- 선택적 버전 관리와 SSE-KMS 기본 암호화
- 버킷 이름과 ARN 출력

### Non-goals

- 버킷 정책, ACL, 정적 웹사이트, 객체 업로드
- Lifecycle, Replication, Access Point, 서버 액세스 로그
- KMS 키 생성과 키 정책
- AWS 계정에 실제 버킷 배포

사용자는 2026-09-23에 S3, Security Group, IAM Role과 Policy, ALB, RDS, ECR 순서의 작업 진행을 요청했습니다. 이 요청으로 모듈 선정과 순서를 승인받은 상태로 기록합니다.

## 2. Inception

### Functional Requirements

- 필수 입력 `bucket_name`으로 버킷을 하나 생성합니다. S3 버킷 이름의 전역 중복 여부는 AWS가 확인합니다.
- 선택적 `tags`를 버킷에 적용합니다.
- 공개 ACL과 공개 버킷 정책의 생성 및 사용을 버킷 수준에서 차단합니다.
- `versioning_enabled`의 기본값은 `false`이며 `true`일 때 버전 관리를 활성화합니다.
- `kms_key_arn`이 없으면 AWS의 기본 SSE-S3를 사용합니다. 값이 있으면 해당 키로 SSE-KMS 기본 암호화를 설정합니다.
- 버킷 이름과 ARN을 출력합니다.

### Non-Functional Requirements

- `force_destroy`는 사용하지 않아 객체가 있는 버킷을 실수로 삭제하지 않습니다.
- 기본 구성에서 버킷을 공개하거나 KMS 요청 비용을 발생시키지 않습니다.
- Provider와 Terraform 버전 조건은 기존 모듈과 호환되게 설정합니다.
- 실제 AWS 자격 증명 없이 mock provider 기반 테스트를 실행할 수 있어야 합니다.

### Architecture

```text
Root Module
  bucket_name, tags, versioning_enabled, kms_key_arn
        |
        v
  modules/s3
    aws_s3_bucket
    aws_s3_bucket_public_access_block
    aws_s3_bucket_versioning (선택)
    aws_s3_bucket_server_side_encryption_configuration (KMS 선택 시)
        |
        v
  bucket name, ARN
```

### Unit of Work

1. 비공개 S3 버킷 모듈과 사용법, mock Plan 테스트

### Acceptance Criteria

- 기본 Plan에 버킷 하나와 공개 접근 차단 설정이 포함됩니다.
- 기본 Plan에는 버전 관리 리소스와 KMS 암호화 설정 리소스가 없습니다.
- 선택 입력을 주면 버전 관리와 지정한 KMS 키를 사용하는 설정이 포함됩니다.
- 버킷 이름과 ARN 출력이 정의됩니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행해 결과를 기록합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| 버킷 종류 | 일반 목적 S3 버킷 한 개 |
| 공개 접근 | 버킷 수준 Block Public Access 네 항목을 모두 `true`로 고정 |
| 기본 암호화 | AWS의 기본 SSE-S3 사용 |
| 선택적 암호화 | KMS 키 ARN을 입력받으면 SSE-KMS 설정, S3 Bucket Key 사용 |
| 버전 관리 | 기본 미사용, 명시적으로 요청할 때 활성화 |
| 삭제 | `force_destroy = false` |
| IAM과 정책 | 버킷 밖의 Root Module이 소유 |

버전 관리를 활성화한 뒤 다시 끄면 S3는 미사용 상태로 되돌리지 않고 버전 관리를 중지합니다. 이 동작을 모듈 README에 명시합니다.

### Implementation Plan

1. `modules/s3`에 버킷, 공개 접근 차단, 선택적 버전 관리와 KMS 암호화 설정을 작성합니다.
2. 필수 입력과 선택 입력, 버킷 출력값을 정의합니다.
3. README에 기본 사용법, KMS와 버전 관리 사용법, 삭제 및 비용 주의 사항을 작성합니다.
4. mock provider 테스트에서 기본 구성과 선택적 구성의 리소스 및 속성을 확인합니다.
5. 포맷, `terraform validate`, `terraform test`를 실행하고 날짜와 결과를 이 문서에 기록합니다.
6. 코드와 테스트 결과를 검토하고 `docs/README.md`의 상태를 갱신합니다.

### Approval

2026-09-23 사용자가 S3 구현 계획을 승인했습니다.

### Implementation

- [`main.tf`](../../modules/s3/main.tf): 버킷, 공개 접근 차단, 선택적 버전 관리와 SSE-KMS
- [`variables.tf`](../../modules/s3/variables.tf): 입력과 빈 값 검증
- [`outputs.tf`](../../modules/s3/outputs.tf): 버킷 이름과 ARN
- [`versions.tf`](../../modules/s3/versions.tf): Terraform과 AWS Provider 버전 조건
- [`README.md`](../../modules/s3/README.md): 사용법과 제한 사항
- [`s3.tftest.hcl`](../../modules/s3/tests/s3.tftest.hcl): mock provider Plan 테스트

### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `terraform fmt -recursive modules/s3` | PASS, 변경 필요 없음 |
| 2026-09-23 | `terraform fmt -check -recursive modules` | PASS |
| 2026-09-23 | 임시 복사본에서 `terraform init -backend=false -input=false -no-color -plugin-dir=/Users/hwjeong/Workspace/01.Project/ws-haiops/src/prod/.terraform/providers` | PASS, 로컬 AWS Provider v6.56.0 사용 |
| 2026-09-23 | 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | 임시 복사본에서 `terraform test -no-color` | PASS, 4 passed and 0 failed |

검증은 `/private/tmp/template-s3.GBE7wY/s3`의 복사본에서 실행했습니다. 온라인 `terraform init`은 네트워크 DNS 제한으로 실패했고, Provider의 로컬 소켓 생성은 샌드박스에서 차단되어 `validate`와 `test`를 승인된 권한으로 재실행했습니다. 첫 테스트에서는 Provider가 암호화 규칙을 집합으로 반환하는데 인덱스로 참조하여 1개가 실패했고, 집합 접근 방식을 고친 후 4개 모두 통과했습니다.

mock provider 테스트는 실제 AWS 계정의 Plan, Apply, 버킷 생성 결과를 증명하지 않습니다.

### Git 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `git push origin main` | S3 구현 커밋 `e2cf4ef` 푸시 완료 |
| 2026-09-23 | `git ls-remote origin refs/heads/main` | 원격 main이 `e2cf4ef9397fdbd6078b3cd8a7ad30765ff765e9`인 것을 확인 |

### Review

- 기본 SSE-S3는 AWS가 제공하며, 기본 구성에서 Terraform 암호화 설정 리소스는 만들지 않습니다.
- KMS 키는 외부 입력입니다. 실제 키의 존재, Region, 사용 권한은 mock 테스트로 검증되지 않았습니다.
- 버전 관리 활성화 후 비활성화 요청은 기존 객체 버전을 제거하지 않습니다.
- 객체가 있는 버킷은 `force_destroy = false` 때문에 Terraform으로 삭제되지 않습니다.
- 환경별 Root Module이 없으므로 실제 AWS Plan과 Apply는 수행하지 않았습니다.

## 4. Operation

Deployment, Observability, Rollback, Runbook은 아직 시작하지 않았습니다. Root Module과 AWS 계정 연결 후 별도 작업에서 다룹니다.

## 근거

- [AWS S3 기본 암호화](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html)
- [AWS S3 버킷 공개 접근 차단](https://docs.aws.amazon.com/AmazonS3/latest/userguide/configuring-block-public-access-bucket.html)
- [Terraform AWS Provider S3 버전 관리](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/s3_bucket_versioning.html.markdown)
