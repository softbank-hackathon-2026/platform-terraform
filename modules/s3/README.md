# S3 module

비공개 일반 목적 S3 버킷 하나를 생성하는 로컬 Terraform 모듈입니다.

## 기본 동작

- 버킷 수준 Block Public Access의 네 설정을 모두 켭니다.
- 암호화는 Amazon S3의 기본 SSE-S3를 사용합니다.
- 버전 관리는 기본적으로 사용하지 않습니다.
- `force_destroy = false`이므로 객체가 남은 버킷은 삭제되지 않습니다.
- 입력 태그보다 버킷 이름을 사용한 `Name` 태그를 우선합니다.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `bucket_name` | `string` | 필수 | 생성할 일반 목적 S3 버킷 이름입니다. 전역에서 고유해야 합니다. |
| `versioning_enabled` | `bool` | `false` | 버킷 버전 관리를 켭니다. |
| `kms_key_arn` | `string` | `null` | SSE-KMS에 사용할 기존 KMS 키 ARN입니다. 생략하면 기본 SSE-S3를 사용합니다. |
| `tags` | `map(string)` | `{}` | 버킷에 붙일 추가 태그입니다. Name은 버킷 이름이 우선합니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `bucket_name` | 생성된 버킷 이름입니다. |
| `bucket_arn` | 생성된 버킷 ARN입니다. |

## 사용 예시

```hcl
module "data_bucket" {
  source = "../../modules/s3"

  bucket_name = "sample-dev-data-unique-name"
  tags = {
    Environment = "dev"
    Project     = "sample"
  }
}
```

버킷 이름은 전역에서 고유해야 합니다. 이름의 사용 가능 여부는 AWS가 확인합니다.

## 선택적 설정

`versioning_enabled = true`로 버전 관리를 켭니다. 한 번 활성화한 버전 관리는 완전한 미사용 상태로 되돌릴 수 없습니다. 값을 다시 `false`로 바꾸면 기존 버전은 유지되고 버전 관리가 중지됩니다. 버전마다 저장 비용이 발생할 수 있습니다.

`kms_key_arn`에 같은 Region의 고객 관리 KMS 키 ARN을 전달하면 버킷 기본 암호화를 SSE-KMS로 설정하고 S3 Bucket Key를 켭니다. 해당 키를 사용할 권한과 KMS 비용을 확인하세요. 값을 지정하지 않으면 AWS의 기본 SSE-S3를 사용합니다.

이 모듈은 KMS 키, 버킷 정책, ACL, Lifecycle, Replication, 웹사이트, 객체를 만들지 않습니다. 필요한 정책은 호출하는 Root Module에서 관리하세요.

## 검증

```sh
terraform init -backend=false
terraform validate
terraform test
terraform fmt -check -recursive
```
