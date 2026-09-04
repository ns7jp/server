# 引き渡しチェックリスト

> 💡 **初めて読む方へ**: この文書は作業を依頼者に引き渡す前の最終確認リストです。案件パック全体の地図は[初心者ガイド](beginner-guide.md#07-引き渡しチェックリスト)を参照してください。

## 引き渡し判定

| 項目 | 状態 |
| --- | --- |
| 文書パック | 作成済み |
| 単体・構成試験 DUT-01〜05 | サンドボックスラボで全件`PASS`（[結果票](../evidence/2026-09-04-dhcp-build-validation.md)）。独立した実ホストでは`NOT RUN` |
| 新規構築・冪等性 DIT-01 | サンドボックスラボで`PASS`（初回`failed=0`、2回目`changed=0`）。独立した実ホストでは`NOT RUN` |
| DORA実機確認 DIT-02 / 固定予約 DIT-03 | サンドボックスラボで`PASS`。独立した実ホストでは`NOT RUN` |
| プール枯渇 DIT-04 / リース更新 DIT-05 / 再起動後のリース永続化 DIT-06 / リース解放 DIT-07 | サンドボックスラボで`PASS`（DIT-05はRENEW/unicastのみ実測、REBIND分岐は未観測。詳細は[結果票](../evidence/2026-09-04-dhcp-build-validation.md)）。独立した実ホストでは`NOT RUN` |
| オプション配布（gateway・DNS・ドメイン名）DIT-08 | サンドボックスラボで`PASS`。独立した実ホストでは`NOT RUN` |
| サービス停止復旧 DIT-09 | サンドボックスラボで`PASS`（手動RTO ≈ 9秒）。独立した実ホストでは`NOT RUN` |
| 監視統合（node_exporter scrape）DIT-10 | サンドボックスに`monitor-01`が無いため`SKIP-ENV`。独立した実ホストでは`NOT RUN` |
| バックアップ・復元 DIT-11 | サンドボックスラボで`PASS`（RTO ≈ 24秒）。独立した実ホストでは`NOT RUN` |
| セキュリティ試験 DST-01〜06（rogue DHCP確認 DST-06を含む） | サンドボックスラボでDST-01・02・04・06が`PASS`、DST-03（AppArmor）・DST-05（監査ログ）は`SKIP-ENV`。独立した実ホストでは`NOT RUN` |
| 対象host/管理端末の network DNW-01〜09 | サンドボックスラボでDNW-03（DNS）以外`PASS`（[ネットワーク結果票](../evidence/2026-09-04-network-host-validation-dhcp.md)）。独立した実ホストでは`NOT RUN` |
| 構成commit / 設定rollback rehearsal | `NOT RUN`（対象host未指定） |
| 作業結果報告書 | 原本作成済み。対象ホストの報告は `NOT SET` |
| 必須試験完了（DUT/DIT/DST/DNW 合計31 ID） | サンドボックスラボで26 ID `PASS` / 4 ID `SKIP-ENV`。独立した実ホストでは`NOT READY` |
| 受領 | `NOT SET` |

`dhcp_server` roleと`dhcp.yml`playbookが実装済みで静的チェックがPASSしていることは、未指定の引き渡し対象host（`dhcp-01`に相当する実機）を受領可能と判定する材料にはしません。サンドボックスラボでの実測（上表）も、**独立した物理／VPSホストでの受け入れの代替にはしません**。[試験仕様書](06-test-specification.md)を対象hostで実施した日付付き結果票（[記録テンプレート](../evidence/templates/network-host-validation-dhcp.md)を含む）を確認してから、この表を更新します。DST-06（rogue DHCP確認）は[構築手順書](05-build-procedure.md)3.2節の適用前確認と、[ネットワーク実機検証手順](09-network-validation-procedure.md)のDNW-09（構築後の再確認）の両方が揃って初めて完了とみなします。

## 構成と状態

- [ ] 対象ホスト（`dhcp-01`）、環境名、commit SHA を記録した
- [ ] [基本設計書](01-basic-design.md)の構成図と[パラメータシート](03-parameter-sheet.md)を実機値へ更新した（`dhcp_server_interface`に設定した実際のinterface名を含む）
- [ ] 必須試験（DUT-01〜05、DIT-01〜11、DST-01〜06、DNW-01〜09）がすべて `PASS` した
- [ ] 未解決 Issue、制約、残存リスク（単一DHCPサーバー構成のため冗長化なし、isc-dhcp-serverが開発元EOLでKea DHCPへの将来移行が未着手であること、Dockerラボでの払い出し実演が未実装であることを含む）を説明した
- [ ] 監視対象（`dhcp-01`のnode_exporterによるhostメトリクス）、閾値、通知先、対応時間帯を説明した
- [ ] 動的払い出しプール（`192.168.50.100`〜`.200`、101個）と固定IP予約（`dhcp_server_reservations`）の現在の登録内容を説明した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付き evidence へ複製し、計画対実績と試験集計を記入した

## 運用

- [ ] isc-dhcp-serverの起動・停止・状態確認コマンドを引き渡した
- [ ] [運用runbook索引](../runbooks/README.md)を確認した（`dhcp-01`固有の手順は本パックの[構築手順書](05-build-procedure.md)を正本とする。索引側の手順はDocker Compose前提のため、そのままでは適用できない箇所がある点に注意する）
- [ ] サービス停止復旧演習（DIT-09）を実施し、RTO を記録した
- [ ] `dhcpd.conf`とリースDB（`/var/lib/dhcp/dhcpd.leases`）のバックアップ日時、保持方法、復元手順（DIT-11）を確認した
- [ ] 変更申請、事前確認（プール拡張・固定予約追加時のGo/No-Go条件）、ロールバックの流れを説明した

## 運用クイックリファレンス

詳細は各文書を正本とし、引き渡し時は`dhcp-01`実ホストで一度ずつ実行して出力を運用ログへ残します。

| 目的 | コマンド / 正本 |
| --- | --- |
| サービス状態確認 | `sudo systemctl status isc-dhcp-server --no-pager` |
| systemd有効化確認 | `systemctl is-enabled isc-dhcp-server` |
| 設定構文検査 | `sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf` |
| リースDB確認 | `sudo cat /var/lib/dhcp/dhcpd.leases` |
| 待受port確認（UDP 67） | `sudo ss -lunp \| grep :67` |
| 待受port確認（TCP 22/9100） | `sudo ss -lntup` |
| リース割当・解放ログ | `journalctl -u isc-dhcp-server --since today --no-pager` |
| UFW状態 | `sudo ufw status verbose` |
| AppArmor状態 | `sudo aa-status \| grep dhcpd` |
| ファイル権限確認 | `stat -c '%U:%G %a' /etc/dhcp/dhcpd.conf` |
| 構築手順 | [構築手順書](05-build-procedure.md) |
| 試験仕様・結果票 | [試験仕様書](06-test-specification.md) |
| runbook一覧 / 共通前提 | [`docs/runbooks/README.md`](../runbooks/README.md) |
| backup / restore一般ルール | [`docs/backup-restore.md`](../backup-restore.md) |
| 変更 / rollback | [変更・ロールバック計画](08-change-rollback-plan.md) |
| network 調査 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

中央監視統合（Prometheus/Grafana）側の確認コマンドは、既存Linux監視host（`monitor-01`）側の運用に含まれるため[Linux版運用クイックリファレンス](../build-package/07-handover-checklist.md)を参照してください。本表は`dhcp-01`単体で完結するコマンドのみを掲載しています。

## 連絡・エスカレーション記入欄

| 条件 | 一次対応 | エスカレーション先 / 期限 |
| --- | --- | --- |
| isc-dhcp-server停止、新規リース払い出し停止 | [構築手順書](05-build-procedure.md)6節の検知・復旧手順を参照 | `NOT SET` |
| 動的プール枯渇の常態化（DIT-04相当の再発） | プール拡張の要否を判断し、[変更・ロールバック計画](08-change-rollback-plan.md)に従う | `NOT SET` |
| rogue DHCPサーバーの検出（想定外のDHCPOFFER） | クライアント側の応答元IPを特定し、該当サーバーを停止またはセグメント分離 | `NOT SET` |
| UFW / AppArmor設定の消失・無効化 | 直ちに是正し、原因と対応を記録 | `NOT SET` |
| `dhcp-01`host障害 | 復元判断（[08](08-change-rollback-plan.md)参照）、RPOの確認 | `NOT SET` |
| 復旧見込みが RTO 超過 | 状況、影響、次回報告時刻を共有 | `NOT SET` |

## セキュリティ

- [ ] 本パックはAPIトークンやDB資格情報のような秘密値を扱わないことを確認した（[構築手順書](05-build-procedure.md)2節のとおり、`ansible-vault`によるVault暗号化は不要）
- [ ] 不要な一時アカウント、テストデータ（rogue DHCP確認・DORA確認でクライアント検証VMに残った一時リース）、firewallの一時許可を削除した
- [ ] SSH、UFW（UDP 67の許可がinterface `dhcp_server_interface`限定であること）、AppArmor（`usr.sbin.dhcpd`がenforceモード）、公開port（22/tcp、67/udp、9100/tcp）を確認し、SSH許可元が上流FW/VPNまたはsource指定UFW ruleで管理元CIDRのみに限定されていることを採録した
- [ ] `/etc/dhcp/dhcpd.conf`の所有者・権限が`root:root`かつ`0644`以下であることを確認した
- [ ] 実ログとスクリーンショットからIP、MACアドレス、account IDをマスクした

## 定期作業

| 頻度 | 作業 | 記録先 |
| --- | --- | --- |
| 日次 | isc-dhcp-serverの状態、UFW許可、直近のリース割当・解放ログ確認 | 運用ログ |
| 週次 | 動的プールの使用率、固定予約の登録漏れ、未処理alertの確認 | 週次レビュー |
| 月次 | サービス停止復旧演習（DIT-09相当）、rogue DHCP再確認 | drill記録 |
| 四半期 | `dhcpd.conf`とリースDBのバックアップ復元試験（DIT-11）、固定予約・アクセス棚卸し | 記録 |

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
| 作業結果報告書 | `NOT SET` |
| rogue DHCP確認記録（構築直前、NFR-08 / DST-06） | `NOT SET` |
