# RDS and Aurora modules AI-DLC

마지막 확인일: 2026-09-24

## 현재 상태

| 구분 | 상태 |
|---|---|
| Ideation | 일반 RDS, Provisioned Aurora, 같은 Region의 읽기 복제본 범위 승인. 일반 DB 사용자 IAM 인증 추가 및 관리자 계정 제외 범위 확정 |
| Inception | 일반 DB 사용자 IAM 인증 범위를 포함한 수정 요구사항 2026-09-23 승인 |
| Construction | 기존 두 Unit 로컬 구현·Review 완료. Unit 3의 Design과 Implementation Plan 2026-09-24 승인, 로컬 구현·테스트·Review 완료 |
| RR/Secret 제약 수정 | Ideation·수정 Inception·Unit 3 Construction 계획 승인. 모드별 Secret과 RR 조합 수정 완료, AWS 확인 대기 |
| 구현과 테스트 | 일반 RDS 수정 후 mock Plan 16개, Aurora 회귀 mock Plan 14개 PASS |
| Terraform Plan과 Apply | 미수행 |
| AWS 리소스 확인 | 미수행. 일반 RDS RR과 RDS 관리형 관리자 Secret의 AWS 제약 확인 |
| 커밋과 푸시 | 구현 커밋 `aa26615` 원격 main 포함 확인. 상태 기록은 후속 문서 커밋에 반영 |
| Operation | 실제 배포·관측·복구 미수행. 배포 전 점검과 삭제 절차를 README에 기록 |

## 1. Ideation

### 문제 정의

착수 당시 저장소에는 관계형 데이터베이스 모듈이 없었습니다. 환경별 Root Module에서 일반 RDS DB 인스턴스 또는 Aurora 클러스터를 반복해서 구성해야 했습니다. 두 방식은 리소스와 읽기 복제 구조가 다르므로 독립적으로 사용할 수 있는 모듈 경계가 필요했습니다.

### 사용자

- `env/dev`, `env/stg`, `env/prd`에서 데이터베이스를 구성하는 작성자
- 쓰기와 읽기 연결을 구분하고 백업 및 삭제 정책을 관리하는 운영자

### 성공 기준

- PostgreSQL 또는 MySQL 기반 일반 RDS와 Provisioned Aurora 중 필요한 구성을 선택해 생성할 수 있습니다.
- 일반 RDS의 Read Replica 또는 Aurora의 reader 인스턴스를 0개 이상 정의할 수 있습니다.
- 쓰기 연결 주소와 실제 복제본의 읽기 연결 주소를 구분해 출력합니다.
- 기존 Network의 Private Subnet과 기존 Security Group을 연결하고 비공개·암호화·백업·관리자 암호 관리 정책을 적용합니다.
- 필요한 DB 사용자에게 IAM 기반 로그인 경로를 선택적으로 제공할 수 있습니다.

### Scope

- `modules/rds/instance`: PostgreSQL 또는 MySQL 기본 DB 인스턴스 하나, 선택적 Multi-AZ DB 인스턴스, 같은 Region의 Read Replica 0개 이상
- `modules/rds/aurora`: Aurora PostgreSQL 또는 Aurora MySQL Provisioned 클러스터 하나, writer 인스턴스 하나와 reader 인스턴스 0개 이상
- 각 모듈이 생성하는 DB Subnet Group, 기존 Security Group 참조, 암호화와 백업, 삭제 보호와 최종 스냅샷, RDS가 관리하는 관리자 암호, 선택적 IAM DB 인증 활성화
- Root Module 연결 예시와 식별자, 쓰기·읽기 연결 정보, 관리자 Secret ARN 및 IAM 접속 권한 정책에 필요한 Resource ID 출력

### Non-goals

- Aurora Serverless v2, Aurora Global Database, 다른 Region의 복제본과 복제본의 복제본
- 일반 RDS Multi-AZ DB 클러스터, RDS Proxy, 읽기 부하 자동 확장
- VPC, Subnet, Security Group, KMS 키, DB 사용자·스키마·파라미터 그룹 및 DB 접속 주체용 IAM Policy·Role 생성
- 관리자 계정의 IAM 인증 전환 또는 IAM 로그인 설정
- 실제 AWS 계정에 Plan, Apply, 배포

2026-09-23 사용자가 기존 모듈 작업 순서의 다음 항목인 RDS 진행을 요청했습니다. 이후 Aurora와 RR(Read Replica)을 범위에 추가했고, Aurora Serverless v2는 이번 범위에서 제외하고 Provisioned만 우선하겠다고 답했습니다. 당시의 Ideation 범위는 2026-09-23 승인됐습니다.

2026-09-23 추가 피드백으로 IAM 기반 DB 접속 옵션을 요청했습니다. 같은 날 관리자는 제외하고 일반 DB 사용자용 IAM 인증만 포함하기로 범위를 확정했습니다. PostgreSQL과 MySQL 모두 이 기능을 지원합니다. 당시 관리자 암호는 RDS가 Secrets Manager에서 관리하도록 설계했고, 2026-09-24 Unit 3에서 일반 RDS RR용 모드를 추가했습니다. 수정된 Inception과 최초 두 Unit의 Construction 계획은 2026-09-23 승인됐습니다.

## 2. Inception

아래 2~3절은 최초 RDS/Aurora 구현 당시 승인된 계약과 검증 기록입니다. 일반 RDS의 `read_replicas`와 RDS 관리형 관리자 Secret을 함께 허용한다는 부분은 5절의 AWS 제약 때문에 수정 대상입니다. 수정 Inception 제안은 6절에 기록합니다.

### Functional Requirements

#### 공통

