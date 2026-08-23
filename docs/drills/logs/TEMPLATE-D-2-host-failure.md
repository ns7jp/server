# D-2 AWS Backup別ホスト復旧演習記録テンプレート

> 初期状態: **NOT RUN**。これは記録用テンプレートで、実施証跡ではない。

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象commit | `40-character-sha` |
| 環境 | `terraform/environments/staging` |
| AWS account / region | masked / `ap-northeast-1` |
| 操作 / 観測 / 承認 | name / name / name |
| source / restored EC2 | masked / masked |
| Backup / Restore job | masked / masked |
| 目標RTO / RPO | 60分 / 24時間 |

## 境界と事前判定

- 障害注入はsource EC2の安全なstopのみ。disk破壊、volume detach、OS破損は未検証。
- 日次RPOを評価する場合、`CreatedBy.BackupPlanId`が現行staging plan IDと一致すること。
- on-demand recovery pointの場合、restore手順は評価できるが日次schedule RPOは`NOT RUN`。
- Slack実配信と外部probeは、それぞれ実到達ログがある場合だけPASS。
- ALB Target Group登録、ALB `/healthz`、cleanupまで完了しない場合はD-2をPASSにしない。

| preflight | 結果 | 証跡 |
| --- | --- | --- |
| caller / staging tag / CIDR / cost承認 | NOT RUN | — |
| recovery point status / age / provenance | NOT RUN | — |
| source SSM / Ansible inventory / Vault decrypt | NOT RUN | — |
| SSM bucket put / head / delete | NOT RUN | — |
| 中断scriptの対象確認 | NOT RUN | — |

## タイムライン

| 時刻 | イベント | 証跡 |
| --- | --- | --- |
| HH:MM:SS | preflight完了 | checklist / recovery point |
| HH:MM:SS | source stop開始（RTO開始） | EC2 event |
| HH:MM:SS | ALB unhealthy / 検知 | CloudWatch / Alertmanager |
| HH:MM:SS | Restore job開始 | idempotency token / job ID |
| HH:MM:SS | Restore job完了 | CreatedResourceArn |
| HH:MM:SS | restored EC2 status OK / SSM Online | CLI output |
| HH:MM:SS | explicit restore tags付与 | masked tag list |
| HH:MM:SS | Ansible site / verify完了 | recap / host vars assertion |
| HH:MM:SS | temporary Target Group登録 / healthy | target health |
| HH:MM:SS | ALB `/healthz`成功（RTO終了） | HTTP status |
| HH:MM:SS | deregister / restored EC2 terminate | CLI output |
| HH:MM:SS | staging destroy / 残存確認 | plan / apply / inventory |

## 結果

| 指標 | 目標 | 実測 | 評価 |
| --- | --- | --- | --- |
| 検知時間 | 2分以内 | NOT RUN | NOT RUN |
| Restore job | 15分目安 | NOT RUN | NOT RUN |
| Ansible適用 | 15分目安 | NOT RUN | NOT RUN |
| Target Group healthy | 10分目安 | NOT RUN | NOT RUN |
| RTO（stop開始→ALB成功） | 60分以内 | NOT RUN | NOT RUN |
| 日次plan RPO | 24時間以内 | NOT RUN | NOT RUN |
| Slack到達 | 2分以内 | NOT RUN | NOT RUN |
| 外部probe | 期待どおり | NOT RUN | NOT RUN |
| 費用 | 承認上限内 | NOT RUN | NOT RUN |

## 中断 / cleanup

| 項目 | 結果 | 証跡 |
| --- | --- | --- |
| `d2-abort.sh`の要否 / source復旧 | NOT RUN | — |
| restored target deregister | NOT RUN | — |
| restored EC2 terminate | NOT RUN | — |
| restore由来volume / snapshot確認 | NOT RUN | — |
| staging destroy | NOT RUN | — |
| 翌日Cost Explorer確認 | NOT RUN | — |

## マスクした情報

- AWS account ID、IP / hostname、ARN固有部、email、secret / token / webhook。

## 所見

- 良かった点:
- 見つかった課題:
- 中断 / rollbackの結果:
- 改善action / owner / due:
