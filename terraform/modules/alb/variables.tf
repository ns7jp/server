variable "name" {
  description = "リソース名の接頭辞。"
  type        = string
}

variable "vpc_id" {
  description = "ALB を配置する VPC ID。"
  type        = string
}

variable "public_subnet_ids" {
  description = "ALB を配置するパブリックサブネット ID のリスト（2 個以上）。"
  type        = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB は最低 2 個のサブネットを必要とする。"
  }
}

variable "target_port" {
  description = "EC2 上で受け付けるアプリポート。compute モジュールの ec2_application_port と一致させる。"
  type        = number
  default     = 8080
}

variable "allowed_ingress_cidrs" {
  description = "HTTPS 443 を許可する CIDR。社内 NAT などに限定すると望ましい。"
  type        = list(string)
  default     = []
}

variable "certificate_arn" {
  description = "ALB Listener に使う ACM 証明書 ARN。未指定の場合は HTTPS リスナーを作らない（開発用 HTTP のみ）。"
  type        = string
  default     = ""
}

variable "access_log_retention_days" {
  description = "ALB アクセスログ S3 のライフサイクル日数。"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "短時間の非本番環境でALB log bucket内のobjectもdestroyするか。prodではfalseのまま使う。"
  type        = bool
  default     = false
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
