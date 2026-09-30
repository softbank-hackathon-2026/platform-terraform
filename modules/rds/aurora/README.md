# Provisioned Aurora 클러스터

Aurora PostgreSQL 또는 Aurora MySQL 클러스터 하나, 최초 인스턴스 하나와 선택적인 reader 인스턴스를 만듭니다. DB Subnet Group은 모듈이 만들고, Private Subnet과 기존 Security Group은 Root Module에서 전달합니다. 인스턴스는 비공개이며 `db.serverless` 클래스는 허용하지 않습니다.

## 기본 구성

```hcl
module "database" {
  source = "../../modules/rds/aurora"

  cluster_identifier    = "sample-aurora"
  writer_identifier     = "sample-aurora-one"
  engine                = "aurora-postgresql"
  engine_version        = "16.4"
  writer_instance_class = "db.r6g.large"
  master_username       = "dbadmin"
  subnet_ids            = values(module.network.private_subnet_ids)
  security_group_ids    = [module.db_security_group.security_group_id]

  readers = {
    reporting = { identifier = "sample-aurora-reporting" }
    analytics = { identifier = "sample-aurora-analytics", promotion_tier = 0 }
  }
}
```

MySQL은 `engine = "aurora-mysql"`과 해당 Region에서 지원하는 `engine_version`을 지정합니다. 기본 포트는 PostgreSQL 5432, MySQL 3306입니다. 엔진 버전과 인스턴스 클래스 조합, Subnet의 AZ는 실제 AWS 환경에서 확인해야 합니다.

`writer_endpoint`는 클러스터의 현재 writer를 가리킵니다. `readers`가 비어 있으면 모듈의 `reader_endpoint` 출력은 `null`입니다. reader를 지정하면 클러스터의 reader endpoint를 출력하지만, 가용한 reader가 일시적으로 없으면 AWS endpoint가 writer를 가리킬 수 있습니다. `reader_addresses`는 각 인스턴스의 직접 주소이며 장애 조치 뒤 역할이 바뀔 수 있으므로 읽기 전용 접속 보장 용도로 사용하지 마세요. `promotion_tier`의 기본값은 1이고 0~15 사이에서 낮은 값이 장애 조치 우선순위가 높습니다.

## 입력 속성

기본값이 없는 속성은 Root Module에서 반드시 지정해야 합니다. 아래 기본값은 현재 모듈 코드 기준입니다.

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `cluster_identifier` | `string` | 필수 | Aurora 클러스터의 이름을 정합니다. |
| `writer_identifier` | `string` | 필수 | 최초 인스턴스의 이름을 정합니다. 장애 조치 뒤 실제 writer 역할은 바뀔 수 있습니다. |
| `engine` | `string` | 필수 | `aurora-postgresql` 또는 `aurora-mysql`을 선택합니다. |
| `engine_version` | `string` | 필수 | 클러스터 엔진 버전을 지정합니다. 실제 사용 가능 여부는 AWS가 확인합니다. |
| `writer_instance_class` | `string` | 필수 | 최초 인스턴스의 컴퓨팅 크기를 정합니다. `db.serverless`는 허용하지 않습니다. |
| `database_name` | `string` | `null` | 생성할 초기 데이터베이스 이름입니다. 생략할 수 있습니다. |
| `port` | `number` | `null` → 엔진별 5432/3306 | DB 접속 포트입니다. PostgreSQL은 5432, MySQL은 3306을 기본으로 씁니다. |
| `subnet_ids` | `list(string)` | 필수 | DB Subnet Group에 넣을 Private Subnet ID입니다. 중복 없이 2개 이상 전달합니다. |
| `security_group_ids` | `list(string)` | 필수 | 클러스터에 연결할 기존 Security Group ID입니다. 하나 이상 전달합니다. |
| `master_username` | `string` | 필수 | RDS가 암호를 관리할 관리자 계정의 이름입니다. |
| `kms_key_id` | `string` | `null` | 저장 데이터 암호화에 사용할 기존 KMS 키입니다. 생략하면 AWS 기본 키를 사용합니다. |
| `secret_kms_key_id` | `string` | `null` | 관리자 Secret 암호화에 사용할 기존 KMS 키입니다. 생략하면 AWS 기본 키를 사용합니다. |
| `iam_database_authentication_enabled` | `bool` | `false` | 클러스터의 일반 DB 사용자용 IAM 인증을 켭니다. 관리자 인증 방식은 바꾸지 않습니다. |
| `backup_retention_period` | `number` | `7` | 클러스터 자동 백업을 보존할 일수입니다. 1~35일의 정수를 지정할 수 있습니다. |
| `deletion_protection` | `bool` | `true` | 클러스터를 실수로 삭제하지 못하게 막습니다. |
| `skip_final_snapshot` | `bool` | `false` | `true`이면 클러스터를 삭제할 때 최종 스냅샷을 만들지 않습니다. |
| `final_snapshot_identifier` | `string` | `null` → `<cluster_identifier>-final` | 최종 스냅샷의 이름을 지정합니다. `skip_final_snapshot = true`와 함께 지정할 수 없습니다. |
| `extended_support_enabled` | `bool` | `false` | 지원 종료 엔진 버전에 대한 RDS Extended Support 등록을 선택합니다. |
| `readers` | `map(object)` | `{}` | 논리 키별 reader 인스턴스를 추가합니다. 각 값의 `identifier`는 필수, `instance_class`는 최초 인스턴스 클래스를 사용하고 `promotion_tier`는 기본 `1`입니다. |
| `tags` | `map(string)` | `{}` | DB Subnet Group, 클러스터와 인스턴스에 태그를 붙입니다. `Name`은 모듈이 만든 리소스 이름이 우선합니다. |

