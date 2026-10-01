# dev CloudFront 사용자 도메인 `sbh.howon.me`

## Ideation: 승인됨

- 문제 정의: 사용자는 Cloudflare에 `sbh.howon.me` CNAME을 설정했다고 했지만, 현재 CloudFront 배포본은 별칭이 없고 기본 인증서를 사용합니다. 이 상태에서는 해당 호스트 이름의 HTTPS 요청을 정상 제공할 수 없습니다.
- 사용자: dev 프론트엔드와 API에 `sbh.howon.me`로 접속하는 사용자 및 인프라 운영자입니다.
- 성공 기준: 기존 CloudFront 배포본에 별칭과 유효한 인증서를 연결하고, `https://sbh.howon.me`의 DNS, TLS 및 HTTP 응답을 실제로 확인합니다.
- Scope: 미국 동부 리전 ACM 인증서, DNS 검증 CNAME, 기존 dev CloudFront 배포본의 별칭과 인증서, 관련 Terraform 및 문서, Plan, Apply와 운영 검증입니다.
- Non-goals: 새 CloudFront 배포본 생성, Cloudflare 프록시 활성화, 프론트엔드나 API 배포, 다른 환경의 도메인 연결, 커밋과 푸시입니다.
- 승인: 2026-10-01 사용자가 이 범위의 Ideation에 `승인`으로 답했습니다. Cloudflare 프록시는 `DNS only`라고 답했으며 CNAME 대상 값은 아직 독립적으로 확인하지 못했습니다.

## 현재 상태와 사전 조사

2026-10-01 AWS `sbh-platform` 프로필의 계정 `723225040786`에서 기존 배포본 `ECSDZ4JA6Z85U`가 `Deployed` 상태이고 기본 도메인은 `d2ixsg0owj0zhf.cloudfront.net`임을 확인했습니다. 별칭은 0개이며 기본 CloudFront 인증서를 사용합니다. 배포본 태그에는 `ManagedBy=terraform`, `Environment=dev`가 있습니다. `us-east-1` ACM의 발급 완료 또는 검증 대기 중인 인증서 목록은 비어 있습니다.

S3 Backend의 `sbh-platform/dev/terraform.tfstate`는 2026-10-01 04:50:40 UTC에 갱신됐고 serial 6, 관리 리소스 인스턴스 46개를 기록합니다. 해당 State에는 이 CloudFront 배포본이 포함됩니다. 기존 문서의 “Apply 미수행, State 비어 있음”은 이전 Plan 시점 기록이며 현재 상태로 해석하지 않습니다. 어떤 명령으로 그 Apply가 실행됐는지는 이번 조회로 확인하지 못했습니다.

`AWS_PROFILE=sbh-platform terraform -chdir=env/dev state list`는 로컬 SSO 캐시 토큰 JSON 파싱 오류로 실패했습니다. AWS CLI를 이용한 계정, CloudFront, ACM 및 S3 State 조회는 성공했습니다. 로컬 DNS 질의는 네트워크 응답 문제로 CNAME 대상을 확인하지 못했습니다. 사용자가 말한 CNAME과 `DNS only` 상태는 아직 독립 검증 전입니다.

## Inception: 승인됨

