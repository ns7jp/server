# Server Monitor on AWS (Terraform)

`server-monitor` を AWS 上で再構築する Terraform 構成。設計の根拠は
[docs/aws-architecture.md](../docs/aws-architecture.md)、コスト計画は
[docs/cost-report.md](../docs/cost-report.md) を参照する。

## ディレクトリ

```text
terraform/
├── versions.tf          # provider / Terraform バージョンピン
├── modules/
│   ├── network/         # VPC / Subnet / IGW / NAT / Route / VPC Flow Logs
│   ├── compute/         # EC2 (IMDSv2 強制) / IAM / EBS / SG
│   ├── alb/             # ALB / Target Group / Listener / ACM / Access Log
│   ├── monitoring/      # CloudWatch Alarms / SNS / CloudTrail / GuardDuty / Budgets
│   └── backup/          # AWS Backup vault / plan / S3 archive
└── environments/
    ├── dev/             # 単一 AZ・EC2 1 台・Budgets 1,500 円
    └── prod/            # マルチ AZ・EC2 2 台・Budgets 5,000 円
```

すべて Tokyo (`ap-northeast-1`) を既定とする。

## State 管理

`backend.tf` は環境ごとに `key` を分けて S3 にリモート保存し、DynamoDB
テーブルでロックを取る。S3 バケットと DynamoDB テーブルは Terraform の
管理対象外（先に手動 / 別 stack で作る）として扱う。

```bash
# 例: dev 環境
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

`backend.hcl` と `terraform.tfvars` は `.example` を雛形にして実値を入れる。
実値は git に含めない（`.gitignore` で `*.tfvars`、`backend.hcl` を除外）。

## EC2 への Ansible 適用

Terraform で作成された EC2 のプライベート IP に対し、SSM Session Manager
経由（または bastion 経由）で SSH し、`ansible-playbook -i ... site.yml`
を実行する。Ansible 側は `ansible/inventory/aws.yml.example` を参照。

## 検証

- `terraform fmt -recursive -check`
- `terraform init -backend=false && terraform validate`（環境ごと）
- `tfsec` / `checkov`：High 以上 0 件
- CI（`.github/workflows/terraform-check.yml`）で上記を毎回実行する

## コスト

設計上の月額目標は **3,000 円以内**。NAT Gateway は単一 AZ、EC2 は
EventBridge スケジュールで夜間停止する設計で実現する。詳細試算は
[docs/cost-report.md](../docs/cost-report.md) を参照。
