resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = var.assume_role_policy_json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.managed_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0

  name = aws_iam_role.this.name
  role = aws_iam_role.this.name
  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.this]
}
