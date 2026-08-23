variable "region" {
  description = "AWS リージョン。"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境名。"
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "リソース名の接頭辞。"
  type        = string
  default     = "server-monitor-prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR。"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "利用する AZ。prod は 2 AZ。"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "instance_type" {
  description = "EC2 インスタンスタイプ。"
  type        = string
  default     = "t3.small"
}

variable "certificate_arn" {
  description = "ALB に使う ACM 証明書 ARN。prod は必須。"
  type        = string
  validation {
    condition     = length(var.certificate_arn) > 0
    error_message = "prod 環境では ALB に HTTPS を強制するため certificate_arn を必須とする。"
  }
}

variable "alarm_emails" {
  description = "アラート通知先メール。"
  type        = list(string)
  validation {
    condition     = length(var.alarm_emails) >= 1
    error_message = "prod では通知先メールを 1 件以上指定する。"
  }
}

variable "monthly_budget_jpy" {
  description = "24h 稼働の設計試算を踏まえた AWS Budgets 通知閾値（円）。"
  type        = number
  default     = 15000
}

variable "ssh_ingress_cidrs" {
  description = "緊急 SSH を許可する CIDR。原則 SSM のみで空。"
  type        = list(string)
  default     = []
}

variable "allowed_ingress_cidrs" {
  description = "ALB の HTTPS を許可する CIDR。"
  type        = list(string)
  validation {
    condition = (
      length(var.allowed_ingress_cidrs) >= 1
      && !contains(var.allowed_ingress_cidrs, "0.0.0.0/0")
    )
    error_message = "prod では allowed_ingress_cidrs を 1 件以上指定し、フルオープン (0.0.0.0/0) を避ける。"
  }
}

variable "backup_admin_principal_arns" {
  description = "AWS Backup保護変更を許可する実在break-glass/deploy role ARN。以後のTerraform更新は列挙roleをassumeする。"
  type        = list(string)
}
