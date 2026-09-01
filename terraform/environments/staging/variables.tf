variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name. D-2 uses an isolated staging environment."
  type        = string
  default     = "staging"

  validation {
    condition     = var.environment == "staging"
    error_message = "This root module is reserved for the staging environment."
  }
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "server-monitor-staging"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.15.0.0/16"
}

variable "azs" {
  description = "Network / ALB Availability Zones. ALB requires two Availability Zones."
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "compute_azs" {
  description = "EC2 Availability Zones. Staging uses one instance to limit drill cost."
  type        = list(string)
  default     = ["ap-northeast-1a"]
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.small"
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN. Empty uses HTTP for short-lived staging validation."
  type        = string
  default     = ""
}

variable "alarm_emails" {
  description = "Alarm notification email addresses."
  type        = list(string)

  validation {
    condition     = length(var.alarm_emails) >= 1
    error_message = "Staging requires at least one monitored alarm email address."
  }
}

variable "monthly_budget_jpy" {
  description = "Guardrail for a short-lived staging drill; not a monthly estimate."
  type        = number
  default     = 3000
}

variable "ssh_ingress_cidrs" {
  description = "Emergency SSH CIDRs. Keep empty when using SSM Session Manager."
  type        = list(string)
  default     = []
}

variable "ssm_controller_role_name" {
  description = "Optional existing IAM role to attach the generated least-privilege Ansible SSM transfer policy to."
  type        = string
  default     = ""
}

variable "enable_central_observability" {
  description = "外部probe（CloudWatch Synthetics）とmetrics中央化（AMP）を有効化する。設計: docs/roadmap/external-probe-central-telemetry.md。追加コストが発生するため既定はfalse。"
  type        = bool
  default     = false
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the staging ALB."
  type        = list(string)

  validation {
    condition = (
      length(var.allowed_ingress_cidrs) >= 1
      && !contains(var.allowed_ingress_cidrs, "0.0.0.0/0")
    )
    error_message = "Staging requires an explicit restricted CIDR and rejects 0.0.0.0/0."
  }
}
