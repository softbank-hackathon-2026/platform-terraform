# ALB module AI-DLC

마지막 확인일: 2026-09-23

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | ALB 작업 순서와 범위 승인 |
| Inception | 요구사항과 인수 기준 승인 |
| Construction | 최초 두 Unit과 Listener 확장의 구현, Test, Review 완료 |
| 구현과 테스트 | 완료, 확장 후 포맷 및 구성 검증과 mock 테스트 15개 통과 |
| Terraform Plan과 Apply | mock provider Plan 테스트만 수행, 실제 AWS 기준 미수행 |
| AWS 리소스 확인 | 미수행 |
| 커밋과 푸시 | 구현 커밋 `50b854f`를 원격 main에 푸시하고 원격 SHA 확인 |
| Operation | 시작하지 않음 |
| 0개·여러 개 Listener 확장 | 구현, Test, Review 완료. 기존 12개 테스트는 확장 전 결과로 별도 보존 |

## 1. Ideation

### 문제 정의

Network 모듈은 VPC와 Subnet을 만들고 Security Group 모듈은 트래픽 규칙을 관리하지만, 애플리케이션 트래픽을 여러 대상으로 전달할 ALB 모듈은 없습니다. 환경별 Root Module에서 같은 ALB, Listener, Target Group 구성을 반복하지 않도록 기본 구성 요소가 필요합니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 애플리케이션 진입점을 구성하는 작성자
- EC2 등의 대상 등록과 네트워크 접근을 별도로 관리하는 운영자

### 성공 기준

- 기존 Network의 Subnet ID와 Security Group ID로 ALB를 구성할 수 있습니다.
- 하나의 기본 Listener가 Target Group으로 요청을 전달합니다.
- 내부 HTTP와 인증서를 사용하는 HTTPS 구성을 선택할 수 있습니다.
- Target Group ARN과 Listener ARN을 출력해 호출자가 대상을 등록하거나 추가 라우팅 규칙을 연결할 수 있습니다.

### Scope

- IPv4 Application Load Balancer 하나
- HTTP 또는 HTTPS 기본 Listener 하나와 Target Group 하나
- HTTPS 구성에서 선택적인 HTTP→HTTPS 리디렉션 Listener
- Target Group의 HTTP 또는 HTTPS 상태 확인 경로 및 성공 코드 설정
- ALB, Listener, Target Group 식별 정보 출력

### Non-goals

- VPC, Subnet, Security Group, 인증서, DNS 레코드, 대상 인스턴스 생성
- Target Group 대상 등록, Auto Scaling, ECS 서비스 연결
- 추가 Target Group, Host/Path 라우팅 규칙, 가중치 라우팅
- WAF, 인증, 고급 Listener 설정, 액세스 로그용 S3 버킷과 버킷 정책
- IPv6, Lambda Target Group, gRPC, 실제 AWS 배포

2026-09-23 사용자 요청으로 S3, Security Group, IAM Role과 Policy, ALB, RDS, ECR의 작업 순서는 승인됐습니다. 이후 이 문서의 ALB 세부 요구사항과 구현 계획도 승인됐습니다.

## 2. Inception

### Functional Requirements

