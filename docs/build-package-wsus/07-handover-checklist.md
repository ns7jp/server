# 引き渡しチェックリスト

## 引き渡し判定

| 項目 | 状態 |
| --- | --- |
| 文書パック | 作成済み |
| フェーズ1: 単体・設定確認 SUT-01〜05 | `NOT RUN`（対象host未指定） |
| フェーズ1: 初回構築・冪等性 SIT-01・02、Microsoft Update初回同期 SIT-03 | `NOT RUN` |
| フェーズ1: GPO適用・自己登録 SIT-04、承認済み更新の適用 SIT-05、自動承認ルール SIT-06 | `NOT RUN` |
| フェーズ1: クリーンアップウィザード SIT-07、バックアップ・リストア SIT-08 | `NOT RUN` |
| フェーズ1: セキュリティ試験 SST-01〜06 | `NOT RUN` |
| フェーズ1: 対象host/管理端末の network SNW-01〜09 | `NOT RUN` |
| フェーズ1: 構成commit相当の記録 / 設定rollback rehearsal | `NOT RUN`（対象host未指定。Ansible role非対応のため[変更・ロールバック計画兼記録票](08-change-rollback-plan.md)の手動手順で実施） |
| フェーズ2: 中央監視統合 SIT-09 | `BLOCKED`（[要件定義書](00-requirements.md)記載の未実装3点の解消まで解除不可。詳細は[試験仕様書・結果票](06-test-specification.md)） |
| 作業結果報告書 | 原本作成済み。対象ホストの報告は`NOT SET` |
| 必須試験完了（フェーズ1） | `NOT READY` |
| 必須試験完了（フェーズ2） | `BLOCKED`（未実装3点の解消が前提） |
| 受領 | `NOT SET` |

文書が存在するだけでは、未指定の引き渡し対象host（`wsus-01`に相当する実機）を受領可能と判定しません。[試験仕様書・結果票](06-test-specification.md)を対象hostで実施した日付付き結果票を確認してから更新します。[AD版パック](../build-package-ad/README.md)のような実機評価済みの体裁は取らず、[Windows版パック](../build-package-windows/07-handover-checklist.md)と同じ「作成済みだが未実施」の状態を保ちます。フェーズ2が`BLOCKED`のままであること自体は、フェーズ1の受領判定を妨げません。

## 構成と状態

- [ ] 対象ホスト（`wsus-01`）、環境名、Windows Serverのビルド番号（`Get-ComputerInfo`の`OsBuildNumber`）を記録した
- [ ] `Get-ADComputer wsus-01 -Properties DistinguishedName`でコンピューターオブジェクトが既定`Computers`コンテナではなく`Servers`OU配下にあることを確認した（SUT-01）
- [ ] コンテンツストア（`D:\WSUS\WSUSContent`）がDドライブに配置され、`wsusutil postinstall`実行済みでコンソールが正常起動することを確認した（SUT-02、SUT-03、SIT-01）
- [ ] [基本設計書](01-basic-design.md)の構成図と[パラメータシート](03-parameter-sheet.md)を実機値へ更新した
- [ ] フェーズ1の必須試験がすべて`PASS`した（フェーズ2は`BLOCKED`のまま明記する）
- [ ] 未解決Issue、制約、残存リスク（未実装3点、windows_exporterサービスアカウント最小権限化、WSUS通信HTTPS化(8531番)が次点課題であることを含む）を説明した
- [ ] GPO「WSUS-Client-Policy」の対象グループ名がWSUSコンソール側のコンピューターグループ名（`Servers`）と一致していることを確認した（SIT-04）
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、計画対実績と試験集計を記入した

## 運用

- [ ] サービス起動・停止・状態確認コマンド（`WsusService`、`W3SVC`、`windows_exporter`）を引き渡した
- [ ] [運用runbook索引](../runbooks/README.md)を確認した（WSUS固有の手順は本パックの[構築手順書](05-build-procedure.md)を正本とする）
- [ ] 同期スケジュール（毎日01:00 Asia/Tokyo）と、承認状況をWSUSコンソールのレポート機能で確認する手順（レポート表示用ランタイムの追加インストールが必要な場合がある点を含む）を説明した
- [ ] クリーンアップウィザード相当（`Invoke-WsusServerCleanup`、毎週日曜03:00 Asia/Tokyo）とバックアップ3点（SUSDB、コンテンツストア、IIS構成）の格納先（`NOT SET`）を確認した（SIT-07、SIT-08）
- [ ] [変更・ロールバック計画兼記録票](08-change-rollback-plan.md)（一般ルールは[`docs/change-management.md`](../change-management.md)を正本とする）の流れを説明した

## 運用クイックリファレンス

詳細は各文書を正本とし、引き渡し時は実ホストで一度ずつ実行して出力を運用ログへ残します。試験ID接頭辞の意味は次のとおりです。

| 略号 | 意味 |
| --- | --- |
| `SUT` | 単体・設定確認（ドメイン参加、WSUS機能インストール等） |
| `SIT` | 構築・結合試験（構築手順、同期、承認、クリーンアップ、バックアップ等） |
| `SST` | セキュリティ試験（Firewall、WinRM、RDP、権限最小化等） |
| `SNW` | ネットワーク実機検証（interface、DNS、待受port、packet capture等） |

