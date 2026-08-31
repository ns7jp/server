# 引き渡しチェックリスト

> 💡 **初めて読む方へ**: この文書は作業を依頼者に引き渡す前の最終確認リストです。案件パック全体の地図は[初心者ガイド](beginner-guide.md#07-引き渡しチェックリスト)を参照してください。

## 引き渡し判定

| 項目 | 状態 |
| --- | --- |
| 文書パック | 作成済み |
| 新規構築 ZIT-01 / 冪等性 ZIT-02 | `NOT RUN`（対象host未指定） |
| host active check ZIT-03 / Frontend認証 ZIT-04 / healthz item ZIT-05 | `NOT RUN` |
| alert通知 ZIT-06（Trigger発火は必須。Slack実配信はwebhookと受信先を用意した場合のみ） | `NOT RUN` |
| D-Z1 Agent停止演習・RTO記録 ZIT-07 | `NOT RUN` |
| DB backup/restore（`pg_restore`）ZIT-08 | `NOT RUN` |
| zbx-01・monitor-01間 network ZIT-09（ZNW-01〜09） | `NOT RUN` |
| セキュリティ試験 ZST-01〜04（bind address、既定パスワード変更、secret tracking、firewall） | `NOT RUN` |
| zbx-01の構成commit / 設定rollback rehearsal | `NOT RUN`（対象host未指定） |
| 作業結果報告書 | 原本作成済み。対象ホストの報告は `NOT SET` |
| 必須試験完了 | `NOT READY` |
| 受領 | `NOT SET` |

文書や`compose.zabbix.yaml`がCIで構文検証されていることは、未指定の引き渡し対象host（`zbx-01`）を受領可能と判定する材料にはしません。[試験仕様書](06-test-specification.md)を対象hostで実施した日付付き結果票を確認してから、この表を更新します。`ZIT-06`はwebhookと受信先が無い環境では実配信部分が`BLOCKED`となり得ますが、Trigger発火までの確認は必須のまま残ります。

## 構成と状態

- [ ] 対象ホスト（`zbx-01`）、対応する監視対象ホスト（`monitor-01`）、環境名、commit SHA を記録した
- [ ] [基本設計書](01-basic-design.md)の構成図と[パラメータシート](03-parameter-sheet.md)を実機値へ更新した
- [ ] 必須試験（`ZUT-01`〜`03`、`ZIT-01`〜`05`、`ZIT-07`〜`09`、`ZST-01`〜`04`）がすべて `PASS` した
- [ ] 未解決 Issue、制約、残存リスク（passive check 未使用、カスタムテンプレート未自作、専用Ansible role 未実装）を説明した
- [ ] 監視対象（`monitor-01`のホストメトリクスと`service_monitor.healthz`）、Severity、通知先（Slack）、対応時間帯を説明した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付き evidence へ複製し、計画対実績と試験集計を記入した

## 運用

- [ ] `docker compose -f compose.zabbix.yaml`の起動・停止・状態確認コマンドを引き渡した
- [ ] [運用runbook索引](../runbooks/README.md)を確認した（`zbx-01`固有の手順は本パックの[構築手順書](05-build-procedure.md)を正本とする）
- [ ] D-Z1（`monitor-01`のZabbix Agent2停止）復旧演習を実施し、RTO を記録した
- [ ] バックアップ日時（毎日03:45 Asia/Tokyo）、保持世代（14日）、復元手順（`pg_restore`、ZIT-08）を確認した
- [ ] Zabbix Frontend既定管理者（`Admin`/`zabbix`）のパスワード変更（ZST-02、必須の済(手動)手順）を確認した
- [ ] 変更申請、Go / No-Go、ロールバックの流れを説明した（[08-change-rollback-plan.md](08-change-rollback-plan.md)）

## 運用クイックリファレンス

詳細は各文書を正本とし、引き渡し時は`zbx-01`実ホストで一度ずつ実行して出力を運用ログへ残します。

| 目的 | コマンド / 正本 |
| --- | --- |
| 全体状態 | `docker compose -f compose.zabbix.yaml ps` |
| compose構文確認 | `docker compose -f compose.zabbix.yaml config --quiet` |
| bind address確認 | `ss -lntup` |
| trapper firewall確認 | `ufw status verbose` |
| Zabbix Server/Web ログ | `docker compose -f compose.zabbix.yaml logs --tail 100 zabbix-server zabbix-web` |
| DB backup実行 | [`scripts/ops/zabbix-backup.sh`](../../scripts/ops/zabbix-backup.sh) |
| backup timer | `systemctl list-timers`（unit名は[構築手順書](05-build-procedure.md)の実機記入欄を参照） |
| 直近error log | `journalctl -p err --since today --no-pager` |
| runbook一覧 / 共通前提 | [`docs/runbooks/README.md`](../runbooks/README.md) |
| backup / restore一般ルール | [`docs/backup-restore.md`](../backup-restore.md) |
| 変更 / rollback | [変更・ロールバック計画兼記録票](08-change-rollback-plan.md) |
| network 調査 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

`monitor-01`側（既存Linux監視host）のコマンドは対象外です。[Linux版運用クイックリファレンス](../build-package/07-handover-checklist.md)を参照してください。

## 連絡・エスカレーション記入欄

| 条件 | 一次対応 | エスカレーション先 / 期限 |
| --- | --- | --- |
| Zabbix agent 停止（Trigger PROBLEM、Severity: Disaster） | D-Z1手順に沿って検知・復旧を確認 | `NOT SET` |
| `service_monitor.healthz` 異常（Severity: High） | Frontend上のProblem詳細を確認し、`monitor-01`側で一次切り分け | `NOT SET` |
| 認証回避、DBパスワード / Slack webhook URL漏えい | 外部公開を止め、秘密値を再発行 | `NOT SET` |
| `zbx-01` host障害 | 復元判断（[08](08-change-rollback-plan.md)参照）、RPOの確認 | `NOT SET` |
| 復旧見込みが RTO 超過 | 状況、影響、次回報告時刻を共有 | `NOT SET` |

## セキュリティ

- [ ] 秘密値（DBパスワード、Slack webhook URL）そのものではなく、安全な受け渡し・再発行方法を共有した
- [ ] 不要な一時アカウント、テストデータ、UFW許可を削除した
- [ ] SSH、sudo、UFW、Frontend / trapperの公開portを確認し、trapper（`10051/tcp`）の許可送信元が`monitor-01`のIPのみに限定されていることを採録した（ZST-04）
- [ ] Zabbix Frontend既定管理者（`Admin`/`zabbix`）のパスワードが変更済みであることを確認した（ZST-02）
- [ ] 実ログとスクリーンショットから IP、account ID、秘密値をマスクした

## 定期作業

| 頻度 | 作業 | 記録先 |
| --- | --- | --- |
| 日次 | backup timer / failed unit / Zabbix Problem 一覧確認 | 運用ログ |
| 週次 | disk増加、未処理Problem、Zabbixコンポーネントの更新状況 | 週次レビュー |
| 月次 | D-Z1、通知試験（webhookと受信先を用意した場合） | drill記録 |
| 四半期 | DB復元試験（`pg_restore`、ZIT-08）、Frontendアクセス棚卸し | 記録 |

## 受領記録

| 項目 | 値 |
| --- | --- |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 対象環境 | `NOT SET` |
| 未解決事項 | `NOT SET` |
| 関連 Issue / PR | `NOT SET` |
| 適用 commit SHA（`compose.zabbix.yaml`等） | `NOT SET` |
| Zabbix Frontend Admin初期パスワード変更完了（ZST-02） | `NOT SET` |
| 試験結果票 | `NOT SET` |
| network 結果票 | `NOT SET` |
| 変更 / rollback 記録 | `NOT SET` |
| 作業結果報告書 | `NOT SET` |
| 秘密値受け渡し完了（DBパスワード・Slack webhook URL。値は記載しない） | `NOT SET` |