- Root Module은 `modules/rds/instance`와 `modules/rds/aurora`를 각각 독립적으로 호출합니다. `modules/rds`는 분류용 디렉터리이며 단일 모드 전환 모듈이 아닙니다.
- 두 모듈은 명시적인 식별자, 엔진과 엔진 버전, 관리자 사용자 이름, DB 인스턴스 클래스, Private Subnet ID 목록과 기존 Security Group ID 목록, 선택적 태그를 받습니다. 일반 RDS의 엔진은 `postgres` 또는 `mysql`, Aurora의 엔진은 `aurora-postgresql` 또는 `aurora-mysql`로 제한합니다.
- 각 모듈은 전달받은 Subnet ID로 DB Subnet Group 하나를 만듭니다. Subnet ID는 중복 없는 두 개 이상이어야 합니다. 실제로 서로 다른 AZ와 Private Subnet인지 여부는 AWS 환경 또는 Root Module에서 확인합니다.
- 모든 DB 인스턴스와 Aurora 인스턴스는 공개 접근을 비활성화합니다. 네트워크 접근 규칙은 전달받은 Security Group에서 관리하고 모듈은 규칙을 추가하지 않습니다.
- 저장 데이터 암호화를 활성화합니다. 호출자는 스토리지 암호화용 기존 KMS 키 ID와 관리자 Secret 암호화용 기존 KMS 키 ID를 각각 선택적으로 전달할 수 있습니다. 모듈은 KMS 키를 만들지 않습니다.
- 관리자의 평문 비밀번호는 입력받거나 출력하지 않습니다. RDS의 Secrets Manager 관리 기능을 사용하고 Secret ARN을 출력합니다. 선택한 Secret KMS 키가 없으면 AWS 기본 키를 사용합니다.
- `iam_database_authentication_enabled`를 선택적으로 받아 기본값 `false`로 둡니다. 활성화하면 DB의 IAM 인증 기능을 켭니다. IAM 접속은 인증 토큰을 사용하며, `rds-db:connect` 권한을 가진 IAM 주체와 해당 인증 방식으로 설정된 DB 사용자가 따로 필요합니다. 이 옵션은 관리자 Secret을 제거하거나 DB 사용자와 IAM 권한을 생성하지 않습니다.
- 관리자 계정은 IAM 접속 대상으로 구성하지 않고 Secrets Manager 암호 인증을 유지합니다. PostgreSQL에서 관리자에게 `rds_iam` 역할을 부여하면 IAM 로그인이 암호 로그인보다 우선하므로 부여하지 않도록 README에 안내합니다. PostgreSQL은 별도 사용자에게 `rds_iam` 역할을 부여하고, MySQL은 별도 사용자를 `AWSAuthenticationPlugin`으로 구성합니다.
- 자동 백업 보존 기간은 기본 7일이며 1~35일 범위에서 바꿀 수 있습니다. 삭제 보호는 기본 활성화하고, 기본 삭제 정책은 최종 스냅샷을 남깁니다. 최종 스냅샷의 이름은 입력으로 바꾸거나 식별자에서 결정합니다.
- PostgreSQL/MySQL의 엔진 버전과 클래스는 호출자가 명시합니다. 엔진 버전의 AWS Region 지원 여부 및 클래스 조합은 실제 AWS가 검증합니다. RDS Extended Support 등록은 기본 비활성화하고 필요할 때만 명시적으로 활성화합니다. 지원 종료 버전은 AWS가 생성을 거부하거나 상위 버전으로 자동 업그레이드할 수 있으므로 실제 Plan·Apply 전에 확인합니다.

#### 일반 RDS 인스턴스

- `modules/rds/instance`는 기본 DB 인스턴스 하나를 만들고 스토리지 용량을 입력받습니다. 스토리지 유형의 기본값은 `gp3`이며 호출자가 변경할 수 있습니다.
- Multi-AZ DB 인스턴스 옵션의 기본값은 `false`입니다. 이 고가용성 대기 인스턴스와 읽기용 Read Replica는 별개의 설정입니다.
- `read_replicas`는 논리 키를 사용하는 Map이며 기본값은 `{}`입니다. 각 항목은 고유 식별자와 선택적 인스턴스 클래스 및 삭제 보호 설정을 지정하고, 같은 Region의 기본 DB 인스턴스를 복제 원본으로 사용합니다. 클래스 생략 시 기본 인스턴스 클래스를 사용하고 복제본 삭제 보호는 기본 활성화합니다.
- 읽기 복제본은 관리자 암호, 초기 DB 이름 또는 최종 스냅샷 식별자를 별도로 받지 않습니다. 기본 DB 인스턴스와 같은 DB Subnet Group과 Security Group을 사용합니다.
- IAM DB 인증 옵션은 기본 DB 인스턴스와 모든 Read Replica에 동일하게 적용합니다. 복제본의 IAM 접속 권한은 각 복제본의 Resource ID를 사용합니다.
- 기본 DB 인스턴스의 ID, ARN, Resource ID, 쓰기 주소와 포트, Secret ARN, 논리 키별 Read Replica ID·Resource ID·주소 Map을 출력합니다. 복제본이 없으면 Map은 비어 있습니다.

#### Provisioned Aurora

- `modules/rds/aurora`는 `engine_mode = "provisioned"`인 클러스터 하나와 writer 인스턴스 하나를 만듭니다. Serverless 인스턴스 클래스와 Serverless v2 용량 설정은 받지 않습니다.
- `readers`는 논리 키를 사용하는 Map이며 기본값은 `{}`입니다. 각 항목은 고유 식별자와 선택적 인스턴스 클래스 및 장애 조치 우선순위를 지정합니다. 클래스 생략 시 writer 클래스를 사용합니다.
- writer와 reader는 같은 클러스터 및 DB Subnet Group을 사용하고, reader는 writer가 생성된 후 추가합니다. 저장 데이터 암호화, 백업, 관리자 암호와 삭제 정책은 클러스터에서 관리합니다.
- IAM DB 인증 옵션은 클러스터에서 설정하고 writer·reader에 공통 적용합니다. IAM 접속 권한은 클러스터 Resource ID를 사용합니다.
- 클러스터 ID와 ARN, Resource ID, writer 주소와 포트, Secret ARN, 논리 키별 reader 인스턴스 주소 Map을 출력합니다. reader가 하나 이상일 때만 클러스터 reader endpoint를 출력하고, 없으면 `null`로 출력합니다. Aurora의 실제 reader endpoint는 사용 가능한 reader가 없을 때 writer를 가리킬 수 있으므로, 이 출력만으로 읽기 전용 연결을 보장하지는 않습니다.

### Non-Functional Requirements

- Terraform `>= 1.5.0` 및 AWS Provider `>= 6.24` 조건을 기존 모듈과 맞춥니다. 읽기 복제본 Map의 키는 Plan 시점에 결정되어 안정적인 `for_each` 주소가 됩니다.
- 잘못된 엔진, 비어 있는 식별자, 중복 Subnet ID, 부족한 Subnet 또는 Security Group, 유효하지 않은 백업 기간, 중복 복제본 식별자를 실제 AWS 호출 전에 거부합니다. AWS 고유의 엔진·버전·인스턴스 클래스·AZ·KMS·네트워크 연결 가능성은 mock Plan으로 확인하지 못합니다.
- 기본 구성에는 읽기 복제본이 없으며, 복제본 수를 명시해야 추가 DB 인스턴스 비용이 생깁니다. 실제 AWS 생성 전에는 Region별 지원과 비용을 Root Module에서 확인합니다.
- IAM DB 인증은 엔진 버전과 Region 지원, 추가 메모리 요구, 연결 빈도 제약을 고려해 선택합니다. mock Plan은 기능 플래그만 검증하며 실제 토큰 로그인과 접속 권한을 검증하지 않습니다.
- AWS 자격 증명 없이 mock provider Plan 테스트를 실행할 수 있어야 합니다. `terraform validate`와 mock 테스트는 실제 AWS Plan, Apply, 백업 복구 또는 복제 지연 검증을 대신하지 않습니다.
- README는 Root Module에서 Private Subnet ID와 Security Group ID를 연결하는 예시, 쓰기·읽기 주소의 차이, 삭제 보호와 최종 스냅샷 정책, IAM 접속에 필요한 DB 사용자·IAM 정책·토큰·TLS 절차를 설명합니다.

### Architecture

```text
Root Module
  Network Private Subnet IDs + Security Group ID
             |                               |
             v                               v
  modules/rds/instance              modules/rds/aurora
    aws_db_subnet_group               aws_db_subnet_group
    aws_db_instance.primary           aws_rds_cluster
    aws_db_instance.replica[key]      aws_rds_cluster_instance.initial_writer
                                     aws_rds_cluster_instance.reader[key]
             |                               |
             v                               v
  primary endpoint + replica Map     writer endpoint + reader endpoint/Map
  master Secret ARN + Resource IDs   master Secret ARN + cluster Resource ID
```

