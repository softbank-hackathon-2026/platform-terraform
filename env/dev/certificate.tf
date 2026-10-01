resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = "sbh.howon.me"
  validation_method = "DNS"

  options {
    export = "DISABLED"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "${local.name}-acm-web" })
}

resource "aws_acm_certificate_validation" "frontend" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.frontend.arn
  validation_record_fqdns = [for option in aws_acm_certificate.frontend.domain_validation_options : option.resource_record_name]
}
