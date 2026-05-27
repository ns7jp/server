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

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
