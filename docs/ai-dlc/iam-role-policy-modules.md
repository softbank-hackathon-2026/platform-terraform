# IAM Role and Policy modules AI-DLC

마지막 확인일: 2026-09-24

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 모듈 종류와 작업 순서 승인 |
| Inception | 요구사항 승인 |
| Construction | 두 Unit의 구현, Test, Review 완료. 결합 테스트 Root Provider 선언 보강 |
| 구현과 테스트 | 두 모듈과 결합 구성의 mock 테스트 9개 통과. 2026-09-24 결합 테스트 1개 재검증 통과 |
| Terraform Plan과 Apply | mock provider Plan만 수행, 실제 AWS 기준 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋과 푸시 | 기존 구현 `2190a91`, 결합 테스트 보강 `df31fab` 원격 main 확인 |
| Operation | 시작하지 않음 |

## 1. Ideation

### 문제 정의

EC2 모듈은 기존 IAM Instance Profile 이름을 입력받지만, 이 저장소에는 Role, Policy, Instance Profile을 생성하는 모듈이 없습니다. 정책을 독립적으로 만들고 여러 Role에 재사용할 수 있어야 하며, Role은 서비스별 신뢰 정책을 받아 EC2와 다른 서비스에 연결할 수 있어야 합니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 서비스 권한을 구성하는 작성자
- EC2에 Instance Profile을 연결하거나 다른 서비스에 Role ARN을 전달하는 운영자

### 성공 기준

- 고객 관리 IAM Policy를 Role과 독립적으로 생성하고 ARN을 출력합니다.
- 서비스별 신뢰 정책으로 IAM Role을 생성하고 기존 또는 새 관리형 Policy를 연결합니다.
- EC2용으로 선택적 Instance Profile을 만들고, 출력한 이름을 기존 EC2 모듈에 그대로 전달합니다.
- IAM Role ARN을 다른 서비스의 Root Module 구성에 전달할 수 있습니다.

### Scope

- `modules/iam/policy`: 고객 관리 IAM Policy 하나와 태그, 이름 및 ARN 출력
- `modules/iam/role`: IAM Role 하나, 관리형 Policy 연결, 선택적 IAM Instance Profile, 이름 및 ARN 출력
- Root Module에서 두 모듈과 기존 EC2 모듈을 연결하는 사용 예시

`modules/iam`은 분류용 상위 디렉터리입니다. Root Module은 `modules/iam/policy`와 `modules/iam/role`을 각각 독립된 모듈 경로로 참조합니다. 예를 들어 `env/dev`에서는 `source = "../../modules/iam/policy"`와 `source = "../../modules/iam/role"`을 사용합니다.

### Non-goals

- IAM User, Group, 인라인 Policy, Permission Boundary, 서비스 연결 Role
- 특정 서비스의 권한 또는 신뢰 정책을 자동으로 추측해 생성
- 기존 EC2 모듈의 인터페이스 변경
- 실제 AWS 계정에 IAM 리소스 배포

사용자는 2026-09-23에 S3, Security Group, IAM Role과 Policy, ALB, RDS, ECR 순서로 진행하도록 요청했습니다. 이 요청으로 IAM 모듈 종류와 순서는 승인된 상태입니다. 구체적인 요구사항과 두 Unit의 구현 계획은 별도 승인 대상입니다.

## 2. Inception

### Functional Requirements

- Policy 모듈은 `name`과 `policy_json`을 받아 고객 관리 Policy 하나를 생성합니다.
- Policy 모듈은 선택적 설명과 태그를 받으며 Policy 이름과 ARN을 출력합니다.
- Policy 모듈의 출력은 `policy_name`과 `policy_arn`입니다.
- Role 모듈은 `name`과 `assume_role_policy_json`을 받아 Role 하나를 생성합니다.
- Role 모듈은 선택적 `tags`를 Role과 Instance Profile에 적용합니다.
- Role 모듈은 논리 키를 사용하는 `managed_policy_arns` Map으로 기존 또는 새 관리형 Policy를 Role에 연결합니다. 기본값은 빈 Map입니다.
- Role 모듈의 `create_instance_profile` 기본값은 `false`입니다. `true`이면 Role과 같은 이름의 Instance Profile 하나를 생성합니다.
- Role 모듈의 출력은 `role_name`, `role_arn`, `instance_profile_name`, `instance_profile_arn`입니다. Profile을 만들지 않으면 해당 출력은 `null`입니다.
- Root Module은 Policy ARN을 Role의 `managed_policy_arns`에 전달하고, EC2에는 Instance Profile 이름을 전달할 수 있습니다.

