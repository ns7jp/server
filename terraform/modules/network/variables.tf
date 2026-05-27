variable "name" {
  description = "リソース名の接頭辞。環境名（dev / prod）などを含める。"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR。10.0.0.0/16 など /16 を想定。"
  type        = string
}

variable "azs" {
  description = "サブネットを配置する Availability Zone のリスト。"
  type        = list(string)
  validation {
    condition     = length(var.azs) >= 1 && length(var.azs) <= 4
    error_message = "azs は 1〜4 個の AZ を指定する。"
  }
}

variable "enable_nat_gateway" {
  description = "プライベートサブネットからの egress に NAT GW を作成するか。学習目的では false にしてコスト削減できる。"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "NAT GW を 1 個だけ作成する（コスト優先 / 冗長性なし）。false で AZ ごとに作成する。"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "VPC Flow Logs を保存する CloudWatch Logs のリテンション日数。"
  type        = number
  default     = 30
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