두 모듈은 서로 의존하지 않습니다. 같은 환경에서 둘 중 하나만 사용하거나 필요하면 각각 별도로 호출합니다. 일반 RDS의 Read Replica는 각자 주소가 있고, Aurora는 reader가 있을 때 클러스터 reader endpoint로 읽기 연결을 분산합니다.

### Unit of Work

1. 일반 RDS PostgreSQL/MySQL 인스턴스, 선택적 Multi-AZ 및 같은 Region의 Read Replica 모듈
2. Provisioned Aurora PostgreSQL/MySQL 클러스터, writer 및 reader 인스턴스 모듈

각 Unit은 별도의 Design, Implementation Plan, Approval, Implementation, Test, Review 순서를 따릅니다.

### Acceptance Criteria

- 일반 RDS 기본 mock Plan에 Private DB Subnet Group과 암호화·비공개·관리자 암호 관리·백업·삭제 보호가 설정된 기본 DB 인스턴스 하나가 있고, Read Replica는 없습니다.
- 일반 RDS의 `read_replicas`에 두 논리 키를 넣으면 기본 DB를 원본으로 하는 복제본 두 개와 키별 출력이 생깁니다. Multi-AZ 옵션은 Read Replica 개수와 독립적으로 동작합니다.
- Aurora 기본 mock Plan에 DB Subnet Group, Provisioned 클러스터, writer 인스턴스 하나만 있고, reader Map은 비며 공개하는 reader endpoint 출력은 `null`입니다.
- Aurora의 `readers`에 두 논리 키를 넣으면 같은 클러스터에 reader 인스턴스 두 개가 생기고 reader endpoint와 키별 주소를 출력합니다.
- 두 모듈 모두 PostgreSQL 및 MySQL 엔진 경로, 선택적 KMS 키와 삭제 옵션을 확인합니다. 잘못된 엔진, Subnet, Security Group, 백업 기간, 식별자 조합은 거부합니다.
- 두 모듈의 IAM 인증 기본값 `false`와 선택값 `true`가 Plan에 반영되는지 확인합니다. 일반 RDS는 기본 DB와 모든 복제본에 같은 설정을 적용하고 각각의 Resource ID를 출력합니다. Aurora는 클러스터에 적용하고 클러스터 Resource ID를 출력합니다. IAM 사용 설정에서도 관리자 Secret 관리가 유지되는지 확인합니다.
- Terraform 포맷, 구성 검증, mock 테스트를 실제 실행한 뒤 날짜·명령·결과를 이 문서와 `docs/README.md`에 기록합니다. 실제 AWS Plan·Apply는 별도로 구분합니다.

### Approval

2026-09-23 사용자가 당시 Inception 요구사항, Architecture, Unit of Work, Acceptance Criteria를 승인했습니다. 같은 날 요청한 일반 DB 사용자 IAM 인증 옵션을 위에 추가하고 관리자 계정은 범위에서 제외했습니다. 수정된 Inception도 2026-09-23 승인됐습니다.

## 3. Construction 준비

두 Unit의 Design과 Implementation Plan은 2026-09-23 승인됐습니다. IAM DB 인증 활성화는 일반 DB 사용자 대상 옵션이며, 관리자는 Secrets Manager 암호 인증을 유지합니다.

### Unit 1: 일반 RDS DB 인스턴스와 Read Replica

#### Design

| 항목 | 결정 |
|---|---|
| 모듈 경계 | `modules/rds/instance`가 DB Subnet Group 하나, 기본 `aws_db_instance` 하나, 논리 키별 복제본 0개 이상을 소유 |
| 네트워크 | 호출자가 Private Subnet ID 두 개 이상과 기존 Security Group ID를 전달. 기본 인스턴스와 복제본 모두 같은 DB Subnet Group을 사용하고 `publicly_accessible = false`로 고정 |
| 엔진과 저장소 | `postgres` 또는 `mysql`, 명시한 엔진 버전·인스턴스 클래스·초기 용량. 저장소 유형은 `gp3` 기본, 선택 가능한 다른 유형은 `gp2`까지로 제한 |
| 인증과 암호화 | 기본 인스턴스에서 `manage_master_user_password = true`, `storage_encrypted = true`. `iam_database_authentication_enabled`는 기본 `false`, 선택 시 기본 인스턴스와 모든 복제본에 `true` 적용. 복제본에는 비밀번호를 전달하지 않음. 스토리지 KMS 키와 Secret KMS 키는 각각 선택 사항 |
| 복제본 | `read_replicas` Map의 키로 `for_each` 주소를 고정. 각 항목에 식별자와 선택적 클래스·삭제 보호 지정. 같은 Region과 DB Subnet Group을 명시하므로 원본의 ARN을 `replicate_source_db`에 사용 |
| 고가용성 | `multi_az = false` 기본. Multi-AZ 대기 인스턴스와 읽기 복제본을 서로 독립적으로 설정 |
| 데이터 보존 | 백업 7일, 삭제 보호와 최종 스냅샷 생성 기본 활성화. 기본 인스턴스의 최종 스냅샷 이름은 식별자에 `-final`을 붙이고 재사용 시 호출자가 바꿀 수 있음. 복제본은 최종 스냅샷을 만들 수 없어 `skip_final_snapshot = true` |
| 업데이트와 비용 | `apply_immediately = false`로 유지. Extended Support는 기본 비활성화하고 명시적으로만 활성화. 리소스와 Secret의 실제 과금은 AWS Apply 뒤 시작 |
| 출력 | 기본 인스턴스 ID·ARN·Resource ID·주소·포트·Secret ARN, 복제본 논리 키별 ID·Resource ID·주소 Map. 복제본이 없으면 빈 Map |

입력 이름은 `identifier`, `engine`, `engine_version`, `instance_class`, `allocated_storage`, `storage_type`, `db_name`, `port`, `subnet_ids`, `security_group_ids`, `master_username`, `kms_key_id`, `secret_kms_key_id`, `iam_database_authentication_enabled`, `backup_retention_period`, `deletion_protection`, `skip_final_snapshot`, `final_snapshot_identifier`, `extended_support_enabled`, `multi_az`, `read_replicas`, `tags`로 정합니다. `db_name`과 KMS 키는 선택 사항이고, `port`를 생략하면 엔진별 기본 포트(5432 또는 3306)를 사용합니다. `read_replicas`의 값은 `identifier` 필수, `instance_class`와 `deletion_protection` 선택입니다. 복제본 삭제 보호의 기본값은 `true`입니다.

식별자는 AWS RDS 이름 규칙에 맞춰 검증하고 기본 인스턴스와 복제본 간 중복을 거부합니다. `allocated_storage`는 20~65536 GiB 정수, `port`는 1~65535 정수, 백업 기간은 1~35일 정수여야 합니다. Subnet과 Security Group 목록은 비어 있거나 중복된 값을 거부합니다. `skip_final_snapshot = true`와 명시적인 `final_snapshot_identifier`를 함께 주는 경우도 거부합니다. 실제 엔진·버전·클래스·용량 조합과 Subnet AZ는 AWS가 확인합니다.

#### Implementation Plan

