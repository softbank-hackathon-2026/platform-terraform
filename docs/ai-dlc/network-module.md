# Network module AI-DLC

마지막 확인일: 2026-09-22

이 문서는 승인된 AI-DLC 단계, 현재 코드, 실제 테스트 결과를 이어서 확인할 수 있도록 작성했습니다.

## 현재 상태

| 구분 | 상태 |
|---|---|
| 구현 | 완료 |
| 로컬 검증 | 포맷과 `terraform validate` 통과, mock 테스트 7개 통과 |
| Terraform Plan | mock provider Plan만 수행, 실제 AWS Plan 미수행 |
| Terraform Apply | 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋 | `3587c82` |
| 푸시 | 원격 main 포함 확인 |
| Operation | 시작하지 않음 |

## 1. Ideation

### 문제 정의

환경별 Root Module에서 공통으로 사용할 VPC와 Subnet 구성이 필요했습니다. NAT 비용과 가용성 요구에 따라 NAT를 사용하지 않거나 Regional 또는 Zonal 방식으로 선택할 수 있어야 했습니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 Network를 구성하는 작성자
- EC2와 다른 AWS 리소스에 VPC와 Subnet ID를 전달하는 운영자

### 성공 기준

- Public과 Private Subnet을 논리 키로 정의할 수 있습니다.
- NAT 모드를 `none`, `regional`, `zonal` 중에서 선택할 수 있습니다.
- Zonal NAT를 배치할 Public Subnet을 AZ별로 직접 선택할 수 있습니다.
- Private Subnet은 모드에 맞는 NAT Gateway로 기본 경로를 사용합니다.

### Scope

- IPv4 VPC
- Public과 Private Subnet
- Internet Gateway와 Route Table
- 선택적 Regional과 Zonal NAT Gateway
- Network 리소스 ID 출력

### Non-goals

- Security Group과 Network ACL 정책
- VPC Endpoint, Peering, Transit Gateway, VPN
- Network Firewall과 Route 53 Resolver
- IAM 리소스
- IPv6

## 2. Inception

### Functional Requirements

- `private_subnets`에는 하나 이상의 Subnet이 필요합니다.
- Public과 Private Subnet마다 지정한 AZ와 CIDR을 사용합니다.
- 모든 Subnet에서 Public IP 자동 할당을 끕니다.
- Private Subnet마다 Route Table을 하나씩 만듭니다.
- `none` 모드에서는 NAT와 Private 인터넷 기본 경로를 만들지 않습니다.
- `regional` 모드에서는 VPC 범위 Regional NAT 하나를 모든 Private Route가 사용합니다.
- `zonal` 모드에서는 Private Subnet이 있는 AZ마다 Zonal NAT 하나를 만듭니다.
- Zonal NAT는 `zonal_nat_subnet_keys`에서 선택한 같은 AZ의 Public Subnet을 사용합니다.

### Non-Functional Requirements

- 기본 NAT 모드는 `none`으로 비용 발생을 피합니다.
- 잘못된 NAT 모드, 누락된 AZ, 알 수 없는 Subnet 키, AZ 불일치를 Plan 전에 거부합니다.
- 태그를 모든 지원 리소스에 일관되게 적용합니다.
- 모듈 테스트에서 AWS 계정과 자격 증명을 요구하지 않습니다.

### Architecture

```text
VPC
  Internet Gateway
  Public Subnets
    Shared Public Route Table
    Zonal NAT Gateway when selected
  Private Subnets
    One Route Table per Subnet
    No NAT, Regional NAT, or same-AZ Zonal NAT
```

Regional NAT는 VPC에 생성되므로 Subnet을 선택하지 않습니다. Zonal NAT는 `AZ -> Public Subnet logical key` Map으로 배치 위치를 선택합니다.

### Unit of Work

1. VPC, Subnet, Route Table, 선택적 NAT를 포함하는 Network 모듈

### Acceptance Criteria

- 세 NAT 모드가 서로 다른 리소스 구성을 만들어야 합니다.
- Zonal NAT의 Public Subnet 선택과 같은 AZ의 Private Route 연결을 검증해야 합니다.
- 잘못된 모드와 Zonal NAT Map을 거부해야 합니다.
- 실제 AWS 리소스를 만들지 않는 자동 테스트가 있어야 합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| Subnet 입력 | 논리 이름을 키로 하는 Map |
| Private Route Table | Private Subnet마다 하나 |
| Public Route Table | Public Subnet이 있으면 하나를 공유 |
| Regional NAT | VPC 범위 NAT 하나, Subnet과 EIP 입력 없음 |
| Zonal NAT | Private Subnet이 있는 AZ마다 하나 |
| Zonal 배치 | `zonal_nat_subnet_keys`로 Public Subnet 직접 선택 |
| 기본 모드 | `none` |
| Public IP | 모든 Subnet에서 자동 할당 비활성화 |

### Implementation

- [`main.tf`](../../modules/network/main.tf): VPC, Subnet, Route Table, NAT Gateway
- [`variables.tf`](../../modules/network/variables.tf): 입력과 Zonal NAT 검증
- [`outputs.tf`](../../modules/network/outputs.tf): VPC, Subnet, Route Table, NAT ID
- [`network.tftest.hcl`](../../modules/network/tests/network.tftest.hcl): mock provider Plan 테스트
- [`README.md`](../../modules/network/README.md): 모드별 사용법
- 구현 커밋: `3587c82`

### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-22 | `terraform fmt -check -recursive modules` | PASS |
| 2026-09-22 | 임시 복사본에서 `terraform init -backend=false -input=false -no-color` | PASS, AWS provider v6.66.0 |
| 2026-09-22 | 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-22 | 임시 복사본에서 `terraform test -no-color` | PASS, 7 passed and 0 failed |

테스트 시나리오는 다음과 같습니다.

1. NAT 없음
2. Regional NAT
3. Zonal NAT와 명시적 Public Subnet 선택
4. 잘못된 NAT 모드 거부
5. 존재하지 않는 Zonal NAT Subnet 거부
6. 누락된 Zonal NAT AZ 거부
7. Zonal NAT와 Public Subnet AZ 불일치 거부

### Review

- Regional NAT에는 선택할 Subnet이 없습니다.
- Zonal NAT는 같은 AZ에 여러 Public Subnet이 있어도 논리 키로 하나를 선택할 수 있습니다.
- 동일한 CIDR 문자열은 거부하지만 VPC 포함 관계와 부분 중첩은 AWS 적용 단계에서 확인합니다.
- NAT 모드 변경은 NAT Gateway와 EIP의 생성 또는 제거와 인터넷 송신 중단을 일으킬 수 있습니다.

## 4. Operation

| 항목 | 상태 |
|---|---|
| Deployment | 미수행 |
| Observability | 없음 |
| Rollback | 미검증 |
| Runbook | 없음 |

환경별 Root Module에 연결한 뒤 Terraform Plan을 먼저 검토해야 합니다. Apply와 AWS 리소스 확인은 실행 결과가 있을 때만 이 문서에 추가합니다.
