# EC2 module

EC2 인스턴스 하나를 생성하는 로컬 Terraform 모듈입니다.

이 모듈은 VPC, Subnet, Security Group, IAM Role, IAM Instance Profile, Key Pair, Elastic IP를 생성하지 않습니다. 호출하는 Root Module이 필요한 값을 전달해야 합니다.

## 기본 보안 설정

- Root EBS 볼륨은 gp3, 암호화, 종료 시 삭제로 고정됩니다.
- Instance Metadata Service는 IMDSv2만 허용합니다.
- Public IP 자동 연결은 기본적으로 꺼져 있습니다.
- 구매 옵션은 기본적으로 On-Demand입니다.
- `user_data`는 Terraform state에 평문으로 남을 수 있으므로 비밀번호와 토큰을 넣지 마세요.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | 인스턴스와 Root EBS 볼륨의 Name 태그를 정합니다. |
| `ami_id` | `string` | 필수 | 인스턴스에 사용할 AMI ID입니다. |
| `instance_type` | `string` | 필수 | 인스턴스 유형입니다. |
| `purchase_option` | `string` | `"on-demand"` | `on-demand` 또는 일회성 `spot`을 선택합니다. |
| `subnet_id` | `string` | 필수 | 인스턴스를 생성할 Subnet ID입니다. |
| `security_group_ids` | `set(string)` | 필수 | 연결할 Security Group ID입니다. 하나 이상 필요합니다. |
| `key_name` | `string` | `null` | 연결할 EC2 Key Pair 이름입니다. |
| `iam_instance_profile` | `string` | `null` | 연결할 IAM Instance Profile 이름입니다. |
| `user_data` | `string` | `null` | 부트스트랩 스크립트입니다. State에 평문으로 남을 수 있습니다. |
| `associate_public_ip_address` | `bool` | `false` | Public IP 자동 연결 여부입니다. |
| `monitoring` | `bool` | `false` | 상세 모니터링 활성화 여부입니다. |
| `root_volume_size` | `number` | `20` | gp3 Root EBS 크기입니다. 단위는 GiB입니다. |
| `root_volume_kms_key_id` | `string` | `null` | Root EBS 암호화에 사용할 KMS 키 ID 또는 ARN입니다. 생략하면 계정 기본 키를 사용합니다. |
| `tags` | `map(string)` | `{}` | 인스턴스와 Root EBS에 붙일 추가 태그입니다. Name은 모듈 이름이 우선합니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `id` | 생성된 인스턴스 ID입니다. |
| `arn` | 인스턴스 ARN입니다. |
| `availability_zone` | 인스턴스가 생성된 AZ입니다. |
| `private_ip` | Private IP 주소입니다. |
| `private_dns` | Private DNS 이름입니다. |
| `public_ip` | Public IP 주소입니다. Public IP가 없으면 비어 있습니다. |
| `public_dns` | Public DNS 이름입니다. Public IP가 없으면 비어 있습니다. |

## 사용 예시

```hcl
provider "aws" {
  region = "ap-northeast-2"
}

module "app" {
  source = "../../modules/ec2"

  name               = "sample-dev-app"
  ami_id             = "ami-0123456789abcdef0"
  instance_type      = "t3.micro"
  subnet_id          = "subnet-0123456789abcdef0"
  security_group_ids = ["sg-0123456789abcdef0"]

  iam_instance_profile = "sample-dev-app"
  root_volume_size     = 30

  tags = {
    Environment = "dev"
    Project     = "sample"
  }
}
```

## Spot 사용

`purchase_option`을 `spot`으로 지정하면 일회성 Spot Instance를 생성합니다. AWS가 Spot Instance를 회수하면 종료되며, 이 단일 인스턴스 모듈은 자동으로 대체 인스턴스를 만들지 않습니다.

```hcl
module "batch" {
  source = "../../modules/ec2"

  name               = "sample-dev-batch"
  ami_id             = "ami-0123456789abcdef0"
  instance_type      = "t3.micro"
  purchase_option    = "spot"
  subnet_id          = "subnet-0123456789abcdef0"
  security_group_ids = ["sg-0123456789abcdef0"]
}
```

`purchase_option`을 변경하면 기존 EC2 인스턴스가 교체됩니다. 중단 후 자동 복구가 필요한 워크로드에는 Auto Scaling Group 또는 EC2 Fleet 사용을 검토하세요.

여러 인스턴스가 필요하면 모듈 내부를 바꾸지 말고 호출하는 Root Module에서 `for_each`를 사용하세요.

## 검증

호출하는 Root Module에서 다음 명령을 실행하세요.

```sh
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```