1. `modules/rds/instance`에 `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`를 만들고 입력 계약과 검증을 정의합니다.
2. DB Subnet Group과 기본 DB 인스턴스를 구성합니다. 읽기 복제본은 Map `for_each`로 생성하고 기본 인스턴스를 복제 원본으로 참조합니다. IAM 인증 플래그를 기본 DB와 모든 복제본에 적용하고 각각의 Resource ID를 출력합니다. 복제본을 제거하려면 해당 항목의 삭제 보호를 `false`로 적용한 뒤 Map에서 제거하는 절차를 README에 기록합니다.
3. README에 PostgreSQL/MySQL 기본 구성, Multi-AZ와 복제본의 차이, Root Module의 Network·Security Group 연결, Secret ARN 사용, 최종 스냅샷 재사용 주의를 설명합니다. IAM 연결을 위해 기본 DB와 복제본마다 다른 Resource ID로 `rds-db:connect` 범위를 작성하고, 별도 DB 사용자·토큰·TLS를 준비하는 예시도 포함합니다.
4. mock provider Plan 테스트로 기본 안전 설정, 복제본 0개·2개, Multi-AZ의 독립성, 두 엔진의 기본 포트, 선택적 KMS 키, IAM 인증 꺼짐·켜짐 및 잘못된 입력 거부를 확인합니다. IAM 인증을 켜도 관리자 Secret 관리가 유지되는지 확인합니다.
5. Terraform 포맷, 구성 검증, mock 테스트를 실제 실행하고 결과를 기록한 뒤 코드와 문서를 Review합니다. 실제 AWS Plan·Apply와 복제 지연 확인은 별도 단계로 남깁니다.

#### Approval

2026-09-23 사용자 승인. 구현을 진행합니다.

#### Implementation, Test, Review

2026-09-23 `modules/rds/instance`에 기본 DB, 선택적 Multi-AZ와 Read Replica, 관리자 Secret, 일반 사용자 IAM 인증 옵션, 출력, README 및 mock 테스트를 구현했습니다. 초기 mock 테스트에서 생성 전 Secret 출력의 빈 목록 참조가 실패해 `try(one(...).secret_arn, null)`로 수정했습니다. 공급자 `id`와 DB 식별자가 혼동되지 않도록 식별자 출력은 `identifier` 필드를 사용합니다. 당시 코드와 README의 로컬 Review를 완료했습니다.