- 필수 입력 `name`, `target_group_name`, `vpc_id`, `subnet_ids`, `security_group_ids`로 ALB와 Target Group을 만듭니다. Subnet ID는 중복 없는 두 개 이상, Security Group ID는 한 개 이상이어야 합니다.
- `internal`의 기본값은 `true`입니다. 인터넷 공개형은 `internal = false`로 명시합니다.
- `target_type`은 `instance` 또는 `ip`이고 기본값은 `instance`입니다. `target_protocol`은 HTTP 또는 HTTPS이고 기본값은 HTTP이며, `target_port`의 기본값은 80입니다.
- `health_check_path`의 기본값은 `/`, `health_check_matcher`의 기본값은 `200`이며 호출자가 바꿀 수 있습니다.
- `listener_protocol`은 HTTP 또는 HTTPS이고 기본값은 HTTP입니다. `listener_port`를 생략하면 프로토콜에 따라 80 또는 443을 사용하며, 1~65535 범위에서 직접 지정할 수 있습니다.
- HTTPS Listener에는 호출자가 제공한 `certificate_arn`이 필수입니다. `tls_policy`는 `ELBSecurityPolicy-TLS13-1-2-2021-06`을 기본값으로 사용하고 변경할 수 있습니다.
- 공개형 ALB는 HTTPS Listener와 인증서 ARN을 반드시 사용합니다. `enable_http_redirect = true`이면 포트 80의 HTTP Listener가 기본 HTTPS Listener 포트로 301 리디렉션합니다.
- ALB와 Target Group에 `tags`를 적용합니다. `enable_deletion_protection`의 기본값은 `false`입니다.
- `load_balancer_arn`, `dns_name`, `zone_id`, `target_group_arn`, `listener_arn`, `redirect_listener_arn`을 출력합니다. 리디렉션을 사용하지 않으면 마지막 값은 `null`입니다.

### Non-Functional Requirements

- 기존 모듈과 같은 Terraform `>= 1.5.0`, AWS Provider `>= 6.24` 조건을 사용합니다.
- 공개형 구성에서 암호화되지 않은 HTTP 전달을 허용하지 않도록 입력 단계에서 검증합니다.
- 모듈은 네트워크 규칙과 대상 등록을 소유하지 않습니다. 호출자는 ALB와 대상 Security Group의 Listener, 전달, 상태 확인 포트를 열어야 합니다.
- Subnet이 서로 다른 AZ에 있고 충분한 여유 IP를 갖는지, 인증서가 같은 Region에서 유효한지, 대상이 정상 상태인지 여부는 실제 AWS에서 확인합니다.
- AWS 자격 증명 없이 mock provider 기반 Plan 테스트로 기본 구성, HTTPS, 리디렉션, 입력 거부를 검증합니다.

### Architecture

```text
Root Module
  Network -> VPC ID, 서로 다른 AZ의 Subnet IDs
  Security Group -> ALB Security Group IDs
  외부 인증서 -> HTTPS Certificate ARN
         |
         v
  modules/alb
    aws_lb
    aws_lb_target_group
    aws_lb_listener (기본 전달)
    aws_lb_listener (선택적 HTTP 리디렉션)
         |
         v
  Target Group ARN -> Root Module의 대상 등록 또는 서비스 연결
  Listener ARN     -> Root Module의 추가 Listener Rule
```

### Unit of Work

1. ALB와 Target Group, 기본 HTTP/HTTPS Listener를 구성하고 출력합니다.
2. 선택적 HTTP→HTTPS 리디렉션과 입력 제약을 추가합니다.

### Acceptance Criteria

- 기본 mock Plan에는 내부 ALB 하나, Target Group 하나, HTTP Listener 하나가 있고 리디렉션 Listener는 없습니다.
- HTTPS mock Plan에는 인증서 ARN과 명시한 TLS 정책이 연결됩니다.
- 리디렉션을 켜면 포트 80 Listener의 기본 동작은 HTTPS로 보내는 301 리디렉션입니다.
- 공개형 HTTP, 인증서 없는 HTTPS, HTTP와 인증서의 잘못된 조합, 두 개 미만 또는 중복 Subnet ID, 빈 Security Group ID를 거부합니다.
- Target Group ARN과 Listener ARN이 출력되고 대상 등록은 모듈 안에서 생성되지 않습니다.
- Terraform 포맷, `terraform validate`, `terraform test`를 실제 실행한 뒤 날짜, 명령, 결과를 기록합니다.

## 3. Construction

### Design

| 결정 | 내용 |
|---|---|
| 모듈 경계 | ALB 하나와 기본 Target Group, Listener만 소유. 대상 연결은 호출자가 소유 |
| 네트워크 | 기존 Network와 Security Group 모듈의 출력값을 입력받음 |
| 기본 노출 | 내부형 ALB와 HTTP Listener. 공개형은 HTTPS와 인증서 요구 |
| 대상 유형 | `instance`와 `ip`만 지원. 한 모듈 호출에서 Target Group 하나 |
| TLS | HTTPS에 명시적인 TLS 1.2/1.3 정책을 사용 |
| 리디렉션 | HTTPS일 때에만 포트 80 Listener를 추가. 기본 Listener 포트와 80의 충돌을 거부 |
| 삭제 보호 | 호출자가 선택. 기본은 `false` |
| 이름 | ALB와 Target Group 이름을 각각 명시적으로 입력받아 AWS의 32자 제한과 고유성 요구를 설명 |