- Functional Requirements: `sbh.howon.me` 인증서를 ACM `us-east-1`에서 DNS 방식으로 요청합니다. ACM 검증용 CNAME의 이름과 대상을 확인하고 Cloudflare DNS에 `DNS only`로 등록합니다. 인증서가 `ISSUED`가 된 뒤 기존 배포본에 정확히 이 별칭과 인증서를 연결합니다. dev `frontend.url`은 사용자 도메인 HTTPS 주소를 가리키고 기본 CloudFront 도메인도 조회 가능하게 유지합니다.
- Non-Functional Requirements: 배포본 ID와 기존 S3 및 ALB Origin, 캐시 동작, 태그를 유지합니다. ACM 인증서는 추가 발급 요금이 없는 비내보내기 공개 인증서를 사용하고 CloudFront는 추가 고정 요금이 없는 SNI 방식을 사용합니다. 요청과 전송량에 따른 기존 CloudFront 요금은 계속 발생할 수 있습니다. 인증서 발급 전 CloudFront 변경을 실행하지 않습니다. 민감한 자격 증명과 State 원문을 문서나 Git에 저장하지 않습니다. 전체 Plan의 예상 밖 변경, 삭제 또는 교체가 있으면 Apply 전에 중단해 검토합니다.
- Architecture: dev Root Module에 `us-east-1` AWS Provider 별칭과 ACM 인증서 및 검증 대기 리소스를 둡니다. Cloudflare가 DNS 레코드를 소유하므로 Terraform은 검증 레코드를 생성하지 않습니다. 기존 CloudFront 모듈에는 선택적 단일 별칭과 인증서 ARN을 전달합니다. 인증서 검증 완료를 CloudFront 변경의 의존성으로 둡니다. 현재 기본 인증서 동작은 다른 모듈 호출에서 유지합니다.
- Unit of Work: 단일 Unit 10에서 인증서, 기존 배포본 설정, 관련 모듈 README와 dev 문서, 로컬 검증, 두 단계 AWS Apply 및 운영 검증을 처리합니다.
- Acceptance Criteria: ACM 인증서가 `ISSUED`이고 이름이 `sbh.howon.me`입니다. 배포본 ID가 `ECSDZ4JA6Z85U` 그대로이며 별칭은 `sbh.howon.me`, 연결된 인증서는 해당 ACM ARN, 배포 상태는 `Deployed`입니다. 공개 DNS CNAME은 이 배포본의 기본 도메인을 가리키고 프록시는 `DNS only`입니다. `https://sbh.howon.me`에서 인증서 호스트 이름과 실제 HTTP 응답을 확인합니다. Terraform fmt, validate 및 모듈과 dev의 관련 mock 검사를 실제 실행해 결과를 기록합니다. 전체 AWS Plan에는 의도하지 않은 삭제, 교체 또는 다른 변경이 없습니다.

## Construction Unit 10: Design과 Implementation Plan 승인됨

- Design: CloudFront 모듈에 선택적 도메인과 ACM ARN 입력 두 개를 추가합니다. 두 값이 함께 제공될 때만 `aliases`, ACM 인증서, `sni-only`, TLS 1.2 이상을 설정하고, 그 외에는 기존 기본 인증서 경로를 유지합니다. 모듈 `url` 출력은 별칭 사용 시 사용자 도메인을, 미사용 시 기본 CloudFront 도메인을 반환합니다. `domain_name` 출력은 계속 기본 CloudFront 도메인입니다. dev Root Module은 내보내기를 비활성화한 `sbh.howon.me` 공개 인증서를 요청하고 `aws_acm_certificate_validation` 완료 ARN을 모듈에 전달합니다.
- Implementation Plan: 먼저 SSO 자격 증명 경로와 Backend State, 기존 Cloudflare CNAME의 대상을 다시 확인합니다. 대상이 기존 배포본의 기본 도메인과 다르면 DNS 수정을 요청합니다. Root Provider, ACM 리소스와 모듈 호출, CloudFront 모듈 입력, 배포본과 URL 출력, 관련 모듈 README, dev README와 Runbook을 갱신합니다. 기본 인증서와 사용자 인증서 경로를 최소 mock Plan으로 확인하고 fmt 및 validate를 실행합니다. 실제 AWS Plan을 검토한 뒤 인증서 리소스만 대상으로 먼저 Apply하여 검증 CNAME을 확인합니다. Cloudflare 접근이 가능하면 검증 CNAME을 `DNS only`로 등록하고, 접근이 불가능하면 레코드 값을 전달해 등록을 기다립니다. 공개 DNS 및 ACM `ISSUED`를 확인하고 다시 전체 Plan을 검토한 뒤 기존 배포본의 별칭과 인증서 변경을 Apply합니다. 마지막으로 배포 상태, DNS, TLS 및 HTTP를 검증하고 이 문서와 프로젝트 README에 명령, 날짜 및 실제 결과를 기록합니다.
- Approval: 2026-10-01 사용자가 비용 질문에 대한 답변을 확인한 뒤 `적용 ㄱㄱ`로 Inception, Unit 10 계획과 승인된 범위의 AWS Apply를 진행하도록 승인했습니다. Cloudflare 검증 레코드 등록은 별도 DNS 작업이 필요합니다.
- Implementation: `env/dev`에 미국 동부 리전 Provider, 비내보내기 ACM 인증서와 DNS 검증 대기 리소스를 추가했습니다. CloudFront 모듈에는 선택적 단일 별칭과 ACM ARN, SNI 및 TLS 정책을 추가하고 URL 출력을 사용자 도메인으로 전환했습니다. 다른 호출의 기본 인증서 경로는 유지했습니다. 모듈 README, dev README와 Runbook을 갱신했습니다.
- Test: 허용된 실행 환경에서 `terraform validate`, CloudFront 모듈 mock 4개, dev 결합 mock 4개와 전체 Plan 검사 2개가 통과했습니다. 최초 Sandbox 실행에서는 Provider 프로세스 시작이 실패했고, 허용된 실행 환경에서 재실행해 검증했습니다. 기존 CloudFront 테스트의 null 판정도 현재 Provider에서 동작하도록 수정했습니다.
- Review: 첫 전체 실제 AWS Plan은 ACM 인증서와 검증 대기 리소스 2개 생성, 기존 CloudFront 배포본 1개 제자리 변경, 삭제 0개였습니다. ACM 발급 완료 후 최신 Plan은 검증 대기 리소스 1개 생성, 같은 배포본 1개 제자리 변경, 삭제 0개였고 별칭, 인증서 및 `frontend.url` 변경을 확인했습니다. 배포본 ID와 S3 및 ALB Origin의 도메인과 식별자는 유지됐습니다. Apply 후 Plan에는 기존 Origin 블록의 빈 값 표현 차이만 남아 0 add / 1 change / 0 destroy가 표시됩니다. 첫 Plan에도 같은 Origin 차이가 있었으며 별칭과 인증서의 재변경은 없습니다. 이 Plan은 추가 적용하지 않았습니다.

