resource "aws_instance" "this" {
  ami                         = var.ami_id
  associate_public_ip_address = var.associate_public_ip_address
  iam_instance_profile        = var.iam_instance_profile
  instance_type               = var.instance_type
  key_name                    = var.key_name
  monitoring                  = var.monitoring
  subnet_id                   = var.subnet_id
  user_data                   = var.user_data
  vpc_security_group_ids      = var.security_group_ids

  dynamic "instance_market_options" {
    for_each = var.purchase_option == "spot" ? [1] : []

    content {
      market_type = "spot"

      spot_options {
        instance_interruption_behavior = "terminate"
        spot_instance_type             = "one-time"
      }
    }
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.root_volume_kms_key_id
    volume_size           = var.root_volume_size
    volume_type           = "gp3"

    tags = merge(var.tags, {
      Name = "${var.name}-root"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}
