# ECR module

비공개 Amazon ECR 저장소 하나를 생성하는 로컬 Terraform 모듈입니다.

## 기본 동작

- 이미지 태그는 `IMMUTABLE`이므로 기존 태그로 다시 push할 수 없습니다. 태그를 재사용해야 한다면 `image_tag_mutability = "MUTABLE"`을 명시하세요.
- 저장소는 AES256으로 암호화합니다.
- 저장소 수준의 `scan_on_push`는 기본적으로 `true`입니다. 실제 기본·향상된 스캔 유형과 주기는 AWS 계정의 Private Registry 스캔 설정 및 필터에 따라 달라집니다. 배포 전 Registry 설정을 확인하세요.
- Lifecycle Policy는 기본으로 만들지 않습니다.
- `force_delete = false`이므로 이미지가 남은 저장소는 강제로 삭제하지 않습니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | 비공개 ECR 저장소 이름입니다. |
| `image_tag_mutability` | `string` | `"IMMUTABLE"` | 태그 재사용 정책입니다. `IMMUTABLE` 또는 `MUTABLE`을 선택합니다. |
| `kms_key_arn` | `string` | `null` | 기존 고객 관리 KMS 키 ARN입니다. 생략하면 AES256 암호화를 사용합니다. |
| `scan_on_push` | `bool` | `true` | 저장소 수준의 push 시 기본 이미지 스캔 설정입니다. 실제 동작은 Registry 설정도 확인해야 합니다. |
| `lifecycle_policy_json` | `string` | `null` | 선택적 Lifecycle Policy JSON입니다. 생략하면 정책을 만들지 않습니다. |
| `tags` | `map(string)` | `{}` | 저장소에 붙일 태그입니다. |

## 기본 사용 예시

```hcl
module "app_images" {
  source = "../../modules/ecr"

  name = "sample/dev/app"
  tags = {
    Environment = "dev"
    Project     = "sample"
  }
}
```

이름의 유효성과 계정·Region 내 중복 여부는 AWS가 최종 확인합니다. 이미지 주소는 `module.app_images.repository_url`에 `:tag`를 붙여 만듭니다.

## 선택적 설정

기존 고객 관리 KMS 키 ARN을 `kms_key_arn`에 전달하면 KMS 암호화를 사용합니다. 키는 저장소와 같은 Region에 있어야 하고, 저장소를 생성하는 주체 및 ECR이 키를 사용할 권한이 필요합니다. **ECR 저장소의 암호화 설정은 생성 후 변경할 수 없습니다.** AES256에서 KMS로 바꾸거나 키를 교체하려면 저장소 교체가 필요할 수 있으며, 이미지가 남아 있으면 `force_delete = false` 때문에 기존 저장소 삭제가 실패합니다.

기존 KMS 키를 사용하는 저장소는 다음처럼 구성합니다. ARN은 실제로 사용할 키의 값으로 바꾸세요.

```hcl
module "app_images" {
  source = "../../modules/ecr"

  name        = "sample/dev/app"
  kms_key_arn = "arn:aws:kms:ap-northeast-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}
```

Root Module에서 KMS 키를 Terraform으로 관리한다면 `kms_key_arn = aws_kms_key.ecr.arn`처럼 리소스의 ARN을 전달할 수도 있습니다. 모듈은 전달받은 키를 저장소 생성 시 적용합니다.

보존 정책이 필요할 때만 `lifecycle_policy_json`을 지정하세요. 예를 들어 태그가 없는 이미지를 14일 후 만료시키는 정책은 다음과 같습니다.

```hcl
module "app_images" {
  source = "../../modules/ecr"

  name = "sample/dev/app"

  lifecycle_policy_json = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images after 14 days"
      selection = {
        tagStatus  = "untagged"
        countType  = "sinceImagePushed"
        countUnit  = "days"
        countNumber = 14
      }
      action = { type = "expire" }
    }]
  })
}
```

모듈은 JSON 문법만 검증합니다. 정책을 적용하기 전에 AWS ECR Lifecycle Policy Preview로 실제 만료·보관 대상을 확인하세요. 정책에 맞는 이미지는 적용 후 자동으로 만료·보관될 수 있습니다.

`scan_on_push = false`로 저장소 수준 설정을 끌 수 있지만 Registry 설정이 실제 스캔 방식을 결정할 수 있습니다. 이 모듈은 Registry 설정, 향상된 스캔, IAM 및 저장소 접근 정책, 이미지 업로드를 관리하지 않습니다.

## 출력 속성

| 속성 | 역할 |
|---|---|
| `repository_name` | 저장소 이름 |
| `repository_arn` | 저장소 ARN |
| `repository_url` | 이미지 주소의 기본 URL |

## 로컬 검증

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```
