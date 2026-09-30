mock_provider "aws" {
  override_during = plan
}

variables {
  name   = "sample-app"
  vpc_id = "vpc-0123456789abcdef0"
}

run "deny_by_default" {
  command = plan

  override_resource {
    target          = aws_security_group.this
    override_during = plan
    values = {
      id  = "sg-0123456789abcdef0"
      arn = "arn:aws:ec2:ap-northeast-2:123456789012:security-group/sg-0123456789abcdef0"
    }
  }

  assert {
    condition = (
      aws_security_group.this.name == "sample-app" &&
      aws_security_group.this.vpc_id == var.vpc_id &&
      aws_security_group.this.tags["Name"] == "sample-app" &&
      length(aws_vpc_security_group_ingress_rule.this) == 0 &&
      length(aws_vpc_security_group_egress_rule.this) == 0
    )
    error_message = "기본 구성은 Security Group 하나를 만들고 규칙을 추가하지 않아야 합니다."
  }

  assert {
    condition = (
      output.security_group_id == "sg-0123456789abcdef0" &&
      output.security_group_arn == "arn:aws:ec2:ap-northeast-2:123456789012:security-group/sg-0123456789abcdef0"
    )
    error_message = "Security Group ID와 ARN 출력이 올바르지 않습니다."
  }
}

run "explicit_rules" {
  command = plan

  variables {
    ingress_rules = {
      https = {
        ip_protocol = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.10.0.0/16"
      }
      peer_udp = {
        ip_protocol                  = "udp"
        from_port                    = 5000
        to_port                      = 5001
        referenced_security_group_id = "sg-11111111111111111"
      }
    }

    egress_rules = {
      all_ipv4 = {
        ip_protocol = "-1"
        cidr_ipv4   = "0.0.0.0/0"
      }
      database = {
        ip_protocol                  = "tcp"
        from_port                    = 5432
        to_port                      = 5432
        referenced_security_group_id = "sg-22222222222222222"
      }
    }
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.this) == 2 &&
      length(aws_vpc_security_group_egress_rule.this) == 2 &&
      aws_vpc_security_group_ingress_rule.this["https"].cidr_ipv4 == "10.10.0.0/16" &&
      aws_vpc_security_group_ingress_rule.this["https"].from_port == 443 &&
      aws_vpc_security_group_ingress_rule.this["peer_udp"].referenced_security_group_id == "sg-11111111111111111" &&
      aws_vpc_security_group_egress_rule.this["all_ipv4"].ip_protocol == "-1" &&
      aws_vpc_security_group_egress_rule.this["all_ipv4"].from_port == null &&
      aws_vpc_security_group_egress_rule.this["database"].to_port == 5432
    )
    error_message = "명시한 IPv4 및 Security Group 참조 규칙이 올바르게 생성되어야 합니다."
  }
}

run "rejects_missing_target" {
  command = plan

  variables {
    ingress_rules = {
      invalid = {
        ip_protocol = "tcp"
        from_port   = 443
        to_port     = 443
      }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_multiple_targets" {
  command = plan

  variables {
    ingress_rules = {
      invalid = {
        ip_protocol                  = "tcp"
        from_port                    = 443
        to_port                      = 443
        cidr_ipv4                    = "10.10.0.0/16"
        referenced_security_group_id = "sg-11111111111111111"
      }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_missing_tcp_ports" {
  command = plan

  variables {
    ingress_rules = {
      invalid = {
        ip_protocol = "tcp"
        cidr_ipv4   = "10.10.0.0/16"
      }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_all_protocol_ports" {
  command = plan

  variables {
    egress_rules = {
      invalid = {
        ip_protocol = "-1"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "10.10.0.0/16"
      }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_missing_udp_ports" {
  command = plan

  variables {
    egress_rules = {
      invalid = {
        ip_protocol = "udp"
        from_port   = 53
        cidr_ipv4   = "10.10.0.0/16"
      }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_invalid_ipv4_cidr" {
  command = plan

  variables {
    ingress_rules = {
      invalid = {
        ip_protocol = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_ipv4   = "not-a-cidr"
      }
    }
  }

  expect_failures = [var.ingress_rules]
}
