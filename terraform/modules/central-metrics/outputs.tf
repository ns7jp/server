output "workspace_id" {
  description = "AMP workspace ID。"
  value       = aws_prometheus_workspace.this.id
}

output "workspace_arn" {
  description = "AMP workspace ARN。"
  value       = aws_prometheus_workspace.this.arn
}

output "remote_write_url" {
  description = "PrometheusのremoteWrite urlにそのまま設定できるendpoint。"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "remote_write_policy_arn" {
  description = "EC2 instance roleへ additional_iam_policy_arns として渡すIAM policy ARN。"
  value       = aws_iam_policy.remote_write.arn
}
