# 作業結果・引き渡し報告書（原本）

> 💡 **初めて読む方へ**: この文書は予定と実績の差、トラブル、残課題をまとめて報告する文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#11-作業結果引き渡し報告書)を参照してください。

本書は、構築作業の「予定」と「実績」、試験結果、差異、障害、残存リスク、受領判断を 1 件にまとめるための原本です。対象ホストごとに `docs/evidence/YYYY-MM-DD-work-result-<change-id>.md` へ複製して記入し、この原本は上書きしません。

初期値の `NOT SET` は情報未確定、`NOT RUN` は未実行、`NOT READY` は完了条件未達です。空欄や `NOT RUN` を `PASS` として集計しません。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件 ID | `SM-LAB-001` |
| 変更 ID / チケット | `NOT SET` |
| 作業目的 | `NOT SET` |
| 対象環境 / ホスト | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 作業予定日時 | `NOT SET` |
| 作業実績日時 | `NOT RUN` |
| 対象 commit SHA | `NOT SET` |
| 変更前の正常 commit SHA | `NOT SET` |
| 作業結果 | `NOT READY` |
| 関連 Issue / PR | `NOT SET` |

対象 commit は 40 桁 SHA で記録します。作業ツリーに未コミット差分がある場合は `git status --short` と `git diff --stat` を保存し、commit SHA だけで再現できる証跡として扱いません。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | — |
| 管理端末から SSH / sudo が利用可能 | NOT RUN | — |
| コンソール等の代替接続手段を確認 | NOT RUN | — |
| 対象 SHA と rollback SHA を固定 | NOT SET | — |
| backup / 復元ポイントを確認 | NOT RUN | — |
| Go / No-Go 条件を確認 | NOT SET | [変更・ロールバック計画](08-change-rollback-plan.md) |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | inventory、疎通、容量、backup、変更前状態 | `NOT RUN` | NOT RUN | — | — |
| 初回構築 | `site.yml` 適用 | `NOT RUN` | NOT RUN | — | — |
| 冪等性 | `site.yml` 2 回目、`changed=0` | `NOT RUN` | NOT RUN | — | — |
| 構築後確認 | `verify.yml`、service、listen、FW | `NOT RUN` | NOT RUN | — | — |
| 監視・ログ | Grafana、Prometheus、Loki、Alertmanager | `NOT RUN` | NOT RUN | — | — |
| 障害復旧 | D-1、必要に応じて rollback / restore | `NOT RUN` | NOT RUN | — | — |
| 後処理 | 一時許可・データ削除、最終状態取得 | `NOT RUN` | NOT RUN | — | — |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかとし、実行コマンド、主要出力、exit code、所要時間を日付付き evidence へ残します。

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・構成試験 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 構築・結合試験 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| セキュリティ試験 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 合計 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | [試験仕様書・結果票](06-test-specification.md) |

集計値は個別結果票から転記し、合計が一致することを確認します。対象ホストが違う結果や、別 commit の結果を合算しません。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / kernel | [パラメータシート](03-parameter-sheet.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| CPU / memory / disk | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| IP / DNS / route | [ネットワーク設計](04-network-ip-plan.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| package / image version | [パラメータシート](03-parameter-sheet.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| port / firewall | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |

差異が無い場合も「差異なし」と記録し、未確認のまま空欄にしません。承認されていない差異が残る場合は作業完了にしません。

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `NOT SET` | `NOT RUN` | `NOT SET` | `NOT SET` | `NOT SET` | NOT RUN | `NOT SET` |

切り分けは[一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ仮説、コマンド、実出力、判断を残します。既知の実例は[欠陥台帳](../evidence/defects-found.md)を参照します。

## 7. 残存リスク・未実施

この原本の初期状態では、少なくとも次は引き渡し対象ホストで `NOT RUN` です。実施した項目だけ、日付付き結果と置き換えます。

| 項目 | 状態 | 解除条件 |
| --- | --- | --- |
| 対象ホストの新規構築・冪等性・受け入れ | NOT RUN | 対象ホストで `site.yml` と `acceptance-check.sh` を実行 |
| 実管理端末 / DNS / firewall | NOT RUN | [ネットワーク実機検証](09-network-validation-procedure.md)を実行 |
| 再起動後の永続性、24h / 72h 稼働 | NOT RUN | [立ち上げ・受け入れ手順](10-host-bringup-and-acceptance.md)を実行 |
| Alertmanager → Slack 実配信 | NOT RUN | webhook と受信先を用意して送受信を採録 |
| D-2 別ホスト復旧 | NOT RUN | 2 台目のホストで復元演習を実行 |
| AWS `apply / destroy` と実費 | NOT RUN | 費用上限承認後に短時間検証を実行 |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 構成コード | 40 桁 commit SHA: `NOT SET` | NOT SET |
| 設計・パラメータ | `docs/build-package/` | NOT SET |
| 試験結果・実行ログ | `NOT SET` | NOT SET |
| 運用ランブック | `docs/runbooks/` | NOT SET |
| backup / restore 手順 | `docs/backup-restore.md` | NOT SET |
| 変更 / rollback 記録 | `NOT SET` | NOT SET |
| 秘密値の受け渡し・再発行方法 | 値そのものは記載しない | NOT SET |

## 9. 完了・受領判定

- [ ] 必須試験がすべて `PASS` で、結果票と集計が一致する
- [ ] `FAIL` / `BLOCKED` / 必須の `NOT RUN` が残っていない
- [ ] 設計差異、障害、残存リスク、未解決 Issue を説明した
- [ ] 一時設定とテストデータを撤去し、最終状態を採録した
- [ ] rollback または restore の開始条件と連絡先を共有した
- [ ] [引き渡しチェックリスト](07-handover-checklist.md)を完了した

| 判定 | 値 |
| --- | --- |
| 作業完了 | `NOT READY` |
| 引き渡し可否 | `NOT READY` |
| 判定理由 | 必須試験と受領情報が未記入 |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 承認者 | `NOT SET` |