### Non-Functional Requirements

- 기본 Role에는 권한 정책 연결과 Instance Profile이 없습니다.
- 신뢰 정책과 권한 정책은 호출자가 `aws_iam_policy_document` 또는 `jsonencode`로 구성합니다. 모듈은 JSON 형식만 검증하고 IAM 권한의 의미를 추측하지 않습니다.
- 관리형 Policy 연결은 AWS Provider의 별도 `aws_iam_role_policy_attachment` 리소스로 관리합니다. Role의 `managed_policy_arns` 인라인 인수와 섞지 않습니다.
- Policy ARN Map의 논리 키는 Plan 시점에 알 수 있어야 합니다. 새 Policy의 ARN이 Apply 시점에 결정되어도 연결할 수 있어야 합니다.
- AWS 자격 증명 없이 mock provider로 주요 구성을 테스트합니다.

### Architecture

```text
Root Module
  Policy JSON -> modules/iam/policy -> Policy ARN
                                      |
                                      v
  Trust JSON -> modules/iam/role <- 관리형 Policy ARN Map
                Role 이름과 ARN
                선택적 Instance Profile 이름과 ARN
                                      |
                                      v
                           modules/ec2.iam_instance_profile
```

EC2는 Instance Profile 이름을 사용합니다. 다른 서비스에서 Role을 요구할 때는 그 서비스의 Terraform 리소스나 모듈이 요구하는 형식에 맞춰 Role ARN 또는 이름을 연결합니다.

### Unit of Work

1. 독립적인 고객 관리 IAM Policy 모듈
2. 서비스별 신뢰 정책을 받는 IAM Role, 관리형 Policy 연결, 선택적 EC2 Instance Profile 모듈

### Acceptance Criteria

- Policy 모듈의 mock Plan에 `aws_iam_policy` 한 개가 있고 이름, 정책 JSON, 태그와 출력값이 입력에 맞습니다.
- Role 모듈의 기본 mock Plan에 `aws_iam_role` 한 개만 있고 Policy 연결과 Instance Profile은 없습니다.
- 생성된 Policy ARN 또는 기존 Policy ARN을 논리 키로 연결하면 키별 `aws_iam_role_policy_attachment`가 생성됩니다.
- EC2 옵션을 켜면 Role을 담은 Instance Profile 하나가 생성되고, 출력 이름이 기존 EC2 모듈의 `iam_instance_profile` 입력 형식과 맞습니다.
- 비어 있는 이름과 잘못된 JSON은 Plan 전에 거부합니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행한 뒤 날짜와 결과를 기록합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| 모듈 경계 | Policy와 Role을 분리해 Policy 단독 생성 및 다중 Role 재사용 허용 |
| 신뢰 정책 | 호출자가 완전한 JSON을 제공해 서비스 Principal과 조건을 직접 통제 |
| 권한 정책 | 호출자가 완전한 JSON을 제공하고 Policy 모듈은 리소스 생성만 담당 |
| 관리형 Policy 연결 | Role 모듈의 논리 키 Map과 별도 Attachment 리소스 사용 |
| EC2 연결 | 선택적 Instance Profile을 Role과 같은 이름으로 생성, 이름 출력 |
| 다른 서비스 연결 | Role 이름과 ARN 출력, 서비스 리소스 생성은 Root Module 담당 |
| 기본 권한 | Policy 연결 없음, Instance Profile 없음 |

### Unit 1 Implementation Plan: IAM Policy

1. `modules/iam/policy`에 Policy 리소스, 필수 입력, 선택적 설명과 태그, 이름 및 ARN 출력을 작성합니다.
2. README에 `aws_iam_policy_document` 또는 `jsonencode` 입력과 독립 사용 예시를 작성합니다.
3. mock provider 테스트로 Policy 생성과 빈 이름 및 잘못된 JSON 거부를 확인합니다.
4. 포맷, `terraform validate`, `terraform test`를 실행하고 결과를 기록합니다.

### Unit 2 Implementation Plan: IAM Role

