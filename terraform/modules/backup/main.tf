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
  name          = "${local.name}-vault"
  kms_key_arn   = aws_kms_key.backup.arn
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = "${local.name}-vault" })
}

locals {
  # terraform を実行している principal。assumed-role の ARN は
  # arn:aws:sts::<acct>:assumed-role/<role>/<session> の形で来るので、
  # policy の条件で使える arn:aws:iam::<acct>:role/<role> へ直す。
  caller_arn = data.aws_caller_identity.current.arn
  caller_role_arn = can(regex("^arn:[^:]+:sts::[0-9]+:assumed-role/", local.caller_arn)) ? format(
    "arn:%s:iam::%s:role/%s",
    data.aws_partition.current.partition,
    data.aws_caller_identity.current.account_id,
    split("/", local.caller_arn)[1],
  ) : local.caller_arn

  # 自己ロックアウトを防ぐため、実行中の principal を必ず例外へ含める。
  vault_policy_admin_arns = distinct(concat(
    var.recovery_point_delete_principal_arns,
    [local.caller_role_arn],
  ))
}

resource "aws_backup_vault_policy" "this" {
  count = var.protect_recovery_points ? 1 : 0

  backup_vault_name = aws_backup_vault.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyRecoveryPointMutation"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action = [
          "backup:DeleteRecoveryPoint",
          "backup:UpdateRecoveryPointLifecycle",
        ]
        Resource = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = concat(
              local.vault_policy_admin_arns,
              [
                aws_iam_role.backup.arn,
                "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup",
              ]
            )
          }
        }
      },
      # resource-based policy の explicit Deny はアカウント管理者でも
      # 回避できない。ここで列挙し忘れた principal は、以後この vault の
      # policy を書き換えられず、recovery point も消せず、terraform destroy
      # も通らなくなる（自己ロックアウト）。
      # そのため、実行中の principal を必ず例外へ含める。
      {
        Sid       = "DenyVaultPolicyMutation"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action = [
          "backup:PutBackupVaultAccessPolicy",
          "backup:DeleteBackupVaultAccessPolicy",
        ]
        Resource = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = local.vault_policy_admin_arns
          }
        }
      },
    ]
  })

  lifecycle {
    precondition {
      condition     = length(var.recovery_point_delete_principal_arns) >= 1
      error_message = "protect_recovery_points=true requires at least one real break-glass principal ARN."
    }
  }
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

  lifecycle {
    precondition {
      condition = (
        var.cold_storage_after_days == 0
        || var.backup_retention_days >= var.cold_storage_after_days + 90
      )
      error_message = "backup_retention_days must be at least 90 days after cold_storage_after_days."
    }
  }
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

  # Explicit environment-scoped ARNs prevent dev/staging/prod selections from
  # forming a union through a broad account-wide Application tag.
  resources = var.instance_arns
}

# ----------------------------------------------------------------------------
# S3 archive bucket（Prometheus / Loki / Grafana の長期保存）
# ----------------------------------------------------------------------------
resource "random_id" "archive_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "archive" {
  bucket        = "${local.name}-archive-${random_id.archive_bucket_suffix.hex}"
  force_destroy = var.force_destroy

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
