output "alb_dns_name" {
  description = "ALB DNS name."
  value       = module.alb.alb_dns_name
}

output "alb_healthz_url" {
  description = "ALB health endpoint matching the configured listener."
  value       = format("%s://%s/healthz", var.certificate_arn != "" ? "https" : "http", module.alb.alb_dns_name)
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR used to restrict the restored host UFW rule for ALB traffic."
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by Availability Zone."
  value       = module.network.private_subnet_ids
}

output "ec2_instance_ids" {
  description = "EC2 instance IDs keyed by Availability Zone."
  value       = module.compute.instance_ids
}

output "ec2_private_ips" {
  description = "EC2 private IP addresses keyed by Availability Zone."
  value       = module.compute.private_ips
}

output "ec2_security_group_id" {
  description = "EC2 Security Group ID used in restore metadata."
  value       = module.compute.security_group_id
}

output "ec2_instance_profile_name" {
  description = "EC2 IAM instance profile name used in restore metadata."
  value       = module.compute.instance_profile_name
}

output "target_group_arn" {
  description = "ALB Target Group ARN."
  value       = module.alb.target_group_arn
}

output "sns_topic_arn" {
  description = "SNS alert topic ARN."
  value       = module.monitoring.sns_topic_arn
}

output "backup_vault_name" {
  description = "AWS Backup Vault name."
  value       = module.backup.vault_name
}

output "backup_plan_id" {
  description = "Staging daily AWS Backup plan ID used to prove scheduled-RPO provenance."
  value       = module.backup.plan_id
}

output "backup_role_arn" {
  description = "AWS Backup service role ARN used for restore jobs."
  value       = module.backup.backup_role_arn
}

output "ssm_transfer_bucket_name" {
  description = "Same-region, short-lived S3 bucket used by amazon.aws.aws_ssm."
  value       = aws_s3_bucket.ssm_transfer.id
}

output "ssm_transfer_controller_policy_arn" {
  description = "Least-privilege policy for the approved Ansible SSM controller role."
  value       = aws_iam_policy.ssm_transfer_controller.arn
}
