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
  description = "network / ALBが利用するAvailability Zone。ALB要件のため2 AZを指定する。"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "compute_azs" {
  description = "EC2を配置するAvailability Zone。devは費用を抑えるため1 AZ。azsの部分集合にする。"
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
  description = "ALBの有効listener（dev既定はHTTP）を許可するCIDR。"
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_ingress_cidrs, "0.0.0.0/0")
    error_message = "devのALBは0.0.0.0/0を許可しない。承認済みの管理CIDRへ限定する。"
  }
}

variable "backup_admin_principal_arns" {
  description = "AWS Backup保護変更を許可する実在break-glass/deploy role ARN。以後のTerraform更新は列挙roleをassumeする。"
  type        = list(string)
}
