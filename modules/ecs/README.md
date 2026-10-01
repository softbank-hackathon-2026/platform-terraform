# ECS module

ECS Cluster와 CloudWatch Logs 그룹을 만들고, 선택적으로 On-Demand Fargate 서비스 하나를 구성해요. Terraform 1.11 이상과 AWS Provider 6.24 이상 7 미만을 사용해요.

`service = null`이면 Cluster와 로그 그룹만 만들어요. 서비스가 활성화되면 Linux X86_64, awsvpc, Public IP 비활성화, AZ 재분산, 배포 Circuit Breaker와 Rollback을 사용해요. 기본 Task 수는 2개예요. 100% 최소 정상 Task와 200% 최대 Task 설정으로 배포 중 최대 4개가 실행될 수 있어요.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | Cluster, Service, Task Family 이름과 로그 그룹 접두사예요. |
| `log_group_name` | `string` | `null` → `/ecs/<name>` | Task 로그 그룹 이름이에요. dev Root Module은 네이밍 규칙에 맞는 이름을 지정해요. |
| `log_region` | `string` | `null` | 로그 그룹과 호출 AWS Provider의 Region이에요. 생략하면 조회하고, 명시하면 로그 구성이 Plan 단계에 확정돼요. 같은 Region을 지정하세요. |
| `log_retention_days` | `number` | `30` | Task 로그 보존 기간이에요. |
| `service` | `object` | `null` | Task Definition과 Service를 활성화하는 설정이에요. |
| `tags` | `map(string)` | `{}` | ECS 리소스와 로그 그룹에 붙일 태그예요. `Name`은 모듈이 각 이름으로 설정해요. |

`service`의 내부 속성이에요. CPU 단위는 1024 = 1 vCPU, 메모리 단위는 MiB예요.

| 내부 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `image` | `string` | 필수 | 컨테이너 이미지 URI예요. 운영에서는 Digest로 고정하세요. |
| `container_name` | `string` | `"app"` | 컨테이너와 ALB 등록에 사용할 이름이에요. |
| `container_port` | `number` | `8080` | 컨테이너의 TCP 포트예요. |
| `cpu` | `number` | `512` | Fargate Task CPU예요. |
| `memory` | `number` | `1024` | Fargate Task 메모리예요. CPU와 지원되는 조합이어야 해요. |
| `desired_count` | `number` | `2` | 정상 상태의 Task 수예요. 1 이상 정수예요. |
| `subnet_ids` | `list(string)` | 필수 | 서로 다른 AZ의 App Private Subnet 두 개 이상이에요. |
| `security_group_ids` | `list(string)` | 필수 | Task에 연결할 Security Group이에요. |
| `target_group_arn` | `string` | 필수 | Listener에 연결된 `ip` Target Group ARN이에요. |
| `execution_role_arn` | `string` | 필수 | ECR 이미지, 로그, Secret 주입에 사용하는 Role이에요. |
| `task_role_arn` | `string` | 필수 | 애플리케이션의 AWS API 접근 Role이에요. |
| `environment` | `map(string)` | `{}` | 비밀이 아닌 환경변수예요. 암호를 넣으면 State에 저장돼요. |
| `secrets` | `map(string)` | `{}` | 환경변수 이름별 Secrets Manager 또는 SSM ARN 참조예요. Secret 값은 받지 않아요. |
| `health_check_grace_period_seconds` | `number` | `60` | 서비스 시작 후 ALB 상태 확인 유예 시간이예요. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `cluster_name` | ECS Cluster 이름이에요. |
| `cluster_arn` | ECS Cluster ARN이에요. |
| `log_group_name` | Task 로그 그룹 이름이에요. |
| `log_group_arn` | Task 로그 그룹 ARN이에요. |
| `service_name` | Service 이름이에요. 초기 구성은 `null`이에요. |
| `service_arn` | Service ARN이에요. 초기 구성은 `null`이에요. |
| `task_definition_arn` | Task Definition ARN이에요. 초기 구성은 `null`이에요. |

## 사용 예시

```hcl
module "ecs" {
  source = "../../modules/ecs"
  name   = "sample-dev-backend"
  # service를 생략하면 인프라 준비 구성입니다.
}
```

활성화 시 `service`에 이미지와 네트워크, IAM Role, Target Group을 전달하세요. 호출하는 Root Module은 ALB Listener 연결, NAT 경로, IAM Policy 연결을 완료한 뒤 Service가 생성되도록 `depends_on`을 설정해야 해요. 모듈은 기존 Subnet의 AZ나 Target Group 유형을 AWS에서 조회하지 않아요. Secrets Manager JSON 키 참조는 `secret_arn:json-key::` 형식으로 전달할 수 있어요.

## 검증

```sh
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
```

mock Plan은 서비스 생략, 기본 Fargate 설정, Secret 참조, 잘못된 CPU/메모리와 네트워크를 확인해요. 실제 이미지 실행, 정상 Target, 롤링 배포와 AZ 장애 대응은 별도 배포 검증이 필요해요.
