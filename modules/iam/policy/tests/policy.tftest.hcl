mock_provider "aws" {
  override_during = plan
}

variables {
  name = "sample-object-read"
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["arn:aws:s3:::example-data/*"]
    }]
  })
}

run "creates_policy" {
  command = plan

  override_resource {
    target          = aws_iam_policy.this
    override_during = plan
    values = {
      arn = "arn:aws:iam::123456789012:policy/sample-object-read"
    }
  }

  variables {
    tags = {
      Service = "sample"
    }
  }

  assert {
    condition = (
      aws_iam_policy.this.name == "sample-object-read" &&
      aws_iam_policy.this.tags["Service"] == "sample" &&
      jsondecode(aws_iam_policy.this.policy).Statement[0].Action[0] == "s3:GetObject" &&
      output.policy_name == "sample-object-read" &&
      output.policy_arn == "arn:aws:iam::123456789012:policy/sample-object-read"
    )
    error_message = "고객 관리 IAM Policy와 출력값이 입력에 맞아야 합니다."
  }
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "rejects_invalid_json" {
  command = plan

  variables {
    policy_json = "invalid-json"
  }

  expect_failures = [var.policy_json]
}
