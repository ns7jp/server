locals {
  name = var.name
  tags = merge(var.tags, { Module = "synthetics-probe" })
}

data "aws_partition" "current" {}

# ----------------------------------------------------------------------------
# Canary source。ローカルの .js を zip するだけなので apply 前のネットワーク
# アクセスは不要（Synthetics/SyntheticsLogger は Lambda runtime layer が実行時に
# 注入する。npm install は行わない）。
# ----------------------------------------------------------------------------
data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/canary-src"
  output_path = "${path.module}/dist/healthz-canary.zip"
}

# ----------------------------------------------------------------------------
# S3 bucket for canary artifacts (screenshots / HAR / run履歴)
# ----------------------------------------------------------------------------
resource "random_id" "artifacts_bucket_suffix" {
  byte_length = 4
}

#tfsec:ignore:aws-s3-encryption-customer-key Canary runs are short-lived Lambda invocations; SSE-S3 avoids coupling the managed canary execution role to a customer KMS key.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name}-synthetics-${random_id.artifacts_bucket_suffix.hex}"
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = "${local.name}-synthetics-artifacts" })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.artifact_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# ----------------------------------------------------------------------------
# IAM execution role（canary は AWS 管理の Lambda として実行される）
# ----------------------------------------------------------------------------
resource "aws_iam_role" "canary" {
  name = "${local.name}-synthetics-canary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "canary_execution" {
  role       = aws_iam_role.canary.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/CloudWatchSyntheticsExecutionRolePolicy"
}

# CloudWatchSyntheticsExecutionRolePolicy は CloudWatch Logs / X-Ray と
# s3:ListAllMyBuckets のみを許可し、この artifacts bucket への書き込みは
# 含まない。
resource "aws_iam_role_policy" "canary_artifacts" {
  name = "${local.name}-synthetics-artifacts"
  role = aws_iam_role.canary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "WriteCanaryArtifacts"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetBucketLocation"]
      Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    }]
  })
}

# ----------------------------------------------------------------------------
# Canary
# ----------------------------------------------------------------------------
resource "aws_synthetics_canary" "healthz" {
  name                 = var.canary_name
  artifact_s3_location = "s3://${aws_s3_bucket.artifacts.id}/canary"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "healthzCanary.handler"
  zip_file             = data.archive_file.canary.output_path
  runtime_version      = var.runtime_version
  start_canary         = var.start_canary

  schedule {
    expression = var.schedule_expression
  }

  run_config {
    timeout_in_seconds = 30
    environment_variables = {
      HEALTHZ_URL = var.target_url
    }
  }

  success_retention_period = var.artifact_retention_days
  failure_retention_period = var.artifact_retention_days

  tags = merge(local.tags, { Name = "${local.name}-healthz-canary" })
}

# ----------------------------------------------------------------------------
# 失敗アラート
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "healthz_canary_failure" {
  alarm_name          = "${local.name}-healthz-canary-failure"
  alarm_description   = "External CloudWatch Synthetics canary against ${var.target_url} is failing (probed from outside the monitored host)."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  period              = 60
  threshold           = 100
  statistic           = "Average"
  namespace           = "CloudWatchSynthetics"
  metric_name         = "SuccessPercent"
  treat_missing_data  = "breaching"

  dimensions = {
    CanaryName = aws_synthetics_canary.healthz.name
  }

  alarm_actions = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]
  ok_actions    = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]

  tags = local.tags
}
