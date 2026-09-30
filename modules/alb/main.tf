resource "aws_lb" "this" {
  name                       = var.name
  internal                   = var.internal
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = var.subnet_ids
  security_groups            = var.security_group_ids
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = length(var.target_groups) == 0 || var.vpc_id != null
      error_message = "target_groups가 있으면 vpc_id를 지정해야 합니다."
    }

    precondition {
      condition = alltrue([
        for listener in values(var.listeners) :
        var.internal || listener.protocol == "HTTPS" || listener.default_action.type == "redirect"
      ])
      error_message = "공개형 ALB의 HTTP Listener는 HTTPS로 리디렉션해야 합니다."
    }

    precondition {
      condition = alltrue([
        for listener in values(var.listeners) :
        listener.default_action.type != "forward" ||
        contains(keys(var.target_groups), listener.default_action.target_group_key)
      ])
      error_message = "forward Listener의 target_group_key는 target_groups에 있어야 합니다."
    }

    precondition {
      condition = alltrue([
        for listener in values(var.listeners) :
        listener.default_action.type != "redirect" || (
          contains(keys(var.listeners), listener.default_action.redirect_to_listener_key) &&
          try(var.listeners[listener.default_action.redirect_to_listener_key].protocol == "HTTPS", false) &&
          try(var.listeners[listener.default_action.redirect_to_listener_key].default_action.type == "forward", false)
        )
      ])
      error_message = "redirect Listener는 전달 동작을 가진 HTTPS Listener의 논리 키를 참조해야 합니다."
    }
  }
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = each.value.name
  vpc_id      = var.vpc_id
  target_type = each.value.target_type
  protocol    = each.value.protocol
  port        = each.value.port

  health_check {
    protocol = each.value.protocol
    path     = each.value.health_check_path
    matcher  = each.value.health_check_matcher
  }

  tags = merge(var.tags, {
    Name = each.value.name
  })
}

resource "aws_lb_listener" "forward" {
  for_each = {
    for key, listener in var.listeners : key => listener
    if listener.default_action.type == "forward"
  }

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol
  certificate_arn   = each.value.protocol == "HTTPS" ? each.value.certificate_arn : null
  ssl_policy        = each.value.protocol == "HTTPS" ? each.value.tls_policy : null

  default_action {
    type             = "forward"
    target_group_arn = try(aws_lb_target_group.this[each.value.default_action.target_group_key].arn, null)
  }
}

resource "aws_lb_listener" "redirect" {
  for_each = {
    for key, listener in var.listeners : key => listener
    if listener.default_action.type == "redirect"
  }

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = tostring(try(var.listeners[each.value.default_action.redirect_to_listener_key].port, 443))
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  depends_on = [aws_lb_listener.forward]
}