### Unit 1 Implementation Plan: ALB와 기본 전달

1. `modules/alb`에 버전 조건, ALB, Target Group, 기본 전달 Listener를 작성합니다.
2. 필수 네트워크 입력, 대상 유형·포트·상태 확인, HTTP/HTTPS 인증서·TLS 정책 입력을 정의하고 조합을 검증합니다.
3. ALB DNS와 Zone ID, ALB·Target Group·Listener ARN을 출력합니다.
4. README에 기존 Network·Security Group 연결, 대상 등록 주체, 내부 HTTP 및 공개 HTTPS 예시를 작성합니다.
5. mock provider 테스트로 기본 내부 HTTP, HTTPS, 공개형 HTTP 거부, 잘못된 네트워크 입력을 확인합니다.

### Unit 2 Implementation Plan: HTTP→HTTPS 리디렉션

1. HTTPS에서만 생성되는 포트 80 리디렉션 Listener와 ARN 출력을 작성합니다.
2. 인증서와 리디렉션 옵션의 조합, 기본 Listener 포트 80 충돌을 검증합니다.
3. README에 80/443 인바운드 규칙과 Target Group 전달 및 상태 확인 아웃바운드 규칙을 설명합니다.
4. mock provider 테스트로 301 리디렉션과 잘못된 옵션 거부를 확인합니다.
5. 두 Unit의 포맷, `terraform validate`, `terraform test`를 실행하고 실제 결과를 기록합니다. 코드와 문서를 검토한 뒤 `docs/README.md`를 갱신합니다.

### Approval

2026-09-23 사용자가 이 문서의 요구사항과 두 Unit의 구현 계획을 승인했습니다.

### Implementation

#### Unit 1: ALB와 기본 전달

- [`main.tf`](../../modules/alb/main.tf): 내부형 또는 공개형 ALB, Target Group, 기본 HTTP/HTTPS Listener
- [`variables.tf`](../../modules/alb/variables.tf): 네트워크·대상·Listener 입력과 이름, 포트, 인증서 조합 검증
- [`outputs.tf`](../../modules/alb/outputs.tf): ALB, Target Group, Listener 식별 정보
- [`versions.tf`](../../modules/alb/versions.tf): Terraform과 AWS Provider 버전 조건
- [`README.md`](../../modules/alb/README.md): 기본 사용법, 공개형 HTTPS, Security Group 및 대상 등록 경계

#### Unit 2: HTTP→HTTPS 리디렉션

- [`main.tf`](../../modules/alb/main.tf): 선택적 포트 80 리디렉션 Listener, 301 응답 및 포트 충돌 거부
- [`alb.tftest.hcl`](../../modules/alb/tests/alb.tftest.hcl): 기본 구성, HTTPS와 사용자 지정 포트, 리디렉션, 잘못된 입력 mock Plan 테스트

### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -recursive modules/alb` | PASS, 테스트 파일 포맷 정리 |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -check -recursive modules/alb` | PASS |
| 2026-09-23 | 임시 복사본에서 `TF_PLUGIN_CACHE_DIR=/tmp/terraform-plugin-cache /tmp/terraform-1.13.3/terraform init -backend=false -input=false -no-color` | PASS, AWS Provider v6.66.0 설치 |
| 2026-09-23 | 임시 복사본에서 `/tmp/terraform-1.13.3/terraform validate -no-color` | PASS, configuration is valid |
| 2026-09-23 | 임시 복사본에서 `/tmp/terraform-1.13.3/terraform test -no-color` | PASS, 최종 테스트 12 passed, 0 failed |
| 2026-09-23 | `git diff --check` | PASS, 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-23 | `! rg -n '[[:blank:]]+$' modules/alb docs/ai-dlc/alb-module.md docs/README.md` | PASS, 새 파일을 포함해 줄 끝 공백 없음 |

