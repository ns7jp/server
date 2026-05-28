# AWS 短時間検証記録テンプレート

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象 commit | `commit-sha` |
| 環境 | dev / prod |
| 実行者 | name |
| Terraform version | `terraform version` |
| AWS region | `ap-northeast-1` |

## 実行コマンド

```bash
cd terraform/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
terraform destroy
```

## 結果

| 確認項目 | 結果 | 証跡 |
| --- | --- | --- |
| `terraform plan` | PASS / FAIL | ログ抜粋またはスクリーンショット |
| `terraform apply` | PASS / FAIL | 作成リソース数、所要時間 |
| ALB `/healthz` | PASS / FAIL | HTTP status、時刻 |
| CloudWatch Alarm | PASS / FAIL | Alarm 名、状態 |
| `terraform destroy` | PASS / FAIL | 削除リソース数、所要時間 |
| Cost Explorer | 金額 | 期間、サービス別費用 |

## マスクした情報

- AWS account ID
- Public IP / hostname
- ALB DNS name
- Secret / token / webhook

## 所見

- 良かった点:
- 見つかった課題:
- 次の対応:
