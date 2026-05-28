# D-2 ホスト障害復旧演習記録テンプレート

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象 commit | `commit-sha` |
| 環境 | AWS staging |
| シナリオ | host failure / snapshot restore |
| 目標 RTO | 60 分 |
| 目標 RPO | 24 時間以内 |

## タイムライン

| 時刻 | イベント | 証跡 |
| --- | --- | --- |
| HH:MM:SS | 演習開始 | 事前周知 |
| HH:MM:SS | 障害注入 | EC2 stop / target deregistration |
| HH:MM:SS | 外部 probe 失敗 | CloudWatch / UptimeRobot |
| HH:MM:SS | スナップショット特定 | AWS Backup recovery point |
| HH:MM:SS | 新 EC2 起動 | Terraform / AWS Console |
| HH:MM:SS | Ansible 適用 | playbook output |
| HH:MM:SS | `/healthz` 復旧 | HTTP status |
| HH:MM:SS | 演習終了 | summary |

## 結果

| 指標 | 目標 | 実測 | 評価 |
| --- | --- | --- | --- |
| 検知時間 | 2 分以内 | ? 分 | PASS / FAIL |
| 復旧時間 RTO | 60 分以内 | ? 分 | PASS / FAIL |
| データ損失 RPO | 24 時間以内 | ? 時間 | PASS / FAIL |
| 通知到達 | 2 分以内 | ? 分 | PASS / FAIL |
| 費用 | 予定内 | ? 円 | PASS / FAIL |

## マスクした情報

- AWS account ID
- Public IP / hostname
- Recovery point ARN
- Secret / token / webhook

## 所見

- 良かった点:
- 見つかった課題:
- 次の対応:
