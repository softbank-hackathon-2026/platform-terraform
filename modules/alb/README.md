# ALB 모듈

Application Load Balancer 하나와 0개 이상의 Target Group, Listener를 생성합니다. `target_groups`와 `listeners`는 논리 키를 사용하는 Map이며 기본값은 빈 Map입니다. 여러 Listener가 같은 Target Group을 공유하거나 각자 다른 Target Group을 선택할 수 있습니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | ALB 이름입니다. 1~32자이며 `internal-`로 시작할 수 없습니다. |
| `vpc_id` | `string` | `null` | Target Group이 속할 VPC ID입니다. Target Group을 만들 때 필요합니다. |
| `subnet_ids` | `list(string)` | 필수 | ALB를 배치할 Subnet ID입니다. 중복 없이 2개 이상 필요합니다. |
| `security_group_ids` | `list(string)` | 필수 | ALB에 연결할 Security Group ID입니다. 하나 이상 필요합니다. |
| `internal` | `bool` | `true` | 내부형 ALB 여부입니다. `false`이면 공개형입니다. |
| `target_groups` | `map(object)` | `{}` | 논리 키별 Target Group 정의입니다. |
| `listeners` | `map(object)` | `{}` | 논리 키별 Listener 정의입니다. |
| `enable_deletion_protection` | `bool` | `false` | ALB 삭제 보호를 켭니다. |
| `tags` | `map(string)` | `{}` | ALB와 Target Group에 붙일 태그입니다. Name은 모듈 이름이 우선합니다. |

`target_groups`의 각 값은 다음 속성을 사용합니다.

| 내부 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | Target Group 이름입니다. |
| `target_type` | `string` | `"instance"` | 대상을 `instance` 또는 `ip`로 지정합니다. |
| `protocol` | `string` | `"HTTP"` | 대상 통신과 상태 확인에 사용할 `HTTP` 또는 `HTTPS`입니다. |
| `port` | `number` | `80` | 대상 통신 포트입니다. |
| `health_check_path` | `string` | `"/"` | 상태 확인 경로입니다. `/`로 시작해야 합니다. |
| `health_check_matcher` | `string` | `"200"` | 상태 확인 성공 응답 코드입니다. |

`listeners`의 각 값과 내부 `default_action`은 다음 속성을 사용합니다.

| 내부 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `port` | `number` | 필수 | Listener 포트입니다. 같은 ALB 안에서 중복될 수 없습니다. |
| `protocol` | `string` | 필수 | `HTTP` 또는 `HTTPS`입니다. |
| `certificate_arn` | `string` | `null` | HTTPS Listener에 필요한 인증서 ARN입니다. |
| `tls_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | HTTPS Listener의 TLS 정책입니다. |
| `default_action` | `object` | 필수 | Listener의 기본 전달 또는 리디렉션 동작입니다. |
| `default_action.type` | `string` | 필수 | `forward` 또는 `redirect`입니다. |
| `default_action.target_group_key` | `string` | `null` | `forward`일 때 전달할 `target_groups` 논리 키입니다. |
| `default_action.redirect_to_listener_key` | `string` | `null` | `redirect`일 때 이동할 HTTPS Listener 논리 키입니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `load_balancer_arn` | ALB ARN입니다. |
| `dns_name` | ALB DNS 이름입니다. |
| `zone_id` | ALB의 Route 53 Hosted Zone ID입니다. |
| `target_group_arns` | 논리 키별 Target Group ARN Map입니다. 없으면 `{}`입니다. |
| `listener_arns` | 논리 키별 Listener ARN Map입니다. 없으면 `{}`입니다. |

## Listener 없이 ALB만 만들기

```hcl
module "alb" {
  source = "../../modules/alb"

  name = "sample-dev-alb"
  subnet_ids = [
    module.network.private_subnet_ids["app_a"],
    module.network.private_subnet_ids["app_c"],
  ]
  security_group_ids = [module.alb_security_group.security_group_id]
}
```

이 구성은 내부형 IPv4 ALB만 만듭니다. `module.alb.target_group_arns`와 `module.alb.listener_arns`는 모두 빈 Map입니다. **Listener가 없는 ALB는 클라이언트 요청을 받지 못합니다.** Target Group만 미리 만들고 싶다면 `vpc_id`와 `target_groups`를 지정하고 `listeners`는 비워 두세요.

## Listener 하나로 전달하기

```hcl
module "alb" {
  source = "../../modules/alb"

  name = "sample-dev-alb"
  subnet_ids = [
    module.network.private_subnet_ids["app_a"],
    module.network.private_subnet_ids["app_c"],
  ]
  security_group_ids = [module.alb_security_group.security_group_id]
  vpc_id             = module.network.vpc_id

