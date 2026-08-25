locals {
  common_tags = {
    Project     = "server-monitor"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# amazon.aws.aws_ssm connection pluginがmodule転送に使う短命bucket。
# versioningを有効化すると一時objectの旧versionが残るため、意図的に未設定（Disabled）とする。
resource "random_id" "ssm_transfer_bucket_suffix" {
  byte_length = 4
}

#tfsec:ignore:aws-s3-enable-versioning Ansible SSM transfer objects must not retain versions.
#tfsec:ignore:aws-s3-encryption-customer-key Short-lived transfer objects use SSE-S3 and expire in one day.
resource "aws_s3_bucket" "ssm_transfer" {
  bucket        = "${var.name_prefix}-ssm-transfer-${random_id.ssm_transfer_bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-ssm-transfer" })
}

resource "aws_s3_bucket_public_access_block" "ssm_transfer" {
  bucket                  = aws_s3_bucket.ssm_transfer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#trivy:ignore:AWS-0132 SSM transfer uses short-lived SSE-S3 objects; CMK would add controller and managed-node KMS coupling.
resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id

  rule {
    id     = "expire-ansible-ssm-transfer"
    status = "Enabled"

    expiration {
      days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "ssm_transfer" {
  bucket = aws_s3_bucket.ssm_transfer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.ssm_transfer.arn,
        "${aws_s3_bucket.ssm_transfer.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_iam_policy" "ssm_transfer_controller" {
  name        = "${var.name_prefix}-ssm-transfer-controller"
  description = "Least-privilege S3 access for the approved Ansible SSM controller."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketMetadata"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = aws_s3_bucket.ssm_transfer.arn
      },
      {
        Sid      = "TransferObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.ssm_transfer.arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_transfer_controller" {
  count = var.ssm_controller_role_name == "" ? 0 : 1

  role       = var.ssm_controller_role_name
  policy_arn = aws_iam_policy.ssm_transfer_controller.arn
}

module "network" {
  source = "../../modules/network"

  name               = var.name_prefix
  cidr_block         = var.vpc_cidr
  azs                = var.azs
  enable_nat_gateway = true
  single_nat_gateway = true
  tags               = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  name                  = var.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_id_list
  target_port           = 8080
  certificate_arn       = var.certificate_arn
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  force_destroy         = true
  tags                  = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  name                  = var.name_prefix
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  azs                   = var.compute_azs
  instance_type         = var.instance_type
  alb_security_group_id = module.alb.alb_security_group_id
  ssh_ingress_cidrs     = var.ssh_ingress_cidrs
  # ssh_ingress_cidrs を空にすると SSM が唯一の経路になる。
  # amazon.aws.aws_ssm は S3 バケット経由でファイルを渡すので、controller 側
  # （aws_iam_policy.ssm_transfer_controller）だけでなく、**管理対象ノード側**
  # にも同じバケットへの読み書き権限が要る。
  # AmazonSSMManagedInstanceCore にはこの S3 権限が含まれないため、これが無いと
  # apply は通っても「Ansible で構成を適用」の段階で AccessDenied になる。
  ssm_file_transfer_bucket = aws_s3_bucket.ssm_transfer.bucket
  # D-2の障害注入中に定時startが競合しないよう、短命stagingは手動で停止・破棄する。
  schedule_stop_enabled = false
  tags                  = merge(local.common_tags, { AlbHealthCheckSourceCidr = var.vpc_cidr })
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = module.compute.instance_ids

  target_group_arn = module.alb.target_group_arn
  target_id        = each.value
  port             = 8080
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                     = var.name_prefix
  instance_ids             = module.compute.instance_ids
  target_group_arn         = module.alb.target_group_arn
  load_balancer_arn_suffix = split("loadbalancer/", module.alb.alb_arn)[1]
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  alarm_emails             = var.alarm_emails
  monthly_budget_jpy       = var.monthly_budget_jpy
  # GuardDuty is account/region-scoped and CloudTrail is account-wide. A
  # short-lived restore drill must not create competing detectors or trails.
  enable_guardduty  = false
  enable_cloudtrail = false
  tags              = local.common_tags
}

module "backup" {
  source = "../../modules/backup"

  name                    = var.name_prefix
  instance_arns           = module.compute.instance_arns
  backup_retention_days   = 14
  force_destroy           = true
  protect_recovery_points = false
  tags                    = local.common_tags
}
