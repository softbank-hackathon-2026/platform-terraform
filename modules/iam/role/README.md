# IAM Role 모듈

이 모듈은 IAM Role을 만들고 기존 또는 새 관리형 Policy를 연결합니다. EC2에 연결할 때는 Instance Profile도 선택적으로 만듭니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | Role과 선택적 Instance Profile의 이름입니다. |
| `assume_role_policy_json` | `string` | 필수 | Role을 사용할 주체를 정하는 신뢰 정책 JSON입니다. |
| `managed_policy_arns` | `map(string)` | `{}` | 논리 키별 관리형 권한 Policy ARN입니다. |
| `create_instance_profile` | `bool` | `false` | EC2에 연결할 Instance Profile 생성 여부입니다. |
| `tags` | `map(string)` | `{}` | Role과 선택적 Instance Profile에 붙일 태그입니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `role_name` | 생성된 Role 이름입니다. |
| `role_arn` | 생성된 Role ARN입니다. |
| `instance_profile_name` | EC2 모듈에 전달할 Instance Profile 이름입니다. 생성하지 않으면 `null`입니다. |
| `instance_profile_arn` | Instance Profile ARN입니다. 생성하지 않으면 `null`입니다. |

`assume_role_policy_json`은 Role에 직접 저장되는 리소스 기반 신뢰 정책입니다. Role에 권한을 부여하는 인라인 권한 정책인 `aws_iam_role_policy`와 다릅니다. 이 모듈은 인라인 권한 정책을 만들지 않으며, 관리형 권한 Policy는 `managed_policy_arns`로 연결합니다.

## 기존 Policy를 EC2 Role에 연결

이미 생성된 고객 관리 Policy의 ARN을 `managed_policy_arns`에 넣습니다. 아래 ARN의 계정 ID와 Policy 이름은 실제 값으로 바꿔야 합니다.

```hcl
module "app_role" {
  source = "../../modules/iam/role"

  name = "sample-app-role"
  assume_role_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  managed_policy_arns = {
    existing = "arn:aws:iam::123456789012:policy/existing-app-policy"
  }

  create_instance_profile = true
}
```

`managed_policy_arns`의 키인 `existing`은 Terraform에서 연결을 식별하는 이름입니다. AWS 관리형 Policy도 ARN을 같은 방식으로 넣을 수 있습니다. 이 모듈을 사용해 새로 만든 Policy는 `existing`의 값 대신 `module.object_read_policy.policy_arn`처럼 출력 ARN을 연결합니다. 인라인 권한 정책은 독립된 ARN이 없으므로 이 입력으로 연결할 수 없습니다.

EC2 모듈은 Role ARN이 아니라 Instance Profile 이름을 입력받습니다. 다음 예시의 AMI, Subnet, Security Group ID는 실제 환경 값으로 바꿔야 합니다.

```hcl
module "app" {
  source = "../../modules/ec2"

  name                 = "sample-app"
  ami_id               = "ami-0123456789abcdef0"
  instance_type        = "t3.micro"
  subnet_id            = "subnet-0123456789abcdef0"
  security_group_ids   = ["sg-0123456789abcdef0"]
  iam_instance_profile = module.app_role.instance_profile_name
}
```

## Instance Profile이 필요 없는 경우

`create_instance_profile`은 EC2용 선택지입니다. EC2는 Role을 Instance Profile에 담아 연결하므로 위 예시에서는 `true`가 필요합니다. 다른 서비스가 Role ARN을 직접 받는다면 이 입력을 생략하고 `module.app_role.role_arn`을 전달합니다. 생략하면 Instance Profile은 만들지 않으며 `instance_profile_name`과 `instance_profile_arn`은 `null`입니다.

`create_instance_profile = false`인 상태에서 EC2 모듈에 `iam_instance_profile = module.app_role.instance_profile_name`을 전달해도 오류가 나지 않습니다. 전달되는 값이 `null`이어서 EC2의 선택적 Instance Profile 설정이 생략되고, 인스턴스에는 이 Role이 연결되지 않습니다. EC2에 Role이 필요하면 `create_instance_profile = true`로 설정합니다.

Instance Profile은 관리형 Policy 연결을 기다리도록 설정했지만, IAM 전파 지연으로 생성 직후 서비스 연결이 바로 반영되지 않을 수 있습니다. 신뢰 정책의 Principal과 연결할 권한 Policy는 호출자가 서비스별로 정해야 합니다.

## 참고

- [AWS IAM Role의 신뢰 정책과 권한 정책](https://docs.aws.amazon.com/IAM/latest/UserGuide/when-to-use-iam.html)
- [EC2에서 IAM Role과 Instance Profile 사용](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html)
- [Terraform 관리형 Policy 연결 리소스](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)
