# 일반 RDS DB 인스턴스

PostgreSQL 또는 MySQL 기본 인스턴스 하나와 선택적인 같은 Region의 Read Replica를 만듭니다. DB Subnet Group은 이 모듈이 만들고, Private Subnet과 Security Group은 Root Module에서 전달합니다. 모든 DB는 비공개입니다.

Read Replica를 사용하려면 `master_password_mode = "module_managed_secret"`을 명시해야 합니다. [AWS 문서](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)에 따르면 RDS가 관리자 암호를 관리하는 PostgreSQL/MySQL 원본에서는 Read Replica를 생성할 수 없습니다. 모듈은 이 조합을 Plan에서 거부합니다.

## 기본 구성

```hcl
module "database" {
  source = "../../modules/rds/instance"

  identifier         = "sample-db"
  engine             = "postgres"
  engine_version     = "16.4"
  instance_class     = "db.t4g.medium"
  allocated_storage  = 100
  master_username    = "dbadmin"
  subnet_ids         = values(module.network.private_subnet_ids)
  security_group_ids = [module.db_security_group.security_group_id]
}
```

MySQL은 `engine = "mysql"`과 지원되는 `engine_version`을 지정합니다. 기본 포트는 PostgreSQL 5432, MySQL 3306입니다. 엔진 버전과 인스턴스 클래스의 조합 및 Subnet의 AZ는 실제 AWS 환경에서 확인해야 합니다.

Read Replica가 필요하면 같은 모듈 호출에 다음 속성을 추가합니다. 복제본이 없어도 `module_managed_secret` 모드를 선택할 수 있습니다.

```hcl
master_password_mode = "module_managed_secret"
read_replicas = {
  reporting = { identifier = "sample-db-reporting" }
}
```

`multi_az = true`는 기본 인스턴스에 장애 조치용 대기 인스턴스를 추가합니다. 대기 인스턴스는 읽기 주소가 아닙니다. `read_replicas`는 읽기용 DB를 추가하며 각 복제본에 독립적인 주소가 있습니다. `writer_address`는 기본 DB, `read_replica_addresses`는 논리 키별 복제본 주소입니다.

## 입력 속성

기본값이 없는 속성은 Root Module에서 반드시 지정해야 합니다. 아래 기본값은 현재 모듈 코드 기준입니다.

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `identifier` | `string` | 필수 | 기본 DB 인스턴스의 이름을 정합니다. |
| `engine` | `string` | 필수 | `postgres` 또는 `mysql`을 선택합니다. |
| `engine_version` | `string` | 필수 | DB 엔진 버전을 지정합니다. 실제 사용 가능 여부는 AWS가 확인합니다. |
| `instance_class` | `string` | 필수 | 기본 DB의 컴퓨팅 크기를 정합니다. |
| `allocated_storage` | `number` | 필수 | 기본 DB의 초기 저장 공간을 GiB 단위로 정합니다. 20~65536의 정수입니다. |
| `storage_type` | `string` | `gp3` | 기본 DB 저장소를 `gp3` 또는 `gp2`로 선택합니다. |
| `db_name` | `string` | `null` | 생성할 초기 데이터베이스 이름입니다. 생략할 수 있습니다. |
| `port` | `number` | `null` → 엔진별 5432/3306 | DB 접속 포트입니다. PostgreSQL은 5432, MySQL은 3306을 기본으로 씁니다. |
| `subnet_ids` | `list(string)` | 필수 | DB Subnet Group에 넣을 Private Subnet ID입니다. 중복 없이 2개 이상 전달합니다. |
| `security_group_ids` | `list(string)` | 필수 | DB에 연결할 기존 Security Group ID입니다. 하나 이상 전달합니다. |
| `master_username` | `string` | 필수 | 관리자 계정의 이름입니다. 선택한 방식의 Secret에 이 이름을 사용합니다. |
| `master_password_mode` | `string` | `rds_managed` | `rds_managed`는 RDS가 관리자 Secret을 관리합니다. RR이 있으면 `module_managed_secret`을 명시해야 합니다. |
| `kms_key_id` | `string` | `null` | 저장 데이터 암호화에 사용할 기존 KMS 키입니다. 생략하면 AWS 기본 키를 사용합니다. |
| `secret_kms_key_id` | `string` | `null` | 관리자 Secret 암호화에 사용할 기존 KMS 키입니다. 생략하면 AWS 기본 키를 사용합니다. |
| `iam_database_authentication_enabled` | `bool` | `false` | 일반 DB 사용자용 IAM 인증을 기본 DB와 복제본에 켭니다. 관리자 인증 방식은 바꾸지 않습니다. |
| `backup_retention_period` | `number` | `7` | 기본 DB 자동 백업을 보존할 일수입니다. 1~35일의 정수를 지정할 수 있습니다. |
| `deletion_protection` | `bool` | `true` | 기본 DB를 실수로 삭제하지 못하게 막습니다. |
| `skip_final_snapshot` | `bool` | `false` | `true`이면 기본 DB를 삭제할 때 최종 스냅샷을 만들지 않습니다. |
| `final_snapshot_identifier` | `string` | `null` → `<identifier>-final` | 최종 스냅샷의 이름을 지정합니다. `skip_final_snapshot = true`와 함께 지정할 수 없습니다. |
| `extended_support_enabled` | `bool` | `false` | 지원 종료 엔진 버전에 대한 RDS Extended Support 등록을 선택합니다. |
| `multi_az` | `bool` | `false` | 기본 DB에 장애 조치용 대기 인스턴스를 둡니다. 읽기 복제본과는 별도입니다. |
| `read_replicas` | `map(object)` | `{}` | 논리 키별 읽기 복제본을 추가합니다. 각 값의 `identifier`는 필수, `instance_class`는 기본 DB 클래스를 사용하고 `deletion_protection`은 기본 `true`입니다. |
| `tags` | `map(string)` | `{}` | DB Subnet Group과 인스턴스, 모듈 소유 Secret에 태그를 붙입니다. `Name`은 모듈이 만든 리소스 이름이 우선합니다. |

