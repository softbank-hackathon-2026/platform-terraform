mock_provider "aws" {
  override_during = plan
}

variables {
  name               = "sample-alb"
  subnet_ids         = ["subnet-11111111111111111", "subnet-22222222222222222"]
  security_group_ids = ["sg-11111111111111111"]
}

run "alb_without_listeners_or_target_groups" {
  command = plan

  override_resource {
    target          = aws_lb.this
    override_during = plan
    values = {
      arn      = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/sample-alb/1234567890123456"
      dns_name = "internal-sample.example.elb.amazonaws.com"
      zone_id  = "Z1234567890"
    }
  }

  assert {
    condition = (
      aws_lb.this.internal &&
      aws_lb.this.load_balancer_type == "application" &&
      aws_lb.this.ip_address_type == "ipv4" &&
      length(aws_lb_target_group.this) == 0 &&
      length(aws_lb_listener.forward) == 0 &&
      length(aws_lb_listener.redirect) == 0 &&
      output.target_group_arns == {} &&
      output.listener_arns == {} &&
      output.load_balancer_arn == aws_lb.this.arn &&
      output.dns_name == "internal-sample.example.elb.amazonaws.com" &&
      output.zone_id == "Z1234567890"
    )
    error_message = "기본 구성은 Listener와 Target Group 없이 내부형 ALB 하나만 만들어야 합니다."
  }
}

run "public_alb_without_listeners" {
  command = plan

  variables {
    internal = false
  }

  assert {
    condition = (
      !aws_lb.this.internal &&
      length(aws_lb_target_group.this) == 0 &&
      length(aws_lb_listener.forward) == 0 &&
      length(aws_lb_listener.redirect) == 0
    )
    error_message = "공개형 ALB도 Listener 없이 준비할 수 있어야 합니다."
  }
}

run "target_group_without_listener" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web = { name = "sample-web" }
    }
  }

  override_resource {
    target          = aws_lb_target_group.this["web"]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample-web/1234567890123456"
    }
  }

  assert {
    condition = (
      length(aws_lb_target_group.this) == 1 &&
      aws_lb_target_group.this["web"].target_type == "instance" &&
      aws_lb_target_group.this["web"].protocol == "HTTP" &&
      aws_lb_target_group.this["web"].port == 80 &&
      one(aws_lb_target_group.this["web"].health_check).path == "/" &&
      one(aws_lb_target_group.this["web"].health_check).matcher == "200" &&
      output.target_group_arns["web"] == aws_lb_target_group.this["web"].arn &&
      output.listener_arns == {}
    )
    error_message = "Target Group만 만들고 Listener는 생략할 수 있어야 합니다."
  }
}

run "one_internal_http_listener" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web = { name = "sample-web", port = 8080, health_check_path = "/health" }
    }
    listeners = {
      web_http = {
        port           = 80
        protocol       = "HTTP"
        default_action = { type = "forward", target_group_key = "web" }
      }
    }
  }

  override_resource {
    target          = aws_lb_target_group.this["web"]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample-web/1234567890123456"
    }
  }

  assert {
    condition = (
      length(aws_lb_target_group.this) == 1 &&
      length(aws_lb_listener.forward) == 1 &&
      length(aws_lb_listener.redirect) == 0 &&
      aws_lb_listener.forward["web_http"].port == 80 &&
      aws_lb_listener.forward["web_http"].protocol == "HTTP" &&
      one(aws_lb_listener.forward["web_http"].default_action).target_group_arn == output.target_group_arns["web"] &&
      aws_lb_target_group.this["web"].port == 8080 &&
      one(aws_lb_target_group.this["web"].health_check).path == "/health"
    )
    error_message = "Listener 하나가 지정한 Target Group으로 전달해야 합니다."
  }
}

