locals {
  name = var.name
  tags = merge(var.tags, { Module = "compute" })
}

# ----------------------------------------------------------------------------
# Ubuntu 22.04 LTS AMI (Canonical)
# ----------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ----------------------------------------------------------------------------
# Security Group
# ----------------------------------------------------------------------------
resource "aws_security_group" "instance" {
  name        = "${local.name}-ec2-sg"
  description = "Server-monitor EC2 instances; ingress from ALB only."
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name}-ec2-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.instance.id
  description                  = "Application port from ALB target group only"
  ip_protocol                  = "tcp"
  from_port                    = var.ec2_application_port
  to_port                      = var.ec2_application_port
  referenced_security_group_id = var.alb_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "ssh_emergency" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.instance.id
  description       = "Emergency SSH access (prefer SSM Session Manager)"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# EC2 egress: NAT 経由で apt / Docker registry / AWS API へ出るため 0.0.0.0/0 を許可する。
# VPC エンドポイントで AWS サービス分は閉域化可能だが、apt / Docker Hub は閉じられない
# ため受け入れる。学習目的の単一ホスト構成。
# trivy:ignore:AVD-AWS-0104 tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS egress for apt / Docker pulls / SSM endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# trivy:ignore:AVD-AWS-0104 tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "http_out" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTP egress for apt mirror redirects"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Amazon Time Sync Service（169.254.169.123）に固定。NTP の汎用解放は不要。
resource "aws_vpc_security_group_egress_rule" "ntp_out" {
  security_group_id = aws_security_group.instance.id
  description       = "NTP to Amazon Time Sync Service"
  ip_protocol       = "udp"
  from_port         = 123
  to_port           = 123
  cidr_ipv4         = "169.254.169.123/32"
}

# ----------------------------------------------------------------------------
# IAM: EC2 Instance Profile (SSM + CloudWatch Agent)
# ----------------------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name = "${local.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# amazon.aws.aws_ssm connection plugin は、S3 バケット経由でファイルを
# 受け渡す。AmazonSSMManagedInstanceCore にはその S3 権限が含まれないため、
# これが無いと apply は通っても次の「Ansible で構成を適用」の段階で
# AccessDenied になる。ssh_ingress_cidrs = [] の環境では SSM が唯一の
# 経路なので、そこで詰まると入る手段が無くなる。
data "aws_partition" "current" {}

resource "aws_iam_role_policy" "ssm_file_transfer" {
  count = var.ssm_file_transfer_bucket == "" ? 0 : 1

  name = "${local.name}-ssm-file-transfer"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "AllowSsmTransferObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.ssm_file_transfer_bucket}/*"
      },
      {
        Sid      = "AllowSsmTransferBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.ssm_file_transfer_bucket}"
      },
      ], var.ssm_file_transfer_kms_key_arn == "" ? [] : [
      {
        Sid      = "AllowSsmTransferKms"
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
        Resource = var.ssm_file_transfer_kms_key_arn
      },
    ])
  })
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_iam_policy_arns)

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.instance.name

  tags = local.tags
}

# ----------------------------------------------------------------------------
# EBS encryption KMS key
# ----------------------------------------------------------------------------
resource "aws_kms_key" "ebs" {
  description             = "${local.name} EBS encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.tags, { Name = "${local.name}-ebs-kms" })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${local.name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# ----------------------------------------------------------------------------
# EC2 Instances (one per AZ)
# ----------------------------------------------------------------------------
locals {
  user_data = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - python3
      - python3-apt
      - rsync
    runcmd:
      # SSM Agent はマスタ AMI に入っているが念のため有効化
      - systemctl enable --now amazon-ssm-agent || true
  EOT
}

resource "aws_instance" "this" {
  for_each = toset(var.azs)

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[each.value]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  user_data                   = local.user_data
  user_data_replace_on_change = false

  monitoring    = true
  ebs_optimized = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 強制
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.ebs.arn
    delete_on_termination = true

    tags = merge(local.tags, { Name = "${local.name}-${each.value}-root" })
  }

  tags = merge(local.tags, {
    Name        = "${local.name}-${each.value}"
    Application = "server-monitor"
    AnsibleHost = "true"
  })

  lifecycle {
    ignore_changes = [
      ami,       # AMI 更新は別途 blue/green で行う
      user_data, # Ansible で構成適用するため initial bootstrap のみ
    ]
  }
}

# ----------------------------------------------------------------------------
# 夜間停止 / 朝起動スケジュール（コスト削減）
# ----------------------------------------------------------------------------
resource "aws_iam_role" "scheduler" {
  count = var.schedule_stop_enabled ? 1 : 0

  name = "${local.name}-ec2-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.schedule_stop_enabled ? 1 : 0

  name = "${local.name}-ec2-scheduler"
  role = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:StartInstances",
        "ec2:StopInstances",
      ]
      Resource = [for i in aws_instance.this : i.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "stop" {
  count = var.schedule_stop_enabled ? 1 : 0

  name                = "${local.name}-ec2-stop"
  schedule_expression = var.schedule_stop_cron

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [for i in aws_instance.this : i.id]
    })
  }
}

resource "aws_scheduler_schedule" "start" {
  count = var.schedule_stop_enabled ? 1 : 0

  name                = "${local.name}-ec2-start"
  schedule_expression = var.schedule_start_cron

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      InstanceIds = [for i in aws_instance.this : i.id]
    })
  }
}

data "aws_caller_identity" "current" {}
