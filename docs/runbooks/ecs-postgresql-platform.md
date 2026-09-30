# ECS and PostgreSQL platform runbook

작성일: 2026-10-01

이 문서는 후속 배포를 위한 절차예요. 이번 작업에서는 Apply, 프론트 파일/이미지 업로드, DB 계정 생성, ECS 시작과 장애 전환을 실행하지 않아요. 현재 구현과 실제 검증 결과는 [AI-DLC](../ai-dlc/ecs-postgresql-platform.md)에 기록해요.

## 배포 순서

1. `sbh-platform` 인증, 서울 리전과 기존 S3 Backend를 확인해요. State Key는 dev 전용으로 유지해요. `AWS_PROFILE=sbh-platform ./tf dev plan`에서 변경과 삭제, 비용이 발생하는 NAT 2개, ALB, RDS Multi-AZ를 검토해요.
2. 후속 Apply 승인 후 인프라 준비 구성을 적용해요. `backend_image_digest = null`이면 Task Definition과 Service는 없어요. ALB Target이 비어 있으므로 `/api`의 503은 이 단계의 예상 상태예요.
3. VPC 내부에서 DB에 접속할 수 있는 별도 관리 경로를 준비해요. 현재 Terraform에는 DB 접근용 공개 포트, Bastion과 관리자 ECS Task가 없어요. RDS 관리자 Secret으로 접속해 `sbhapp` DB의 앱 전용 사용자를 만들고 필요한 스키마 권한만 부여해요. 관리자 계정을 앱에서 사용하지 않아요.
4. 앱 Secret에 `username`, `password` JSON 키를 Secrets Manager의 승인된 운영 경로로 등록해요. Terraform에는 Secret 메타데이터만 있어요. Terraform 변수, 출력, 명령행 인자와 로그에 암호를 넣지 않아요. RDS 관리자 Secret과 앱 Secret은 별개예요.
5. Linux X86_64 이미지를 빌드하고 해당 ECR에 업로드해요. 앱은 지정 포트에서 `0.0.0.0`으로 수신하고 `/api/health`에 인증 없이 HTTP 200을 반환해야 해요. 환경변수 `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`를 사용하고 `DB_SSLMODE=verify-full`에 맞춰 RDS CA 인증서를 이미지에 포함해요.
6. 이미지 Digest를 로컬 tfvars에 설정하고 새 Plan을 검토해요. Task Definition과 Service가 추가되고 Task 2개, Public IP 비활성화, 두 App Subnet, AZ 재분산이 유지되는지 확인해요. 승인 후 활성화 Apply를 진행해요.
7. 두 AZ의 정상 Task와 ALB Target을 확인한 후 프론트 빌드 결과를 S3에 업로드해요. API는 같은 CloudFront Origin의 `/api`를 사용해요. `/assets/*`와 `/static/*`에는 콘텐츠 해시가 있는 파일명을 사용하고 HTML은 캐싱하지 않아요.
8. CloudFront HTTPS 주소에서 SPA 직접 접근, 인증 헤더, 쿠키, Query String, POST/PATCH/DELETE와 API 4xx/5xx 응답을 검증해요. ALB Host와 전송 구간은 내부 HTTP예요. 앱의 공개 URL과 신뢰할 프록시/HTTPS 인식 설정을 CloudFront에 맞춰 구성하고 로그인 Redirect와 Secure Cookie를 확인해요.

Terraform의 AWS 실행은 `sbh-platform` 프로필을 사용해요. AWS CLI의 운영 확인 명령에도 `--profile sbh-platform --region ap-northeast-2`를 붙여요.

앱 포트는 최초 인프라 Apply 전에 확정하세요. 기존 Target Group의 포트를 바꾸면 교체가 필요하고 ALB Listener와 활성 서비스가 해당 Target Group을 참조할 수 있어요. 배포 후 포트 변경은 Target Group 이름과 생성/삭제 순서를 별도 검토한 후 진행해요.

## 접근 규칙

| 구간 | 허용 |
|---|---|
| CloudFront -> ALB | CloudFront origin-facing 관리형 Prefix List, TCP 80 |
| ALB -> ECS | ALB/ECS Security Group 참조, 앱 TCP 포트 |
| ECS -> RDS | ECS/DB Security Group 참조, TCP 5432 |
| ECS -> 인터넷 | TCP 443, 같은 AZ의 NAT |
| 인터넷 -> DB | 경로와 허용 규칙 없음 |

