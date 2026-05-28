# AWS コスト計画と実測記録

このリポジトリの通常の学習・デモ環境はローカル Docker Compose であり、AWS の
継続課金は発生しない。Terraform 構成を AWS で検証する場合は、短時間の
`apply` / 確認 / `destroy` を前提にし、実費は検証後に記録する。

## 設計上の訂正

現行 Terraform は dev / prod ともに NAT Gateway と ALB を作成する。そのため、
dev を 1 か月常時稼働させて **1,500 円 / 月** とする旧想定は成立しない。
NAT Gateway と ALB だけで概算 **約 7,000 円 / 月** となり、EC2、EBS、ログ、
バックアップ等はその上に加算される。

`monthly_budget_jpy` は月額見積の宣言ではなく、意図しない継続起動を早く検知する
警戒値として扱う。低予算で常時稼働する設計に変更する場合は、NAT / ALB を除く
別アーキテクチャを設計してから Terraform を変更する。

## 試算（東京リージョン、24h 稼働ベース）

| リソース | 仕様 | prod 想定月額（円） |
| --- | --- | --- |
| EC2 t3.small x 2 | オンデマンド | 約 4,000 |
| EBS gp3 30GB x 2 | スナップショット込み | 約 720 |
| ALB | 1 LCU 想定 | 約 2,500 |
| NAT Gateway x 1 | 単一 AZ、データ転送 5GB | 約 4,500 |
| S3（ALB access log、CloudTrail、archive） | 合計 10GB | 約 40 |
| CloudWatch Logs | 5GB / 30d 保持 | 約 200 |
| KMS | 5 鍵 + リクエスト | 約 250 |
| AWS Backup | 月 30GB | 約 400 |
| GuardDuty | 無料枠終了後 | 約 250 |
| Data Transfer (out) | 5GB | 約 80 |
| **prod 合計 (24h)** | | **約 12,940** |

dev は EC2 が 1 台で夜間停止される一方、NAT Gateway と ALB は存在し続ける。
従って常時作成したままの dev 月額は **少なくとも約 7,000 円** であり、正確な値は
実際の適用期間を Cost Explorer で計測する。

## 運用する予算閾値

| 環境 | `monthly_budget_jpy` | 意味 |
| --- | ---: | --- |
| dev | 3,000 | 短時間検証で削除忘れを検知する警戒値。常時稼働見積ではない |
| prod | 15,000 | 24h 稼働の概算 12,940 円を踏まえた通知閾値 |

`terraform/modules/monitoring/main.tf` は 80% の Actual 通知と 100% の Forecasted
通知を作成する。換算レートは `jpy_per_usd`（既定 150）で調整する。

## 短時間検証の手順

1. `terraform plan` で作成対象と budget 値をレビューする。
2. `terraform apply` 実行時刻を `docs/evidence/YYYY-MM-DD-aws-validation.md` に記録する。
3. 疎通、CloudWatch alarm、AWS Backup 対象を確認する。
4. 検証後直ちに `terraform destroy` を実行する。
5. Cost Explorer に反映された期間費用と削除確認を同じ証跡へ追記する。

## 実測記録

AWS 上での `apply` / `destroy` および Cost Explorer 実測は、現時点ではまだ
リポジトリに証跡がない。実行した値のみを次表と
[検証証跡台帳](evidence/README.md) に記録する。

| 年月 | 環境 | 作成時間 | 実費（円） | 証跡 |
| --- | --- | ---: | ---: | --- |
| - | - | - | 未測定 | 未実施 |

## 削除手順

```bash
cd terraform/environments/dev
terraform destroy -var-file=terraform.tfvars
cd ../prod
terraform destroy -var-file=terraform.tfvars
```

KMS key、AWS Backup recovery point など、削除が遅延するリソースがある。課金停止は
`destroy` の成功だけで断定せず、翌日以降の Cost Explorer と残存リソース一覧で確認する。
