# AWS staging短時間検証記録テンプレート

> 初期状態: **NOT RUN**。実ログが揃うまでPASSへ変更しない。
> `terraform/environments/staging`専用で、dev/prodへ適用しない。

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象commit | `40-character-sha` |
| AWS account / region | `masked-account` / `ap-northeast-1` |
| 実行者 / 承認者 | name / name |
| Terraform / AWS CLI | `terraform version` / `aws --version` |
| 管理CIDR / 通知先確認 | masked / confirmed or NOT RUN |
| 予定上限 / 終了予定 | JPY / YYYY-MM-DD HH:MM JST |

## Go / No-Go

- [ ] staging専用backendとtfvarsを使用
- [ ] caller identity、対象tag、管理CIDR、通知先を相互確認
- [ ] Ansible Vault、SSM transfer bucket、controller IAM、source SSMをpreflight
- [ ] D-2なら中断scriptを確認し、利用可能なrecovery pointを確保
- [ ] apply / drill / destroyの承認者と中断条件を記録

## plan / apply

```bash
TF_ENV_DIR=terraform/environments/staging
terraform -chdir="$TF_ENV_DIR" init -backend-config=backend.hcl
terraform -chdir="$TF_ENV_DIR" fmt -check
terraform -chdir="$TF_ENV_DIR" validate
terraform -chdir="$TF_ENV_DIR" plan -var-file=terraform.tfvars -out=apply.tfplan
terraform -chdir="$TF_ENV_DIR" show apply.tfplan
# 承認後のみ
terraform -chdir="$TF_ENV_DIR" apply apply.tfplan
```

## 結果

| 確認項目 | 結果 | 証跡 |
| --- | --- | --- |
| 保存済みplanのreview / apply | NOT RUN | run ID / masked log |
| ALB `/healthz`（制限CIDRから） | NOT RUN | status / timestamp |
| 許可外経路の拒否 | NOT RUN | probe result |
| EC2 status / SSM Online | NOT RUN | instance ID masked |
| CloudWatch Alarm / SNS email | NOT RUN | alarm / delivery time |
| AWS Backup on-demand job | NOT RUN | job ID / status |
| 日次planのrecovery point / RPO | NOT RUN | plan ID / creation time |
| SSM transfer bucket probe / cleanup | NOT RUN | object key masked |
| [D-2復旧演習](../../roadmap/restore-from-snapshot.md) | NOT RUN | drill log |

## destroy / 残存確認

```bash
terraform -chdir="$TF_ENV_DIR" plan -destroy -var-file=terraform.tfvars -out=destroy.tfplan
terraform -chdir="$TF_ENV_DIR" show destroy.tfplan
# review・承認後のみ
terraform -chdir="$TF_ENV_DIR" apply destroy.tfplan
```

| 確認項目 | 結果 | 証跡 |
| --- | --- | --- |
| 一時restore EC2のderegister / terminate | NOT RUN | instance / restore job |
| 保存済みdestroy plan適用 | NOT RUN | apply summary |
| staging tagの残存resourceなし | NOT RUN | Resource Groups / CLI |
| Backup / S3一時objectなし | NOT RUN | vault / bucket listing |
| KMS keyの予定削除 | NOT RUN | PendingDeletion date |
| 当日費用の一次確認 | NOT RUN | Billing screenshot |
| 翌日のCost Explorer確定確認 | NOT RUN | service別 / tag別金額 |

## マスクと判定

- マスク: account ID、public IP / DNS、email、ARNの固有部、token / webhook / secret。
- 日次RPOは、recovery pointの`CreatedBy.BackupPlanId`が現行staging plan IDと一致した場合だけ評価する。
- ALB確認またはcleanupを省略した場合は`PARTIAL`で、D-2 PASSにしない。
- 費用は翌日確認まで`NOT RUN`のままにする。

## 所見

- 良かった点:
- 見つかった課題:
- rollback / cleanup結果:
- 次の対応とowner / due:
