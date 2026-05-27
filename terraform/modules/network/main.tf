locals {
  name = var.name
  tags = merge(var.tags, { Module = "network" })
}

# ----------------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

# 既定 SG を完全に閉じる（tfsec aws-vpc-no-default-vpc 緩和、default-sg-with-rules 対策）
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-default-sg-locked" })
}

# ----------------------------------------------------------------------------
# Subnets
# ----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, 8, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = false # ALB 等が EIP / 自前のパブリック IP を持つ。EC2 にはアタッチしない

  tags = merge(local.tags, {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = { for i, az in var.azs : az => i }

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, each.value + 100)
  availability_zone = each.key

  tags = merge(local.tags, {
    Name = "${local.name}-private-${each.key}"
    Tier = "private"
  })
}

# ----------------------------------------------------------------------------
# Internet Gateway / NAT Gateway
# ----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-igw" })
}

locals {
  nat_subnet_keys = var.enable_nat_gateway ? (
    var.single_nat_gateway ? [keys(aws_subnet.public)[0]] : keys(aws_subnet.public)
  ) : []
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_subnet_keys)

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name}-nat-eip-${each.value}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_subnet_keys)

  allocation_id = aws_eip.nat[each.value].id
  subnet_id     = aws_subnet.public[each.value].id

  tags = merge(local.tags, { Name = "${local.name}-nat-${each.value}" })

  depends_on = [aws_internet_gateway.this]
}

# ----------------------------------------------------------------------------
# Route Tables
# ----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# プライベート RT は AZ ごとに作るが、NAT が single_nat_gateway = true の場合は
# 同じ NAT を指す。
resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-private-rt-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? aws_route_table.private : {}

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.single_nat_gateway ? (
    aws_nat_gateway.this[local.nat_subnet_keys[0]].id
    ) : (
    aws_nat_gateway.this[each.key].id
  )
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# ----------------------------------------------------------------------------
# VPC Flow Logs (tfsec aws-vpc-no-flow-logs)
# ----------------------------------------------------------------------------
resource "aws_kms_key" "flow_logs" {
  description             = "${local.name} VPC flow logs encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRoot"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })

  tags = merge(local.tags, { Name = "${local.name}-flow-logs-kms" })
}

resource "aws_kms_alias" "flow_logs" {
  name          = "alias/${local.name}-flow-logs"
  target_key_id = aws_kms_key.flow_logs.key_id
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${local.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = aws_kms_key.flow_logs.arn

  tags = merge(local.tags, { Name = "${local.name}-flow-logs" })
}

resource "aws_iam_role" "flow_logs" {
  name = "${local.name}-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# VPC Flow Logs の配送先 log streams は動的生成のため、log group 配下を wildcard で許可する。
# Resource は VPC 専用 log group の ARN に限定済みで、横断アクセスはできない。
#tfsec:ignore:aws-iam-no-policy-wildcards
resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.name}-flow-logs"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-flow-log" })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
