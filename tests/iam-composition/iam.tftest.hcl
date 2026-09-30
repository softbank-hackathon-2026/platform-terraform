mock_provider "aws" {
  override_during = plan
}

run "connects_policy_role_and_ec2" {
  command = plan

  override_resource {
    target          = module.policy.aws_iam_policy.this
    override_during = plan
    values = {
      arn = "arn:aws:iam::123456789012:policy/sample-object-read"
    }
  }

  override_resource {
    target          = module.ec2.aws_instance.this
    override_during = plan
    values = {
      id = "i-0123456789abcdef0"
    }
  }

  assert {
    condition = (
      output.policy_arn == "arn:aws:iam::123456789012:policy/sample-object-read" &&
      output.role_name == "sample-app-role" &&
      output.instance_profile_name == "sample-app-role" &&
      output.ec2_id == "i-0123456789abcdef0"
    )
    error_message = "Policy, Role, Instance Profile과 EC2 모듈이 함께 계획되어야 합니다."
  }
}
