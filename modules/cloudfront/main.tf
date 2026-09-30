locals {
  # AWS publishes these managed policy IDs. Keep them known during bootstrap Plan.
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
  caching_disabled_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  caching_optimized_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html
  api_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name}-s3"
  description                       = "Private frontend S3 access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_vpc_origin" "api" {
  vpc_origin_endpoint_config {
    name                   = "${var.name}-api"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-api" })
}

resource "aws_cloudfront_function" "spa" {
  name    = "${var.name}-spa"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite extensionless frontend routes to index.html"
  publish = true
  code    = file("${path.module}/spa.js")
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = "index.html"
  http_version        = "http2"
  price_class         = "PriceClass_All"

  origin {
    origin_id                = "frontend"
    domain_name              = var.s3_origin_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
    s3_origin_config {
      origin_access_identity = ""
    }
  }

  origin {
    origin_id   = "api"
    domain_name = var.alb_dns_name
    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.api.id
    }
  }

  default_cache_behavior {
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.caching_disabled_id
    compress               = true
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = ["/api", "/api/*"]
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "api"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = local.caching_disabled_id
      origin_request_policy_id = local.api_request_policy_id
      compress                 = true
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/*.html"
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.caching_disabled_id
    compress               = true
  }

  dynamic "ordered_cache_behavior" {
    for_each = ["/assets/*", "/static/*"]
    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = "frontend"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      cache_policy_id        = local.caching_optimized_id
      compress               = true
    }
  }

  # Disable CloudFront error caching without replacing the origin response.
  dynamic "custom_error_response" {
    for_each = toset([400, 403, 404, 405, 414, 500, 501, 502, 503, 504])
    content {
      error_code            = custom_error_response.value
      error_caching_min_ttl = 0
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, { Name = var.name })
}