`readers`의 각 값은 다음 속성을 사용합니다.

| 내부 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `identifier` | `string` | 필수 | reader 인스턴스의 식별자입니다. |
| `instance_class` | `string` | `null` → 최초 인스턴스 클래스 | reader의 Provisioned 인스턴스 클래스입니다. |
| `promotion_tier` | `number` | `1` | 장애 조치 우선순위입니다. 0~15에서 낮을수록 우선합니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `cluster_id` | 클러스터 식별자입니다. |
| `cluster_arn` | 클러스터 ARN입니다. |
| `cluster_resource_id` | DB 사용자에게 `rds-db:connect` 권한을 줄 때 쓰는 클러스터 Resource ID입니다. |
| `writer_endpoint` | 현재 writer를 가리키는 클러스터 접속 주소입니다. |
| `reader_endpoint` | 설정한 reader가 있으면 클러스터 읽기 접속 주소, 없으면 `null`입니다. |
| `port` | 클러스터 접속 포트입니다. |
| `master_secret_arn` | RDS가 관리하는 관리자 암호 Secret의 ARN입니다. 생성 전에는 `null`일 수 있습니다. |
| `reader_addresses` | 논리 키별 reader 인스턴스 주소 Map입니다. 장애 조치 뒤 실제 역할은 바뀔 수 있습니다. |

모듈은 `engine_mode = "provisioned"`, `storage_encrypted = true`, `manage_master_user_password = true`, `apply_immediately = false`를 고정합니다. 모든 인스턴스의 `publicly_accessible`은 `false`로 고정합니다.

## 관리자 암호와 일반 DB 사용자 IAM 접속

관리자 암호는 RDS가 Secrets Manager에서 만들고 관리합니다. 모듈은 평문 암호를 입력받거나 출력하지 않으며 `master_secret_arn`만 출력합니다. `secret_kms_key_id`로 기존 KMS 키를 지정할 수 있습니다. 관리자는 IAM 로그인 대상으로 구성하지 않습니다.

