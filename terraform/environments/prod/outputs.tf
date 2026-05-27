output "alb_dns_name" {
  description = "ALB の DNS 名。Route 53 で Alias レコードを設定する。"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB の Route 53 zone ID。"
  value       = module.alb.alb_zone_id
}

output "vpc_id" {
  description = "VPC ID。"
  value       = module.network.vpc_id
}

output "ec2_instance_ids" {
  description = "EC2 インスタンス ID マップ。"
  value       = module.compute.instance_ids
}

output "ec2_private_ips" {
  description = "EC2 のプライベート IP マップ。"
  value       = module.compute.private_ips
}

output "sns_topic_arn" {
  description = "アラート SNS トピック ARN。"
  value       = module.monitoring.sns_topic_arn
}

output "backup_vault_name" {
  description = "AWS Backup Vault 名。"
  value       = module.backup.vault_name
}