검증은 `/tmp/template-alb.2AnMy3/alb`의 복사본에서 실행했습니다. Terraform v1.13.3 실행 파일은 공식 SHA256 체크섬과 일치했습니다. AWS Provider 실행 소켓이 샌드박스에서 차단되어 처음 `validate`는 실패했고, `validate`와 `test`를 승인된 권한으로 실행했습니다. 최종 테스트 수정 후 `terraform test`를 다시 실행해 12개 모두 통과했습니다.

mock provider 테스트는 실제 AWS 계정의 Plan, Apply 또는 대상의 정상 상태를 증명하지 않습니다.

### Review

- 기본 구성은 내부형 IPv4 ALB이며, 공개형은 HTTPS와 인증서가 있어야 합니다. 선택적 HTTP Listener는 HTTPS로만 리디렉션합니다.
- Target Group의 `target_protocol`이 HTTPS이면 상태 확인도 HTTPS를 사용합니다. 기본값은 둘 다 HTTP입니다.
- 대상 등록과 ALB·대상 Security Group 규칙은 호출자가 관리합니다. 모듈에는 대상 Attachment가 없습니다.
- Subnet ID 중복은 거부하지만 서로 다른 AZ, 여유 IP, 유효한 인증서 및 실제 네트워크 연결은 mock 테스트로 확인할 수 없습니다.
- 환경별 Root Module이 없으므로 실제 AWS Plan과 Apply는 수행하지 않았습니다.

## 4. Operation

Deployment, Observability, Rollback, Runbook은 시작하지 않았습니다. 환경별 Root Module과 실제 AWS 연결은 별도 작업에서 다룹니다.

## 5. Listener 0개·여러 개 확장

기존 1~4절은 2026-09-23 승인된 단일 기본 Listener 구현과 검증의 기록입니다. 아래 확장은 후속 변경 요청이며, 위의 테스트 결과를 새 구조의 검증 결과로 간주하지 않습니다.

### Ideation

#### 문제 정의

현재 `aws_lb_listener.this`가 항상 하나 생성되고, 선택적인 리디렉션 Listener도 이 Listener 하나에 종속됩니다. Target Group도 하나로 고정되어 있습니다. 따라서 ALB만 먼저 만들 수 없고, 서로 다른 서비스로 전달하는 여러 Listener를 한 모듈 호출에서 정의할 수 없습니다.

#### 사용자와 성공 기준

환경별 Root Module 작성자는 Listener 없이 ALB를 준비하거나, 여러 Listener의 기본 전달 대상을 각각 선택할 수 있어야 합니다. Listener나 Target Group이 0개일 때 출력은 빈 Map이어야 하며, 각 Listener와 Target Group은 논리 키로 안정적으로 식별되어야 합니다.

#### Scope

- ALB 하나와 0개 이상의 Target Group, 0개 이상의 Listener
- Listener별 서로 다른 Target Group 선택 또는 같은 Target Group 공유
- 기본 전달 및 HTTP→HTTPS 리디렉션 동작
- 논리 키를 사용하는 Target Group ARN과 Listener ARN 출력 Map
- 기존 공개형 HTTPS 정책, 이름·포트 검증, 대상 등록 및 Security Group 경계 유지

#### Non-goals

- Host/Path Listener Rule, 가중치 라우팅, 고정 응답, 인증 동작
- 외부 Target Group ARN을 기본 동작에 직접 지정하는 방식
- Target Group 대상 등록과 실제 AWS 배포

2026-09-23 사용자가 Listener 0개와 여러 개의 경우를 추가로 제기했고, 여러 Listener가 **서로 다른 Target Group을 각각 선택**하도록 답했습니다. 이후 아래 입력 계약과 구현 계획을 승인했습니다.

### Inception

#### Functional Requirements

