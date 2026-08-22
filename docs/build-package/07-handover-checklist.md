# 引き渡しチェックリスト

## 引き渡し判定

| 項目 | 状態 |
| --- | --- |
| 文書パック | 作成済み |
| ephemeral runner 新規構築 IT-01 / 冪等性 IT-02 | `PASS`（[2026-08-22 E2E](../evidence/2026-08-22-full-stack-e2e.md)） |
| 引き渡し対象hostの新規構築 IT-01 / 冪等性 IT-02 | `NOT RUN`（対象host未指定） |
| 引き渡し対象host/管理端末の network IT-12 | `NOT RUN` |
| 必須試験完了 | `NOT READY` |
| 受領 | `NOT SET` |

文書やephemeral E2Eが存在するだけでは、未指定の引き渡し対象hostを受領可能と判定しません。
[試験仕様書](06-test-specification.md)を対象hostで実施した日付付き結果票を確認してから更新します。

## 構成と状態

- [ ] 対象ホスト、環境名、commit SHA を記録した
- [ ] 構成図とパラメータシートを実機値へ更新した
- [ ] 必須試験がすべて `PASS` した
- [ ] 未解決 Issue、制約、残存リスクを説明した
- [ ] 監視対象、閾値、通知先、対応時間帯を説明した

## 運用

- [ ] 起動・停止・状態確認コマンドを引き渡した
- [ ] サービス停止と latency spike のランブックを確認した
- [ ] D-1 復旧演習を実施し、RTO を記録した
- [ ] バックアップ日時、保持期間、復元手順を確認した
- [ ] 変更申請、事前確認、ロールバックの流れを説明した

## 運用クイックリファレンス

詳細は各文書を正本とし、引き渡し時は実ホストで一度ずつ実行して出力を運用ログへ残します。

| 目的 | コマンド / 正本 |
| --- | --- |
| 全体状態 | `sudo docker compose -f /opt/server-monitor/compose.yaml ps` |
| endpoint smoke test | `ansible-playbook -i inventory/staging.yml playbooks/verify.yml` |
| failed unit | `systemctl --failed --no-pager` |
| 当日の error log | `journalctl -p err --since today --no-pager` |
| backup timer | `systemctl list-timers server-monitor-backup.timer` |
| 日次確認 | [`scripts/ops/daily-check.sh`](../../scripts/ops/daily-check.sh) |
| service 障害 | [`docs/runbooks/service-down.md`](../runbooks/service-down.md) |
| disk / memory | [`disk-full.md`](../runbooks/disk-full.md) / [`memory-pressure.md`](../runbooks/memory-pressure.md) |
| backup / restore | [`docs/backup-restore.md`](../backup-restore.md) |
| 変更 / rollback | [変更・ロールバック計画](08-change-rollback-plan.md) |
| network 調査 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

## 連絡・エスカレーション記入欄

| 条件 | 一次対応 | エスカレーション先 / 期限 |
| --- | --- | --- |
| `/healthz` failure / service alert | service-down runbook | `NOT SET` |
| disk / memory alert | 対応 runbook、直近変更確認 | `NOT SET` |
| 認証回避、秘密値漏えい | 外部公開を止め、秘密値を再発行 | `NOT SET` |
| host 障害 | 復元判断、RPO の確認 | `NOT SET` |
| 復旧見込みが RTO 超過 | 状況、影響、次回報告時刻を共有 | `NOT SET` |

## セキュリティ

- [ ] 秘密値そのものではなく、安全な受け渡し・再発行方法を共有した
- [ ] 不要な一時アカウント、テストデータ、firewall 許可を削除した
- [ ] SSH、sudo、UFW、公開 port を確認した
- [ ] 実ログとスクリーンショットから IP、account ID、秘密値をマスクした

## 定期作業

| 頻度 | 作業 | 記録先 |
| --- | --- | --- |
| 日次 | backup timer / failed unit / alert 確認（[scripts/ops/daily-check.sh](../../scripts/ops/daily-check.sh)） | 運用ログ |
| 週次 | disk 増加、未処理 alert、更新状況 | 週次レビュー |
| 月次 | D-1、SLO、通知試験 | drill / SLO review |
| 四半期 | 復元試験、アクセス棚卸し | D-2 記録 |

## 受領記録

| 項目 | 値 |
| --- | --- |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 対象環境 | `NOT SET` |
| 未解決事項 | `NOT SET` |
| 関連 Issue / PR | `NOT SET` |
| 適用 commit SHA | `NOT SET` |
| 試験結果票 | `NOT SET` |
| network 結果票 | `NOT SET` |
| 変更 / rollback 記録 | `NOT SET` |
| 秘密値受け渡し完了（値は記載しない） | `NOT SET` |

