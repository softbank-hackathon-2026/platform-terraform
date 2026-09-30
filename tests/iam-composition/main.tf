module "policy" {
  source = "../../modules/iam/policy"

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

module "role" {
  source = "../../modules/iam/role"

  name = "sample-app-role"
  assume_role_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  managed_policy_arns = {
    object_read = module.policy.policy_arn
  }

  create_instance_profile = true
}

module "ec2" {
  source = "../../modules/ec2"

  name                 = "sample-app"
  ami_id               = "ami-0123456789abcdef0"
  instance_type        = "t3.micro"
  subnet_id            = "subnet-0123456789abcdef0"
  security_group_ids   = ["sg-0123456789abcdef0"]
  iam_instance_profile = module.role.instance_profile_name
}

output "policy_arn" {
  value = module.policy.policy_arn
}

output "role_name" {
  value = module.role.role_name
}

output "instance_profile_name" {
  value = module.role.instance_profile_name
}

output "ec2_id" {
  value = module.ec2.id
}