- `target_groups`는 논리 키를 사용하는 Map이며 기본값은 `{}`입니다. 각 항목은 AWS 이름과 대상 유형(`instance` 또는 `ip`), 프로토콜(HTTP 또는 HTTPS), 포트, 상태 확인 경로와 성공 코드를 설정합니다.
- `vpc_id`는 기본값 `null`로 바꿉니다. Target Group이 하나 이상이면 VPC ID가 필수이며, ALB만 생성할 때는 생략할 수 있습니다.
- `listeners`는 논리 키를 사용하는 Map이며 기본값은 `{}`입니다. 각 항목은 포트, 프로토콜(HTTP 또는 HTTPS), HTTPS 인증서와 TLS 정책, 기본 동작을 설정합니다.
- 기본 동작 `forward`는 같은 모듈의 `target_groups` 논리 키 하나를 참조합니다. 여러 Listener가 같은 키를 사용하거나 서로 다른 키를 사용할 수 있습니다.
- 기본 동작 `redirect`는 같은 모듈의 **전달 동작을 가진 HTTPS Listener** 논리 키 하나를 참조합니다. HTTP Listener만 리디렉션할 수 있고, 대상 포트로 301 응답을 보냅니다.
- 두 Map이 모두 비어 있으면 ALB만 만들고 `target_group_arns`와 `listener_arns`는 빈 Map을 출력합니다. Target Group만 정의하고 Listener를 비워 두는 구성도 허용합니다.
- Listener 포트는 ALB 안에서 중복될 수 없습니다. HTTPS에는 인증서가 필수이고 HTTP에는 인증서를 지정할 수 없습니다.
- 공개형 ALB에서 HTTP Listener는 HTTPS 리디렉션만 허용합니다. Listener가 없는 공개형 ALB도 준비 단계로 허용하되 트래픽을 받지 못한다는 점을 문서화합니다.
- 기존 단일 입력 `target_group_name`, `target_type`, `target_protocol`, `target_port`, `health_check_path`, `health_check_matcher`, `listener_protocol`, `listener_port`, `certificate_arn`, `tls_policy`, `enable_http_redirect`와 단일 ARN 출력은 Map 계약으로 교체합니다. ALB 자체 입력과 `load_balancer_arn`, `dns_name`, `zone_id` 출력은 유지합니다.

제안하는 입력 형식은 다음과 같습니다. `port`는 1~65535 정수이며, 생략 가능한 대상 설정은 기존 모듈의 기본값을 사용합니다.

```hcl
target_groups = {
  web = {
    name                 = "sample-web"
    target_type          = "instance" # 기본값
    protocol             = "HTTP"     # 기본값
    port                 = 80         # 기본값
    health_check_path    = "/"        # 기본값
    health_check_matcher = "200"      # 기본값
  }
}

listeners = {
  web_https = {
    port            = 443
    protocol        = "HTTPS"
    certificate_arn = "arn:aws:acm:..."
    tls_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06" # 기본값
    default_action  = { type = "forward", target_group_key = "web" }
  }
  web_http = {
    port           = 80
    protocol       = "HTTP"
    default_action = { type = "redirect", redirect_to_listener_key = "web_https" }
  }
}
```

#### Non-Functional Requirements

- Map 키는 Plan 시점에 알아야 하며 `for_each` 주소의 안정적인 식별자로 사용합니다.
- 잘못된 Target Group 참조, HTTPS 리디렉션 대상 누락, 중복 포트와 잘못된 인증서 조합은 실제 AWS 호출 전에 거부합니다.
- AWS 자격 증명 없이 mock provider Plan 테스트로 0개, 1개, 여러 개의 Listener 및 Target Group과 잘못된 조합을 확인합니다.
- 기존 저장소에는 `modules/alb`을 호출하는 Root Module이 없고 ALB 구현은 미커밋입니다. 외부에서 이미 이 코드를 사용했다면 단일 리소스에서 Map 리소스로 주소가 바뀌므로 별도 state 이전이 필요할 수 있습니다.

#### Architecture

