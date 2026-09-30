# Security Group 모듈

VPC 안에 Security Group 하나를 만들고, 명시한 인바운드 및 아웃바운드 규칙만 추가합니다. AWS가 새 Security Group에 넣는 기본 전체 아웃바운드 허용 규칙은 AWS Provider가 생성 시 제거합니다. 실제 계정에서의 결과는 아직 확인하지 않았습니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | Security Group 이름입니다. |
| `vpc_id` | `string` | 필수 | Security Group을 생성할 VPC ID입니다. |
| `ingress_rules` | `map(object)` | `{}` | 논리 키별 인바운드 규칙입니다. 기본값은 규칙 없음입니다. |
| `egress_rules` | `map(object)` | `{}` | 논리 키별 아웃바운드 규칙입니다. 기본값은 규칙 없음입니다. |
| `tags` | `map(string)` | `{}` | Security Group에 붙일 추가 태그입니다. Name은 `name`이 우선합니다. |

`ingress_rules`와 `egress_rules`의 각 규칙은 같은 구조를 사용합니다.

| 내부 속성 | 타입 | 역할 |
|---|---|---|
| `ip_protocol` | `string` | 필수. `tcp`, `udp`, `-1` 중 하나입니다. |
| `from_port` | `number` | TCP/UDP에서는 필수인 시작 포트입니다. `-1`에서는 생략합니다. |
| `to_port` | `number` | TCP/UDP에서는 필수인 끝 포트입니다. `-1`에서는 생략합니다. |
| `cidr_ipv4` | `string` | IPv4 CIDR 대상입니다. 아래 Security Group ID와 둘 중 하나만 지정합니다. |
| `referenced_security_group_id` | `string` | 다른 Security Group 대상입니다. IPv4 CIDR과 둘 중 하나만 지정합니다. |
| `description` | `string` | 규칙에 붙일 선택적 설명입니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `security_group_id` | 생성된 Security Group ID입니다. |
| `security_group_arn` | 생성된 Security Group ARN입니다. |

## 기본 사용법

```hcl
module "app_security_group" {
  source = "../../modules/security-group"

  name   = "sample-app"
  vpc_id = module.network.vpc_id

  ingress_rules = {
    https = {
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "10.10.0.0/16"
    }
  }

  egress_rules = {
    database = {
      ip_protocol                  = "tcp"
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.database_security_group.security_group_id
    }
  }
}

module "app" {
  source = "../../modules/ec2"

  # 다른 필수 입력은 생략했습니다.
  security_group_ids = [module.app_security_group.security_group_id]
}
```

`ingress_rules`와 `egress_rules`의 기본값은 빈 Map입니다. 전체 프로토콜을 허용하려면 `ip_protocol = "-1"`로 지정하고 포트는 생략합니다. 각 규칙에는 `cidr_ipv4` 또는 `referenced_security_group_id` 중 하나만 지정합니다. 논리 키를 바꾸면 Terraform은 해당 규칙을 다른 리소스로 취급합니다.

IPv6, Prefix List, ICMP 규칙과 서비스별 기본 허용 정책은 이 모듈의 범위에 없습니다. Security Group ID와 ARN은 출력값으로 제공합니다.
