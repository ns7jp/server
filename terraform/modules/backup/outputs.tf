output "vault_arn" {
  description = "AWS Backup Vault ARN。"
  value       = aws_backup_vault.this.arn
}

output "vault_name" {
  description = "AWS Backup Vault 名。"
  value       = aws_backup_vault.this.name
}

output "plan_id" {
  description = "AWS Backup Plan ID。"
  value       = aws_backup_plan.this.id
}

output "kms_key_arn" {
  description = "Backup 用 KMS キー ARN。"
  value       = aws_kms_key.backup.arn
}

output "archive_bucket" {
  description = "アーカイブ S3 バケット名。"
  value       = aws_s3_bucket.archive.id
}

output "backup_role_arn" {
  description = "AWS Backup 用 IAM ロール ARN。"
  value       = aws_iam_role.backup.arn
}
