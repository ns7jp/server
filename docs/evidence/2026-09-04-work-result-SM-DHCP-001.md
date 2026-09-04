# 作業結果・引き渡し報告書 — SM-DHCP-001（2026-09-04 記入版）

[原本](../build-package-dhcp/11-work-result-report.md)をコピーし、AI支援セッションのサンドボックスコンテナ上での`dhcp_server` role実測結果を記入したものです。この報告は本パックの正本（VM/実機での実演）ではなく、それを補う追加証跡であることに注意してください。範囲の詳細は[構築・試験結果票](2026-09-04-dhcp-build-validation.md)の「この証跡が示す範囲」を参照してください。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件ID | `SM-DHCP-001` |
| 変更ID / チケット | `NOT SET`（AI支援セッションでの検証作業） |
| 作業目的 | `dhcp_server` roleとplaybookの機能実測（DORA、固定予約、プール枯渇、リース更新・解放、バックアップ復元）。VM/実機が用意できない環境での代替検証 |
| 対象環境 / ホスト | AI支援セッションのサンドボックスコンテナ自身（`dhcp-01`役）。VM/実機ではない |
| 作業者 / 確認者 | ns7jp（AI支援セッション） |
| 作業予定日時 | 2026-09-04 |
| 作業実績日時 | 2026-09-04 |
| 対象commit SHA | `27fc7ec8f1cfe41e03466ba859647b0f66b836a0` |
| 変更前の正常commit SHA | 同上（コード変更を伴わない検証作業） |
| 作業結果 | 部分`PASS`（DHCP機能面は実測完了。セキュリティ強化・監視統合は環境制約により未実施） |
| 関連Issue / PR | 本評価結果を含むPR（作成後にリンクを追記） |

作業ツリーに未コミット差分はありません（`git status --short`で確認済み）。

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | NOT SET | コード変更を伴わない検証作業のため、通常の変更管理プロセスは対象外 |
| 管理端末からSSH / sudoが利用可能 | PASS（代替） | `ansible_connection: local`でコンテナ自身へsudo（`become: true`）が利用可能なことを確認 |
| コンソール等の代替接続手段を確認 | NOT RUN | 単一コンテナのため代替接続手段の概念なし |
| 対象SHAとrollback SHAを固定 | PASS | `27fc7ec8f1cfe41e03466ba859647b0f66b836a0`（コード変更なし） |
| `dhcpd.conf`とリースDBのbackup / 復元ポイントを確認 | PASS | DIT-11で実施・確認済み（[結果票](2026-09-04-dhcp-build-validation.md)） |
| 同一セグメントにrogue DHCPサーバーが存在しないことを確認（NFR-08） | PASS（構築後のみ） | DST-06/DNW-09（[結果票](2026-09-04-dhcp-build-validation.md)） |
| Go / No-Go条件を確認 | NOT SET | — |

## 3. 計画対実績

| 工程 | 予定操作 | 実績開始–終了 / 所要時間 | 結果 | 証跡 | 差異・備考 |
| --- | --- | --- | --- | --- | --- |
| 事前確認 | inventory、疎通、rogue DHCP非存在確認（DST-06）、backup、変更前状態 | 2026-09-04 | PASS（構築後のみのrogue確認） | [結果票](2026-09-04-dhcp-build-validation.md) | 構築直前確認は未実施 |
| 初回構築 | `dhcp.yml`適用（`common` role→`dhcp_server` role） | 2026-09-04 | 部分PASS | 同上 | `common` roleは安全上の理由で未適用。`dhcp_server` role単独で適用し、systemdタスクのみ環境制約でfailed |
| 冪等性 | `dhcp.yml` 2回目、`changed=0` | 2026-09-04 | PASS（非systemdタスクのみ） | 同上 | systemdタスク以外の6タスクが`changed=0`を実測 |
| 構築後確認 | `dhcpd -t`構文検査、systemd状態、待受port、UFW、AppArmor | 2026-09-04 | 部分PASS | 同上 | 構文検査・待受portはPASS。systemd状態・UFW・AppArmorはBLOCKED（環境制約） |
| DORA・払い出し実機試験 | DORA実測、固定予約、プール枯渇、リース更新・解放（DIT-02〜08） | 2026-09-04 | PASS | 同上 | 全項目実測PASS |
| 監視統合 | `app_node_exporter_targets`へ`dhcp-01`追加、Prometheusで`up=1`確認 | — | NOT RUN | — | `monitor-01`が本環境に存在しない |
| 障害復旧 | DIT-09サービス停止復旧、DIT-11バックアップ・復元 | 2026-09-04 | PASS | 同上 | RTO実測: 停止復旧約2.06秒、バックアップ復元約3.12秒（いずれも手動操作込みの参考値） |
| 後処理 | 一時リース・テストデータ削除、最終状態取得 | 2026-09-04 | PASS | 同上 | プール範囲・lease時間を設計値へ復元し再適用済み |

## 4. 試験集計

集計元は[2026-09-04構築・試験結果票](2026-09-04-dhcp-build-validation.md)です。

| 区分 | 対象件数 | PASS | FAIL | BLOCKED | NOT RUN | 結果票 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 単体・構成試験（DUT） | 5 | 4 | 0 | 1（DUT-04） | 0 | [結果票](2026-09-04-dhcp-build-validation.md) |
| 構築・結合試験（DIT） | 11 | 9 | 0 | 1（DIT-01、非systemdタスクは実測PASS相当） | 1（DIT-10） | 同上 |
| セキュリティ試験（DST） | 6 | 2 | 0 | 3（DST-01/03/05） | 1（DST-04） | 同上 |
| ネットワーク実機検証（DNW） | 9 | 7 | 0 | 1（DNW-07） | 1（DNW-03） | 同上 |
| 合計（必須31 ID） | 31 | 22 | 0 | 6 | 3 | [試験仕様書・結果票](../build-package-dhcp/06-test-specification.md) |

**DHCPプロトコル動作とAnsible roleの機能面（DUT-01〜03/05、DIT-01〜09/11、DST-02/06、DNW-01/02/04〜06/08/09）は22/22実測`PASS`。** 残るBLOCKED/NOT RUNは、このサンドボックス環境に実systemd・AppArmor・journald・`monitor-01`が無いこと、および安全上の理由で`common` roleを適用しなかったことに起因する。役割・playbookの実装上の欠陥は見つかっていない。

## 5. 設計値と実績値の差異

| 項目 | 設計値 | 実績値 | 差異の理由 |
| --- | --- | --- | --- |
| OS / kernel | Ubuntu Server 24.04 LTS | Ubuntu 24.04.4 LTS、kernel `6.18.44-fc-v24` | 差異なし（同一メジャーバージョン） |
| `dhcp-01`静的IP | `192.168.50.5/24` | `192.168.50.5/24`（veth手動設定） | 差異なし |
| isc-dhcp-serverパッケージversion | 設計はversion固定なし（`isc-dhcp-server`パッケージ名のみ指定） | `4.4.3-P1-4ubuntu2`（noble/universe） | 差異なし |
| DHCPプール・予約・オプション値 | [パラメータシート](../build-package-dhcp/03-parameter-sheet.md)参照 | 最終状態はすべて設計値と一致（プール`100-200`、lease `43200`/`86400`、DNS/gateway/domain-name） | 差異なし（検証中一時的に縮小プール・短縮lease時間を使用したが、試験後に復元） |
| port / firewall | UFW default deny、UDP67限定許可 | UFW `inactive`（未適用） | `common` role未適用（安全上の理由）。BLOCKED、承認された既知の差異 |

## 6. 障害・課題・再試験

| ID | 発生時刻 | 事象 / 影響 | 原因 | 対応 | 再試験 | Issue |
| --- | --- | --- | --- | --- | --- | --- |
| SBX-01 | 2026-09-04 | bridge経由のDORAブロードキャストが`veth-d01`まで届かなかった | `net.bridge.bridge-nf-call-iptables=1`により`FORWARD`チェーンのdefault DROP policyが適用され、別フェーズの残存Docker iptables状態の影響を受けた | `br-dhcp50`向けの最小限ACCEPTルールを追加 | 済み（以後のDORA試験はすべて成功） | — |
| SBX-02 | 2026-09-04 | Ansible `Enable and start isc-dhcp-server`タスクが毎回失敗 | サンドボックスに実systemd（PID1）が無い | 環境制約として受容。DORA実演のためだけにAnsible管理外で手動`service`コマンドを使用 | 該当なし（VM/実機では発生しない事象） | — |

切り分けの詳細は[構築・試験結果票](2026-09-04-dhcp-build-validation.md)の「見つかった構築上のつまずき」を参照してください。role/playbookコード自体の欠陥は見つかっていないため、[欠陥台帳](defects-found.md)への追加はありません。

## 7. 残存リスク

| リスク | 影響 | 対応方針 |
| --- | --- | --- |
| VM/実機（正本）での構築・DORA実演が未実施 | 本証跡はDHCP機能面の代替検証にとどまり、本パックの完了条件（[README](../build-package-dhcp/README.md)の完了の定義）は満たしていない | [10-host-bringup-and-acceptance.md](../build-package-dhcp/10-host-bringup-and-acceptance.md)の手順でVM/実機を用意し、正本の検証を別途実施する |
| セキュリティ強化（UFW/AppArmor/SSH hardening/監査ログ）が未検証 | `common` role適用後の実際のセキュリティ姿勢が未確認 | VM/実機で`common`→`dhcp_server`の完全な2play構成を適用して検証する |
| 中央監視統合（DIT-10）が未検証 | `up{host="dhcp-01"}=1`が未確認 | `monitor-01`が存在する環境で`app_node_exporter_targets`へ追加後に検証する |
| rogue DHCP確認が構築後のみ | 構築直前の確認手順が未実証 | VM/実機での正本検証時に、構築直前・構築後の両方を手順どおり実施する |

## 8. 引き渡し物

| 成果物 | 対象版 / 保存先 | 受領確認 |
| --- | --- | --- |
| 構成コード（`ansible/roles/dhcp_server/`、`ansible/playbooks/dhcp.yml`） | 40桁commit SHA: `27fc7ec8f1cfe41e03466ba859647b0f66b836a0`（本検証でコード変更なし） | 検証環境での動作確認済み |
| 設計・パラメータ | `docs/build-package-dhcp/` | 実績値を[パラメータシート](../build-package-dhcp/03-parameter-sheet.md)へ反映済み |
| 試験結果・実行ログ | [構築・試験結果票](2026-09-04-dhcp-build-validation.md)、[ネットワーク実機検証結果票](2026-09-04-network-host-validation-dhcp.md) | 本報告書に記録 |
| 運用ランブック | [引き渡しチェックリスト](../build-package-dhcp/07-handover-checklist.md)の運用クイックリファレンス | NOT SET（VM/実機での正本検証待ち） |
| backup / restore手順 | DIT-11で実測（[結果票](2026-09-04-dhcp-build-validation.md)） | 動作確認済み |
| 変更 / rollback記録 | `NOT SET` | NOT SET |
| 秘密値の受け渡し・再発行方法 | 本パックは秘密値を扱わない | 該当なし |

## 9. 完了・受領判定

- [ ] 必須試験（DUT-01〜05、DIT-01〜11、DST-01〜06、DNW-01〜09の合計31 ID）がすべて`PASS`で、結果票と集計が一致する → **未達（22/31、詳細は4節）**
- [x] `FAIL`は残っていない（`BLOCKED`/`NOT RUN`は6+3件残るが、いずれも環境制約または意図的な未適用によるもの）
- [x] 設計差異、障害、残存リスクを説明した（5〜7節）
- [x] 一時リース・テストデータを撤去し、最終状態（設計値どおりのプール・lease時間）を採録した
- [ ] rollbackまたはrestoreの開始条件と連絡先を共有した → VM/実機での正本検証時に実施
- [ ] [引き渡しチェックリスト](../build-package-dhcp/07-handover-checklist.md)を完了した → 未達

| 判定 | 値 |
| --- | --- |
| 作業完了 | `NOT READY`（DHCP機能面の実測は完了。本パックの完了条件全体は未達） |
| 引き渡し可否 | `NOT READY` |
| 判定理由 | セキュリティ強化・監視統合・VM/実機での正本検証が未実施のため |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 承認者 | `NOT SET` |
