locals {
  common_tags = {
    Project     = "server-monitor"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "../../modules/network"

  name               = var.name_prefix
  cidr_block         = var.vpc_cidr
  azs                = var.azs
  enable_nat_gateway = true
  # コスト優先で単一 AZ NAT。学習目的なので冗長性を犠牲にする。
  # 完全冗長化が必要になったら false にする。
  single_nat_gateway = true
  tags               = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  name                  = var.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_id_list
  target_port           = 8080
  certificate_arn       = var.certificate_arn
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
  tags                  = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  name                  = var.name_prefix
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  azs                   = var.azs
  instance_type         = var.instance_type
  alb_security_group_id = module.alb.alb_security_group_id
  ssh_ingress_cidrs     = var.ssh_ingress_cidrs
  # prod は 24h 稼働
  schedule_stop_enabled = false
  tags                  = merge(local.common_tags, { AlbHealthCheckSourceCidr = var.vpc_cidr })
}

# ALB と Compute の循環依存を避けるため、Target Group attachment は環境側で配線する。
resource "aws_lb_target_group_attachment" "this" {
  for_each = module.compute.instance_ids

  target_group_arn = module.alb.target_group_arn
  target_id        = each.value
  port             = 8080
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                     = var.name_prefix
  instance_ids             = module.compute.instance_ids
  target_group_arn         = module.alb.target_group_arn
  load_balancer_arn_suffix = split("loadbalancer/", module.alb.alb_arn)[1]
  target_group_arn_suffix  = module.alb.target_group_arn_suffix
  alarm_emails             = var.alarm_emails
  monthly_budget_jpy       = var.monthly_budget_jpy
  enable_guardduty         = true
  enable_cloudtrail        = true
  tags                     = local.common_tags
}

module "backup" {
  source = "../../modules/backup"

  name                                 = var.name_prefix
  instance_arns                        = module.compute.instance_arns
  backup_retention_days                = 180
  cold_storage_after_days              = 90
  archive_bucket_lifecycle_days        = 365
  recovery_point_delete_principal_arns = var.backup_admin_principal_arns
  tags                                 = local.common_tags
}
