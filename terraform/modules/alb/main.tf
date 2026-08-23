locals {
  name                 = var.name
  tags                 = merge(var.tags, { Module = "alb" })
  use_https            = var.certificate_arn != ""
  client_listener_port = local.use_https ? 443 : 80
}

# ----------------------------------------------------------------------------
# Security Group for ALB
# ----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Application Load Balancer for server-monitor; HTTPS in production and HTTP in short-lived validation."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(length(var.allowed_ingress_cidrs) > 0 ? var.allowed_ingress_cidrs : [])

  security_group_id = aws_security_group.alb.id
  description       = local.use_https ? "HTTPS from allowed networks" : "HTTP from allowed networks for short-lived validation"
  ip_protocol       = "tcp"
  from_port         = local.client_listener_port
  to_port           = local.client_listener_port
  cidr_ipv4         = each.value
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward to EC2 target port within VPC CIDR"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = data.aws_vpc.this.cidr_block
}

# ----------------------------------------------------------------------------
# S3 bucket for ALB access logs
# ----------------------------------------------------------------------------
resource "random_id" "log_bucket_suffix" {
  byte_length = 4
}

# ALB のアクセスログは AWS ELB サービスからの書き込みのため、SSE-S3 (AES256) を用いる。
# SSE-KMS (customer-managed key) は ALB Access Logs の仕様上未サポート。
# trivy:ignore:AVD-AWS-0132 tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket" "access_logs" {
  bucket        = "${local.name}-alb-access-logs-${random_id.log_bucket_suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = "${local.name}-alb-access-logs" })
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ALB アクセスログは SSE-S3 (AES256) で書き込まれる。SSE-KMS (CMK) は仕様上未対応のため受け入れる。
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.access_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowELBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.access_logs.arn}/${local.name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid    = "DenyInsecureTransport"
        Effect = "Deny"
        Principal = {
          AWS = "*"
        }
        Action   = "s3:*"
        Resource = ["${aws_s3_bucket.access_logs.arn}", "${aws_s3_bucket.access_logs.arn}/*"]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

# ----------------------------------------------------------------------------
# ALB
# ----------------------------------------------------------------------------
# 運用者向けのダッシュボード入口であり、インターネットからの HTTPS を受ける必要があるため
# internal=false (パブリック) を採用する。アクセス元 CIDR は allowed_ingress_cidrs で絞る。
#tfsec:ignore:aws-elb-alb-not-public
resource "aws_lb" "this" {
  name                       = "${local.name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = false
  enable_http2               = true
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    enabled = true
    prefix  = local.name
  }

  tags = merge(local.tags, { Name = "${local.name}-alb" })

  depends_on = [aws_s3_bucket_policy.access_logs]
}

# ----------------------------------------------------------------------------
# Target Group
# ----------------------------------------------------------------------------
resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/healthz"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = merge(local.tags, { Name = "${local.name}-tg" })
}

# Target Group Attachment は環境側で作る（compute モジュール出力を渡す）。
# こうしないと alb -> compute -> alb の循環参照になる。

# ----------------------------------------------------------------------------
# Listeners
# ----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  count = local.use_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.tags
}

# HTTP listener。use_https=true なら 443 へリダイレクト、false (dev) なら平文転送。
# 平文転送モードは dev / 検証専用で、prod は certificate_arn 必須のため必ずリダイレクトになる。
# trivy:ignore:AVD-AWS-0054 tfsec:ignore:aws-elb-http-not-used
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.use_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.use_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.app.arn
    }
  }

  tags = local.tags
}
