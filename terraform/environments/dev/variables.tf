variable "region" {
  description = "AWS リージョン。"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境名（dev / prod）。"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "リソース名の接頭辞。"
  type        = string
  default     = "server-monitor-dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR。"
  type        = string
  default     = "10.10.0.0/16"
}

variable "azs" {
  description = "利用する Availability Zone。dev は単一 AZ。"
  type        = list(string)
  default     = ["ap-northeast-1a"]
}

variable "instance_type" {
  description = "EC2 インスタンスタイプ。"
  type        = string
  default     = "t3.small"
}

variable "certificate_arn" {
  description = "ALB に使う ACM 証明書 ARN。dev では未設定（HTTP のみ）でも動く。"
  type        = string
  default     = ""
}

variable "alarm_emails" {
  description = "アラート通知先メール。"
  type        = list(string)
  default     = []
}

variable "monthly_budget_jpy" {
  description = "短時間検証の削除忘れを検知する AWS Budgets 警戒値（円）。常時稼働の月額見積ではない。"
  type        = number
  default     = 3000
}

variable "ssh_ingress_cidrs" {
  description = "緊急 SSH を許可する CIDR。空で SSM のみ。"
  type        = list(string)
  default     = []
}

variable "allowed_ingress_cidrs" {
  description = "ALB の HTTPS を許可する CIDR。"
  type        = list(string)
  default     = []
}