일반 DB 사용자에게 IAM 로그인을 허용하려면 `iam_database_authentication_enabled = true`를 지정합니다. 이 설정은 클러스터의 IAM 인증 기능만 켜므로 DB 모듈에 IAM Role ARN을 전달하지 않습니다. 실제 접속에 사용할 IAM Role은 EC2 Instance Profile, ECS Task Role, Lambda 실행 Role 등 애플리케이션 쪽에서 선택합니다. 그 Role에 `rds-db:connect` 권한을 부여하고 DB 사용자, 토큰 발급과 TLS 접속을 별도로 준비해야 합니다. IAM 사용자나 Permission Set을 사용할 때도 권한 정책이 필요합니다.

PostgreSQL은 관리자 암호로 접속해 별도 사용자를 만들고 `GRANT rds_iam TO app_user;`를 실행합니다. 여기서 `rds_iam`은 PostgreSQL 내부 역할이며 AWS IAM Role과 다릅니다. **관리자에게 `rds_iam`을 부여하지 마세요.** 관리자 암호 로그인이 IAM 로그인으로 바뀝니다. MySQL은 별도 사용자를 `CREATE USER 'app_user' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';`로 만듭니다. 두 엔진 모두 필요한 최소 DB 권한만 부여합니다.

IAM Policy의 Resource는 `cluster_resource_id`를 사용합니다.

```text
arn:aws:rds-db:<region>:<account-id>:dbuser:<cluster-resource-id>/<db-user-name>
```

Root Module에서 기존 IAM Policy 모듈에 전달할 문서는 다음과 같습니다.

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  db_user_arn = "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.database.cluster_resource_id}/app_user"
}

data "aws_iam_policy_document" "db_connect" {
  statement {
    actions   = ["rds-db:connect"]
    resources = [local.db_user_arn]
  }
}
```

이 정책 문서를 IAM Policy로 만들고 접속 주체의 Role에 연결합니다. 아래 `module.app_role`은 Root Module에서 별도로 만든 애플리케이션 Role입니다. Role을 해당 EC2/ECS/Lambda 워크로드에 연결하는 단계도 별도로 필요합니다.

```hcl
module "db_connect_policy" {
  source      = "../../modules/iam/policy"
  name        = "sample-aurora-db-connect"
  policy_json = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "app_db_connect" {
  role       = module.app_role.role_name
  policy_arn = module.db_connect_policy.policy_arn
}
```

IAM 주체에 정책을 연결한 뒤, 클러스터 주소와 포트 및 사용자 이름으로 `aws rds generate-db-auth-token`을 호출합니다. 발급된 토큰을 DB 클라이언트의 암호 자리에 사용하고 AWS CA 인증서로 TLS 서버 인증을 설정합니다. 토큰은 발급 후 15분 동안 새 연결에 사용할 수 있습니다. Private DB이므로 클라이언트의 네트워크 경로와 Security Group 규칙도 필요합니다.

## 데이터 보호와 삭제

스토리지 암호화, 자동 백업 7일, 삭제 보호, 최종 스냅샷 생성이 기본입니다. `kms_key_id`, `backup_retention_period`, `deletion_protection`, `skip_final_snapshot`으로 조정할 수 있습니다. 최종 스냅샷 기본 이름은 `<cluster_identifier>-final`입니다. 같은 이름의 스냅샷이 이미 있으면 삭제가 실패할 수 있으므로 삭제 전에 `final_snapshot_identifier`를 새 이름으로 바꾸세요. 클러스터를 제거할 때는 필요하면 `deletion_protection = false`를 먼저 적용합니다.

백업 보존 기간과 최종 스냅샷 정책은 고정이 아닙니다. 예를 들어 `backup_retention_period = 14`로 자동 백업을 14일 보존할 수 있습니다. 다만 현재 모듈은 자동 백업을 끄는 `0`일을 허용하지 않고, 백업 실행 시간(`preferred_backup_window`)은 입력으로 받지 않습니다. 백업 정책은 개별 reader가 아닌 클러스터에 적용합니다.

이 모듈은 실제 AWS 생성, 백업 복구, 장애 조치 또는 IAM 로그인 성공을 검증하지 않습니다. 비용과 지원 엔진 버전·클래스는 Apply 전에 확인하세요.