```text
Root Module
  target_groups = { web = {...}, admin = {...} }
  listeners = {
    web_https   = { port = 443,  action = forward(web) }
    admin_https = { port = 8443, action = forward(admin) }
    web_http    = { port = 80,   action = redirect(web_https) }
  }
        |
        v
  modules/alb
    aws_lb.this
    aws_lb_target_group.this[논리 키]  0..N
    aws_lb_listener.forward[논리 키]   0..N
    aws_lb_listener.redirect[논리 키]  0..N
        |
        v
  target_group_arns, listener_arns (논리 키별 Map)
```

#### Unit of Work

1. Target Group과 Listener를 Map 입력 및 `for_each` 리소스로 재구성하고, 기본 전달과 HTTPS 리디렉션을 Listener별로 설정합니다.

#### Acceptance Criteria

- 빈 Map mock Plan에는 ALB 하나만 있고 Target Group 및 Listener는 없습니다. 두 출력 Map은 비어 있습니다.
- Listener 1개와 Target Group 1개 구성은 기존 HTTP 또는 HTTPS 전달 동작을 재현합니다.
- Listener 3개가 2개 Target Group을 각각 선택하거나 공유하고, HTTP Listener 하나가 지정한 HTTPS Listener로 301 리디렉션합니다.
- 중복 Listener 포트, 없는 Target Group 또는 HTTPS 리디렉션 대상, 공개형 HTTP 전달, 인증서 없는 HTTPS를 거부합니다.
- Terraform 포맷, `terraform validate`, `terraform test`를 실제 실행하고 날짜·명령·결과를 별도로 기록합니다.

### Construction: Design과 Implementation Plan

| 결정 | 내용 |
|---|---|
| 개수 제어 | 빈 Map이면 0개, 논리 키마다 하나씩 `for_each`로 생성 |
| 기본 동작 | Listener마다 `forward`의 Target Group 키 또는 `redirect`의 HTTPS Listener 키를 명시. 리디렉션은 전달 Listener 생성 후 배치 |
| 출력 | 기존 단일 ARN 출력 대신 논리 키별 ARN Map 사용 |
| 기본 구성 | ALB만 생성. Listener와 Target Group은 호출자가 명시적으로 추가 |
| 기존 코드 전환 | 단일 입력과 테스트 및 README 예시를 Map 형식으로 함께 변경 |

1. `modules/alb`의 Target Group 및 Listener 입력과 출력을 Map 계약으로 바꿉니다. ALB 자체 입력은 유지합니다.
2. `aws_lb_target_group`과 `aws_lb_listener`에 `for_each`를 적용하고 Listener별 전달 또는 리디렉션 기본 동작을 구성합니다.
3. Map 키, 이름, 포트, 프로토콜, 인증서, 대상 키, 리디렉션 키 및 공개형 정책의 입력 제약을 검증합니다.
4. README에 ALB만 생성하는 예시와 여러 Listener가 서로 다른 Target Group을 선택하는 예시를 작성합니다. Root Module의 대상 등록 예시도 Map 출력으로 고칩니다.
5. mock provider 테스트를 0개·1개·여러 개 구성과 잘못된 조합에 맞춰 갱신합니다. 포맷, 구성 검증, 테스트를 실행한 뒤 이 문서와 `docs/README.md`에 실제 결과를 기록하고 Review합니다.

#### Approval

2026-09-23 사용자가 이 확장의 요구사항과 구현 계획을 승인했습니다.

#### 문서 검토

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `git diff --check` | PASS, 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-23 | `! rg -n '[[:blank:]]+$' docs/README.md docs/ai-dlc/alb-module.md` | PASS, 두 문서에 줄 끝 공백 없음 |

이 표는 승인 전 문서 검토 기록입니다. 확장 코드의 검증 결과는 아래에 별도로 기록합니다.

#### Implementation

