variable "name" {
  description = "リソース名の接頭辞（タグ用）。"
  type        = string
}

variable "canary_name" {
  description = "CloudWatch Synthetics canary名。AWSの上限（21文字、英小文字/数字/ハイフン/アンダースコア）に収める。"
  type        = string

  validation {
    condition     = length(var.canary_name) <= 21 && can(regex("^[a-z0-9_-]+$", var.canary_name))
    error_message = "canary_name must be 21 characters or fewer and match ^[a-z0-9_-]+$ (AWS Synthetics naming limit)."
  }
}

variable "target_url" {
  description = "外部から probe する対象 URL（例: ALB経由の /healthz）。"
  type        = string

  validation {
    condition     = startswith(var.target_url, "https://") || startswith(var.target_url, "http://")
    error_message = "target_url must start with http:// or https://."
  }
}

variable "schedule_expression" {
  description = "Canary実行間隔。rate() または cron() 式。"
  type        = string
  default     = "rate(1 minute)"
}

variable "runtime_version" {
  description = "Synthetics runtime version。apply前に `aws synthetics describe-runtime-versions` で現行サポート版を確認する（AWSが定期的に旧versionを廃止するため）。"
  type        = string
  default     = "syn-nodejs-puppeteer-9.1"
}

variable "start_canary" {
  description = "作成直後にcanaryの実行を開始するか。falseだとRUNNING状態にせず作成のみ行う。"
  type        = bool
  default     = true
}

variable "artifact_retention_days" {
  description = "Canary成果物（S3 screenshot / HAR / run履歴）の保持日数。"
  type        = number
  default     = 31
}

variable "alarm_evaluation_periods" {
  description = "失敗とみなすまでの連続評価回数。scheduleと合わせて通知までの時間を決める（既定: 1分間隔 x 1回 = 最短1〜2分で通知）。"
  type        = number
  default     = 1
}

variable "alarm_sns_topic_arn" {
  description = "Alarm通知先のSNS topic ARN。空だと通知アクションを設定しない。"
  type        = string
  default     = ""
}

variable "force_destroy" {
  description = "短時間の非本番環境でartifacts bucketもdestroyするか。prodではfalseのまま使う。"
  type        = bool
  default     = false
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
