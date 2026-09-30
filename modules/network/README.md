# Network module

IPv4 VPC, Public Subnet, Private Subnet, Route Table과 선택적 NAT Gateway를 생성하는 로컬 Terraform 모듈입니다.

Security Group, VPC Endpoint, VPC Peering, Transit Gateway, VPN, Network Firewall과 Route 53 Resolver는 생성하지 않습니다.

## 기본 동작

- VPC DNS resolution과 DNS hostname을 활성화합니다.
- 모든 Subnet의 Public IP 자동 할당을 끕니다.
- Private Subnet마다 Route Table을 하나씩 생성합니다.
- NAT Gateway는 기본적으로 생성하지 않습니다.
- 입력 태그보다 모듈의 `Name` 태그를 우선합니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | VPC와 관련 리소스 이름의 접두사입니다. |
| `vpc_cidr` | `string` | 필수 | VPC의 IPv4 CIDR입니다. |
| `public_subnets` | `map(object)` | `{}` | 논리 키별 Public Subnet 정의입니다. |
| `private_subnets` | `map(object)` | 필수 | 논리 키별 Private Subnet 정의입니다. 하나 이상 필요합니다. |
| `nat_gateway_mode` | `string` | `"none"` | `none`, `regional`, `zonal` 중 NAT 구성을 선택합니다. |
| `zonal_nat_subnet_keys` | `map(string)` | `{}` | Zonal NAT를 배치할 Public Subnet 논리 키를 AZ별로 지정합니다. |
| `tags` | `map(string)` | `{}` | 네트워크 리소스에 붙일 추가 태그입니다. Name은 모듈 이름이 우선합니다. |

`public_subnets`와 `private_subnets`의 각 값은 같은 구조를 사용합니다.

| 내부 속성 | 타입 | 역할 |
|---|---|---|
| `availability_zone` | `string` | Subnet을 생성할 AZ입니다. |
| `cidr_block` | `string` | Subnet의 IPv4 CIDR입니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `vpc_id` | 생성된 VPC ID입니다. |
| `vpc_cidr_block` | VPC의 IPv4 CIDR입니다. |
| `public_subnet_ids` | 논리 키별 Public Subnet ID Map입니다. 없으면 `{}`입니다. |
| `private_subnet_ids` | 논리 키별 Private Subnet ID Map입니다. |
| `public_route_table_id` | Public Route Table ID입니다. Public Subnet이 없으면 `null`입니다. |
| `private_route_table_ids` | 논리 키별 Private Route Table ID Map입니다. |
| `nat_gateway_ids_by_az` | AZ별 NAT Gateway ID Map입니다. NAT가 없으면 `{}`입니다. |

## NAT 모드

| 모드 | 동작 |
|---|---|
| `none` | NAT Gateway와 Private 인터넷 기본 경로를 생성하지 않습니다. |
| `regional` | Regional NAT Gateway 하나를 생성하고 모든 Private Route를 연결합니다. |
| `zonal` | Private Subnet이 사용하는 각 AZ에 EIP와 Zonal NAT Gateway를 생성합니다. |

NAT Gateway에는 시간 및 데이터 처리 비용이 발생합니다. `nat_gateway_mode` 변경 시 NAT Gateway와 EIP가 생성되거나 제거되고 인터넷 송신이 일시적으로 중단될 수 있으므로 적용 전에 Plan을 확인하세요.

## NAT 없이 사용

```hcl
module "network" {
  source = "../../modules/network"

  name     = "sample-dev"
  vpc_cidr = "10.10.0.0/16"

  private_subnets = {
    app_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.10.10.0/24"
    }
    app_c = {
      availability_zone = "ap-northeast-2c"
      cidr_block        = "10.10.11.0/24"
    }
  }

  tags = {
    Environment = "dev"
    Project     = "sample"
  }
}
```

## Regional NAT 사용

Regional NAT는 VPC에 생성되며 Subnet을 선택하지 않습니다. AWS가 EIP와 AZ 확장을 관리합니다.

```hcl
module "network" {
  source = "../../modules/network"

  name             = "sample-prd"
  vpc_cidr         = "10.30.0.0/16"
  nat_gateway_mode = "regional"

  private_subnets = {
    app_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.30.10.0/24"
    }
    app_c = {
      availability_zone = "ap-northeast-2c"
      cidr_block        = "10.30.11.0/24"
    }
  }
}
```

## Zonal NAT 사용

Zonal NAT는 `zonal_nat_subnet_keys`에서 AZ별 Public Subnet을 직접 선택합니다. 같은 AZ에 Public Subnet이 여러 개 있어도 NAT를 배치할 Subnet을 구분할 수 있습니다.

```hcl
module "network" {
  source = "../../modules/network"

  name             = "sample-prd"
  vpc_cidr         = "10.30.0.0/16"
  nat_gateway_mode = "zonal"

  public_subnets = {
    web_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.30.0.0/24"
    }
    nat_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.30.1.0/24"
    }
    nat_c = {
      availability_zone = "ap-northeast-2c"
      cidr_block        = "10.30.2.0/24"
    }
  }

  private_subnets = {
    app_a = {
      availability_zone = "ap-northeast-2a"
      cidr_block        = "10.30.10.0/24"
    }
    app_c = {
      availability_zone = "ap-northeast-2c"
      cidr_block        = "10.30.11.0/24"
    }
  }

  zonal_nat_subnet_keys = {
    "ap-northeast-2a" = "nat_a"
    "ap-northeast-2c" = "nat_c"
  }
}
```

## EC2 모듈과 연결

```hcl
module "app" {
  source = "../../modules/ec2"

  name               = "sample-dev-app"
  ami_id             = "ami-0123456789abcdef0"
  instance_type      = "t3.micro"
  subnet_id          = module.network.private_subnet_ids["app_a"]
  security_group_ids = [aws_security_group.app.id]
}
```

Security Group은 Network 모듈 밖에서 만들고 `module.network.vpc_id`를 사용하세요.

## 입력 검증 범위

모듈은 IPv4 CIDR 형식과 동일한 CIDR 문자열의 중복을 검사합니다. Subnet CIDR이 VPC 범위에 포함되는지와 서로 부분적으로 겹치는지는 AWS가 리소스 생성 시 검사하므로 호출자가 적용 전에 확인해야 합니다.

## 검증

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```