- [`main.tf`](../../modules/alb/main.tf): ALB 하나, 논리 키별 Target Group, 전달 Listener와 리디렉션 Listener. 리디렉션 Listener는 전달 Listener 생성 이후에 배치
- [`variables.tf`](../../modules/alb/variables.tf): 빈 Map 기본값, Target Group과 Listener별 설정, VPC 조건 및 참조·포트·프로토콜 검증
- [`outputs.tf`](../../modules/alb/outputs.tf): Target Group과 Listener ARN을 논리 키별 Map으로 출력
- [`README.md`](../../modules/alb/README.md): ALB만 생성, 단일 Listener, 여러 서비스 전달 및 대상 등록 예시
- [`alb.tftest.hcl`](../../modules/alb/tests/alb.tftest.hcl): 0개·1개·여러 개 구성 및 잘못된 조합 mock Plan 테스트

구현에서는 전달 Listener와 리디렉션 Listener를 별도 `aws_lb_listener` 리소스 Map으로 나눴습니다. 리디렉션 대상인 HTTPS Listener가 먼저 생성되도록 의존성을 명시하기 위한 결정이며, 승인된 입력·출력 계약은 유지합니다.

#### Test

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -recursive modules/alb` | PASS, 확장 테스트 파일 포맷 정리 |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -check -recursive modules/alb` | PASS |
| 2026-09-23 | 임시 복사본에서 `/tmp/terraform-1.13.3/terraform validate -no-color` | PASS, configuration is valid, 경고 없음 |
| 2026-09-23 | 임시 복사본에서 `/tmp/terraform-1.13.3/terraform test -no-color` | PASS, 15 passed, 0 failed |
| 2026-09-23 | `git diff --check` | PASS, 추적 중인 문서 변경에 공백 오류 없음 |
| 2026-09-23 | `! rg -n '[[:blank:]]+$' modules/alb docs/ai-dlc/alb-module.md docs/README.md` | PASS, 새 파일을 포함해 줄 끝 공백 없음 |

확장 검증은 기존에 AWS Provider v6.66.0으로 초기화한 `/tmp/template-alb.2AnMy3/alb` 복사본에 변경 파일을 복사해 실행했습니다. mock provider Plan 테스트 결과는 실제 AWS Plan, Apply 및 Listener 트래픽 성공을 증명하지 않습니다.

#### Review

- 두 Map이 비면 내부형 또는 공개형 ALB만 만들어지고 두 ARN 출력은 빈 Map입니다. Listener가 없는 ALB는 요청을 받지 못합니다.
- Listener별 전달 Target Group을 선택하거나 공유할 수 있습니다. HTTP→HTTPS 리디렉션은 같은 Map의 전달 HTTPS Listener를 참조합니다.
- 중복 Listener 포트, 잘못된 Target Group 및 리디렉션 대상, 공개형 HTTP 전달, HTTPS 인증서 누락을 Plan 단계에서 거부합니다.
- `vpc_id`는 Target Group이 있을 때만 필요합니다. 실제 Subnet AZ, 인증서, Security Group 경로와 대상 상태는 mock 테스트로 확인할 수 없습니다.
- 기존 단일 입력과 출력은 Map 계약으로 교체했습니다. 저장소에는 이 모듈을 호출하는 Root Module이 없지만 외부에서 이전 코드를 사용했다면 입력 변경과 Terraform state 주소 이전을 검토해야 합니다.

#### Git 기록

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m "feat(alb): support optional listeners and target groups"` | 구현과 문서 커밋 `50b854f` 생성 |
| 2026-09-23 | `git push origin main` | PASS, `aaba7dc..50b854f` 원격 main에 반영 |
| 2026-09-23 | `git ls-remote origin refs/heads/main` | PASS, `50b854fa2beb72160dabe0df83f363c6209bae1d` 확인 |

## 근거

- [AWS ALB Subnet 및 Security Group 요구사항](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
- [AWS ALB Target Group과 대상 유형](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html)
- [AWS HTTPS Listener와 인증서](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html)
- [AWS ALB TLS 보안 정책](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)
- [Terraform AWS Provider ALB](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)
- [Terraform AWS Provider Listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener)
- [Terraform AWS Provider Target Group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group)
- [AWS ALB Listener 동작과 Listener가 없는 상태](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [AWS CreateListener 중복 포트 오류](https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateListener.html)
- [Terraform `for_each`와 논리 키](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)
