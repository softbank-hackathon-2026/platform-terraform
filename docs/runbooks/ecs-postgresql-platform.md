# ECS and PostgreSQL platform runbook

작성일: 2026-10-01

이 문서는 인프라와 앱 배포 절차예요. 2026-10-01 Unit 11 Parameter 생성 Apply 후 S3 Backend State는 serial 10, 관리 리소스 인스턴스 49개예요. 최신 전체 Plan에는 기존 CloudFront Origin 표현 차이 변경 1개만 남고 Parameter는 추가 변경이 없어요. 실제 리소스 상태는 새 Plan과 서비스 조회로 다시 확인하세요. 기존 구현과 Parameter 생성 검증은 [Platform AI-DLC](../ai-dlc/ecs-postgresql-platform.md), 사용자 도메인 작업은 [CloudFront AI-DLC](../ai-dlc/dev-cloudfront-custom-domain.md)에 기록해요.

## CloudFront 사용자 도메인

`sbh.howon.me`는 기존 CloudFront 배포본 `ECSDZ4JA6Z85U`에 연결해요. Cloudflare의 서비스용 CNAME은 `d2ixsg0owj0zhf.cloudfront.net`을 가리키고 `DNS only`여야 해요. 인증서 검증용 CNAME은 별도의 이름과 대상이에요. 인증서 요청 후 ACM이 제공하는 값으로 Cloudflare에 `DNS only` 레코드를 등록하고 인증서가 `ISSUED`가 될 때까지 기다려요.

먼저 현재 State와 전체 Plan을 확인한 뒤 `aws_acm_certificate.frontend`만 대상으로 인증서 요청을 Apply해요. 대상 지정 Apply는 이 초기 발급 단계에만 사용해요. 검증 CNAME과 인증서 상태를 확인한 뒤 전체 Plan을 다시 실행하고, 기존 배포본 변경 외에 예상하지 않은 변경이나 삭제가 없을 때 적용해요. 적용 후 ACM `ISSUED`, CloudFront `Deployed`, 별칭과 인증서 ARN, 공개 DNS CNAME과 `https://sbh.howon.me`의 TLS 및 HTTP 응답을 각각 확인해요.

복구할 때는 먼저 배포본의 별칭과 사용자 인증서를 Terraform으로 제거하고 기본 인증서 배포가 완료됐는지 확인해요. 그 뒤 필요하면 Cloudflare 서비스용 CNAME을 정리하고 ACM 인증서를 제거해요. CloudFront에 연결된 인증서는 먼저 삭제하지 않아요.

## 배포 순서

1. `sbh-platform` 인증, 서울 리전과 기존 S3 Backend를 확인해요. State Key는 dev 전용으로 유지해요. `AWS_PROFILE=sbh-platform ./tf dev plan`에서 변경과 삭제, 활성 AZ별 비용이 발생하는 Regional NAT 1개, ALB, RDS Multi-AZ를 검토해요.
2. 초기 구축이 필요한 환경에서는 승인 후 인프라 준비 구성을 적용해요. 이미 State가 있는 dev는 새 Plan의 변경과 삭제를 검토한 뒤 필요한 변경만 적용해요. Terraform은 ECS Cluster와 로그 그룹을 관리하지만 Task Definition과 Service는 관리하지 않아요. CI/CD가 서비스를 배포하기 전에는 ALB Target이 비어 있으므로 `/api`의 503은 예상 상태예요.
3. VPC 내부에서 DB에 접속할 수 있는 별도 관리 경로를 준비해요. 현재 Terraform에는 DB 접근용 공개 포트, Bastion과 관리자 ECS Task가 없어요. RDS 관리자 Secret으로 접속해 실제 `db_name`의 앱 전용 사용자를 만들고 필요한 스키마 권한만 부여해요. 관리자 계정을 앱에서 사용하지 않아요. 현재 기본 DB 이름은 `freesia`예요.
4. Terraform이 `/sbh/platform/demo/backend/DATABASE_URL`을 Standard SecureString으로 생성한 뒤 운영 경로에서 기존 Parameter의 초기값 `NOT_CONFIGURED`를 실제 접속값으로 갱신해요. 기본 `aws/ssm` 키를 사용하면 ECS 실행 역할에 추가 KMS 권한은 필요하지 않아요. 값은 실제 앱 사용자, URL 인코딩된 비밀번호, RDS Writer 주소와 DB 이름을 사용해 `postgresql+psycopg://<앱 사용자>:<URL 인코딩된 암호>@<DB 주소>:5432/<DB 이름>?sslmode=require` 형식으로 만들어요. 예약 문자 `@`, `:`, `/`, `?`, `#` 등은 비밀번호 안에서 URL 인코딩해야 해요. 값과 비밀번호를 Terraform 변수, 출력, 명령행 인자와 로그에 넣지 마세요. Terraform이 관리하지 않는 같은 이름의 Parameter가 이미 있으면 생성은 실패해요. 이때 기존 값을 덮어쓰거나 Parameter를 삭제하지 말고 별도 편입 설계를 검토해요.
5. 값 자체를 조회하지 않는 아래 명령으로 Parameter의 Name, Type과 KeyId를 확인해요. 생성 전에는 지정 Parameter가 없을 수 있어요. 리소스가 존재해도 초기값 상태일 수 있으므로 실제 URL 갱신과 DB 연결 성공은 별도로 검증해야 해요.

   ```sh
   aws --profile sbh-platform --region ap-northeast-2 ssm describe-parameters \
     --parameter-filters "Key=Name,Option=Equals,Values=/sbh/platform/demo/backend/DATABASE_URL" \
     --query 'Parameters[].[Name,Type,KeyId]' --output table
   ```

6. Linux X86_64 이미지를 빌드하고 해당 ECR에 업로드해요. 앱은 기본 포트 8000에서 `0.0.0.0`으로 수신하고 `/api/health`에 인증 없이 HTTP 200을 반환해야 해요. DB 접속에는 ECS가 Secret으로 주입한 `DATABASE_URL`을 사용해요. 기존 `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SSLMODE`는 더는 전달하지 않아요.
7. CI/CD가 고정된 이미지 Digest로 Fargate Task Definition revision을 등록해요. 컨테이너 이름과 포트, 실행 및 Task Role, 로그 그룹, `DATABASE_URL` SSM ARN은 아래 인프라 출력 계약에 맞춰요. DB와 Parameter가 준비된 후 같은 App Subnet 및 ECS Security Group에서 필요한 마이그레이션 Task를 한 번 실행하고 성공을 확인해요.
8. CI/CD가 등록한 revision으로 ECS Service를 생성하거나 기존 Service를 갱신해요. 기본 Task 수는 2개, Public IP는 비활성화하고 두 App Subnet과 IP Target Group을 사용해요. AZ 재분산과 배포 Circuit Breaker의 롤백을 활성화해요. 새 배포마다 CI/CD가 Service의 Task Definition revision을 갱신하며 Terraform Apply는 이를 관리하지 않아요.
9. 두 AZ의 정상 Task와 ALB Target을 확인한 후 프론트 빌드 결과를 S3에 업로드해요. API는 같은 CloudFront Origin의 `/api`를 사용해요. `/assets/*`와 `/static/*`에는 콘텐츠 해시가 있는 파일명을 사용하고 HTML은 캐싱하지 않아요.
10. CloudFront HTTPS 주소에서 SPA 직접 접근, 인증 헤더, 쿠키, Query String, POST/PATCH/DELETE와 API 4xx/5xx 응답을 검증해요. ALB Host와 전송 구간은 내부 HTTP예요. 앱의 공개 URL과 신뢰할 프록시/HTTPS 인식 설정을 CloudFront에 맞춰 구성하고 로그인 Redirect와 Secure Cookie를 확인해요.

Terraform의 AWS 실행은 `sbh-platform` 프로필을 사용해요. AWS CLI의 운영 확인 명령에도 `--profile sbh-platform --region ap-northeast-2`를 붙여요.

Parameter의 값과 메타데이터는 최초 생성 이후 운영자가 관리해요. Terraform은 `value_wo`로 값을 State에 저장하지 않지만 현재 Provider는 refresh 시 `GetParameter`를 복호화 옵션으로 호출해요. `ignore_changes`로 값 갱신 번호와 값 쓰기를 유발하는 메타데이터 변경을 무시하고, 태그만 갱신해요. `overwrite = false`와 `prevent_destroy = true`를 유지하며 이름, 유형, 등급, 키, 설명 변경과 삭제는 별도 설계 및 승인으로 다뤄요. 고객 관리 KMS 키로 바꾸려면 키 정책과 실행 역할의 `kms:Decrypt` 권한을 함께 검토하세요.

## CI/CD 인프라 출력 계약

CI/CD는 Terraform의 `network.app_subnet_ids`, `backend.ecr_repository_url`, `backend.cluster_name`, `backend.log_group_name`, `backend.execution_role_arn`, `backend.task_role_arn`, `backend.ecs_security_group_id`, `backend.target_group_arn`, `backend.container_name`, `backend.container_port`, `database.database_url_parameter_arn`을 사용해요. Task Definition은 Fargate `awsvpc`, Linux X86_64, CPU 512, 메모리 1024 MiB, `awslogs` 서울 리전, Secret 이름 `DATABASE_URL`과 해당 SSM ARN을 사용해요. Service의 Load Balancer 컨테이너 이름과 포트는 `backend` 출력과 일치해야 해요. CI/CD는 Service의 AZ 재분산과 배포 Circuit Breaker도 설정해야 해요.

CI/CD 배포 주체에는 이미지 업로드, Task Definition 등록, Service 생성과 갱신, 정확한 두 Task Role을 ECS에 전달할 권한이 필요해요. 이 주체와 워크플로의 생성은 이번 Terraform 범위에 없어요. 배포 후에도 Terraform Plan에서 ALB Target Group, 보안 그룹과 Role 변경이 서비스에 미칠 영향을 검토해요.

앱 포트는 최초 인프라 Apply 전에 확정하세요. 기존 Target Group의 포트를 바꾸면 교체가 필요하고 ALB Listener와 활성 서비스가 해당 Target Group을 참조할 수 있어요. 배포 후 포트 변경은 Target Group 이름과 생성/삭제 순서를 별도 검토한 후 진행해요.

## 접근 규칙

| 구간 | 허용 |
|---|---|
| CloudFront -> ALB | CloudFront origin-facing 관리형 Prefix List, TCP 80 |
| ALB -> ECS | ALB/ECS Security Group 참조, 기본 TCP 8000 |
| ECS -> RDS | ECS/DB Security Group 참조, TCP 5432 |
| ECS -> 인터넷 | TCP 443, Regional NAT |
| 인터넷 -> DB | 경로와 허용 규칙 없음 |

CloudFront가 생성하는 `CloudFront-VPCOrigins-Service-SG`는 AWS 관리 대상이므로 수정하지 않아요. 현재는 관리형 Prefix List를 사용하며 특정 Distribution 제한은 S3 OAC 버킷 정책에 적용해요. Prefix List 규칙은 SG 할당량을 크게 사용하므로 포트를 추가하기 전에 할당량을 확인해요. [VPC Origin 접근 규칙](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)

VPC에는 Public Subnet과 Public Route Table이 없어요. Regional NAT와 CloudFront VPC Origin을 위해 Internet Gateway는 연결하지만 App과 DB Subnet에는 Internet Gateway 기본 경로가 없어요. Regional NAT가 사용하는 송신 IP는 AWS가 관리해요. 기존 Zonal NAT를 배포한 환경에서 실제 전환할 때는 송신 IP 허용 목록과 연결 재설정을 확인하고, 새 NAT로 경로를 바꾼 뒤 이전 NAT를 제거하는 순서를 Plan과 작업 창에서 검토해요. [Regional NAT 전환](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateways-regional.html)

## 모니터링

- ECS: Running/Desired Task 수, 서비스 이벤트, CPU와 메모리, 배포 Circuit Breaker, `sbh-platform-dev-log-api` 로그를 확인해요. 로그는 30일 보존해요.
- ALB: Healthy/UnHealthy Host 수, Target 5xx, ALB 5xx와 응답 지연을 확인해요.
- CloudFront: 4xx/5xx와 API 지연을 확인해요. 오류는 SPA HTML로 바꾸지 않아요.
- RDS: DB 상태, 장애 전환 이벤트, CPU, FreeableMemory, FreeStorageSpace와 DatabaseConnections를 확인해요. 백업은 7일 보존해요.
- NAT: Regional NAT의 AZ별 확장 상태, ErrorPortAllocation, 연결 수와 데이터 처리량을 확인해요.

알림 채널, CloudWatch Alarm, ALB/CloudFront 액세스 로그, 대시보드는 이번 구현 범위에 없어요. 후속 운영 작업에서 기준과 수신 대상을 정해요.

## 복구와 Rollback

CI/CD가 Service의 배포 Circuit Breaker 롤백을 설정했다면 실패 시 이전 정상 배포로 되돌릴 수 있어요. 최초 배포는 이전 정상 배포가 없어서 자동 복구 대상이 없어요. 서비스 이벤트, 이미지 Digest, Parameter 이름과 유형, 앱 로그와 Health Check를 확인한 뒤 CI/CD에서 이전 검증된 Digest로 새 revision을 배포하세요.

RDS Multi-AZ Standby는 자동 장애 전환용이며 읽기 접속 대상이 아니에요. 앱은 Primary DNS를 사용하고 연결 풀에 재연결과 재시도 정책을 적용해야 해요. 장애 전환 시 기존 연결이 끊길 수 있어요. 데이터 복구는 자동 백업의 시점 복구 또는 스냅샷에서 새 인스턴스를 만든 뒤 접속 대상을 변경하는 절차로 진행해요. [RDS Multi-AZ 동작](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)

`DATABASE_URL` Parameter 값을 회전해도 실행 중인 Task의 환경변수는 자동으로 갱신되지 않아요. DB 계정 암호와 Parameter 값을 함께 변경하고 승인된 새 배포로 Task를 교체한 뒤 두 AZ의 접속을 확인해요.

프론트엔드는 S3 버전 관리로 이전 객체를 복원할 수 있어요. 콘텐츠 해시 파일명을 사용하고 필요한 경로만 CloudFront Invalidation으로 갱신하세요. State 복구는 Backend 버킷의 버전 관리에 따라 진행하며 State를 변경하기 전 실제 리소스와 Plan을 대조해요.

삭제가 승인된 경우 RDS 삭제 보호를 먼저 별도 Plan으로 해제하고 고유한 최종 스냅샷 이름을 지정해요. 프론트 S3는 `force_destroy = false`이므로 버전과 Delete Marker를 포함한 객체가 남으면 삭제되지 않아요. VPC Origin 변경은 Distribution과의 연결 해제/재연결이 필요할 수 있으므로 [AWS VPC Origin 갱신 절차](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)를 확인해요.

## 후속 장애 검증

1. 부하와 성공률 기준을 정하고 정상 상태에서 두 AZ에 Task가 하나씩 배치되는지 확인해요. 재분산과 배포 중에는 Task 수가 일시적으로 증가할 수 있어요.
2. 승인된 장애 시나리오로 한 AZ의 Task가 사용할 수 없을 때 다른 AZ에서 요청을 처리하는지 확인해요. 남은 Task 하나의 용량도 측정해요.
3. 별도 승인 후 RDS 강제 장애 전환을 수행하고 DNS 변경, 연결 풀 재연결, 재시도와 데이터 일관성을 확인해요.
4. 프론트 롤백과 DB 시점 복구를 격리된 환경에서 검증하고 실제 시간과 결과를 기록해요.

위 절차는 문서화만 했어요. 로컬 mock Plan과 실제 AWS Plan은 장애 대응, DB 접속이나 배포 성공을 증명하지 않아요.
