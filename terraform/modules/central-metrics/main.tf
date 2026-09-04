locals {
  name = var.name
  tags = merge(var.tags, { Module = "central-metrics" })
}

# ----------------------------------------------------------------------------
# Amazon Managed Service for Prometheus (AMP) workspace
#
# ホストが消えると時系列の正本も一緒に失われる単一ホストPrometheusの制約
# （docs/roadmap/external-probe-central-telemetry.md）を解消するための
# remote_write先。既存のホスト内Prometheusは維持し、ここへremote_writeで
# 転送するだけなので、ローカルのdashboard/alertルールは変更不要。
# ----------------------------------------------------------------------------
resource "aws_prometheus_workspace" "this" {
  alias = "${local.name}-amp"

  tags = merge(local.tags, { Name = "${local.name}-amp" })
}

# ----------------------------------------------------------------------------
# remote_write用の最小権限 IAM policy。
# compute module の additional_iam_policy_arns へ remote_write_policy_arn を
# 渡してEC2 instance roleへアタッチする（このモジュール自身はEC2 roleを
# 知らないため、アタッチは呼び出し側=environment root moduleが行う）。
# ----------------------------------------------------------------------------
resource "aws_iam_policy" "remote_write" {
  name        = "${local.name}-amp-remote-write"
  description = "Least-privilege remote_write access scoped to this AMP workspace only."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowRemoteWrite"
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      Resource = aws_prometheus_workspace.this.arn
    }]
  })

  tags = local.tags
}