run "multiple_listeners_and_target_groups" {
  command = plan

  variables {
    internal                   = false
    vpc_id                     = "vpc-0123456789abcdef0"
    enable_deletion_protection = true
    target_groups = {
      web = {
        name              = "sample-web"
        port              = 8080
        health_check_path = "/health"
      }
      admin = {
        name                 = "sample-admin"
        target_type          = "ip"
        protocol             = "HTTPS"
        port                 = 8443
        health_check_matcher = "200-299"
      }
    }
    listeners = {
      web_https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        default_action  = { type = "forward", target_group_key = "web" }
      }
      admin_https = {
        port            = 8443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/22345678-1234-1234-1234-123456789012"
        tls_policy      = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
        default_action  = { type = "forward", target_group_key = "admin" }
      }
      web_http = {
        port           = 80
        protocol       = "HTTP"
        default_action = { type = "redirect", redirect_to_listener_key = "web_https" }
      }
    }
    tags = { Environment = "test" }
  }

  override_resource {
    target          = aws_lb_target_group.this["web"]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample-web/1234567890123456"
    }
  }

  override_resource {
    target          = aws_lb_target_group.this["admin"]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample-admin/1234567890123456"
    }
  }

  assert {
    condition = (
      !aws_lb.this.internal &&
      aws_lb.this.enable_deletion_protection &&
      aws_lb.this.tags["Environment"] == "test" &&
      length(aws_lb_target_group.this) == 2 &&
      length(aws_lb_listener.forward) == 2 &&
      length(aws_lb_listener.redirect) == 1 &&
      toset(keys(output.target_group_arns)) == toset(["web", "admin"]) &&
      toset(keys(output.listener_arns)) == toset(["web_https", "admin_https", "web_http"])
    )
    error_message = "공개형 ALB에 두 Target Group과 세 Listener가 있어야 합니다."
  }

  assert {
    condition = (
      one(aws_lb_listener.forward["web_https"].default_action).target_group_arn == output.target_group_arns["web"] &&
      one(aws_lb_listener.forward["admin_https"].default_action).target_group_arn == output.target_group_arns["admin"] &&
      aws_lb_listener.forward["admin_https"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-2021-06" &&
      aws_lb_target_group.this["admin"].target_type == "ip" &&
      one(aws_lb_target_group.this["admin"].health_check).protocol == "HTTPS" &&
      one(aws_lb_target_group.this["admin"].health_check).matcher == "200-299" &&
      one(one(aws_lb_listener.redirect["web_http"].default_action).redirect).port == "443" &&
      one(one(aws_lb_listener.redirect["web_http"].default_action).redirect).protocol == "HTTPS" &&
      one(one(aws_lb_listener.redirect["web_http"].default_action).redirect).status_code == "HTTP_301"
    )
    error_message = "Listener별 전달 대상과 HTTP→HTTPS 리디렉션이 올바르지 않습니다."
  }
}

run "shared_target_group" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web = { name = "sample-web" }
    }
    listeners = {
      app_a = { port = 8080, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
      app_b = { port = 8081, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
    }
  }

  override_resource {
    target          = aws_lb_target_group.this["web"]
    override_during = plan
    values = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:targetgroup/sample-web/1234567890123456"
    }
  }

  assert {
    condition = (
      length(aws_lb_listener.forward) == 2 &&
      one(aws_lb_listener.forward["app_a"].default_action).target_group_arn == output.target_group_arns["web"] &&
      one(aws_lb_listener.forward["app_b"].default_action).target_group_arn == output.target_group_arns["web"]
    )
    error_message = "서로 다른 Listener가 같은 Target Group을 공유할 수 있어야 합니다."
  }
}

run "rejects_target_group_without_vpc" {
  command = plan

  variables {
    target_groups = { web = { name = "sample-web" } }
  }

  expect_failures = [aws_lb.this]
}

run "rejects_unknown_target_group" {
  command = plan

  variables {
    listeners = {
      web_http = { port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_key = "missing" } }
    }
  }

  expect_failures = [aws_lb.this]
}

run "rejects_unknown_redirect_listener" {
  command = plan

  variables {
    listeners = {
      web_http = { port = 80, protocol = "HTTP", default_action = { type = "redirect", redirect_to_listener_key = "missing" } }
    }
  }

  expect_failures = [aws_lb.this]
}

run "rejects_redirect_to_http_listener" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { name = "sample-web" } }
    listeners = {
      app_http = { port = 8080, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
      web_http = { port = 80, protocol = "HTTP", default_action = { type = "redirect", redirect_to_listener_key = "app_http" } }
    }
  }

  expect_failures = [aws_lb.this]
}

run "rejects_duplicate_listener_port" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { name = "sample-web" } }
    listeners = {
      first  = { port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
      second = { port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
    }
  }

  expect_failures = [var.listeners]
}

run "rejects_public_http_forward" {
  command = plan

  variables {
    internal      = false
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { name = "sample-web" } }
    listeners = {
      web_http = { port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_key = "web" } }
    }
  }

  expect_failures = [aws_lb.this]
}

run "rejects_https_without_certificate" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { name = "sample-web" } }
    listeners = {
      web_https = { port = 443, protocol = "HTTPS", default_action = { type = "forward", target_group_key = "web" } }
    }
  }

  expect_failures = [var.listeners]
}

run "rejects_http_with_certificate" {
  command = plan

  variables {
    vpc_id        = "vpc-0123456789abcdef0"
    target_groups = { web = { name = "sample-web" } }
    listeners = {
      web_http = {
        port            = 80
        protocol        = "HTTP"
        certificate_arn = "arn:aws:acm:ap-northeast-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
        default_action  = { type = "forward", target_group_key = "web" }
      }
    }
  }

  expect_failures = [var.listeners]
}

run "rejects_duplicate_target_group_name" {
  command = plan

  variables {
    vpc_id = "vpc-0123456789abcdef0"
    target_groups = {
      web   = { name = "sample-web" }
      admin = { name = "sample-web" }
    }
  }

  expect_failures = [var.target_groups]
}
