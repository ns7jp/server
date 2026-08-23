output "alb_arn" {
  description = "ALB ARN。"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB の DNS 名。Route 53 で CNAME / Alias を貼る。"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB の Route 53 zone ID。Alias レコードに使う。"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "ALB の Security Group ID。EC2 側で referenced_security_group_id に渡す。"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target Group ARN。"
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "CloudWatch ApplicationELB dimension用のtargetgroup/name/hash。"
  value       = aws_lb_target_group.app.arn_suffix
}

output "access_logs_bucket" {
  description = "ALB アクセスログを保存している S3 バケット名。"
  value       = aws_s3_bucket.access_logs.id
}
