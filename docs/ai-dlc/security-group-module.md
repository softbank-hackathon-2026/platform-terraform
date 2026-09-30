# Security Group module AI-DLC

마지막 확인일: 2026-09-23

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 모듈 종류와 작업 순서 승인 |
| Inception | 요구사항 승인 |
| Construction | 구현, Test, Review 완료 |
| 구현과 테스트 | 완료, 포맷과 구성 검증 및 mock 테스트 8개 통과 |
| Terraform Plan과 Apply | mock provider Plan만 수행, 실제 AWS 기준 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋과 푸시 | 구현 커밋 `8949e16` 푸시 완료, 원격 main SHA 일치 확인 |
| Operation | 시작하지 않음 |

## 1. Ideation

### 문제 정의

Network 모듈은 VPC를 생성하고 EC2 모듈은 Security Group ID를 요구하지만, 현재 저장소에는 Security Group을 생성하는 모듈이 없습니다. VPC 안의 서비스가 명시적으로 허용한 트래픽만 사용할 수 있도록 Security Group과 규칙을 재사용 가능한 단위로 제공합니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 네트워크 접근 규칙을 구성하는 작성자
- EC2, ALB, RDS에 Security Group ID를 전달하는 운영자

### 성공 기준

- VPC ID, 이름, 규칙 입력으로 Security Group 하나를 생성할 수 있습니다.
- 인바운드와 아웃바운드 규칙을 논리 키로 구분해 관리할 수 있습니다.
- 기본 규칙 없이 시작하고 필요한 접근만 명시할 수 있습니다.
- Security Group ID와 ARN을 다른 모듈에 전달할 수 있습니다.

### Scope

- VPC Security Group 하나와 태그
- IPv4 CIDR 또는 다른 Security Group ID를 대상으로 하는 인바운드와 아웃바운드 규칙
- TCP, UDP, 전체 프로토콜 허용 규칙
- Security Group ID와 ARN 출력

### Non-goals

- Network ACL, VPC 생성, 서비스별 고정 포트 정책
- IPv6 CIDR, Prefix List, ICMP 전용 규칙
- SSH 또는 모든 아웃바운드 트래픽을 기본으로 허용
- 실제 AWS 계정에 규칙 적용

사용자는 2026-09-23에 이 모듈을 S3 다음으로 진행하도록 요청했습니다. 모듈 선정과 순서는 승인된 상태입니다.

## 2. Inception

### Functional Requirements

- 필수 입력 `name`과 `vpc_id`로 Security Group 하나를 생성합니다.
- `ingress_rules`와 `egress_rules`는 논리 키를 사용하는 Map이고 기본값은 빈 Map입니다.
- 각 규칙은 `ip_protocol`, 선택적 `from_port`와 `to_port`, 그리고 `cidr_ipv4` 또는 `referenced_security_group_id` 중 정확히 하나를 받습니다.
- TCP와 UDP 규칙에는 시작 포트와 끝 포트가 필요합니다. `ip_protocol = "-1"`인 전체 프로토콜 규칙에는 포트를 지정하지 않습니다.
- 이름과 태그를 Security Group에 적용합니다.
- Security Group ID와 ARN을 출력합니다.

### Non-Functional Requirements

- 기본 구성에는 인바운드와 아웃바운드 규칙이 없습니다.
- AWS가 새 Security Group에 추가하는 전체 아웃바운드 허용 규칙은 Provider가 제거하도록 합니다.
- 잘못된 규칙 출처 또는 목적지와 포트 조합은 Plan 전에 거부합니다.
- `aws_security_group`의 인라인 규칙과 별도 규칙 리소스를 섞지 않습니다.
- AWS 자격 증명 없이 mock provider로 주요 규칙을 테스트합니다.

### Architecture

```text
Root Module
  VPC ID, 이름, ingress_rules, egress_rules
        |
        v
  modules/security-group
    aws_security_group
    aws_vpc_security_group_ingress_rule (규칙별)
    aws_vpc_security_group_egress_rule (규칙별)
        |
        v
  Security Group ID, ARN
```

### Unit of Work

1. Security Group과 명시적 IPv4 및 Security Group 참조 규칙을 관리하는 모듈

### Acceptance Criteria

- 기본 mock Plan에는 Security Group 하나만 있고 인바운드와 아웃바운드 규칙은 없습니다.
- 입력한 TCP 규칙과 전체 프로토콜 규칙이 각각 올바른 리소스로 생성됩니다.
- 한 규칙에 출처 또는 목적지를 둘 이상 지정하거나 아무것도 지정하지 않으면 거부합니다.
- TCP 또는 UDP의 포트 누락과 전체 프로토콜의 포트 지정은 거부합니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행해 결과를 기록합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| Security Group 생명 주기 | 모듈 호출당 한 개 생성 |
| 규칙 식별 | 논리 키를 사용하는 Map으로 `for_each` 적용 |
| 규칙 출처와 목적지 | IPv4 CIDR 또는 Security Group ID 중 정확히 하나 |
| 기본 규칙 | 인바운드와 아웃바운드 모두 없음 |
| 규칙 리소스 | 별도 `aws_vpc_security_group_ingress_rule` 및 `aws_vpc_security_group_egress_rule` 사용 |
| 포트 | TCP와 UDP는 범위 필수, `-1`은 미사용 |
| 태그 | Security Group의 `Name` 태그는 모듈 이름 우선 |

