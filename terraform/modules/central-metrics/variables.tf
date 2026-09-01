variable "name" {
  description = "リソース名の接頭辞。"
  type        = string
}

variable "tags" {
  description = "全リソースに付与する共通タグ。"
  type        = map(string)
  default     = {}
}
