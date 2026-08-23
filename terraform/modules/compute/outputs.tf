output "instance_ids" {
  description = "AZ をキーにした EC2 インスタンス ID マップ。"
  value       = { for k, i in aws_instance.this : k => i.id }
}

output "instance_arns" {
  description = "EC2 ARN のリスト。AWS Backup / CloudWatch Alarm から参照する。"
  value       = [for i in aws_instance.this : i.arn]
}

output "private_ips" {
  description = "AZ をキーにした EC2 プライベート IP マップ。Ansible inventory で利用する。"
  value       = { for k, i in aws_instance.this : k => i.private_ip }
}

output "security_group_id" {
  description = "EC2 の Security Group ID。"
  value       = aws_security_group.instance.id
}

output "iam_role_arn" {
  description = "EC2 にアタッチされた IAM ロールの ARN。"
  value       = aws_iam_role.instance.arn
}

output "iam_role_name" {
  description = "EC2 にアタッチされた IAM ロール名。"
  value       = aws_iam_role.instance.name
}

output "instance_profile_name" {
  description = "EC2 にアタッチされた IAM instance profile 名。AWS Backup restore metadata で利用する。"
  value       = aws_iam_instance_profile.this.name
}

output "ebs_kms_key_arn" {
  description = "EBS 暗号化用の KMS キー ARN。AWS Backup から参照する。"
  value       = aws_kms_key.ebs.arn
}