CloudFront가 생성하는 `CloudFront-VPCOrigins-Service-SG`는 AWS 관리 대상이므로 수정하지 않아요. 현재는 관리형 Prefix List를 사용하며 특정 Distribution 제한은 S3 OAC 버킷 정책에 적용해요. Prefix List 규칙은 SG 할당량을 크게 사용하므로 포트를 추가하기 전에 할당량을 확인해요. [VPC Origin 접근 규칙](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)

## 모니터링

- ECS: Running/Desired Task 수, 서비스 이벤트, CPU와 메모리, 배포 Circuit Breaker, `/ecs/sbh-platform-dev-backend` 로그를 확인해요. 로그는 30일 보존해요.
- ALB: Healthy/UnHealthy Host 수, Target 5xx, ALB 5xx와 응답 지연을 확인해요.
- CloudFront: 4xx/5xx와 API 지연을 확인해요. 오류는 SPA HTML로 바꾸지 않아요.
- RDS: DB 상태, 장애 전환 이벤트, CPU, FreeableMemory, FreeStorageSpace와 DatabaseConnections를 확인해요. 백업은 7일 보존해요.
- NAT: AZ별 NAT 상태, ErrorPortAllocation, 연결 수와 데이터 처리량을 확인해요.

알림 채널, CloudWatch Alarm, ALB/CloudFront 액세스 로그, 대시보드는 이번 구현 범위에 없어요. 후속 운영 작업에서 기준과 수신 대상을 정해요.

## 복구와 Rollback

ECS 배포가 실패하면 Circuit Breaker가 이전 정상 배포로 되돌려요. 최초 배포는 이전 정상 배포가 없어서 자동 복구 대상이 없어요. 서비스 이벤트, 이미지 Digest, Secret 버전, 앱 로그와 Health Check를 확인한 뒤 이전 검증된 Digest로 Plan을 검토하세요.

RDS Multi-AZ Standby는 자동 장애 전환용이며 읽기 접속 대상이 아니에요. 앱은 Primary DNS를 사용하고 연결 풀에 재연결과 재시도 정책을 적용해야 해요. 장애 전환 시 기존 연결이 끊길 수 있어요. 데이터 복구는 자동 백업의 시점 복구 또는 스냅샷에서 새 인스턴스를 만든 뒤 접속 대상을 변경하는 절차로 진행해요. [RDS Multi-AZ 동작](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)

앱 Secret 값을 회전하면 실행 중인 Task의 환경변수는 자동으로 갱신되지 않아요. DB 계정 암호와 Secret 버전을 함께 변경하고 승인된 새 배포로 Task를 교체한 뒤 두 AZ의 접속을 확인해요.

프론트엔드는 S3 버전 관리로 이전 객체를 복원할 수 있어요. 콘텐츠 해시 파일명을 사용하고 필요한 경로만 CloudFront Invalidation으로 갱신하세요. State 복구는 Backend 버킷의 버전 관리에 따라 진행하며 State를 변경하기 전 실제 리소스와 Plan을 대조해요.

삭제가 승인된 경우 RDS 삭제 보호를 먼저 별도 Plan으로 해제하고 고유한 최종 스냅샷 이름을 지정해요. 프론트 S3는 `force_destroy = false`이므로 버전과 Delete Marker를 포함한 객체가 남으면 삭제되지 않아요. VPC Origin 변경은 Distribution과의 연결 해제/재연결이 필요할 수 있으므로 [AWS VPC Origin 갱신 절차](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)를 확인해요.

## 후속 장애 검증

1. 부하와 성공률 기준을 정하고 정상 상태에서 두 AZ에 Task가 하나씩 배치되는지 확인해요. 재분산과 배포 중에는 Task 수가 일시적으로 증가할 수 있어요.
2. 승인된 장애 시나리오로 한 AZ의 Task가 사용할 수 없을 때 다른 AZ에서 요청을 처리하는지 확인해요. 남은 Task 하나의 용량도 측정해요.
3. 별도 승인 후 RDS 강제 장애 전환을 수행하고 DNS 변경, 연결 풀 재연결, 재시도와 데이터 일관성을 확인해요.
4. 프론트 롤백과 DB 시점 복구를 격리된 환경에서 검증하고 실제 시간과 결과를 기록해요.

위 절차는 문서화만 했어요. 로컬 mock Plan과 실제 AWS Plan은 장애 대응, DB 접속이나 배포 성공을 증명하지 않아요.