1. `modules/iam/role`에 Role, 관리형 Policy 연결, 선택적 Instance Profile을 작성합니다.
2. 필수 신뢰 정책과 Policy ARN Map, 출력값을 정의합니다.
3. README에 EC2 서비스 Principal, 새 Policy 연결, 기존 EC2 모듈에 Profile 이름 전달 예시를 작성합니다.
4. mock provider 테스트로 기본 Role, 새 Policy ARN 참조, 선택적 Profile, 잘못된 입력 거부를 확인합니다.
5. 포맷, `terraform validate`, `terraform test`를 실행하고 결과를 기록합니다.
6. 두 모듈과 기존 EC2 입력 계약을 검토하고 `docs/README.md`의 상태를 갱신합니다.

### Approval

2026-09-23 사용자가 두 Unit의 요구사항과 구현 계획을 승인했습니다.

### Implementation

#### Unit 1: IAM Policy

- [`main.tf`](../../modules/iam/policy/main.tf): 고객 관리 IAM Policy 생성
- [`variables.tf`](../../modules/iam/policy/variables.tf): 이름, Policy JSON, 설명과 태그 입력 및 검증
- [`outputs.tf`](../../modules/iam/policy/outputs.tf): Policy 이름과 ARN
- [`README.md`](../../modules/iam/policy/README.md): 독립 사용 예시와 제한 사항
- [`policy.tftest.hcl`](../../modules/iam/policy/tests/policy.tftest.hcl): mock provider Plan 테스트

#### Unit 2: IAM Role

- [`main.tf`](../../modules/iam/role/main.tf): Role, 관리형 Policy 연결, 선택적 Instance Profile 생성
- [`variables.tf`](../../modules/iam/role/variables.tf): 신뢰 정책, Policy ARN Map, Profile 옵션과 태그 입력 및 검증
- [`outputs.tf`](../../modules/iam/role/outputs.tf): Role과 선택적 Instance Profile의 이름 및 ARN
- [`README.md`](../../modules/iam/role/README.md): Policy와 EC2 연결 예시 및 제한 사항
- [`role.tftest.hcl`](../../modules/iam/role/tests/role.tftest.hcl): mock provider Plan 테스트
- [`iam-composition`](../../tests/iam-composition/main.tf): 새 Policy ARN, Role, Instance Profile, 기존 EC2 모듈을 연결하는 테스트 전용 Root Module

2026-09-24 루트 `tests/` 디렉터리의 용도와 삭제 가능 여부를 조사했습니다. 결합 테스트는 개별 Policy·Role 테스트가 검증하지 않는 모듈 간 연결을 확인하므로 디렉터리를 유지합니다. [`versions.tf`](../../tests/iam-composition/versions.tf)에 테스트 Root의 AWS Provider 요구 조건을 명시하고 [`tests/README.md`](../../tests/README.md)에 용도와 실행 방법을 기록했습니다.

### Test

| 날짜 | 대상과 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `terraform fmt -recursive modules/iam/policy` | PASS, 변경 필요 없음 |
| 2026-09-23 | `terraform fmt -recursive modules/iam/role` | PASS, 변경 필요 없음 |
| 2026-09-23 | `terraform fmt -recursive tests/iam-composition` | PASS, 변경 필요 없음 |
| 2026-09-23 | `terraform fmt -check -recursive modules` | PASS |
| 2026-09-23 | `terraform fmt -check -recursive tests` | PASS |
| 2026-09-23 | 세 임시 복사본에서 `terraform init -backend=false -input=false -no-color -plugin-dir=/Users/hwjeong/Workspace/01.Project/ws-haiops/src/prod/.terraform/providers` | PASS, 로컬 AWS Provider v6.56.0 사용 |
| 2026-09-23 | Policy 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | Policy 임시 복사본에서 `terraform test -no-color` | PASS, 3 passed and 0 failed |
| 2026-09-23 | Role 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | Role 임시 복사본에서 `terraform test -no-color` | PASS, 5 passed and 0 failed |
| 2026-09-23 | 결합 구성 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | 결합 구성 임시 복사본에서 `terraform test -no-color` | PASS, 1 passed and 0 failed |
| 2026-09-23 | 결합 구성 임시 복사본에서 `terraform test -verbose -no-color` | PASS, mock Plan에 Policy, Role, Attachment, Profile, EC2 5개 생성 계획 확인 |
| 2026-09-23 | Role README의 HCL 예시 두 개를 추출해 `terraform fmt -check /private/tmp/iam-role-readme-example.tf` | PASS |
| 2026-09-23 | `git diff --check` | PASS |
| 2026-09-23 | `git rev-parse HEAD origin/main`과 `git ls-remote origin refs/heads/main` | PASS, 모두 `2190a91b4e6023492d71023f6c69a959d1a825b3` |
| 2026-09-24 | `terraform init -backend=false -plugin-dir=/tmp/terraform-plugin-cache -no-color` (임시 복사본) | AWS Provider 6.66.0으로 초기화 성공 |
| 2026-09-24 | `terraform validate -no-color` (기존 결합 테스트 임시 복사본) | PASS |
| 2026-09-24 | `terraform test -no-color` (기존 결합 테스트 임시 복사본) | FAIL, 테스트 Root의 Provider 요구 선언 누락으로 실제 Provider가 자격 증명을 요구 |
| 2026-09-24 | `terraform test -no-color` (진단용 더미 자격 증명) | FAIL, 실제 Provider의 STS 검증까지 진행됨. mock Provider 적용 문제 확인 |
| 2026-09-24 | `terraform fmt -check -recursive tests` | PASS |
| 2026-09-24 | `terraform validate -no-color` (Provider 선언 보강 후 임시 복사본) | PASS |
| 2026-09-24 | `terraform test -no-color` (Provider 선언 보강 후 임시 복사본) | PASS, 1 passed and 0 failed. AWS 자격 증명 불필요 |