`read_replicas`의 각 값은 다음 속성을 사용합니다.

| 내부 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `identifier` | `string` | 필수 | Read Replica의 DB 식별자입니다. |
| `instance_class` | `string` | `null` → 기본 DB 클래스 | 복제본의 인스턴스 클래스입니다. |
| `deletion_protection` | `bool` | `true` | 복제본 삭제 보호 여부입니다. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `db_instance_id` | 기본 DB의 식별자입니다. |
| `db_instance_arn` | 기본 DB의 ARN입니다. |
| `db_resource_id` | 기본 DB 사용자에게 `rds-db:connect` 권한을 줄 때 쓰는 Resource ID입니다. |
| `writer_address` | 기본 DB의 쓰기 접속 주소입니다. |
| `port` | 기본 DB의 접속 포트입니다. |
| `master_secret_arn` | 선택한 방식의 관리자 암호 Secret ARN입니다. RDS 관리형은 생성 전 `null`일 수 있습니다. |
| `read_replica_ids` | 논리 키별 복제본 식별자 Map입니다. 복제본이 없으면 `{}`입니다. |
| `read_replica_resource_ids` | 논리 키별 복제본 IAM 접속 권한용 Resource ID Map입니다. |
| `read_replica_addresses` | 논리 키별 복제본 읽기 접속 주소 Map입니다. |

모듈은 `publicly_accessible = false`, `storage_encrypted = true`, `apply_immediately = false`를 고정합니다. `manage_master_user_password = true`는 `rds_managed` 모드에서만 사용합니다. 복제본의 `skip_final_snapshot`은 `true`로 고정합니다. 이 모듈은 Terraform 1.11 이상이 필요합니다.

## 관리자 암호와 일반 DB 사용자 IAM 접속

기본 `rds_managed` 모드에서는 RDS가 관리자 암호를 생성하고 Secrets Manager에서 관리합니다. RDS 관리형 Secret은 기본적으로 자동 회전됩니다. RR을 만들 수 없으므로 `read_replicas`는 비워야 합니다.

`module_managed_secret` 모드에서는 모듈이 `<identifier>-master` Secret을 만들고 최초 암호를 저장합니다. Secret 값은 `username`과 `password`를 담은 JSON입니다. 암호는 Terraform의 ephemeral 값과 write-only 인수로 전달하므로 모듈 입력·출력, Plan·State에 평문으로 저장하지 않습니다. 기본 DB는 Secret의 해당 버전을 읽어 같은 암호로 생성되고 복제본은 원본을 복제합니다. `secret_kms_key_id`로 두 방식 모두 기존 KMS 키를 지정할 수 있습니다. Secret 조회에는 `secretsmanager:GetSecretValue`와 선택한 KMS 키의 복호화 권한이 필요합니다.

모듈 소유 Secret의 자동 회전은 설정하지 않습니다. Secret 값만 외부에서 바꾸면 DB 암호와 달라질 수 있고, Secret 버전 교체와 DB 암호 변경은 원자적이지 않습니다. `master_username` 변경은 Secret 갱신과 DB 교체를 수반하므로 적용 전에 별도로 검토하세요. 운영 전 별도의 회전·복구 절차를 준비하세요. 이미 배포된 DB의 모드 전환도 이 모듈의 검증 범위가 아닙니다. 관리자는 IAM 로그인 대상으로 구성하지 않습니다.

로컬 mock 테스트는 Terraform 1.17 beta 이상에서 `terraform test -test-directory=tests-terraform-1.17`로 실행합니다. 테스트 파일을 별도 디렉터리에 둬 Terraform 1.11~1.16의 일반 `terraform validate`와 모듈 사용은 유지합니다.

