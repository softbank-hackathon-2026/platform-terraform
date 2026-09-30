# KMS 모듈

고객 관리형 대칭 암호화 KMS 키 하나를 만듭니다. 별칭은 선택 사항입니다. 자동 키 재료 회전은 기본 활성화하며, 키 삭제 대기 기간은 기본 30일입니다.

## 기본 사용법

~~~hcl
module "app_key" {
  source = "../../modules/kms"

  alias_name = "alias/dev/app"
  tags = {
    Environment = "dev"
  }
}
~~~

별칭 이름은 전체 이름인 alias/<이름> 형식으로 전달합니다. alias/aws/ 접두사는 AWS 관리형 키에 예약되어 있습니다.

## 입력 속성

| 속성명 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| alias_name | string | null | 선택적 별칭 전체 이름입니다. null이면 별칭을 만들지 않습니다. |
| description | string | null | 키 설명입니다. |
| kms_admin_arns | set(string) | [] | 키 관리 권한을 직접 부여할 IAM Role/User ARN 집합입니다. |
| key_user_arns | set(string) | [] | 키 암호화 작업과 AWS 서비스용 조건부 Grant 권한을 직접 부여할 IAM Role/User ARN 집합입니다. |
| policy_json | string | null | 키 정책 전체를 대체할 JSON 객체입니다. 지정하면 관리자·사용자 ARN 집합은 비워야 합니다. |
| enable_key_rotation | bool | true | AWS KMS 자동 키 재료 회전 활성화 여부입니다. |
| rotation_period_in_days | number | 365 | 자동 회전 주기입니다. 90~2560일 정수이며, 회전을 켠 경우 적용됩니다. |
| deletion_window_in_days | number | 30 | 키 삭제 예약 후 실제 삭제까지의 대기 기간입니다. 7~30일 정수입니다. |
| tags | map(string) | {} | 키에 적용할 태그입니다. |

## 출력 속성

| 속성명 | 역할 |
|---|---|
| key_id | KMS 키 ID입니다. |
| key_arn | KMS 키 ARN입니다. 기존 서비스 모듈의 KMS 입력에 전달할 수 있습니다. |
| alias_name | 생성된 별칭 이름입니다. 별칭이 없으면 null입니다. |
| alias_arn | 생성된 별칭 ARN입니다. 별칭이 없으면 null입니다. |

## 관리자와 사용자

관리자·사용자 ARN을 지정하면 모듈이 키 정책에 별도 문장을 만듭니다.

~~~hcl
module "app_key" {
  source = "../../modules/kms"

  alias_name = "alias/dev/app"

  kms_admin_arns = [
    "arn:aws:iam::123456789012:role/KmsAdmin"
  ]
  key_user_arns = [
    "arn:aws:iam::123456789012:role/AppRole"
  ]
}
~~~

관리자 문장은 키의 설정·정책·삭제 등을 관리할 수 있게 하지만 Encrypt, Decrypt, GenerateDataKey를 직접 허용하지 않습니다. 관리자는 정책 변경이나 Grant 생성으로 자신의 권한을 바꿀 수 있으므로 독립된 보안 경계로 취급하지 마세요.

사용자 문장은 Encrypt, Decrypt, ReEncrypt, GenerateDataKey, DescribeKey를 허용합니다. AWS 서비스가 사용자를 대신해 Grant를 다루는 작업은 kms:GrantIsForAWSResource 조건으로 제한합니다. 이 권한만으로 모든 서비스와 교차 계정 사용이 보장되지는 않으며 서비스별 권한도 확인해야 합니다.

생성 정책에는 계정 주체가 IAM 정책으로 KMS 권한을 위임할 수 있는 문장도 있습니다. 따라서 kms_admin_arns와 key_user_arns는 유일한 접근 허용 목록이 아닙니다. 계정의 다른 IAM 정책이 키 접근을 허용할 수 있습니다. IAM Group은 키 정책의 Principal로 입력할 수 없습니다.

## 전체 키 정책 직접 지정

policy_json에 정책 JSON을 지정하면 생성 정책 전체를 대체합니다. 이때 kms_admin_arns와 key_user_arns는 함께 지정할 수 없습니다.

~~~hcl
module "app_key" {
  source = "../../modules/kms"

  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowKeyAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::123456789012:role/KmsAdmin" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}
~~~

직접 지정한 정책에는 키를 계속 관리할 주체를 포함하세요. 모듈은 잠금 방지 검사를 우회하지 않습니다. JSON 문법은 로컬에서 검사하지만 정책의 실제 권한 효과는 AWS가 최종 판단합니다.

## 기존 모듈과 연결

S3와 ECR 모듈은 키 ARN을 kms_key_arn에 받습니다. 일반 RDS와 Aurora는 같은 ARN을 kms_key_id 또는 secret_kms_key_id에 받을 수 있습니다.

~~~hcl
module "app_key" {
  source     = "../../modules/kms"
  alias_name = "alias/dev/app"
}

module "bucket" {
  source      = "../../modules/s3"
  bucket_name = "my-private-example-bucket"
  kms_key_arn = module.app_key.key_arn
}

module "repository" {
  source      = "../../modules/ecr"
  name        = "dev/app"
  kms_key_arn = module.app_key.key_arn
}
~~~

RDS 또는 Aurora 모듈 호출에서는 용도에 맞게 다음 입력을 지정합니다.

~~~hcl
kms_key_id        = module.app_key.key_arn
secret_kms_key_id = module.app_key.key_arn
~~~

키 ARN을 전달하는 것만으로 AWS 서비스나 호출자에게 키 사용 권한이 생기지는 않습니다. 키 정책과 필요한 IAM 정책·Grant, 서비스별 조건을 함께 검토하세요. 특히 ECR 저장소의 KMS 암호화는 저장소 생성 시 선택해야 합니다.

## 회전과 삭제

자동 회전은 같은 KMS 키의 키 재료를 교체하며 키 ARN은 유지됩니다. 이 설정은 Secrets Manager의 암호 회전과 별개입니다.

Terraform에서 키를 제거하면 AWS KMS는 삭제를 예약합니다. 삭제 대기 중인 키는 암호화 작업에 사용할 수 없고, 대기 기간이 끝나면 키 재료가 삭제됩니다. 사용 중인 S3 객체, ECR 이미지, RDS 데이터나 Secret에 영향을 줄 수 있으므로 사용처를 확인한 뒤 제거하세요. 삭제 예약을 취소하려면 AWS KMS의 CancelKeyDeletion 작업을 사용하고 키를 다시 활성화해야 합니다. 상태와 Terraform 구성의 복구 절차도 함께 확인하세요.

로컬 mock 테스트는 정책 JSON과 Terraform 계획을 확인할 뿐, 실제 AWS 권한·암호화·회전·삭제 동작을 확인하지 않습니다.

## 참고 자료

- [AWS KMS 기본 키 정책](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html)
- [AWS KMS 키 삭제](https://docs.aws.amazon.com/kms/latest/developerguide/deleting-keys.html)
- [AWS KMS 키 회전](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)