## Operation

- Deployment: 인증서 요청과 기존 배포본 변경을 두 단계 Terraform Apply로 완료했습니다. 첫 단계의 대상 지정 Apply는 인증서 부트스트랩에만 사용했습니다. 인증서 검증 CNAME은 기존 서비스용 CNAME과 별개의 레코드입니다.
- Observability: ACM `ISSUED`, CloudFront `Deployed`, 배포본 ID와 별칭 및 인증서 ARN을 직접 확인했습니다. 사용자는 외부에서 정상 접속됐다고 확인했습니다. 이 컴퓨터에서는 보안 DNS가 도메인을 차단하므로 직접적인 공개 DNS 대상, TLS 제공자와 HTTP 상태 코드 확인은 완료하지 못했습니다.
- Rollback: 문제 발생 시 Terraform으로 기존 배포본의 별칭과 사용자 인증서를 제거하고 기본 인증서로 돌린 뒤 `Deployed`를 확인합니다. 필요하면 Cloudflare 서비스용 CNAME을 운영자가 정리합니다. ACM 인증서는 CloudFront에서 분리된 뒤에만 제거합니다.
- Runbook: 검증 CNAME 등록, DNS 전파와 인증서 상태 확인, 두 단계 Apply 및 복구 순서를 dev Runbook에 반영했습니다.

## 사전 확인 기록

| 날짜 | 명령 또는 확인 | 결과 |
|---|---|---|
| 2026-10-01 | `aws --profile sbh-platform sts get-caller-identity` | 계정 `723225040786` 확인 |
| 2026-10-01 | `aws --profile sbh-platform cloudfront list-distributions` 및 `get-distribution` | `ECSDZ4JA6Z85U`, `Deployed`, 별칭 0개, 기본 인증서 확인 |
| 2026-10-01 | `aws --profile sbh-platform --region us-east-1 acm list-certificates --certificate-statuses ISSUED PENDING_VALIDATION` | 인증서 없음 |
| 2026-10-01 | `aws s3 cp s3://sbh-platform-prod-s3-tf/sbh-platform/dev/terraform.tfstate -` 후 JSON 요약 확인 | serial 6, 관리 인스턴스 46개와 기존 CloudFront 배포본 확인. State 원문은 문서에 기록하지 않음 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev state list` | 로컬 SSO 캐시 JSON 파싱 오류로 실패 |
| 2026-10-01 | 로컬 DNS 질의와 공개 DoH 조회 | 네트워크 응답 문제로 CNAME 대상 미확인 |

## Unit 10 실행 기록

| 날짜 | 명령 또는 확인 | 결과 |
|---|---|---|
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev state list`를 허용된 환경에서 재실행 | 기존 CloudFront를 포함한 dev 관리 리소스 목록 확인 |
| 2026-10-01 | `terraform fmt` 및 `terraform fmt -check -recursive env/dev modules/cloudfront` | 포맷 적용 후 검사 통과 |
| 2026-10-01 | `terraform -chdir=env/dev validate -no-color`를 허용된 환경에서 실행 | 구성 검증 통과 |
| 2026-10-01 | `terraform -chdir=modules/cloudfront test -no-color` | mock 4 PASS, 0 FAIL |
| 2026-10-01 | `.local/terraform-1.17.0-beta2/terraform -chdir=env/dev test -test-directory=tests-terraform-1.17 -no-color -verbose -json > .local/dev-custom-domain-tests.jsonl` | mock 4 PASS, 0 FAIL |
| 2026-10-01 | `python3 scripts/check-dev-test-plan.py .local/dev-custom-domain-tests.jsonl` | 전체 Plan 검사 2 PASS |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-custom-domain.tfplan` | 종료 코드 2, 2 add / 1 change / 0 destroy. ACM 인증서와 검증 대기 생성 및 기존 CloudFront 변경 계획. 미적용 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -target=aws_acm_certificate.frontend -input=false -no-color -out=../../.local/dev-acm-bootstrap.tfplan` | 인증서 1 add / 0 change / 0 destroy 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-acm-bootstrap.tfplan` | 1 added / 0 changed / 0 destroyed. ACM ARN `arn:aws:acm:us-east-1:723225040786:certificate/ecc17052-453e-442f-8fdb-2c22e7e86b02` 생성. CloudFront 미변경 |
| 2026-10-01 | `aws --profile sbh-platform --region us-east-1 acm describe-certificate` | `sbh.howon.me`, 비내보내기, `PENDING_VALIDATION` 확인 |
| 2026-10-01 | 사용자의 Cloudflare 검증 CNAME 등록 완료 응답 후 `aws --profile sbh-platform --region us-east-1 acm wait certificate-validated` 및 `describe-certificate` | ACM `ISSUED`, 도메인 검증 `SUCCESS` 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode -out=../../.local/dev-domain-final.tfplan` 및 Plan JSON 검토 | 종료 코드 2, 검증 대기 1 create, 기존 CloudFront 1 update, 0 destroy. 배포본 ID와 Origin 주소 유지 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev apply -input=false -no-color ../../.local/dev-domain-final.tfplan` | 1 added / 1 changed / 0 destroyed. CloudFront 변경 완료까지 2분 39초 소요 |
| 2026-10-01 | `aws --profile sbh-platform cloudfront get-distribution --id ECSDZ4JA6Z85U` | `Deployed`, 별칭 `sbh.howon.me`, 해당 ACM ARN, `sni-only`, `TLSv1.2_2021` 확인 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev output -json frontend` 및 State 요약 조회 | URL `https://sbh.howon.me`, 배포본 ID 유지. State serial 9, 관리 인스턴스 48개 |
| 2026-10-01 | `AWS_PROFILE=sbh-platform terraform -chdir=env/dev plan -input=false -no-color -detailed-exitcode` | 종료 코드 2, 0 add / 1 change / 0 destroy. CloudFront Origin 블록의 빈 값 표현 차이만 남음, 추가 Apply 미수행 |
| 2026-10-01 | `dig +short CNAME sbh.howon.me`, 기본 CloudFront 도메인과 비교 | 이 컴퓨터의 DNS는 사용자 도메인을 `sinkhole.paloaltonetworks.com`으로 응답. 기본 CloudFront 도메인은 정상 IP 응답 |
| 2026-10-01 | `curl https://sbh.howon.me/`, `curl --resolve sbh.howon.me:443:52.85.128.64 https://sbh.howon.me/`, 인증서 발급자 확인 | 일반 연결 실패. IP 지정 연결은 HTTP 503 보안 정책 차단 페이지이며 인증서 발급자는 로컬 Forward Trust CA. CloudFront 사용자 도메인의 외부 HTTPS 성공으로 판정하지 않음. 기본 CloudFront 주소는 HTTP 200 |
| 2026-10-01 | 사용자 외부 접속 확인 응답 | 사용자가 “배포 잘 됐음”이라고 확인. 응답 코드와 인증서 세부 정보는 전달받지 않음 |
| 2026-10-01 | 후속 요청에 따라 `git commit -m 'feat: add sbh.howon.me to dev CloudFront'`, `git push origin main`, `git ls-remote origin refs/heads/main` | 구현 커밋 `637e5bd316c68288103afa2b1759dc1d16703bbe` 생성과 푸시 완료, 원격 main SHA 일치 확인 |

ACM 검증용 Cloudflare CNAME은 이름 `_9e15a309b5fd291f81fe79d521e3d6c7.sbh.howon.me.`, 대상 `_ce295af0ad7d398da41539f90eed0136.wzccmgtwzk.acm-validations.aws.`입니다. 사용자가 `DNS only` 레코드 등록을 완료했다고 2026-10-01 답했고 ACM이 검증을 완료했습니다. CloudFront 최종 Apply와 AWS 배포 상태 확인도 완료했으며 사용자가 외부 접속 정상 동작을 보고했습니다. 기존 서비스용 CNAME의 정확한 대상과 외부망 HTTP 상태 코드는 독립 확인하지 못했습니다.
