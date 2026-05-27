output "sns_topic_arn" {
  description = "アラート集約 SNS トピックの ARN。"
  value       = aws_sns_topic.alerts.arn
}

output "kms_key_arn" {
  description = "監査ログ / アラート暗号化用 KMS キーの ARN。"
  value       = aws_kms_key.alerts.arn
}

output "cloudtrail_bucket" {
  description = "CloudTrail を保存している S3 バケット名。"
  value       = try(aws_s3_bucket.cloudtrail[0].id, "")
}

output "guardduty_detector_id" {
  description = "GuardDuty 検出器 ID。"
  value       = try(aws_guardduty_detector.this[0].id, "")
}
