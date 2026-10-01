mock_provider "aws" {
  override_during = plan
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:function/sample-dev-spa" }
  }
}

variables {
  name                  = "sample-dev"
  s3_origin_domain_name = "sample-dev.s3.ap-northeast-2.amazonaws.com"
  alb_arn               = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/sample/1234567890123456"
  alb_dns_name          = "internal-sample.ap-northeast-2.elb.amazonaws.com"
}

run "private_origins_and_https" {
  command = plan

  assert {
    condition = (
      toset([for origin in aws_cloudfront_distribution.this.origin : origin.origin_id]) == toset(["frontend", "api"]) &&
      aws_cloudfront_origin_access_control.s3.origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.s3.signing_behavior == "always" &&
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].arn == var.alb_arn &&
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].origin_protocol_policy == "http-only" &&
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].http_port == 80 &&
      aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate &&
      aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    )
    error_message = "S3 OAC, HTTP 80 ALB VPC Origin과 기본 HTTPS 주소를 구성해야 합니다."
  }
}

run "custom_domain_https" {
  command = plan
  variables {
    alternate_domain_name = "sbh.howon.me"
    acm_certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.aliases == toset(["sbh.howon.me"]) &&
      aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == var.acm_certificate_arn &&
      aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021" &&
      output.url == "https://sbh.howon.me"
    )
    error_message = "사용자 도메인은 us-east-1 ACM 인증서와 SNI HTTPS를 사용해야 합니다."
  }
}

run "api_forwarding_and_spa_separation" {
  command = plan

  assert {
    condition = alltrue([
      for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior :
      behavior.target_origin_id == "api" &&
      behavior.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" &&
      behavior.origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac" &&
      behavior.allowed_methods == toset(["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]) &&
      length(behavior.function_association) == 0
      if contains(["/api", "/api/*"], behavior.path_pattern)
      ]) && length([
      for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior : behavior
      if contains(["/api", "/api/*"], behavior.path_pattern)
    ]) == 2
    error_message = "API 두 경로는 캐싱과 SPA 변환 없이 모든 메서드와 인증 정보를 전달해야 합니다."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" &&
      length(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association) == 1 &&
      alltrue([
        for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior :
        behavior.target_origin_id == "frontend" && behavior.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
        if behavior.path_pattern == "/*.html"
      ]) &&
      alltrue([
        for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior :
        behavior.target_origin_id == "frontend" && behavior.cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"
        if contains(["/assets/*", "/static/*"], behavior.path_pattern)
      ]) &&
      alltrue([
        for response in aws_cloudfront_distribution.this.custom_error_response :
        response.error_caching_min_ttl == 0 &&
        (response.response_page_path == null || response.response_page_path == "") &&
        (response.response_code == null || response.response_code == 0)
      ]) &&
      alltrue([for origin in aws_cloudfront_distribution.this.origin : origin.origin_path == null || origin.origin_path == ""])
    )
    error_message = "HTML 캐싱 비활성화, 정적 파일 캐싱, API 원래 경로와 오류 응답 보존을 유지해야 합니다."
  }
}

run "reject_non_alb_origin" {
  command = plan
  variables {
    alb_arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/net/sample/1234567890123456"
  }
  expect_failures = [var.alb_arn]
}