| 目的 | コマンド / 正本 |
| --- | --- |
| サービス状態一括確認 | `Get-Service WsusService, W3SVC, windows_exporter \| Format-Table -AutoSize` |
| GPO再適用（即時適用→適用状況確認→操作ログ） | `gpupdate /force` → `gpresult /r /scope computer` → `Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational" -MaxEvents 20` |
| WSUS同期状況確認 / 手動実行 | `(Get-WsusServer).GetSubscription().GetSynchronizationStatus()` / `.StartSynchronization()` |
| クリーンアップウィザード手動実行 | `Invoke-WsusServerCleanup -CleanupObsoleteUpdates -CleanupUnneededContentFiles -CleanupObsoleteComputers -CompressUpdates -DeclineExpiredUpdates -DeclineSupersededUpdates` |
| `WsusPool`設定確認（アイドルタイムアウト/キュー長/メモリ制限） | `& "$env:windir\System32\inetsrv\appcmd.exe" list apppool WsusPool /text:*` |
| Firewallプロファイル / 許可ルール、WinRM listener確認 | `Get-NetFirewallProfile`、`Get-NetFirewallRule \| Where Enabled -eq 'True'`、`winrm enumerate winrm/config/listener` |
| 直近エラーログ / バックアップ・タスク登録確認 | `Get-WinEvent -LogName System -MaxEvents 20 \| Where LevelDisplayName -eq 'Error'`、`Get-ScheduledTask -TaskName "*Wsus*","*Backup*"` |
| 構築手順 / 試験仕様 / network 調査 | [構築手順書](05-build-procedure.md) / [試験仕様書・結果票](06-test-specification.md) / [ネットワーク実機検証手順](09-network-validation-procedure.md) |

フェーズ2（中央監視統合）に属するコマンド（中央Prometheus/Grafana側の確認）は既存Linux監視host側の運用に含まれるため、[Linux版運用クイックリファレンス](../build-package/07-handover-checklist.md)を参照してください。本表はWindows Server単体（フェーズ1）で完結するコマンドのみを掲載しています。

## 連絡・エスカレーション記入欄

| 条件 | 一次対応 | エスカレーション先 / 期限 |
| --- | --- | --- |
| `WsusService`停止、または同期失敗 | 運用runbook索引に沿って一次切り分け、同期履歴を確認 | `NOT SET` |
| コンテンツストア（Dドライブ）のディスク枯渇兆候 | クリーンアップウィザード手動実行、同期対象言語/製品/分類の見直し | `NOT SET` |
| windows_exporterサービス停止（フェーズ2有効化後はalert相当） | サービス再起動、直近変更確認 | `NOT SET` |
| RDP一時許可の消し忘れ、Firewall許可事故 | 該当ルールを直ちに削除し記録 | `NOT SET` |
| ローカルAdministratorパスワード等の秘密値の漏えい | 外部公開を止め、秘密値を再発行 | `NOT SET` |
| host障害、または復旧見込みがRTO超過 | スナップショット復元判断、状況・影響・次回報告時刻を共有 | `NOT SET` |

## セキュリティ

- [ ] 秘密値（ローカルAdministratorパスワード等）そのものではなく、安全な受け渡し・再発行方法（秘密値台帳経由）を共有した
- [ ] 不要な一時アカウント、テストデータ、Firewallの一時許可（特にRDPの一時許可）を削除した
- [ ] WinRM、Firewall、公開port（SST-01、SST-02、SST-04）を確認し、WinRM許可元が管理元CIDR限定、WSUS管理サイト（8530番）が内部ネットワークCIDR限定であることを採録した
- [ ] ローカルAdministrator名の変更、`WSUS Administrators`ローカルグループのメンバー最小化を確認した（SST-05）
- [ ] windows_exporterサービスの実行アカウント（現状`LocalSystem`）を記録し、最小権限化が継続課題であることを明記した
- [ ] 実ログとスクリーンショットからIP、account ID、秘密値をマスクした

## 定期作業

| 頻度 | 作業 | 記録先 |
| --- | --- | --- |
| 日次 | サービス状態、Firewall許可ルール、直近エラーログ確認 | 運用ログ |
| 週次 | クリーンアップウィザード（毎週日曜03:00 Asia/Tokyo）の実行結果確認、コンテンツストア空き容量確認、パッチ承認レビュー（手動承認対象の棚卸し） | 週次レビュー |
| 月次 | 自動承認ルールの動作確認、同期スケジュール実行結果確認、未処理alert（フェーズ2有効化後） | drill記録 |
| 四半期 | SUSDB・コンテンツストアのバックアップ復元試験、アクセス棚卸し（ローカルAdministrator / `WSUS Administrators`メンバー） | 記録 |

## 受領記録

| 項目 | 値 |
| --- | --- |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 対象環境 | `NOT SET` |
| 対象フェーズ（フェーズ1のみ / フェーズ1+2） | `NOT SET` |
| 未解決事項 | `NOT SET` |
| 関連 Issue / PR | `NOT SET` |
| 対象ホストのビルド番号 / WSUSロールのバージョン / コンテンツストア空き容量 | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| 中央inventory適用commit SHA（フェーズ2有効化時、`app_node_exporter_targets`追記分） | `NOT SET` |
| 試験結果票 / network 結果票 / 変更・rollback記録 / 作業結果報告書 | `NOT SET` |
| 秘密値受け渡し完了（値は記載しない） | `NOT SET` |
