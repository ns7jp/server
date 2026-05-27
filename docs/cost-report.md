# AWS コスト計画と実測記録

設計目標：**月額 3,000 円以内**（学習目的）。AWS Budgets で 80% / 100% / 120% の閾値で
通知し、想定外の課金が出た日に必ず気づける運用にする。

## 試算（東京リージョン、24h 稼働ベース）

| リソース | 仕様 | 想定月額（円） |
| --- | --- | --- |
| EC2 t3.small × 2 (prod 想定) | オンデマンド | 約 4,000 |
| EBS gp3 30GB × 2 | スナップショット込み | 約 720 |
| ALB | 1 LCU 想定 | 約 2,500 |
| NAT Gateway × 1 | 単一 AZ、データ転送 5GB | 約 4,500 |
| S3（ALB アクセスログ、CloudTrail、archive） | 合計 10GB | 約 40 |
| CloudWatch Logs（VPC Flow Logs、CloudTrail）| 5GB / 30d 保持 | 約 200 |
| KMS（5 鍵 + リクエスト） | | 約 250 |
| AWS Backup | 月 30GB | 約 400 |
| GuardDuty | 無料枠 30 日後 | 約 250 |
| Data Transfer (out) | 5 GB | 約 80 |
| **prod 合計 (24h)** | | **約 12,940** |

## コスト削減

| 手段 | 月額削減 |
| --- | --- |
| dev: EC2 を EventBridge Scheduler で平日のみ 7:00–22:00 JST | EC2 / EBS の稼働時間 65% 削減 → 約 1,600 円 |
| dev: 単一 AZ、EC2 × 1 | NAT も 1 つ、ALB は 1 LCU 未満で約 2,500 円のままだが、Compute は半分 |
| 単一 AZ NAT | NAT × 2 を回避（節約 約 4,500 円） |
| GuardDuty を 30 日試用で停止する場合 | 約 250 円 |

**dev 環境の想定月額：1,500 円 / 月**（平日のみ稼働 + EC2 × 1 + 単一 AZ）

**prod 環境を 24h で動かした場合：約 13,000 円 / 月** → 学習用途では起動時のみ apply、
完了後に `terraform destroy`、または「毎週金曜の `terraform destroy`」運用ルールで実費を抑える。

## AWS Budgets 通知

`terraform/modules/monitoring/main.tf` で次の閾値を設定済み。

| 閾値 | 種別 | 動作 |
| --- | --- | --- |
| 80% (Actual) | 実費 | `alarm_emails` と SNS にメール |
| 100% (Forecasted) | 予測 | 月末予測超過時に通知 |

`monthly_budget_jpy` を環境別に変更する：

| 環境 | 既定 (円) |
| --- | --- |
| dev | 1,500 |
| prod | 5,000 |

USD 換算レートは `jpy_per_usd`（既定 150）で調整できる。

## 実測記録

実測値は `terraform apply` 後に Cost Explorer から月次で記録する。

| 年月 | dev 実費 (円) | prod 実費 (円) | コメント |
| --- | --- | --- | --- |
| YYYY-MM | (未測定) | (未測定) | 初回 apply 後に記入 |

## 削除手順（学習が一段落したら）

```bash
cd terraform/environments/dev
terraform destroy -var-file=terraform.tfvars
cd ../prod
terraform destroy -var-file=terraform.tfvars
```

KMS キー、AWS Backup recovery point など、削除が遅延するリソースがある点に注意。
完全に課金停止していることを Cost Explorer の翌日確認で検証する。
