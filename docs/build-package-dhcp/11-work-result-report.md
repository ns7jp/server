# 作業結果・引き渡し報告書（原本）

> 💡 **初めて読む方へ**: この文書は予定と実績の差、トラブル、残課題をまとめて報告する文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#11-作業結果引き渡し報告書)を参照してください。

本書は、構築作業の「予定」と「実績」、試験結果、差異、障害、残存リスク、受領判断を1件にまとめるための原本です。対象ホストごとに`docs/evidence/YYYY-MM-DD-work-result-SM-DHCP-001.md`へ複製して記入し、この原本は上書きしません。

初期値の`NOT SET`は情報未確定、`NOT RUN`は未実行、`NOT READY`は完了条件未達です。空欄や`NOT RUN`を`PASS`として集計しません。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-DHCP-001` |
| 変更ID / チケット | `NOT SET` |
| 作業目的 | `NOT SET` |
| 対象環境 / ホスト | `NOT SET`（想定は`dhcp-01`、Ubuntu Server 24.04 LTS、`192.168.50.0/24`セグメント向けのisc-dhcp-server新規構築） |
| 作業者 / 確認者 | `NOT SET` |
| 作業予定日時 | `NOT SET` |
| 作業実績日時 | `NOT RUN` |
| 対象commit SHA | `NOT SET` |
| 変更前の正常commit SHA | `NOT SET` |
| 作業結果 | `NOT READY` |
| 関連Issue / PR | `NOT SET` |

対象commitは40桁SHAで記録します。作業ツリーに未コミット差分がある場合は`git status --short`と`git diff --stat`を保存し、commit SHAだけで再現できる証跡として扱いません。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | — |
| 管理端末からSSH / sudoが利用可能 | NOT RUN | — |
| コンソール等の代替接続手段を確認 | NOT RUN | — |
| 対象SHAとrollback SHAを固定 | NOT SET | — |
| `dhcpd.conf`とリースDBのbackup / 復元ポイントを確認 | NOT RUN | — |
| 同一セグメントにrogue DHCPサーバーが存在しないことを確認（NFR-08） | NOT RUN | — |
| Go / No-Go条件を確認 | NOT SET | [変更・ロールバック計画](08-change-rollback-plan.md) |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | inventory、疎通、rogue DHCP非存在確認（DST-06）、backup、変更前状態 | `NOT RUN` | NOT RUN | — | — |
| 初回構築 | `dhcp.yml`適用（`common` role→`dhcp_server` role） | `NOT RUN` | NOT RUN | — | — |
| 冪等性 | `dhcp.yml` 2回目、`changed=0` | `NOT RUN` | NOT RUN | — | — |
| 構築後確認 | `dhcpd -t`構文検査、systemd状態、待受port、UFW、AppArmor | `NOT RUN` | NOT RUN | — | — |
| DORA・払い出し実機試験 | DORA実測、固定予約、プール枯渇、リース更新・解放（DIT-02〜08） | `NOT RUN` | NOT RUN | — | — |
| 監視統合 | `app_node_exporter_targets`へ`dhcp-01`追加、Prometheusで`up=1`確認 | `NOT RUN` | NOT RUN | — | — |
| 障害復旧 | DIT-09サービス停止復旧、必要に応じてDIT-11バックアップ・復元 | `NOT RUN` | NOT RUN | — | — |
| 後処理 | 一時リース・テストデータ削除、最終状態取得 | `NOT RUN` | NOT RUN | — | — |

結果は`PASS / FAIL / BLOCKED / NOT RUN`のいずれかとし、実行コマンド、主要出力、exit code、所要時間を日付付きevidenceへ残します。

## 4. 試験集計

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・構成試験（DUT） | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 構築・結合試験（DIT） | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| セキュリティ試験（DST） | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| ネットワーク実機検証（DNW） | `NOT SET` | 0 | 0 | 0 | `NOT SET` | `NOT SET` |
| 合計（必須31 ID） | `NOT SET` | 0 | 0 | 0 | `NOT SET` | [試験仕様書・結果票](06-test-specification.md) |

集計値は個別結果票（[試験仕様書・結果票](06-test-specification.md)のDUT-01〜05、DIT-01〜11、DST-01〜06、DNW-01〜09）から転記し、合計が31件に一致することを確認します。対象ホストが違う結果や、別commitの結果を合算しません。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 影響 | 対応 / 承認 |
| --- | --- | --- | --- | --- |
| OS / kernel | [パラメータシート](03-parameter-sheet.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| CPU / memory / disk | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |
| IP / DNS / route | [ネットワーク設計](04-network-ip-plan.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| isc-dhcp-serverパッケージversion | [パラメータシート](03-parameter-sheet.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| DHCPプール・予約・オプション値（range / routers / dns / domain-name / lease time） | [パラメータシート](03-parameter-sheet.md)参照 | `NOT RUN` | `NOT SET` | `NOT SET` |
| port / firewall | 同上 | `NOT RUN` | `NOT SET` | `NOT SET` |

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
| 対象ホストの新規構築・冪等性（DUT-01〜05、DIT-01） | NOT RUN | 対象ホストで`dhcp.yml`と単体・構成試験を実行 |
| DORA・固定予約・プール枯渇・リース更新解放の実機試験（DIT-02〜08） | NOT RUN | クライアントVMを用意し[立ち上げ・受け入れ手順](10-host-bringup-and-acceptance.md)を実行 |
| サービス停止復旧・バックアップ復元（DIT-09、DIT-11） | NOT RUN | 復旧演習とバックアップ復元演習を実施しRTOを記録 |
| 監視統合の実測（DIT-10） | NOT RUN | `app_node_exporter_targets`へ`dhcp-01`を追加し`site.yml`再適用後、Prometheusで`up=1`を確認 |
| セキュリティ試験（DST-01〜06） | NOT RUN | 対象ホストで[試験仕様書・結果票](06-test-specification.md)のDST試験を実行 |
| rogue DHCP非存在の確認（DST-06、DNW-09） | NOT RUN | 構築直前と構築後の双方で実施し記録 |
| 実管理端末・DNS・UFWの実機検証（DNW-01〜09） | NOT RUN | [ネットワーク実機検証手順](09-network-validation-procedure.md)を実行 |
| Kea DHCPへの移行検討 | NOT RUN | 発展的な設計・将来構想。isc-dhcp-serverのEOLを踏まえた次のステップとして、本案件の対象外のまま[基本設計書](01-basic-design.md)に記録 |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 構成コード（`ansible/roles/dhcp_server/`、`ansible/playbooks/dhcp.yml`） | 40桁commit SHA: `NOT SET` | NOT SET |
| 設計・パラメータ | `docs/build-package-dhcp/` | NOT SET |
| 試験結果・実行ログ | `NOT SET` | NOT SET |
| 運用ランブック | [引き渡しチェックリスト](07-handover-checklist.md)の運用クイックリファレンス | NOT SET |
| backup / restore手順 | `dhcpd.conf`とリースDB（`/var/lib/dhcp/dhcpd.leases`）のバックアップ・復元手順（[詳細設計書](02-detailed-design.md)） | NOT SET |
| 変更 / rollback記録 | `NOT SET` | NOT SET |
| 秘密値の受け渡し・再発行方法 | 本パックは秘密値を扱わない（[構築手順書](05-build-procedure.md)参照）。値そのものは記載しない | NOT SET |

## 9. 完了・受領判定

- [ ] 必須試験（DUT-01〜05、DIT-01〜11、DST-01〜06、DNW-01〜09の合計31 ID）がすべて`PASS`で、結果票と集計が一致する
- [ ] `FAIL` / `BLOCKED` / 必須の`NOT RUN`が残っていない
- [ ] 設計差異、障害、残存リスク（単一DHCPサーバー構成のため冗長化なし、isc-dhcp-serverが開発元EOLでKea DHCPへの将来移行が未着手であることを含む）、未解決Issueを説明した
- [ ] 一時リース・テストデータを撤去し、最終状態を採録した
- [ ] rollbackまたはrestoreの開始条件と連絡先を共有した
- [ ] [引き渡しチェックリスト](07-handover-checklist.md)を完了した

| 判定 | 値 |
| --- | --- |
| 作業完了 | `NOT READY` |
| 引き渡し可否 | `NOT READY` |
| 判定理由 | 必須試験と受領情報が未記入 |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 承認者 | `NOT SET` |
