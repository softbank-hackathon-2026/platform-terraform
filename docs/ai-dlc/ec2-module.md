# EC2 module AI-DLC

마지막 확인일: 2026-09-22

이 문서는 기존 승인 대화, 현재 코드, Git 이력을 바탕으로 사후 작성한 AI-DLC 기록입니다. 확인할 수 없는 과거 실행 결과는 PASS로 간주하지 않습니다.

## 현재 상태

| 구분 | 상태 |
|---|---|
| 구현 | 완료 |
| 로컬 검증 | 포맷과 `terraform validate` 통과 |
| 자동 테스트 | 없음 |
| Terraform Plan | 미수행 |
| Terraform Apply | 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋 | `776d3dd`, `3532c5f` |
| 푸시 | 원격 main 포함 확인 |
| Operation | 시작하지 않음 |

## 1. Ideation

### 문제 정의

환경별 Root Module에서 반복해서 사용할 수 있는 단일 EC2 인스턴스 모듈이 필요했습니다. 기본 보안 설정을 유지하면서 워크로드에 따라 On-Demand와 Spot을 선택할 수 있어야 했습니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 인프라를 정의하는 작성자
- Network와 IAM 리소스를 별도로 조합하는 운영자

### 성공 기준

- 같은 인터페이스로 On-Demand와 Spot을 선택할 수 있습니다.
- Subnet, Security Group, IAM Instance Profile을 외부에서 전달할 수 있습니다.
- Root EBS 암호화와 IMDSv2가 기본 적용됩니다.
- 여러 인스턴스가 필요하면 호출자가 `for_each`로 확장할 수 있습니다.

### Scope

- EC2 인스턴스 한 개
- 선택적 Key Pair, IAM Instance Profile, User Data
- 암호화된 gp3 Root EBS
- On-Demand와 일회성 Spot
- 인스턴스 식별 정보 출력

### Non-goals

- VPC, Subnet, Security Group 생성
- IAM User, Role, Policy, Instance Profile 생성
- Elastic IP 생성
- Auto Scaling Group과 EC2 Fleet
- Spot 중단 후 자동 복구

## 2. Inception

### Functional Requirements

- 기본 `purchase_option`은 `on-demand`입니다.
- `purchase_option = "spot"`이면 일회성 Spot Instance를 요청합니다.
- `iam_instance_profile`은 ARN이 아닌 Instance Profile 이름을 받습니다.
- AMI, Instance Type, Subnet, Security Group을 필수 입력으로 받습니다.
- Root EBS 크기와 선택적 KMS Key를 입력받습니다.
- ID, ARN, AZ, Private와 Public 주소 정보를 출력합니다.

### Non-Functional Requirements

- Root EBS는 항상 암호화하고 종료 시 삭제합니다.
- Instance Metadata Service는 IMDSv2 토큰을 요구합니다.
- Public IP 연결은 기본적으로 끕니다.
- User Data에 비밀값을 넣지 않도록 문서화합니다.
- IAM과 Network 생명 주기를 EC2 모듈과 분리합니다.

### Architecture

호출하는 Root Module이 Network와 IAM 리소스를 만들고 ID 또는 이름을 EC2 모듈에 전달합니다. EC2 모듈은 `aws_instance` 하나만 소유합니다.

```text
Root Module
  Network Subnet ID
  Security Group IDs
  IAM Instance Profile name
          |
          v
     modules/ec2
          |
          v
     aws_instance
```

### Unit of Work

1. 기본 EC2 모듈과 보안 기본값
2. On-Demand와 Spot 선택 기능

### Acceptance Criteria

- 기본 구성에는 Spot 옵션 블록이 없어야 합니다.
- Spot 구성에는 `market_type = "spot"`과 종료 동작이 있어야 합니다.
- `iam_instance_profile` 값이 `aws_instance`에 그대로 전달되어야 합니다.
- Root EBS 암호화와 IMDSv2 설정이 코드에 있어야 합니다.
- Terraform 구성이 유효해야 합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| 구매 옵션 | 문자열 `on-demand`와 `spot`만 허용 |
| Spot 구현 | `dynamic instance_market_options`를 Spot일 때만 생성 |
| Spot 중단 | 일회성 요청, 중단 시 인스턴스 종료 |
| IAM 연결 | `iam_instance_profile`에 Instance Profile 이름 전달 |
| 저장소 | 암호화된 gp3 Root EBS 사용 |
| Metadata | IMDSv2 필수, hop limit 1 |
| 확장 방식 | 다중 인스턴스는 Root Module의 `for_each` 사용 |

### Implementation

- [`main.tf`](../../modules/ec2/main.tf): `aws_instance`와 보안 기본값
- [`variables.tf`](../../modules/ec2/variables.tf): 입력과 검증
- [`outputs.tf`](../../modules/ec2/outputs.tf): 인스턴스 식별 정보
- [`README.md`](../../modules/ec2/README.md): 사용법과 Spot 주의 사항
- 구현 커밋: `776d3dd`
- Spot 추가 커밋: `3532c5f`

### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-22 | `terraform fmt -check -recursive modules` | PASS |
| 2026-09-22 | 임시 복사본에서 `terraform init -backend=false -input=false -no-color` | PASS, AWS provider v6.66.0 |
| 2026-09-22 | 임시 복사본에서 `terraform validate -no-color` | PASS, configuration is valid |

자동 `.tftest.hcl` 테스트는 현재 없습니다. 따라서 On-Demand와 Spot의 Plan 동작은 자동 검증됐다고 표시하지 않습니다.

### Review

- `iam_instance_profile`은 IAM Role ARN이 아니라 IAM Instance Profile 이름입니다.
- 모듈은 IAM 리소스를 만들지 않습니다.
- `purchase_option` 변경은 인스턴스 교체를 유발할 수 있습니다.
- Spot 중단 후 자동 복구가 필요하면 Auto Scaling Group 또는 EC2 Fleet이 별도 작업으로 필요합니다.

## 4. Operation

| 항목 | 상태 |
|---|---|
| Deployment | 미수행 |
| Observability | 상세 모니터링 입력만 제공, 대시보드와 알람 없음 |
| Rollback | 미검증 |
| Runbook | 없음 |

환경별 Root Module에 연결한 뒤 Terraform Plan을 먼저 검토해야 합니다. Apply와 AWS 리소스 확인은 실행 결과가 있을 때만 이 문서에 추가합니다.
