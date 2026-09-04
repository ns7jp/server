output "canary_name" {
  description = "CloudWatch Synthetics canary名。"
  value       = aws_synthetics_canary.healthz.name
}

output "canary_arn" {
  description = "CloudWatch Synthetics canary ARN。"
  value       = aws_synthetics_canary.healthz.arn
}

output "artifacts_bucket" {
  description = "Canary成果物を保存するS3バケット名。"
  value       = aws_s3_bucket.artifacts.id
}

output "alarm_arn" {
  description = "Canary失敗アラームのARN。"
  value       = aws_cloudwatch_metric_alarm.healthz_canary_failure.arn
}