일반 DB 사용자에게 IAM 로그인을 허용하려면 `iam_database_authentication_enabled = true`를 지정합니다. 기본 DB와 모든 Read Replica에 같은 설정이 적용됩니다. 이 옵션은 DB의 IAM 인증 기능만 켜므로 DB 모듈에 IAM Role ARN을 전달하지 않습니다. 실제 접속에 사용할 IAM Role은 EC2 Instance Profile, ECS Task Role, Lambda 실행 Role 등 애플리케이션 쪽에서 선택합니다. 그 Role에 `rds-db:connect` 권한을 부여하고 DB 사용자, 토큰 발급과 TLS 접속을 별도로 준비해야 합니다. IAM 사용자나 Permission Set을 사용할 때도 권한 정책이 필요합니다.

PostgreSQL은 관리자 암호로 접속해 별도 사용자를 만들고 `GRANT rds_iam TO app_user;`를 실행합니다. 여기서 `rds_iam`은 PostgreSQL 내부 역할이며 AWS IAM Role과 다릅니다. **관리자에게 `rds_iam`을 부여하지 마세요.** 관리자 암호 로그인이 IAM 로그인으로 바뀝니다. MySQL은 별도 사용자를 `CREATE USER 'app_user' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';`로 만듭니다. 두 엔진 모두 해당 사용자에게 필요한 최소 DB 권한만 부여합니다.

IAM Policy의 Resource는 다음 형식을 사용합니다. 기본 DB와 각 Read Replica는 서로 다른 Resource ID를 사용하므로 필요한 DB마다 ARN을 작성합니다. `db_resource_id` 및 `read_replica_resource_ids` 출력을 연결하면 됩니다.

```text
arn:aws:rds-db:<region>:<account-id>:dbuser:<db-resource-id>/<db-user-name>
```

예를 들어 Root Module에서 기존 IAM Policy 모듈에 전달할 문서는 다음과 같습니다. 복제본 접근이 필요하면 `module.database.read_replica_resource_ids["reporting"]`을 사용해 Resource를 추가합니다.

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  db_user_arn = "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:dbuser:${module.database.db_resource_id}/app_user"
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
  name        = "sample-db-connect"
  policy_json = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "app_db_connect" {
  role       = module.app_role.role_name
  policy_arn = module.db_connect_policy.policy_arn
}
```

IAM 주체에 이 정책을 연결한 뒤, 해당 DB 주소와 포트 및 DB 사용자 이름으로 `aws rds generate-db-auth-token`을 호출합니다. 생성된 토큰을 DB 클라이언트의 암호 자리에 사용하고 AWS CA 인증서로 TLS 서버 인증을 설정합니다. 토큰은 발급 후 15분 동안 새 연결에 사용할 수 있습니다. Private DB이므로 클라이언트는 허용된 네트워크 경로와 Security Group 규칙도 필요합니다.

## 데이터 보호와 삭제

스토리지 암호화, 자동 백업 7일, 삭제 보호, 최종 스냅샷 생성이 기본입니다. `kms_key_id`, `backup_retention_period`, `deletion_protection`, `skip_final_snapshot`으로 조정할 수 있습니다. 최종 스냅샷 기본 이름은 `<identifier>-final`입니다. 같은 이름의 스냅샷이 이미 있으면 삭제가 실패할 수 있으므로 삭제 전에 `final_snapshot_identifier`를 새 이름으로 바꾸세요.

백업 보존 기간과 최종 스냅샷 정책은 고정이 아닙니다. 예를 들어 `backup_retention_period = 14`로 자동 백업을 14일 보존할 수 있습니다. 다만 현재 모듈은 자동 백업을 끄는 `0`일을 허용하지 않고, 백업 실행 시간(`backup_window`)이나 복제본별 백업 설정은 입력으로 받지 않습니다.

기본 DB와 복제본은 삭제 보호가 기본 활성화됩니다. 복제본을 제거할 때는 먼저 해당 `read_replicas` 항목의 `deletion_protection = false`를 적용한 뒤 Map에서 제거합니다. 복제본에는 최종 스냅샷을 만들지 않습니다. 기본 DB를 제거할 때는 필요하면 `deletion_protection = false`를 먼저 적용합니다.

`module_managed_secret`에서 모듈을 제거하면 Secret은 공급자 기본값에 따라 [30일 복구 대기 기간](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret)을 거쳐 삭제됩니다. 이 기간에 같은 `<identifier>-master` 이름으로 바로 다시 만들 수 없으므로 재생성 전에 Secret 삭제 상태를 확인하세요.

이 모듈은 실제 AWS 생성, Secret 값과 DB 암호의 일치, 백업 복구, 복제 지연 또는 IAM 로그인 성공을 검증하지 않았습니다. 비용과 지원 엔진 버전·클래스는 Apply 전에 확인하세요.
