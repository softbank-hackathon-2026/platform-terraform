mock_provider "aws" {
  override_during = plan
}

variables {
  name = "sample-app-role"
  assume_role_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

run "role_defaults" {
  command = plan

  override_resource {
    target          = aws_iam_role.this
    override_during = plan
    values = {
      arn = "arn:aws:iam::123456789012:role/sample-app-role"
    }
  }

  assert {
    condition = (
      aws_iam_role.this.name == "sample-app-role" &&
      jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com" &&
      length(aws_iam_role_policy_attachment.this) == 0 &&
      length(aws_iam_instance_profile.this) == 0 &&
      output.role_name == "sample-app-role" &&
      output.role_arn == "arn:aws:iam::123456789012:role/sample-app-role" &&
      output.instance_profile_name == null &&
      output.instance_profile_arn == null
    )
    error_message = "기본 구성은 Role만 만들고 Policy 연결과 Instance Profile을 만들지 않아야 합니다."
  }
}

run "policy_attachments_and_profile" {
  command = plan

  override_resource {
    target          = aws_iam_instance_profile.this[0]
    override_during = plan
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/sample-app-role"
    }
  }

  variables {
    managed_policy_arns = {
      custom = "arn:aws:iam::123456789012:policy/sample-object-read"
      ssm    = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    create_instance_profile = true
    tags = {
      Service = "sample"
    }
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.this) == 2 &&
      aws_iam_role_policy_attachment.this["custom"].policy_arn == var.managed_policy_arns["custom"] &&
      aws_iam_role_policy_attachment.this["ssm"].policy_arn == var.managed_policy_arns["ssm"] &&
      aws_iam_instance_profile.this[0].name == "sample-app-role" &&
      aws_iam_instance_profile.this[0].role == aws_iam_role.this.name &&
      aws_iam_instance_profile.this[0].tags["Service"] == "sample" &&
      output.instance_profile_name == "sample-app-role" &&
      output.instance_profile_arn == "arn:aws:iam::123456789012:instance-profile/sample-app-role"
    )
    error_message = "관리형 Policy 연결과 EC2 Instance Profile이 입력에 맞아야 합니다."
  }
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "rejects_invalid_trust_json" {
  command = plan

  variables {
    assume_role_policy_json = "invalid-json"
  }

  expect_failures = [var.assume_role_policy_json]
}

run "rejects_empty_policy_arn" {
  command = plan

  variables {
    managed_policy_arns = {
      invalid = ""
    }
  }

  expect_failures = [var.managed_policy_arns]
}
