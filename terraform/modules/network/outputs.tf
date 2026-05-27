output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR ブロック。"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "AZ をキーにしたパブリックサブネット ID マップ。"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "AZ をキーにしたプライベートサブネット ID マップ。"
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "public_subnet_id_list" {
  description = "ALB など複数 AZ にまたがるリソース用にリスト形式で返す。"
  value       = [for k in var.azs : aws_subnet.public[k].id]
}

output "private_subnet_id_list" {
  description = "プライベートサブネット ID のリスト。"
  value       = [for k in var.azs : aws_subnet.private[k].id]
}

output "internet_gateway_id" {
  description = "IGW ID。"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "NAT GW の ID（複数 / 単一）。"
  value       = { for k, n in aws_nat_gateway.this : k => n.id }
}

output "flow_log_group_arn" {
  description = "VPC Flow Logs を保存している CloudWatch Logs Group の ARN。"
  value       = aws_cloudwatch_log_group.flow_logs.arn
}
