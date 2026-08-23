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
    ├── dev/             # ALB用2 AZ・EC2 1台（account-wide GuardDuty / CloudTrailは作らない）
    ├── staging/         # D-2専用・ALB用2 AZ・EC2 1台（GuardDuty / CloudTrailは作らない）
    └── prod/            # マルチ AZ・EC2 2 台・Budgets 15,000 円
```

同じAWS account / regionで複数environmentを使う場合、GuardDuty detectorは1個だけです。
この構成では長期利用するprod rootだけがGuardDuty / account-wide CloudTrailを所有し、devと
短時間stagingは重複作成しません。environmentを別accountへ分離する場合は、account baselineを
別stateで1回だけ管理する設計へ移します。

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
経由（または承認済みの管理経路）で`ansible-playbook -i ... site.yml`
を実行する。Ansible 側は`ansible/inventory/aws_ec2.yml.example`を
`ansible/inventory/aws_ec2.yml`へコピーし、Environmentを対象環境へ限定してから
SSM用bucketなどの実値をGit管理外で設定する。D-2 stagingは、versioning無効・1日expire・
SSE-S3・public blockを持つ専用transfer bucketとcontroller用最小権限policyを作成し、outputする。
既存controller roleへ自動attachする場合だけ`ssm_controller_role_name`を指定する。

Backup selectionはenvironmentごとの明示的なEC2 ARNだけを対象とし、広いApplication tagとのunionを
作らない。dev/prodのVault policyはrecovery pointの直接削除・lifecycle短縮・policy除去を拒否し、
自動retentionを行うAWS Backup roleと、tfvarsで指定した実在break-glass principalだけを例外にする。
Vault policy更新時もbreak-glass principalを利用する。stagingは承認済みdestroyを可能にするためこの
保護を無効化する。初回apply後のdev/prod Terraform更新・destroyは、tfvarsへ列挙した実在
break-glass/deploy roleを必ずassumeして実行する。通常deploy roleを列挙せずに適用すると自己ロックする。

## 検証

- `terraform fmt -recursive -check`
- `terraform init -backend=false && terraform validate`（環境ごと）
- `tfsec` / `checkov`：High 以上 0 件
- CI（`.github/workflows/terraform-check.yml`）で上記を毎回実行する

## コスト

この構成は NAT Gateway と ALB を含むため、dev であっても常時作成した場合の
月額は **少なくとも約 7,000 円** となる。dev の 3,000 円は短時間検証で削除忘れを
検知する警戒値であり、月額見積ではない。実 AWS での適用・費用の証跡は未収録である。
詳細試算と記録ルールは [docs/cost-report.md](../docs/cost-report.md) および
[docs/evidence/README.md](../docs/evidence/README.md) を参照。
