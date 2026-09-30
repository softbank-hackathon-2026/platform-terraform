# CloudFront module

비공개 S3 프론트엔드와 Internal ALB API를 하나의 CloudFront HTTPS 주소로 연결해요. OAC, ALB VPC Origin, SPA Function과 Distribution을 생성해요.

## 입력 속성

| 속성 | 타입 | 기본값 | 역할 |
|---|---|---|---|
| `name` | `string` | 필수 | OAC, VPC Origin과 Function 이름 접두사예요. |
| `s3_origin_domain_name` | `string` | 필수 | S3 버킷의 리전별 REST 도메인이에요. |
| `alb_arn` | `string` | 필수 | Internal ALB ARN이에요. |
| `alb_dns_name` | `string` | 필수 | Internal ALB DNS 이름이에요. |
| `tags` | `map(string)` | `{}` | Distribution과 VPC Origin에 붙일 태그예요. |

## 출력 속성

| 속성 | 역할 |
|---|---|
| `distribution_id` | Distribution ID예요. |
| `distribution_arn` | S3 버킷 정책의 SourceArn에 사용할 ARN이에요. |
| `domain_name` | CloudFront 기본 도메인이에요. |
| `url` | 기본 HTTPS 주소예요. |
| `vpc_origin_id` | Internal ALB VPC Origin ID예요. |
| `origin_access_control_id` | S3 OAC ID예요. |
| `spa_function_arn` | SPA Function ARN이에요. |

## 경로와 캐싱

| 경로 | Origin | 캐싱 | 요청 처리 |
|---|---|---|---|
| `/api`, `/api/*` | Internal ALB | CachingDisabled | 모든 HTTP 메서드, 인증 헤더, 쿠키와 Query String을 전달해요. |
| `/*.html` | S3 | CachingDisabled | 정적 폴더 안의 HTML도 캐싱하지 않아요. API Behavior를 먼저 적용해요. |
| `/assets/*`, `/static/*` | S3 | CachingOptimized | GET/HEAD와 압축을 사용해요. 파일명에 콘텐츠 해시를 넣으세요. |
| 그 외 | S3 | CachingDisabled | 확장자가 없는 마지막 경로를 `/index.html`로 바꿔요. |

SPA Function은 기본 프론트 Behavior에만 연결돼요. API 경로는 그대로 전달하고 4xx/5xx 응답 코드와 본문은 보존해요. 오류 캐시 TTL은 0으로 설정하며 HTML 오류 페이지로 치환하지 않아요. 파일이 없는 경우 S3의 403/404도 원래대로 전달돼요.

API는 `Managed-AllViewerExceptHostHeader` Origin Request Policy를 사용해요. Authorization을 포함한 요청 헤더, 쿠키와 Query String을 전달하며 Host는 ALB 도메인으로 바뀌어요. 프론트엔드에서는 같은 Origin의 상대 경로 `/api`를 사용하세요. 외부 Origin의 CORS 허용과 사용자 인증은 애플리케이션에서 구성해야 해요. [AWS 관리형 요청 정책](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html)

관리형 정책은 AWS가 공개한 ID를 직접 사용해요. 새 ALB를 먼저 생성해야 하는 구성에서도 정책이 Plan 단계에 확정돼 캐시 설정을 검토할 수 있어요. [AWS 관리형 캐시 정책 ID](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html)

## 연결 전제

Root Module에서 S3 버킷 공개 접근을 차단하고 `cloudfront.amazonaws.com`의 `s3:GetObject` 권한을 이 Distribution ARN으로 제한하세요. S3는 SSE-S3를 사용하며 OAC 서명은 항상 SigV4예요.

ALB는 두 Private Subnet에서 Active 상태여야 하고 HTTP 80 Listener가 필요해요. VPC에는 IGW와 사용 가능한 Private IPv4 주소가 있어야 해요. ALB Security Group에 CloudFront 관리형 Prefix List의 TCP 80 접근을 허용한 뒤 VPC Origin을 생성하도록 의존성을 설정하세요. AWS가 만드는 `CloudFront-VPCOrigins-Service-SG`는 수정하지 않아요. [AWS VPC Origin 전제 조건](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)

```hcl
module "cloudfront" {
  source                = "../../modules/cloudfront"
  name                  = "sample-dev"
  s3_origin_domain_name = module.frontend.bucket_regional_domain_name
  alb_arn               = module.alb.load_balancer_arn
  alb_dns_name          = module.alb.dns_name
  depends_on            = [module.alb, aws_vpc_security_group_ingress_rule.cloudfront]
}
```

## 검증

```sh
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test
node --test tests/spa.test.cjs
```

mock Plan과 로컬 JavaScript 테스트는 캐시와 라우팅 설정을 확인해요. 실제 S3 파일, API 인증, 쿠키, 오류 응답과 VPC Origin 연결은 Apply 후 별도 검증이 필요해요.
