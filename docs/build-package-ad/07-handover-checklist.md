# 引き渡しチェックリスト

> 💡 **初めて読む方へ**: この文書は作業を依頼者に引き渡す前の最終確認リストです。案件パック全体の地図は[初心者ガイド](beginner-guide.md#07-引き渡しチェックリスト)を参照してください。

## 引き渡し判定

| 項目 | 状態 |
| --- | --- |
| 文書パック | 作成済み |
| フェーズ1: 単体・設定確認 AUT-01〜04 | `NOT RUN` |
| フェーズ1: 新規フォレスト作成・初回DC昇格 AIT-01 / 昇格後必須サービス確認 AIT-02 | `NOT RUN`（対象host未指定） |
| フェーズ1: AD統合DNSゾーンでの名前解決 AIT-03 | `NOT RUN` |
| フェーズ1: OU/既定ドメインGPOのパスワードポリシー適用確認 AIT-04 | `NOT RUN` |
| フェーズ1: FSMO確認 AIT-05 | `NOT RUN` |
| フェーズ1: System Stateバックアップ取得 AIT-06 / ADごみ箱によるオブジェクト復元 AIT-07 | `NOT RUN` |
| フェーズ1: サービス停止復旧演習 AIT-08 | `NOT RUN` |
| フェーズ1: 対象host/管理端末のnetwork ANW-01〜09（AIT-10） | `NOT RUN` |
| フェーズ1: 再実行安全性 AIT-11 | `NOT RUN` |
| フェーズ1: セキュリティ試験 AST-01〜08 | `NOT RUN` |
| フェーズ1: 構成commit相当の記録 / 設定rollback rehearsal | `NOT RUN`（対象host未指定。Ansible role非対応のため[変更・ロールバック計画](08-change-rollback-plan.md)の手動手順で実施） |
| フェーズ2: host/ADメトリクスscrape AIT-09 | `BLOCKED`（`compose.yaml`の`monitoring` networkが`internal: true`のため解消まで解除不可。[要件定義書](00-requirements.md)記載の未実装3点、[試験仕様書・結果票](06-test-specification.md)参照） |
| 作業結果報告書 | 原本作成済み。対象ホストの報告は `NOT SET` |
| 必須試験完了（フェーズ1） | `NOT READY` |
| 必須試験完了（フェーズ2） | `BLOCKED`（[要件定義書](00-requirements.md)記載の「未実装」3点の解消が前提） |
| 受領 | `NOT SET` |

文書が存在するだけでは、未指定の引き渡し対象host（`ad-dc01`に相当する実機）を受領可能と判定しません。[試験仕様書・結果票](06-test-specification.md)を対象hostで実施した日付付き結果票を確認してから更新します。

フェーズ2の行は、未実装3点が解消されるまで恒久的に`BLOCKED`です。前提が揃っていないことを理由に安易に`PASS`や`NOT RUN`へ書き換えないでください。`BLOCKED`のままであること自体は、フェーズ1（ホスト単体構築）の受領判定を妨げません。

## 構成と状態

- [ ] 対象ホスト（`ad-dc01`）、環境名、Windows Serverのビルド番号（`winver`または`Get-ComputerInfo`の`OsBuildNumber`）を記録した
- [ ] [基本設計書](01-basic-design.md)の構成図と[パラメータシート](03-parameter-sheet.md)を実機値へ更新した
- [ ] フェーズ1の必須試験がすべて`PASS`した（フェーズ2は[試験仕様書・結果票](06-test-specification.md)の終了判定に従い`BLOCKED`のまま明記する）
- [ ] 未解決Issue、制約、残存リスク（「未実装」3点、`Domain Admins`等特権グループメンバーの最小化継続確認(AST-07)、windows_exporterサービスアカウントの最小権限化(AST-07相当の継続課題)を含む）を説明した
- [ ] 監視対象（windows_exporterのAD/DNS collectorによるhost/ADメトリクス）、閾値、通知先、対応時間帯を説明した（フェーズ2区間は`BLOCKED`である旨を併記する）
- [ ] DSRMパスワード等の秘密値の受け渡し方法（秘密値台帳経由、リポジトリには記載しない）を確認した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、計画対実績と試験集計を記入した

## 運用

- [ ] サービス起動・停止・状態確認コマンド（NTDS、DNS、Netlogon、Kdc、W32Time、windows_exporter）を引き渡した
- [ ] [運用runbook索引](../runbooks/README.md)を確認した（AD DS固有の手順は本パックの[構築手順書](05-build-procedure.md)を正本とする）
- [ ] サービス停止復旧演習（AIT-08）を実施し、RTOを記録した
- [ ] System Stateバックアップ（毎日03:30 Asia/Tokyo、保持14世代、AIT-06）と、ADごみ箱によるオブジェクト復元（AIT-07）の手順を確認した
- [ ] [変更・ロールバック計画](08-change-rollback-plan.md)（スナップショット復元を最優先手段とする）の流れを説明した

## 運用クイックリファレンス

詳細は各文書を正本とし、引き渡し時は実ホストで一度ずつ実行して出力を運用ログへ残します。

| 目的 | コマンド / 正本 |
| --- | --- |
| サービス状態一括確認 | `Get-Service NTDS, DNS, Netlogon, Kdc, W32Time, windows_exporter \| Format-Table -AutoSize` |
| 停止中サービス抽出 | `Get-Service \| Where-Object Status -ne 'Running'` |
| FSMO確認 | `netdom query fsmo` |
| パスワードポリシー確認 | `Get-ADDefaultDomainPasswordPolicy` |
| 特権グループメンバー確認 | `Get-ADGroupMember "Domain Admins"` |
| windows_exporter smoke test | `Invoke-WebRequest -Uri http://localhost:9182/metrics -UseBasicParsing \| Select-Object StatusCode` |
| Firewallプロファイル状態 | `Get-NetFirewallProfile \| Select-Object Name, Enabled, DefaultInboundAction` |
| Firewall許可ルール確認 | `Get-NetFirewallRule \| Where-Object Enabled -eq 'True' \| Select-Object DisplayName, Direction, Action` |
| WinRM listener確認 | `winrm enumerate winrm/config/listener` |
| 直近エラーログ（System） | `Get-WinEvent -LogName System -MaxEvents 20 \| Where-Object LevelDisplayName -eq 'Error'` |
| 直近エラーログ（Directory Service） | `Get-WinEvent -LogName "Directory Service" -MaxEvents 20 \| Where-Object LevelDisplayName -eq 'Error'` |
| バックアップ実行状況 | `wbadmin get versions` |
| バックアップTask Scheduler登録確認 | `Get-ScheduledTask -TaskName "*Backup*" \| Select-Object TaskName, State` |
| 構築手順 | [構築手順書](05-build-procedure.md) |
| 試験仕様・結果票 | [試験仕様書・結果票](06-test-specification.md) |
| runbook一覧 / 共通前提 | [運用runbook索引](../runbooks/README.md) |
| backup / restore一般ルール | [`docs/backup-restore.md`](../backup-restore.md) |
| 変更 / rollback | [変更・ロールバック計画](08-change-rollback-plan.md) |
| network 調査 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

フェーズ2（中央監視統合）に属するコマンド（中央Prometheus/Grafana側の確認）は、既存Linux監視host側の運用に含まれるため[Linux版運用クイックリファレンス](../build-package/07-handover-checklist.md)を参照してください。本表はWindows Server単体（フェーズ1）で完結するコマンドのみを掲載しています。

## 連絡・エスカレーション記入欄

| 条件 | 一次対応 | エスカレーション先 / 期限 |
| --- | --- | --- |
| NTDS / DNS / Netlogon等ディレクトリサービス関連サービス停止 | 運用runbook索引に沿って一次切り分け、AIT-08手順を参照 | `NOT SET` |
| windows_exporterサービス停止（フェーズ2有効化後はalert相当） | サービス再起動、直近変更確認 | `NOT SET` |
| RDP一時許可の消し忘れ、Firewall許可事故 | 該当ルールを直ちに削除し記録 | `NOT SET` |
| DSRMパスワード・ローカルAdministratorパスワード等の漏えい | 外部公開を止め、秘密値を再発行 | `NOT SET` |
| host障害（VM / ハイパーバイザー障害） | スナップショット復元判断、RPOの確認 | `NOT SET` |
| 復旧見込みがRTO超過 | 状況、影響、次回報告時刻を共有 | `NOT SET` |

## セキュリティ

- [ ] 秘密値（DSRMパスワード、ローカルAdministratorパスワード等）そのものではなく、安全な受け渡し・再発行方法（秘密値台帳経由）を共有した
- [ ] 不要な一時アカウント、テストデータ、Firewallの一時許可（特にRDPの一時許可）を削除した
- [ ] WinRM、Firewall、公開port(AST-01, AST-08)を確認し、WinRM許可元が管理元CIDR限定で管理されていることを採録した
- [ ] windows_exporterサービスの実行アカウント（現状`LocalSystem`）を記録し、最小権限化がAST-07相当の継続課題であることを明記した
- [ ] 実ログとスクリーンショットからIP、account ID、秘密値をマスクした

## 定期作業

| 頻度 | 作業 | 記録先 |
| --- | --- | --- |
| 日次 | NTDS / DNS / Netlogon / windows_exporterサービス状態、Firewall許可ルール、直近エラーログ確認 | 運用ログ |
| 週次 | disk使用量増加、未処理alert（フェーズ2有効化後）、Windows Update適用状況 | 週次レビュー |
| 月次 | サービス停止復旧演習（AIT-08）、通知試験（フェーズ2有効化後） | drill記録 |
| 四半期 | System Stateバックアップ復元試験（AIT-06）、ADごみ箱復元試験（AIT-07）、アクセス棚卸し（`Domain Admins`等特権グループメンバー） | 記録 |

## 受領記録

| 項目 | 値 |
| --- | --- |
| 引き渡し日時 | `NOT SET` |
| 引き渡し元 / 先 | `NOT SET` |
| 対象環境 | `NOT SET` |
| 対象フェーズ（フェーズ1のみ / フェーズ1+2） | `NOT SET` |
| 未解決事項 | `NOT SET` |
| 関連 Issue / PR | `NOT SET` |
| 対象ホストのビルド番号（`OsBuildNumber`） | `NOT SET` |
| DSRMパスワード受け渡し完了（値は記載しない） | `NOT SET` |
| windows_exporter バージョン / SHA256 | `NOT SET` |
| 中央inventory適用commit SHA（フェーズ2有効化時、`app_node_exporter_targets`追記分） | `NOT SET` |
| 試験結果票 | `NOT SET` |
| network 結果票 | `NOT SET` |
| 変更 / rollback 記録 | `NOT SET` |
| 作業結果報告書 | `NOT SET` |