검증은 `/private/tmp/template-iam-cxtvfj4i` 아래의 복사본에서 실행했습니다. Provider 실행은 샌드박스가 차단하므로 `terraform validate`와 `terraform test`를 승인된 권한으로 실행했습니다. 결합 mock Plan에서 Attachment의 `policy_arn`은 새 Policy ARN이고, EC2의 `iam_instance_profile`은 `sample-app-role`인 것을 확인했습니다.

mock provider 테스트는 실제 AWS 계정의 Plan, Apply, IAM 권한 적용과 서비스 연결 결과를 증명하지 않습니다.

### Review

- Policy와 Role을 독립 모듈로 두고, 새 Policy ARN을 Role의 논리 키 Map에 연결해 Apply 시점에 ARN이 결정되어도 `for_each` 키는 안정적으로 유지합니다.
- Role에는 인라인 관리형 Policy ARN을 쓰지 않고 별도 Attachment 리소스를 사용합니다.
- Instance Profile은 선택적으로 생성하며 Policy Attachment 이후 생성되도록 Terraform 의존성을 설정했습니다.
- 기존 EC2 모듈의 `iam_instance_profile` 입력은 변경하지 않았습니다. 결합 mock Plan에서 Profile 이름 전달을 확인했습니다.
- Role README에 신뢰 정책과 인라인 권한 정책의 차이, 기존 관리형 Policy ARN 연결, EC2에서 Instance Profile 옵션이 필요한 이유와 옵션이 꺼졌을 때 EC2에 Role이 연결되지 않는 동작을 명시했습니다.
- JSON 구문만 입력 단계에서 검증합니다. 정책의 최소 권한, 신뢰 정책의 실제 AWS 유효성, IAM 전파 지연, 서비스 연결 성공 여부는 mock 테스트로 확인할 수 없습니다.
- 환경별 Root Module이 없으므로 실제 AWS Plan과 Apply는 수행하지 않았습니다.
- 2026-09-24 현재 루트 `tests/iam-composition`은 유일한 Policy·Role·Instance Profile·EC2 결합 mock 테스트입니다. 삭제하면 이 검증이 사라집니다. 현재 Provider에서도 테스트가 실행되도록 Root의 Provider 요구 선언을 추가했으며, 모듈 자체는 변경하지 않았습니다.

### 결합 테스트 보강 커밋과 푸시

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'test(iam): document and enable composition checks'` | 커밋 `df31faba97a7655982c050cd68bc948ea1d9782b` 생성 |
| 2026-09-24 | `git push origin main` | 커밋 `df31fab`을 포함한 main 푸시 완료 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main이 후속 EKS 커밋 `15fe220d2eeb2dd07c88da6b54094bea32c5320d`를 가리켜 결합 테스트 커밋도 원격에 포함됨을 확인 |

## 4. Operation

Deployment, Observability, Rollback, Runbook은 아직 시작하지 않았습니다. Root Module과 AWS 계정 연결 후 별도 작업에서 다룹니다.

## 근거

- [AWS IAM Instance Profile](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2_instance-profiles.html)
- [Terraform AWS Provider IAM Policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy)
- [Terraform AWS Provider IAM Role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)
- [Terraform AWS Provider IAM Role Policy Attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)
- [Terraform AWS Provider IAM Instance Profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile)