### Implementation Plan

1. `modules/security-group`에 Security Group과 인바운드 및 아웃바운드 규칙을 작성합니다.
2. 필수 입력, 규칙 Map, 출처와 포트 검증, ID와 ARN 출력을 정의합니다.
3. README에 기본 차단 상태와 IPv4 및 Security Group 참조 예시를 작성합니다.
4. mock provider 테스트로 기본 상태, TCP 및 전체 프로토콜 규칙, 잘못된 규칙 거부를 확인합니다.
5. 포맷, `terraform validate`, `terraform test`를 실행하고 날짜와 결과를 기록합니다.
6. 코드와 테스트 결과를 검토하고 `docs/README.md`의 상태를 갱신합니다.

### Approval

2026-09-23 사용자가 이 문서의 Security Group 구현 계획을 승인했습니다.

### Implementation

- [`main.tf`](../../modules/security-group/main.tf): Security Group과 별도 인바운드 및 아웃바운드 규칙
- [`variables.tf`](../../modules/security-group/variables.tf): 이름, VPC ID, 규칙 Map과 입력 검증
- [`outputs.tf`](../../modules/security-group/outputs.tf): Security Group ID와 ARN
- [`versions.tf`](../../modules/security-group/versions.tf): Terraform과 AWS Provider 버전 조건
- [`README.md`](../../modules/security-group/README.md): 기본 차단 상태와 다른 모듈 연결 예시
- [`security-group.tftest.hcl`](../../modules/security-group/tests/security-group.tftest.hcl): mock provider Plan 테스트

### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `terraform fmt -recursive modules/security-group` | PASS, 변경 필요 없음 |
| 2026-09-23 | `terraform fmt -check -recursive modules` | PASS |
| 2026-09-23 | 임시 복사본에서 `terraform init -backend=false -input=false -no-color -plugin-dir=/Users/hwjeong/Workspace/01.Project/ws-haiops/src/prod/.terraform/providers` | PASS, 로컬 AWS Provider v6.56.0 사용 |
| 2026-09-23 | 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | 임시 복사본에서 `terraform test -no-color` | PASS, 8 passed and 0 failed |
| 2026-09-23 | `git diff --check` | PASS |

검증은 `/private/tmp/template-sg-afwgseb0/security-group`의 복사본에서 실행했습니다. 샌드박스에서 AWS Provider 실행이 차단되어 `terraform validate`와 `terraform test`는 승인된 권한으로 재실행했습니다. 테스트는 기본 규칙 없음, IPv4 및 Security Group 참조 규칙, 대상 중복과 누락, 포트 조합, 잘못된 IPv4 CIDR을 확인합니다.

mock provider 테스트는 실제 AWS 계정의 Plan, Apply, 기본 아웃바운드 규칙 제거 결과를 증명하지 않습니다.

### Git 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `git push origin main` | Security Group 구현 커밋 `8949e16` 푸시 완료 |
| 2026-09-23 | `git ls-remote origin refs/heads/main` | 원격 main이 `8949e16ce59cb313982ea621081b2ff4202c8668`인 것을 확인 |

### Review

- `aws_security_group`에 인라인 규칙을 정의하지 않고, 규칙마다 별도 리소스를 사용합니다.
- AWS Provider 문서는 새 VPC Security Group의 기본 전체 아웃바운드 규칙을 생성 시 제거한다고 설명합니다. 실제 계정에서의 동작은 아직 확인하지 않았습니다.
- 입력 검증은 TCP, UDP, 전체 프로토콜과 IPv4 CIDR 또는 Security Group 참조만 허용합니다. 실제 VPC 및 참조 Security Group의 존재와 연결 가능성은 mock 테스트로 확인되지 않았습니다.
- 환경별 Root Module이 없으므로 실제 AWS Plan과 Apply는 수행하지 않았습니다.

## 4. Operation

Deployment, Observability, Rollback, Runbook은 아직 시작하지 않았습니다. Root Module과 AWS 계정 연결 후 별도 작업에서 다룹니다.

## 근거

- [AWS Security Group 규칙](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)
- [Terraform AWS Provider Security Group](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/security_group.html.markdown)
- [Terraform AWS Provider 인바운드 규칙](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/vpc_security_group_ingress_rule.html.markdown)
- [Terraform AWS Provider 아웃바운드 규칙](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/vpc_security_group_egress_rule.html.markdown)
