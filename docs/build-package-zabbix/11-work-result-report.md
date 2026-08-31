# 作業結果・引き渡し報告書(原本)

> 💡 **初めて読む方へ**: この文書は予定と実績の差、トラブル、残課題をまとめて報告する文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#11-作業結果引き渡し報告書)を参照してください。

本書は、Zabbix監視基盤構築作業(案件ID `SM-ZBX-001`)の「予定」と「実績」、試験結果、差異、障害、残存リスク、受領判断を1件にまとめるための原本です。対象ホストごとに`docs/evidence/YYYY-MM-DD-work-result-<change-id>.md`へ複製して記入し、この原本は上書きしません。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。

初期値の`NOT SET`は情報未確定、`NOT RUN`は未実行、`NOT READY`は完了条件未達です。空欄や`NOT RUN`を`PASS`として集計しません。

本パックは[Windows版パック](../build-package-windows/README.md)・[AD版パック](../build-package-ad/README.md)と異なり、中央監視基盤への統合待ちの「フェーズ2」を持ちません。既存の中央監視基盤(`SM-LAB-001`)は変更せず、`zbx-01`という独立した2本目の監視経路を単一フェーズで構築・受け入れます。

`zbx-01`に相当する実ホストの構築そのものがまだ行われていないため、本書に対応する日付付きevidenceは現時点で1件もありません。以下の空欄は次の構築作業で複製して使う原本であり、実ホストでの作業結果は現在も`NOT RUN`です。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-ZBX-001` |
| 変更ID / チケット | `NOT SET` |
| 作業目的 | `NOT SET` |
| 対象環境 / ホスト | `NOT SET`(論理ホスト名`zbx-01`、対応する監視対象`monitor-01`) |
| 作業者 / 確認者 | `NOT SET` |
| 作業予定日時 | `NOT SET` |
| 作業実績日時 | `NOT RUN` |
| 対象commit SHA | `NOT SET` |
| 変更前の正常commit SHA | `NOT SET` |
| Zabbix Frontend Admin初期パスワード変更実施(ZST-02) | `NOT RUN` |
| 作業結果 | `NOT READY` |
| 関連Issue / PR | `NOT SET` |

対象commitは40桁SHAで記録します。作業ツリーに未コミット差分がある場合は`git status --short`と`git diff --stat`を保存し、commit SHAだけで再現できる証跡として扱いません。Zabbix Frontend上のHost / Template / Trigger / Actionの設定はGit管理外のため、commit SHAだけでは再現できません。変更前の状態はZabbix標準のexport機能によるXMLで別途保存します([08-change-rollback-plan.md](08-change-rollback-plan.md)参照)。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | — |
| 管理端末から`zbx-01`・`monitor-01`へSSH / sudoが利用可能 | NOT RUN | — |
| コンソール等の代替接続手段を確認 | NOT RUN | — |
| 対象SHAとrollback SHAを固定 | NOT SET | — |
| 秘密値(DBパスワード、Slack webhook URL)の受け渡し手段を確認 | NOT RUN | — |
| 直前の`pg_dump`(`zabbix-backup.sh`)の存在を確認 | NOT RUN | — |
| Go / No-Go条件を確認 | NOT SET | [変更・ロールバック計画兼記録票](08-change-rollback-plan.md) |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | commit SHA固定、疎通、秘密値準備、`monitor-01`変更前状態 | `NOT RUN` | NOT RUN | — | — |
| 初回構築 | `zbx-01`で`docker compose up -d`(ZIT-01) | `NOT RUN` | NOT RUN | — | — |
| 冪等性 | 同一コマンド2回目実行(ZIT-02) | `NOT RUN` | NOT RUN | — | — |
| Admin初期パスワード変更 | Frontend初回ログイン直後の変更(ZST-02) | `NOT RUN` | NOT RUN | — | — |
| Agent2導入・登録 | `monitor-01`へのAgent2導入、Host / Template / Item / Trigger / Action登録(ZIT-03〜05) | `NOT RUN` | NOT RUN | — | — |
| 監視・通知確認 | Trigger発火、Slack通知(webhook用意時)(ZIT-06) | `NOT RUN` | NOT RUN | — | — |
| 障害復旧 | D-Z1、必要に応じてrollback / restore(ZIT-07) | `NOT RUN` | NOT RUN | — | — |
| backup / restore | `zabbix-backup.sh`実行、別DBへの`pg_restore`(ZIT-08) | `NOT RUN` | NOT RUN | — | — |
| 実機network | ZNW-01〜09(ZIT-09) | `NOT RUN` | NOT RUN | — | — |
| 後処理 | 一時許可・テストデータ削除、最終状態取得 | `NOT RUN` | NOT RUN | — | — |

結果は`PASS / FAIL / BLOCKED / NOT RUN`のいずれかとし、実行コマンド、主要出力、所要時間を日付付きevidenceへ残します。

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・構成試験(ZUT) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 構築・結合試験(ZIT) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| セキュリティ試験(ZST) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| ネットワーク実機検証(ZNW) | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 合計 | `NOT SET` | 0 | 0 | 0 | `NOT SET` | [試験仕様書・結果票](06-test-specification.md) |

集計値は個別結果票(ネットワーク実機検証は[結果票テンプレート](../evidence/templates/network-host-validation.md)から作成した日付付きevidence)から転記し、合計が一致することを確認します。対象ホストが違う結果や、別commitの結果を合算しません。`ZIT-06`(Slack実配信)はwebhookと受信先が無い環境では`BLOCKED`となり得ますが、Trigger発火までの確認が必須である点は集計上の`NOT RUN`と区別します。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / kernel(`zbx-01`) | [パラメータシート](03-parameter-sheet.md)参照(Ubuntu Server 24.04 LTS) | `NOT RUN` | `NOT SET` | `NOT SET` |
| CPU / memory / disk(`zbx-01`) | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| IP / DNS / route | [ネットワーク設計・IPアドレス表](04-network-ip-plan.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| Zabbix / PostgreSQLイメージversion | [パラメータシート](03-parameter-sheet.md)参照(`alpine-7.0.29` / `postgres:16-alpine`) | `NOT RUN` | `NOT SET` | `NOT SET` |
| Zabbix Agent2バージョン(`monitor-01`) | 同上(実機決定時に固定) | `NOT RUN` | `NOT SET` | `NOT SET` |
| port / firewall(Frontend loopback、trapper CIDR) | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| Host / Template / Trigger / Action設定 | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |

差異が無い場合も「差異なし」と記録し、未確認のまま空欄にしません。承認されていない差異が残る場合は作業完了にしません。

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| `NOT SET` | `NOT RUN` | `NOT SET` | `NOT SET` | `NOT SET` | NOT RUN | `NOT SET` |

切り分けは[一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ仮説、コマンド、実出力、判断を残します。既知の実例は[欠陥台帳](../evidence/defects-found.md)を参照します。

## 7. 残存リスク・未実施

この原本の初期状態では、少なくとも次は引き渡し対象ホストで`NOT RUN`です。実施した項目だけ、日付付き結果と置き換えます。

| 項目 | 状態 | 解除条件 |
| --- | --- | --- |
| 対象ホスト(`zbx-01`)の新規構築・冪等性・受け入れ | NOT RUN | 対象ホストで[構築手順書](05-build-procedure.md)と[立ち上げ・受け入れ手順](10-host-bringup-and-acceptance.md)を実行 |
| 実管理端末 / `zbx-01` / `monitor-01`間network | NOT RUN | [ネットワーク実機検証手順](09-network-validation-procedure.md)でZNW-01〜09を実行 |
| D-Z1演習・RTO記録 | NOT RUN | 対象ホストでZIT-07を実行 |
| DB backup / restore | NOT RUN | 対象ホストでZIT-08を実行 |
| Slack実配信(ZIT-06のうち配信部分) | NOT RUN(webhook未用意の環境では`BLOCKED`) | webhookと受信先を用意して送受信を採録 |
| passive check(任意拡張) | NOT READY | 複数監視対象host化の要否を判断してから設計・実装を検討 |
| 専用Ansible role(`ansible/roles/zabbix_agent`相当) | NOT READY | 手動手順の自動化方針を検討・実装 |
| ホスト再起動後の永続性、24h / 72h連続稼働 | NOT RUN | [Linux版パックの立ち上げ・受け入れ手順](../build-package/10-host-bringup-and-acceptance.md)4節・5節の考え方を`zbx-01`へ適用して実行 |
| RHEL系(AlmaLinux / Rocky)でのZabbix構築 | NOT READY(対象外) | 対象を広げる場合は[要件定義書](00-requirements.md)の対象外節を見直す |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 構成コード | 40桁commit SHA: `NOT SET` | NOT SET |
| 設計・パラメータ | `docs/build-package-zabbix/` | NOT SET |
| Frontend設定のexport(Host / Template / Trigger / Action XML) | `NOT SET` | NOT SET |
| 試験結果・実行ログ | `NOT SET` | NOT SET |
| ネットワーク実機検証結果票 | `NOT SET` | NOT SET |
| 運用ランブック | [運用runbook索引](../runbooks/README.md) | NOT SET |
| backup / restore手順 | [`docs/backup-restore.md`](../backup-restore.md)、[パラメータシート](03-parameter-sheet.md)の監視設定値節 | NOT SET |
| 変更 / rollback記録 | `NOT SET` | NOT SET |
| 秘密値の受け渡し・再発行方法(DBパスワード、Slack webhook URL、Zabbix Admin新パスワード) | 値そのものは記載しない | NOT SET |

## 9. 完了・受領判定

- [ ] 必須試験がすべて`PASS`で、結果票と集計が一致する
- [ ] `FAIL` / `BLOCKED` / 必須の`NOT RUN`が残っていない
- [ ] 設計差異、障害、残存リスク、未解決Issueを説明した
- [ ] 一時設定とテストデータを撤去し、最終状態を採録した
- [ ] rollbackまたはrestoreの開始条件と連絡先を共有した
- [ ] Zabbix Frontend既定管理者(`Admin`/`zabbix`)のパスワード変更(ZST-02)を確認した
- [ ] [引き渡しチェックリスト](07-handover-checklist.md)を完了した

| 判定 | 値 |
| --- | --- |
| 作業完了 | `NOT READY` |
| 引き渡し可否 | `NOT READY` |
| 判定理由 | 必須試験と受領情報が未記入 |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 承認者 | `NOT SET` |