2026-09-23 후속 확인에서 [AWS RDS의 Secrets Manager 관리 제약](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)을 발견했습니다. AWS는 관리자 인증 정보를 Secrets Manager에서 관리하는 원본 DB에서 Read Replica 생성을 지원하지 않습니다(RDS for SQL Server 예외). 현재 PostgreSQL/MySQL 일반 RDS 모듈은 `manage_master_user_password = true`로 고정하고 `read_replicas`도 허용하므로, 이 조합의 mock Plan PASS는 AWS Apply 가능성을 증명하지 않습니다. 기본 DB만 쓰는 구성과 Aurora 클러스터의 reader 구성은 이 특정 제약의 대상이 아닙니다. 일반 RDS RR 경로의 관리자 암호 관리 방식과 모듈 계약을 다시 설계해야 합니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -check -recursive modules/rds/instance` | PASS |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform validate -no-color` (초기화된 임시 복사본) | PASS |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform test -no-color` (초기화된 임시 복사본) | 11 PASS, 0 FAIL |

### Unit 2: Provisioned Aurora 클러스터와 reader

#### Design

| 항목 | 결정 |
|---|---|
| 모듈 경계 | `modules/rds/aurora`가 DB Subnet Group 하나, `aws_rds_cluster` 하나, 최초 인스턴스 하나와 논리 키별 reader 0개 이상을 소유 |
| 엔진과 인스턴스 | `aurora-postgresql` 또는 `aurora-mysql`만 허용. 클러스터 `engine_mode = "provisioned"`, writer 클래스와 reader별 선택적 클래스에 `db.serverless`를 거부 |
| 생성 순서 | 최초 `aws_rds_cluster_instance.initial_writer`를 만든 후 `aws_rds_cluster_instance.reader[key]`를 추가. Aurora가 장애 조치 시 역할을 바꾸므로 특정 인스턴스를 영구 writer로 가정하지 않음 |
| 네트워크 | 클러스터와 모든 인스턴스에 같은 DB Subnet Group 사용. 인스턴스는 `publicly_accessible = false`, 클러스터는 기존 Security Group ID 사용 |
| 인증과 데이터 보호 | 클러스터가 관리자 Secret, 저장 데이터 암호화, 백업 7일, 삭제 보호, 최종 스냅샷을 소유. `iam_database_authentication_enabled`는 클러스터에서 기본 `false`, 선택 시 `true`. Aurora 인스턴스에 별도 삭제 보호 설정은 없음 |
| reader | `readers` Map으로 안정적인 주소 부여. 각 항목은 식별자, 선택적 클래스, 0~15의 장애 조치 우선순위를 받음. 기본 클래스는 최초 인스턴스와 같고 기본 우선순위는 1 |
| 쓰기·읽기 출력 | 쓰기 주소는 장애 조치에도 현재 writer를 가리키는 클러스터 endpoint를 사용. 설정된 reader가 하나 이상일 때만 클러스터 reader endpoint를 출력하고, 0개면 `null`. reader 인스턴스 주소는 논리 키별 Map이지만 장애 조치 뒤 역할이 바뀔 수 있음. IAM 정책에 쓸 클러스터 Resource ID도 출력 |
| 업데이트와 비용 | 엔진 버전은 클러스터에서 관리하고 인스턴스는 이를 따름. `apply_immediately = false`, Extended Support 기본 비활성화. 실제 과금은 AWS Apply 뒤 시작 |

입력 이름은 `cluster_identifier`, `writer_identifier`, `engine`, `engine_version`, `writer_instance_class`, `database_name`, `port`, `subnet_ids`, `security_group_ids`, `master_username`, `kms_key_id`, `secret_kms_key_id`, `iam_database_authentication_enabled`, `backup_retention_period`, `deletion_protection`, `skip_final_snapshot`, `final_snapshot_identifier`, `extended_support_enabled`, `readers`, `tags`로 정합니다. `database_name`과 KMS 키는 선택 사항이며 `port`를 생략하면 엔진별 기본 포트(5432 또는 3306)를 사용합니다. `readers`의 값은 `identifier` 필수, `instance_class`와 `promotion_tier` 선택입니다.

클러스터와 인스턴스 식별자를 검증하고 최초 인스턴스와 reader 식별자의 중복을 거부합니다. `promotion_tier`는 0~15 정수, 백업 기간은 1~35일 정수로 제한합니다. 최종 스냅샷 이름의 기본값은 클러스터 식별자에 `-final`을 붙이고, 명시적인 이름과 `skip_final_snapshot = true`는 함께 허용하지 않습니다. Region에서 엔진 버전과 클래스가 지원되는지는 실제 AWS가 확인합니다.

#### Implementation Plan

1. `modules/rds/aurora`에 `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`를 만들고 클러스터 및 reader 입력 검증을 정의합니다.
2. DB Subnet Group, Provisioned Aurora 클러스터, 최초 인스턴스, Map 기반 reader를 순서대로 연결합니다. 클러스터에만 관리자 Secret과 삭제 보호 및 IAM 인증 플래그를 설정합니다.
3. 클러스터 endpoint를 writer 주소로, reader가 있을 때만 reader endpoint를 읽기 주소로 출력합니다. IAM 정책에 쓸 클러스터 Resource ID도 출력합니다. README에 사용 가능한 reader가 0개면 AWS reader endpoint가 writer를 가리킬 수 있다는 점과 장애 조치 시 인스턴스 역할 변경을 설명합니다. 인스턴스별 주소 Map은 읽기 전용 보장 용도로 사용하지 않도록 안내합니다.
4. README에 두 엔진, Network·Security Group 연결, reader 추가와 장애 조치 우선순위, Secret ARN과 최종 스냅샷 정책을 예시로 작성합니다. IAM 연결을 위한 `rds-db:connect` 정책 범위, 별도 DB 사용자, 토큰과 TLS 준비 절차를 설명합니다.
5. mock provider Plan 테스트로 클러스터+최초 인스턴스, reader 0개·2개, 출력의 조건부 `null`, 두 엔진, KMS와 삭제 옵션, IAM 인증 꺼짐·켜짐, Serverless 클래스 및 잘못된 입력 거부를 확인합니다. IAM 인증을 켜도 관리자 Secret 관리가 유지되는지 확인합니다.
6. Terraform 포맷, 구성 검증, mock 테스트를 실제 실행하고 결과를 기록한 뒤 코드와 문서를 Review합니다. 실제 AWS Plan·Apply와 장애 조치 확인은 별도 단계로 남깁니다.

#### Approval

2026-09-23 사용자 승인. Unit 1 Review 뒤 구현합니다.

#### Implementation, Test, Review

2026-09-23 `modules/rds/aurora`에 Provisioned 클러스터, 최초 인스턴스와 Map 기반 reader, 관리자 Secret, 일반 사용자 IAM 인증 옵션, 출력, README 및 mock 테스트를 구현했습니다. 클러스터 endpoint를 writer 주소로 사용하고 reader가 없으면 reader endpoint 출력이 `null`이 되도록 했습니다. 코드와 README를 검토했고 승인 범위와 일치합니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform fmt -check -recursive modules/rds/aurora` | PASS |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform validate -no-color` (초기화된 임시 복사본) | PASS |
| 2026-09-23 | `/tmp/terraform-1.13.3/terraform test -no-color` (초기화된 임시 복사본) | 14 PASS, 0 FAIL |

## 문서 검토

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-23 | `git diff --check` | PASS, 추적 중인 `docs/README.md` 변경에 공백 오류 없음 |
| 2026-09-23 | `rg -n '[[:blank:]]+$' docs/README.md docs/ai-dlc/rds-module.md` | 일치 없음(exit 1), 새 문서를 포함해 줄 끝 공백 없음 |
| 2026-09-23 | `rg -n '[[:blank:]]+$' modules/rds/instance/README.md modules/rds/aurora/README.md docs/ai-dlc/rds-module.md` | 일치 없음(exit 1), 입력·출력 속성 표를 포함해 줄 끝 공백 없음 |
| 2026-09-24 | `git diff --check` | PASS, 추적 중인 변경의 공백 오류 없음 |
| 2026-09-24 | `rg -n '[[:blank:]]+$' docs/README.md docs/ai-dlc/rds-module.md modules/rds/instance/README.md modules/rds/instance/main.tf modules/rds/instance/variables.tf modules/rds/instance/versions.tf modules/rds/instance/outputs.tf modules/rds/instance/tests-terraform-1.17/instance.tftest.hcl` | 일치 없음(exit 1), 미추적 파일을 포함해 줄 끝 공백 없음 |

두 Unit의 최초 수정 Inception과 Construction 계획은 승인됐고 로컬 구현·검증·Review를 완료했습니다. 당시 발견한 일반 RDS RR과 관리형 관리자 Secret의 AWS 제약은 7절 Unit 3에서 로컬 설계를 수정했습니다. 실제 AWS Plan·Apply, 백업 복구, 복제 상태, 장애 조치와 IAM 로그인은 검증하지 않았습니다.

2026-09-23 사용자 요청에 따라 두 모듈 README에 전체 입력·출력 속성 표와 변경 가능한 백업 설정을 추가했습니다. Terraform 리소스 구성이나 이전 mock 테스트 결과는 변경하지 않았습니다.

2026-09-23 IAM DB 인증 사용 방식의 후속 질문에 따라 README에 접속 주체의 IAM Role 선택, `rds-db:connect` 정책 연결 예시, PostgreSQL 내부 `rds_iam` 역할과 AWS IAM Role의 차이를 명시했습니다. DB 모듈은 특정 IAM Role을 입력받거나 생성하지 않습니다.

## 4. Operation

- Deployment: 환경별 Root Module과 실제 AWS 계정이 아직 없으므로 Plan, Apply, 배포를 실행하지 않았습니다. 배포 전 엔진 버전·인스턴스 클래스·Subnet AZ·KMS 권한·비용을 확인해야 합니다.
- Observability: 실제 배포 후 인스턴스/클러스터 상태, 백업 성공, 복제 지연, 장애 조치 및 IAM 로그인 성공 여부를 확인해야 합니다. 현재 측정 기록은 없습니다.
- Rollback: 삭제 보호를 해제해야 제거할 수 있으며, 기본 정책은 최종 스냅샷을 남깁니다. 복제본을 먼저 제거하는 절차, 스냅샷 이름 충돌 및 모듈 소유 Secret의 기본 30일 복구 대기 기간은 README에 기록했습니다. 실제 복구는 검증하지 않았습니다.
- Runbook: [일반 RDS README](../../modules/rds/instance/README.md), [Aurora README](../../modules/rds/aurora/README.md)에 구성, 접속, IAM 사용자와 삭제 절차를 기록했습니다. 일반 RDS의 모듈 소유 Secret은 자동 회전하지 않으며 운영 전 별도 회전·복구 절차가 필요합니다.

## 5. 일반 RDS RR과 관리자 Secret 제약 해결: Ideation

상태: 2026-09-23 사용자 승인. 승인 당시에는 미구현이었고 2026-09-24 Unit 3에서 로컬 구현·검증했습니다.

### 문제 정의

[AWS RDS 공식 문서](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)는 RDS가 원본 DB의 관리자 인증 정보를 Secrets Manager에서 관리하면 PostgreSQL/MySQL Read Replica 생성을 지원하지 않는다고 명시합니다. 현재 일반 RDS 모듈은 `manage_master_user_password = true`를 고정하고 `read_replicas`를 허용하므로 두 요구를 동시에 충족하지 못합니다. Aurora의 같은 클러스터 내 reader 인스턴스는 별도 구조입니다.

### 사용자와 성공 기준

- 일반 RDS에 실제 Read Replica가 필요한 Root Module 작성자는 지원되는 관리자 암호 관리 방식을 명시적으로 선택할 수 있어야 합니다.
- 기본 DB만 필요한 작성자는 현재의 RDS 관리형 Secret 방식을 계속 사용할 수 있어야 합니다.
- 관리자 암호를 Terraform Plan 또는 State에 평문으로 저장하지 않고, 배포 후 관리자 인증 정보는 Secrets Manager에서 조회할 수 있어야 합니다.
- 지원하지 않는 모드와 `read_replicas` 조합은 실제 AWS 호출 전에 거부해야 합니다.

### 권장 범위

- 일반 RDS 모듈에 **명시적 관리자 암호 모드**를 추가합니다. 기본 `rds_managed`는 현재 방식을 유지하고 `read_replicas = {}`만 허용합니다. `module_managed_secret`은 모듈이 별도 Secrets Manager Secret과 암호를 만들고 일반 RDS Read Replica를 허용합니다. 모드 전환은 관리자 암호와 Secret의 소유권을 바꾸므로 명시적으로 입력받습니다.
- `module_managed_secret`에서는 Terraform 1.11 이상의 ephemeral 값과 AWS Provider의 `password_wo`/`secret_string_wo`를 사용해 암호가 Plan·State에 남지 않도록 설계합니다. Secret ARN 출력은 두 모드 모두 제공합니다. 정확한 생성·갱신 순서와 회전 절차는 다음 Inception에서 결정합니다.
- Aurora 모듈의 관리자 Secret 관리와 reader 구성은 유지합니다.

### 대안과 제외 범위

| 방법 | 결과 |
|---|---|
| 현재 일반 RDS 구성에 RR 없이 사용 | 현재 코드에서 구성 가능하지만 AWS Apply는 미검증. 일반 RDS의 읽기 복제 요구는 충족하지 못함 |
| Aurora Provisioned로 reader 사용 | 현재 Aurora 모듈은 RDS 관리형 Secret과 reader를 함께 구성함. AWS Apply는 미검증이고 데이터베이스 구조와 비용이 달라짐 |
| 일반 RDS에서 모듈 관리형 Secret 사용 (권장) | 일반 RDS RR 요구를 유지. RDS의 자동 관리자 암호 회전 대신 별도 회전 절차가 필요함 |

자동 회전용 Lambda, 기존 배포 DB의 암호 방식 마이그레이션 및 실제 AWS Apply는 이번 수정의 범위에서 제외합니다. 현재 환경별 Root Module이 없고 AWS 배포도 수행하지 않았습니다.

## 6. 일반 RDS RR과 관리자 Secret 제약 해결: 수정 Inception

상태: 2026-09-23 사용자 승인. 승인 당시에는 미구현이었고 2026-09-24 Unit 3에서 로컬 구현·검증했습니다. 5절에서 승인된 Ideation을 구체화한 내용이며, 기존 Aurora 계약은 변경하지 않습니다.

### Functional Requirements

| 항목 | 요구사항 |
|---|---|
| 암호 관리 모드 | 일반 RDS 모듈에 `master_password_mode`를 추가합니다. 기본값 `rds_managed`는 현재 RDS 관리형 Secret을 유지하고, `module_managed_secret`은 모듈 소유 Secrets Manager Secret을 사용합니다. 허용값 이외는 거부합니다. |
| RR 조합 | `rds_managed`에서는 `read_replicas = {}`만 허용합니다. 복제본이 하나 이상이면 `module_managed_secret`을 명시해야 하며, 지원하지 않는 조합은 AWS 생성 요청 전에 Plan 단계에서 거부합니다. 모듈은 복제본 수에 따라 모드를 자동 변경하지 않습니다. |
| Secret과 암호 | `module_managed_secret`은 Secret과 최초 Secret Version을 만들고, 강한 임의 암호를 생성해 `{ "username": "...", "password": "..." }` JSON으로 저장합니다. 같은 암호를 Secret에서 ephemeral 값으로 읽어 기본 DB의 write-only `password_wo`에 전달합니다. `manage_master_user_password`는 이 모드에서 비활성화하고 복제본에는 별도 암호를 전달하지 않습니다. |
| KMS와 출력 | 기존 `secret_kms_key_id`는 두 모드의 관리자 Secret 암호화에 적용합니다. `master_secret_arn`은 선택한 모드에 맞는 Secret ARN을 반환합니다. 평문 암호는 입력·출력하지 않습니다. 기존 endpoint와 Resource ID 출력은 유지합니다. |
| 기존 옵션 | 엔진, 백업, 삭제 보호, Multi-AZ, 일반 DB 사용자용 IAM 인증 및 Aurora 모듈의 동작은 유지합니다. IAM 인증 옵션은 관리자 암호 모드와 독립적입니다. |

### Non-Functional Requirements

- 일반 RDS 모듈의 Terraform 최소 버전을 1.11로 올리고, write-only 인수를 지원하는 AWS Provider와 ephemeral 암호 생성기를 사용합니다. 선택한 공급자 버전은 Construction에서 고정·검증합니다.
- 암호값은 Terraform 구성, Plan, State, 출력에 저장하지 않습니다. 버전 번호나 Secret ARN 같은 비밀이 아닌 메타데이터는 State에 남을 수 있습니다. AWS 호출 중 암호값은 Secrets Manager와 RDS에 전달됩니다.
- Secret Version을 기본 DB보다 먼저 생성하고, 기본 DB는 저장된 Secret Version을 ephemeral 방식으로 읽어 사용합니다. DB 재생성에도 기존 Secret 암호를 재사용하도록 하며, 새 임의값을 무조건 생성해 DB와 Secret이 어긋나지 않게 합니다.
- Secret 버전 변경과 DB 암호 변경은 원자적 작업이 아닙니다. 이번 Unit에서는 초기 생성 경로만 지원하고 모듈을 통한 암호 회전은 제공하지 않습니다. 자동 회전용 Lambda와 기존 배포 DB의 모드 변경도 범위에서 제외합니다. 운영 전 별도 회전·복구 절차가 필요하다는 제약을 README에 명시합니다.
- 모듈 소유 Secret의 값을 외부에서 바꾸는 작업은 이 Unit의 관리 범위 밖입니다. 별도 회전 절차 없이 Secret만 바꾸면 DB 암호와 달라질 수 있으므로 README에 운영 제한을 명시합니다.
- 실제 AWS 계정의 Plan·Apply, 복제 상태, Secret을 통한 로그인 및 복구는 로컬 mock 검증과 구분합니다.

### Architecture

```text
Root Module → modules/rds/instance
                 ├─ rds_managed (기본, RR 0개)
                 │    └─ RDS 기본 DB → RDS 관리형 Secret
                 └─ module_managed_secret (RR 0개 이상)
                      └─ 모듈 소유 Secret + Secret Version
                           → ephemeral Secret 조회 → password_wo → RDS 기본 DB
                                                             └─ RR[key] 0개 이상
