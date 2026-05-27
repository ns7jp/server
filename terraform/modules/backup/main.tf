locals {
  name = var.name
  tags = merge(var.tags, { Module = "backup" })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ----------------------------------------------------------------------------
# KMS key for Backup vault
# ----------------------------------------------------------------------------
resource "aws_kms_key" "backup" {
  description             = "${local.name} AWS Backup vault encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowAWSBackup"
        Effect    = "Allow"
        Principal = { Service = "backup.amazonaws.com" }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
    ]
  })

  tags = merge(local.tags, { Name = "${local.name}-backup-kms" })
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${local.name}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

# ----------------------------------------------------------------------------
# Backup Vault
# ----------------------------------------------------------------------------
resource "aws_backup_vault" "this" {
  name        = "${local.name}-vault"
  kms_key_arn = aws_kms_key.backup.arn

  tags = merge(local.tags, { Name = "${local.name}-vault" })
}

resource "aws_backup_vault_policy" "this" {
  backup_vault_name = aws_backup_vault.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDeleteRecoveryPoints"
      Effect = "Deny"
      Principal = {
        AWS = "*"
      }
      Action = [
        "backup:DeleteRecoveryPoint",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:PrincipalArn" = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-backup-admin"
        }
      }
    }]
  })
}

# ----------------------------------------------------------------------------
# Backup Plan
# ----------------------------------------------------------------------------
resource "aws_backup_plan" "this" {
  name = "${local.name}-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.backup_schedule_cron
    start_window      = 60
    completion_window = 180

    lifecycle {
      cold_storage_after = var.cold_storage_after_days > 0 ? var.cold_storage_after_days : null
      delete_after       = var.backup_retention_days
    }

    recovery_point_tags = merge(local.tags, { BackupPlan = "${local.name}-daily" })
  }

  tags = merge(local.tags, { Name = "${local.name}-plan" })
}

# ----------------------------------------------------------------------------
# IAM Role for AWS Backup
# ----------------------------------------------------------------------------
resource "aws_iam_role" "backup" {
  name = "${local.name}-backup-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# ----------------------------------------------------------------------------
# Backup Selection (resources)
# ----------------------------------------------------------------------------
resource "aws_backup_selection" "this" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "${local.name}-selection"
  plan_id      = aws_backup_plan.this.id

  resources = var.instance_arns

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Application"
    value = "server-monitor"
  }
}

# ----------------------------------------------------------------------------
# S3 archive bucket（Prometheus / Loki / Grafana の長期保存）
# ----------------------------------------------------------------------------
resource "random_id" "archive_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "archive" {
  bucket        = "${local.name}-archive-${random_id.archive_bucket_suffix.hex}"
  force_destroy = false

  tags = merge(local.tags, { Name = "${local.name}-archive" })
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.backup.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "tier-then-expire"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.archive_bucket_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  bucket = aws_s3_bucket.archive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = { AWS = "*" }
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.archive.arn, "${aws_s3_bucket.archive.arn}/*"]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
