output "alb_dns_name" {
  description = "ALB の DNS 名。"
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID。"
  value       = module.network.vpc_id
}

output "ec2_instance_ids" {
  description = "EC2 インスタンス ID マップ（Ansible inventory 用）。"
  value       = module.compute.instance_ids
}

output "ec2_private_ips" {
  description = "EC2 のプライベート IP マップ。"
  value       = module.compute.private_ips
}

output "private_subnet_ids" {
  description = "AZをキーにしたprivate subnet ID。復元先を明示するときに利用する。"
  value       = module.network.private_subnet_ids
}

output "ec2_security_group_id" {
  description = "EC2用Security Group ID。"
  value       = module.compute.security_group_id
}

output "ec2_instance_profile_name" {
  description = "EC2用IAM instance profile名。"
  value       = module.compute.instance_profile_name
}

output "target_group_arn" {
  description = "ALB Target Group ARN。"
  value       = module.alb.target_group_arn
}

output "alb_healthz_url" {
  description = "現在のlistener方式に対応するALB health endpoint。"
  value       = format("%s://%s/healthz", var.certificate_arn != "" ? "https" : "http", module.alb.alb_dns_name)
}

output "sns_topic_arn" {
  description = "アラート SNS トピック ARN。"
  value       = module.monitoring.sns_topic_arn
}

output "backup_vault_name" {
  description = "AWS Backup Vault 名。"
  value       = module.backup.vault_name
}

output "backup_role_arn" {
  description = "AWS Backupがrestoreに利用するIAM role ARN。"
  value       = module.backup.backup_role_arn
}
