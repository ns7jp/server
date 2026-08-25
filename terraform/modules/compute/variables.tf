variable "name" {
  description = "リソース名の接頭辞。"
  type        = string
}

variable "vpc_id" {
  description = "EC2 を起動する VPC ID。"
  type        = string
}

variable "private_subnet_ids" {
  description = "AZ をキーにしたプライベートサブネット ID マップ。EC2 はここに配置する。"
  type        = map(string)
}

variable "azs" {
  description = "EC2 を配置する AZ のリスト。private_subnet_ids にキーが存在すること。"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 インスタンスタイプ。t3.small / t3.medium など。"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "ルート EBS のサイズ（GiB）。"
  type        = number
  default     = 30
}

variable "alb_security_group_id" {
  description = "ALB の SG ID。EC2 への 8080 を ALB SG からのみ許可する。"
  type        = string
}

variable "ssh_ingress_cidrs" {
  description = "緊急時の SSH 接続を許可する CIDR。空リストにすると SSH を一切開けない（SSM Session Manager のみ）。"
  type        = list(string)
  default     = []
}

variable "ec2_application_port" {
  description = "EC2 上で待ち受けるアプリポート。compose の Nginx が 8080 を expose することを想定。"
  type        = number
  default     = 8080
}

variable "additional_iam_policy_arns" {
  description = "EC2 インスタンスプロファイルに追加でアタッチする IAM ポリシー ARN。"
  type        = list(string)
  default     = []
}

variable "schedule_stop_enabled" {
  description = "EventBridge による夜間停止 / 朝起動スケジュールを有効化する。"
  type        = bool
  default     = false
}

variable "schedule_stop_cron" {
  description = "EC2 停止の cron 式 (UTC)。既定は 13:00 UTC = 22:00 JST。"
  type        = string
  default     = "cron(0 13 ? * MON-FRI *)"
}

variable "schedule_start_cron" {
  description = "EC2 起動の cron 式 (UTC)。既定は 22:00 UTC = 07:00 JST。"
  type        = string
  default     = "cron(0 22 ? * MON-FRI *)"
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}

# amazon.aws.aws_ssm connection plugin が使う S3 バケット名。
# 空のままだと SSM 経由の Ansible 適用ができない（AccessDenied）。
# ssh_ingress_cidrs を空にして SSM だけで運用する環境では必ず指定する。
variable "ssm_file_transfer_bucket" {
  description = "S3 bucket used by the amazon.aws.aws_ssm connection plugin for file transfer. Empty disables the grant."
  type        = string
  default     = ""
}

variable "ssm_file_transfer_kms_key_arn" {
  description = "KMS key ARN protecting the SSM file transfer bucket, if it is SSE-KMS encrypted."
  type        = string
  default     = ""
}
