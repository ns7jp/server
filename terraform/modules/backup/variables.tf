variable "name" {
  description = "リソース名の接頭辞。"
  type        = string
}

variable "instance_arns" {
  description = "AWS Backup の selection で対象に追加する EC2 / EBS リソース ARN。"
  type        = list(string)
}

variable "backup_schedule_cron" {
  description = "AWS Backup の cron 式 (UTC)。"
  type        = string
  default     = "cron(0 17 ? * * *)" # 17:00 UTC = 02:00 JST 翌日
}

variable "backup_retention_days" {
  description = "AWS Backup の保持日数。"
  type        = number
  default     = 14
}

variable "cold_storage_after_days" {
  description = "コールドストレージへ移行する日数。0 で無効化。"
  type        = number
  default     = 0
}

variable "archive_bucket_lifecycle_days" {
  description = "S3 アーカイブバケットのライフサイクル日数（Glacier 移行 → 削除）。"
  type        = number
  default     = 365
}

variable "force_destroy" {
  description = "短時間の非本番環境でvault recovery pointとarchive objectもdestroyするか。prodではfalseのまま使う。"
  type        = bool
  default     = false
}

variable "protect_recovery_points" {
  description = "recovery point削除をAWS Backup lifecycleと明示したbreak-glass principal以外へ拒否するか。"
  type        = bool
  default     = true
}

variable "recovery_point_delete_principal_arns" {
  description = "保護対象のrecovery point/lifecycle/vault policy変更を許可する実在break-glass/deploy IAM principal ARN。Terraform更新時はこのroleをassumeする。"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.recovery_point_delete_principal_arns :
      startswith(arn, "arn:") && !strcontains(arn, "*")
    ])
    error_message = "Break-glass principal ARNs must be explicit ARNs without wildcards."
  }
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