```

암호 생성에는 ephemeral 랜덤 값을 사용하고, 최초 Secret Version은 `secret_string_wo`로 기록합니다. 이후 기본 DB 생성이나 재생성에는 그 Secret Version을 ephemeral 조회해 사용합니다. `secret_kms_key_id`는 `rds_managed`에서 RDS 관리형 Secret KMS 설정, `module_managed_secret`에서 모듈 소유 Secret의 KMS 설정으로 연결합니다. Secret ARN 이외의 암호 관련 값은 출력하지 않습니다.

### Unit of Work

1. 일반 RDS 인스턴스 모듈의 관리자 암호 모드와 Read Replica 조합 수정. 입력 검증, Secret 생성·조회, DB 연결, 출력, README와 mock 테스트를 한 Unit으로 다룹니다. Construction에서 Design → Implementation Plan → 승인 → 구현 → 테스트 → Review 순서를 따릅니다.

### Acceptance Criteria

- 기본 모드·복제본 0개 mock Plan은 RDS 관리형 Secret 경로와 기존 기본 DB 설정을 유지하고, 모듈 소유 Secret을 만들지 않습니다.
- 기본 모드·복제본 1개 이상의 조합 및 잘못된 모드 값은 로컬 Plan에서 실패합니다.
- `module_managed_secret`·복제본 0개와 2개 구성은 모듈 소유 Secret·Version, 비관리형 관리자 암호 경로, 논리 키별 복제본과 Secret ARN 출력을 보입니다. 복제본에는 관리자 암호를 설정하지 않습니다.
- 암호 생성부터 Secret 기록과 DB 적용까지 ephemeral/write-only 경로만 사용함을 구성과 공급자 스키마에서 확인합니다. DB 생성이 Secret Version 이후에 일어나는 의존 관계를 mock 테스트로 확인하고, 일반 `password`/`secret_string` 인수와 평문 암호 출력이 없는지 점검합니다. 실제 AWS Plan·State의 비밀값 부재, Secret 값 일치 및 로그인 성공은 AWS 환경에서 별도로 검증합니다.
- 두 모드에서 `secret_kms_key_id`와 기존 IAM 인증 옵션의 연결을 확인합니다. 기존 Aurora mock 테스트가 계속 통과하는지 확인합니다.
- Terraform 포맷, 구성 검증, 관련 mock 테스트를 실제 실행해 날짜·명령·결과를 기록합니다. 실제 AWS Plan·Apply는 수행한 경우에만 별도로 기록합니다.

### Approval

2026-09-23 사용자 승인. Construction의 상세 Design과 Implementation Plan은 7절에서 별도로 검토합니다.

## 7. 일반 RDS RR과 관리자 Secret 제약 해결: Construction 계획

상태: 2026-09-24 Design과 Implementation Plan 승인, 로컬 구현·테스트·Review 완료. 실제 AWS Plan·Apply 미수행.

### Unit 3: 일반 RDS 관리자 암호 모드와 Read Replica 조합 수정

#### Design

| 항목 | 결정 |
|---|---|
| 입력 계약 | `master_password_mode`만 새로 받습니다. 기본 `rds_managed`, 대안 `module_managed_secret`이며 다른 값은 변수 검증에서 거부합니다. RR이 있으면서 기본 모드이면 기본 DB 리소스의 precondition으로 Plan을 실패시킵니다. RR 개수로 모드를 자동 전환하지 않습니다. |
| 공급자 버전 | `modules/rds/instance`는 Terraform `>= 1.11.0`, AWS Provider `>= 6.24`와 Random Provider `>= 3.7.1, < 4.0`를 요구합니다. `ephemeral.random_password`로 32자 암호를 생성하며 PostgreSQL/MySQL 관리자 암호에서 허용되는 특수문자 집합만 사용합니다. Aurora의 버전 요구사항은 바꾸지 않습니다. |
| 모드별 리소스 | `rds_managed`에서는 현재처럼 `manage_master_user_password = true`와 선택적 `master_user_secret_kms_key_id`를 사용합니다. `module_managed_secret`에서만 `aws_secretsmanager_secret`, `aws_secretsmanager_secret_version`, ephemeral 암호 생성·Secret Version 조회를 만듭니다. 이 모드에서는 `manage_master_user_password`와 `master_user_secret_kms_key_id`를 `null`로 두고 `password_wo`를 사용합니다. |
| Secret 저장 | Secret 이름은 `<identifier>-master`로 정하고 기존 태그를 적용합니다. `secret_kms_key_id`가 있으면 모듈 소유 Secret의 `kms_key_id`에 사용합니다. Secret Version에는 `username`·`password` JSON을 `secret_string_wo`로 기록합니다. write-only 버전 번호는 관리자 사용자 이름에서 결정적으로 계산해 이름 변경 시 Secret JSON도 갱신합니다. 일반 `password`와 `secret_string` 인수는 사용하지 않습니다. |
| DB 암호 연결 | ephemeral Secret 조회는 모듈이 만든 특정 Secret Version ID를 참조합니다. 기본 DB의 `password_wo`는 조회한 JSON의 `password`를 사용합니다. `password_wo_version`은 해당 Secret Version ID에서 결정적으로 만든 숫자로 설정해, Secret Version 교체 시 DB 암호 갱신도 계획되게 합니다. 생성 순서는 Secret → Version → 조회 → 기본 DB → 복제본입니다. |
| 출력과 유지 | `master_secret_arn`은 RDS 관리형 Secret ARN 또는 모듈 소유 Secret ARN을 선택해 반환합니다. 나머지 출력·백업·IAM·Multi-AZ·복제본 속성은 유지합니다. 암호, Secret 본문 및 해시 원문은 출력하지 않습니다. |
| 수명 주기 | 이번 Unit은 최초 생성과 DB 재생성 시 기존 Secret 암호 재사용을 대상으로 합니다. Secret Version이 교체되면 DB 암호 변경이 뒤따르지만 두 AWS 작업은 원자적이지 않아 중간 불일치가 생길 수 있습니다. 계획된 회전, 기존 DB 모드 전환 및 외부 Secret 값 수정은 지원 절차로 제공하지 않고 README에 제한을 적습니다. |

Secret Version ID를 DB의 write-only 버전 입력과 연결하는 부분은 로컬 Plan에서 실제 공급자 스키마로 검증합니다. 이 연결이 공급자 제약으로 동작하지 않으면 구현을 임의로 단순화하지 않고 Design을 수정해 다시 검토합니다.

#### Implementation Plan

1. `versions.tf`에 Terraform·Random Provider 요구 버전을 선언하고, `variables.tf`에 `master_password_mode` 검증을 추가합니다.
2. `main.tf`에서 모드별 조건부 Secret·Version·ephemeral 생성/조회 및 KMS 연결을 구성합니다. 기본 DB에 서로 충돌하지 않는 `manage_master_user_password`/`password_wo` 인수를 적용하고, RR과 기본 모드의 조합을 precondition으로 차단합니다. 복제본의 기존 ARN 원본 참조와 IAM 설정은 유지합니다.
3. `outputs.tf`의 Secret ARN을 모드별로 선택합니다. README의 기본 예시에서는 RR을 빼고, RR 예시에는 `master_password_mode = "module_managed_secret"`을 명시합니다. 모드별 Secret 소유권, IAM/KMS 권한, 회전·모드 전환 제한과 배포 전 AWS 검증 항목을 설명합니다.
4. Terraform 1.17 beta의 ephemeral mock 지원을 사용해 기본 모드, 모듈 소유 Secret 모드의 RR 0개·2개, KMS/IAM/출력 및 잘못된 모드·조합을 mock Plan으로 검증합니다. 기존 1.13.3은 ephemeral mock을 지원하지 않으므로 이 모듈의 수정 후 mock 테스트 실행기로 사용하지 않습니다. Terraform 1.11 이상과 AWS/Random 공급자 스키마를 대상으로 `terraform validate`도 실행하고, Aurora의 기존 테스트를 별도로 재실행합니다.
5. 포맷·검증·테스트의 실제 날짜, 명령, 결과를 기록하고 코드·README를 Review합니다. mock 결과를 실제 AWS Plan·Apply, Secret 값 일치, RR 생성 성공 또는 로그인 성공으로 표기하지 않습니다. AWS 검증은 환경별 Root Module과 계정이 준비된 별도 Operation에서 수행합니다.

Terraform 1.13.3의 mock provider는 ephemeral 리소스를 지원하지 않습니다. [Terraform의 지원 추가 PR](https://github.com/hashicorp/terraform/pull/38928)은 2026-09-04에 병합됐고 목표 릴리스는 1.17.x입니다. 따라서 이 Unit의 mock 테스트는 현재 제공되는 1.17.0-beta1을 대상으로 계획하며, 실행 결과는 실제로 확인한 뒤 기록합니다. 이는 모듈 사용자의 최소 버전 1.11과 구분합니다.

#### Approval

2026-09-24 사용자 승인. 승인된 Design과 Implementation Plan에 따라 구현했습니다.

#### Implementation, Test, Review

2026-09-24 `master_password_mode`의 기본 `rds_managed`와 RR용 `module_managed_secret`을 구현했습니다. 모듈 소유 모드에서는 32자 ephemeral 암호를 JSON Secret Version의 `secret_string_wo`에 기록하고, 그 버전을 ephemeral 조회해 기본 DB의 `password_wo`로 전달합니다. `secret_string_wo_version`은 관리자 사용자 이름, `password_wo_version`은 Secret Version ID의 SHA-256 앞 15자리에서 각각 결정적으로 계산합니다. 사용자 이름 또는 Secret Version이 바뀌면 관련 Secret/DB 암호 갱신이 계획되며, 기본 DB만 재생성하면 기존 Secret 암호를 다시 사용합니다. Terraform 의존 그래프에서 Secret → Version → 조회 → 기본 DB → 복제본 연결을 확인했습니다.

기존 `rds_managed` 모드에서 RR을 지정하면 기본 DB precondition으로 Plan을 거부합니다. 두 엔진의 RR과 복제본 0개인 모듈 소유 모드, 두 모드의 KMS 및 IAM 연결, 기존 입력 검증을 mock Plan으로 확인했습니다. 공급자 스키마에서 `aws_db_instance.password_wo`와 `aws_secretsmanager_secret_version.secret_string_wo`의 write-only 표시와 두 ephemeral 리소스 지원을 확인했습니다. 암호 본문을 일반 `password` 또는 `secret_string` 리소스 인수나 출력에 전달하지 않습니다.

Terraform 1.13.3은 `mock_ephemeral` 테스트 문법을 파싱하지 못하므로 테스트 파일을 `tests-terraform-1.17/`에 두고 1.17.0-beta1의 `-test-directory`로 실행했습니다. 모듈 자체는 테스트 파일을 제외하지 않아도 Terraform 1.13.3에서 `validate`가 통과합니다. 테스트 도중 AWS mock의 계산 필드를 `null`로 단정한 검증과 Plan 시점에 모르는 DB ARN을 비교한 검증이 실패했습니다. mock 값의 성격에 맞게 테스트를 수정한 뒤, Review에서 발견한 관리자 사용자 이름 변경 사례를 추가했습니다. 최종 전체 16개를 재실행해 통과했습니다.

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `/tmp/terraform-1.17.0-beta1/terraform fmt -check -recursive modules/rds/instance` | PASS |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform validate -no-color` (초기화된 임시 일반 RDS 복사본) | PASS, 테스트 디렉터리 분리 후 |
| 2026-09-24 | `/tmp/terraform-1.17.0-beta1/terraform validate -no-color` (초기화된 임시 일반 RDS 복사본) | PASS |
| 2026-09-24 | `/tmp/terraform-1.17.0-beta1/terraform test -test-directory=tests-terraform-1.17 -no-color` (초기화된 임시 일반 RDS 복사본) | 16 PASS, 0 FAIL |
| 2026-09-24 | `/tmp/terraform-1.17.0-beta1/terraform graph` (초기화된 임시 일반 RDS 복사본) | PASS, Secret Version → ephemeral 조회 → 기본 DB → 복제본 의존성 확인 |
| 2026-09-24 | `/tmp/terraform-1.17.0-beta1/terraform providers schema -json > /tmp/rds-instance-unit3-provider-schema.json` (초기화된 임시 일반 RDS 복사본) | PASS, AWS write-only 인수와 AWS/Random ephemeral 스키마 확인 |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform validate -no-color` (초기화된 임시 Aurora 복사본) | PASS |
| 2026-09-24 | `/tmp/terraform-1.13.3/terraform test -no-color` (초기화된 임시 Aurora 복사본) | 14 PASS, 0 FAIL |

Review 결과, `rds_managed`와 `password_wo`가 동시에 설정되지 않으며 모듈 소유 Secret의 KMS·태그·ARN 출력과 복제본 입력은 승인 범위에 맞습니다. Secret 버전 교체와 DB 암호 변경은 AWS에서 원자적이지 않고, 기존 DB의 모드 전환과 자동 회전은 이번 Unit에서 검증하거나 지원하지 않습니다. 로컬 mock 테스트는 AWS의 실제 RR 생성·Secret 조회·로그인을 증명하지 않습니다. 환경별 Root Module이 없어 AWS Plan·Apply는 수행하지 않았습니다.

### 커밋과 푸시

| 날짜 | 명령 | 결과 |
|---|---|---|
| 2026-09-24 | `git -c user.name='Howon Jeong' -c user.email='howon2k@me.com' commit -m 'feat(rds): add instance and aurora modules with replica-safe secrets'` | 구현·테스트·문서 14개 파일 커밋 `aa266157e56ce1380f72ce34817e6ef7f014fe4b` 생성 |
| 2026-09-24 | `git push origin main` | `357f706..aa26615 main -> main` 성공 |
| 2026-09-24 | `git ls-remote origin refs/heads/main` | 원격 main SHA `aa266157e56ce1380f72ce34817e6ef7f014fe4b` 확인 |

## 근거

- [AWS RDS DB Subnet Group과 Private Subnet](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html)
- [AWS RDS DB 인스턴스 스토리지 범위](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [AWS RDS 관리자 암호 길이와 문자 제한](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html)
- [AWS RDS Read Replica](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html)
- [AWS Aurora Replica](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Replication.html)
- [AWS Aurora Reader Endpoint](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Endpoints.Reader.html)
- [AWS RDS Secrets Manager 암호 관리](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [AWS RDS IAM DB 인증과 제약](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [AWS RDS IAM DB 인증 활성화](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.Enabling.html)
- [AWS RDS IAM DB 사용자 설정](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.DBAccounts.html)
- [AWS RDS IAM 접속 권한과 Resource ID](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html)
- [AWS RDS Read Replica의 IAM DB 인증 설정](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstanceReadReplica.html)
- [AWS Aurora IAM DB 인증과 제약](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html)
- [AWS Aurora IAM 접속 권한과 Resource ID](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html)
- [AWS RDS Extended Support 요금](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/extended-support-charges.html)
- [Terraform AWS Provider DB Instance](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/db_instance.html.markdown)
- [Terraform ephemeral 값과 write-only 인수](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral)
- [Terraform write-only 인수의 버전 갱신](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only)
- [Terraform AWS Provider Secrets Manager Secret Version](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/secretsmanager_secret_version.html.markdown)
- [Terraform Random Provider의 ephemeral 암호 생성](https://github.com/hashicorp/terraform-provider-random/blob/main/docs/ephemeral-resources/password.md)
- [Terraform AWS Provider Aurora Cluster](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/rds_cluster.html.markdown)
- [Terraform AWS Provider Aurora Cluster Instance](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/rds_cluster_instance.html.markdown)