  target_groups = {
    web = {
      name              = "sample-dev-web"
      port              = 8080
      health_check_path = "/health"
    }
  }

  listeners = {
    web_http = {
      port           = 80
      protocol       = "HTTP"
      default_action = { type = "forward", target_group_key = "web" }
    }
  }
}
```

이 내부형 Listener는 HTTP 80 요청을 `web` Target Group의 HTTP 8080으로 보냅니다. Target Group의 `target_type`은 기본 `instance`이고 상태 확인 성공 코드는 기본 `200`입니다.

## Listener 여러 개로 서로 다른 서비스 전달하기

```hcl
module "alb" {
  source = "../../modules/alb"

  name = "sample-prd-alb"
  subnet_ids = [
    module.network.public_subnet_ids["web_a"],
    module.network.public_subnet_ids["web_c"],
  ]
  security_group_ids = [module.alb_security_group.security_group_id]
  vpc_id             = module.network.vpc_id
  internal           = false

  target_groups = {
    web = {
      name              = "sample-prd-web"
      port              = 8080
      health_check_path = "/health"
    }
    admin = {
      name        = "sample-prd-admin"
      target_type = "ip"
      protocol    = "HTTPS"
      port        = 8443
    }
  }

  listeners = {
    web_https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate.web.arn
      default_action  = { type = "forward", target_group_key = "web" }
    }
    admin_https = {
      port            = 8443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate.admin.arn
      default_action  = { type = "forward", target_group_key = "admin" }
    }
    web_http = {
      port           = 80
      protocol       = "HTTP"
      default_action = { type = "redirect", redirect_to_listener_key = "web_https" }
    }
  }

  enable_deletion_protection = true
}
```

`web_https`와 `admin_https`는 각자의 Target Group으로 전달합니다. `web_http`는 `web_https`의 443번 포트로 301 리디렉션합니다. 다른 Listener가 같은 Target Group을 사용하려면 `target_group_key`에 같은 논리 키를 지정하면 됩니다.

## 입력 제약과 보안 설정

- ALB의 기본값은 `internal = true`입니다. 공개형 ALB에서 HTTP Listener는 HTTPS로 리디렉션할 때만 사용할 수 있습니다.
- HTTPS Listener에는 기존 인증서 ARN이 필요합니다. 기본 TLS 정책은 `ELBSecurityPolicy-TLS13-1-2-2021-06`이며 Listener별 `tls_policy`로 바꿀 수 있습니다.
- Listener 포트는 ALB 안에서 중복될 수 없습니다. 리디렉션 대상은 이 모듈에 정의된 전달 동작의 HTTPS Listener여야 합니다.
- Target Group이 하나 이상이면 `vpc_id`가 필요합니다. Target Group의 `target_type`은 `instance` 또는 `ip`, `protocol`은 HTTP 또는 HTTPS, `port`의 기본값은 80입니다. 상태 확인에는 같은 프로토콜을 사용합니다.
- ALB와 Target Group 이름은 각각 32자 이하여야 하고 AWS 계정 및 Region에서 고유해야 합니다.
- `subnet_ids`에는 ID가 다른 두 Subnet이 필요합니다. 실제 AZ가 다른지와 남은 IP가 충분한지는 AWS에서 확인합니다.
- `enable_deletion_protection = true`이면 ALB를 제거하기 전에 이 값을 해제해야 합니다.

## 대상 등록과 Security Group

모듈은 EC2 인스턴스나 IP 대상을 등록하지 않습니다. `target_type = "instance"`인 `web` Target Group은 Root Module에서 다음처럼 연결합니다.

```hcl
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = module.alb.target_group_arns["web"]
  target_id        = module.web_instance.id
  port             = 8080
}
```

기존 Security Group 모듈은 인바운드와 아웃바운드 규칙 없이 시작합니다. ALB Security Group에는 사용 중인 Listener 포트의 인바운드와 대상 및 상태 확인 포트의 아웃바운드가 필요합니다. 대상 Security Group에는 ALB Security Group에서 오는 해당 포트의 인바운드가 필요합니다. 공개형 ALB에는 Public Subnet의 인터넷 경로와 같은 Region의 유효한 인증서도 필요합니다.

`load_balancer_arn`, `dns_name`, `zone_id`는 단일 값으로 출력합니다. `target_group_arns`와 `listener_arns`는 논리 키별 ARN Map이며 해당 리소스가 없으면 빈 Map입니다. VPC, Subnet, Security Group, 인증서, DNS 레코드, 대상 등록과 추가 Listener Rule은 호출하는 Root Module이 관리합니다. 이 모듈은 실제 AWS에서 아직 Plan 또는 Apply하지 않았습니다.

## 검증

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```
