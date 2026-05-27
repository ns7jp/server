variable "name" {
  description = "リソース名の接頭辞。"
  type        = string
}

variable "instance_ids" {
  description = "監視対象 EC2 のインスタンス ID マップ。"
  type        = map(string)
}

variable "target_group_arn" {
  description = "ALB Target Group の ARN。Unhealthy ホスト監視に使う。"
  type        = string
}

variable "load_balancer_arn_suffix" {
  description = "ALB ARN suffix。CloudWatch メトリクスのディメンションに使う。"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target Group ARN suffix。CloudWatch メトリクスのディメンションに使う。"
  type        = string
}

variable "alarm_emails" {
  description = "アラート通知先メールアドレス。"
  type        = list(string)
  default     = []
}

variable "enable_guardduty" {
  description = "GuardDuty を有効化する。"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "CloudTrail（全リージョン）を有効化する。"
  type        = bool
  default     = true
}

variable "monthly_budget_jpy" {
  description = "AWS Budgets の月額アラート閾値（円換算）。USD に変換して使う。"
  type        = number
  default     = 3000
}

variable "jpy_per_usd" {
  description = "Budgets を USD で設定するための日本円換算レート。"
  type        = number
  default     = 150
}

variable "log_retention_days" {
  description = "CloudWatch / CloudTrail ログのリテンション日数。"
  type        = number
  default     = 90
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
