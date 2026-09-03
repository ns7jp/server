# 詳細設計書

本書は[基本設計書](01-basic-design.md)を受け、`wsus-01`(Windows Server 2022 Standard、Desktop Experience基準)側のコンポーネント構成・配備手順・アクセス制御・ログ監視・バックアップ/ロールバックを定義する。既存ADドメイン(`ad-dc01`、`ad-dc02`)・中央監視host(論理名`monitor-01`)側は変更しない。フェーズ1/フェーズ2の区分は[要件定義書](00-requirements.md)のとおりで、フェーズ2は未実装3点が解消するまで`BLOCKED`である。

## コンポーネント設計

| コンポーネント | 役割 | 正常性確認方法 |
| --- | --- | --- |
| WSUSロール | Microsoft Update同期、更新プログラムの承認・配布、IIS専用サイト(既定8530/HTTP)での公開。依存先はIIS・WID・`Servers`OU参加 | `Get-Service WsusService`が`Running`(SUT-03)。`wsusutil postinstall`実行済みでコンソールが正常起動(SUT-02、SIT-01) |
| WID(Windows Internal Database。SQL Serverを別途用意せず使えるWindows同梱の軽量データベース機能) | SUSDB(更新メタデータ・承認状態・クライアント登録情報)の格納。名前付きパイプ(`\\.\pipe\MICROSOFT##WID`)経由のみでポート不要 | 構成ウィザードがSUSDB接続でエラーなく完了(SIT-01) |
| IIS(WsusPool) | WSUS管理サイト(8530/HTTP)のホスティング。コンテンツ配信・クライアント通信・コンソールAPIを提供 | `Get-IISAppPool WsusPool`でアイドルタイムアウト0・キュー長2000・メモリ制限0を確認(SNW-06) |
| GPO(`WSUS-Client-Policy`) | `Servers`OUへリンクし、自動更新の構成・更新サービスの場所・クライアント側ターゲティングを配布 | `gpresult /r`で適用を確認、グループポリシー操作ログにエラーなし。`wsus-01`がWSUSコンソールの`Servers`グループへ自己登録(SIT-04) |
| windows_exporter | ホスト/IISメトリクス公開(`cpu, cs, logical_disk, net, os, service, iis`) | フェーズ1: `curl.exe http://localhost:9182/metrics`が200(SUT-04でSHA256検証)。フェーズ2: 中央Prometheusで`up`確認(SIT-09、`BLOCKED`) |

## 配備設計

フェーズ1はAnsible role化されていないため、[構築手順書](05-build-procedure.md)のPowerShell手順による「済(手動)」が中心である。

1. **OS初期設定・Firewall先行設定**: コンピューター名、timezone(`Asia/Tokyo`)、Dドライブ(100GB以上)確保、PowerShell 7.4系導入(SUT-05)を行う。Default Inbound Blockを確認しWinRM(5986/tcp、管理元CIDR限定)を先行許可、RDP(3389/tcp)は既定Disableとする。
2. **ドメイン参加**: `Add-Computer -DomainName corp.example.test`後、`Move-ADObject`で`Computers`コンテナから`Servers`OUへ移動する(FR-01、SUT-01、SIT-01)。参加後Firewallプロファイルは自動的に`Domain`となる。
3. **WSUSロール導入**: `Install-WindowsFeature -Name UpdateServices -IncludeManagementTools`でWSUS本体機能とWID接続用サブ機能を導入する(系統A)。コンテンツストアは`D:\WSUS\WSUSContent`とし、Cドライブには置かない。コンソールを初めて開く前に`wsusutil postinstall CONTENT_DIR=D:\WSUS\WSUSContent`でコンテンツディレクトリを初期化する。忘れるとコンソール起動時にエラーになる、実務でよくあるつまずきである(FR-02、SUT-02、SUT-03、SIT-01)。
4. **IIS(WsusPool)チューニング**: アイドルタイムアウト0、キュー長2000程度、プライベートメモリ制限0を設定する。運用上広く知られた推奨設定である(NFR-07、SNW-06)。
5. **同期設定**: Microsoft Updateを直接の同期元(スタンドアロン/ルート、プロキシ対象外)とし、言語・製品・分類は[パラメータシート](03-parameter-sheet.md)の値に絞る。「更新プログラムをこのサーバーに保存する」を有効にし承認操作が実配信を制御できるようにする。同期は毎日01:00(Asia/Tokyo)、初回はメタデータ取得だけでも相応の時間を要する(FR-03、NFR-05、SIT-03)。
6. **GPO設計**: `WSUS-Client-Policy`を作成し`Servers`OUへリンクする(ドメイン直下・`_Tier0-Admins`OUへは広げない)。「自動更新を構成する」はオプション3(自動ダウンロードを行い、インストールの通知を行う)を選択する。オプション4の自動インストール・自動再起動ではなく通知にとどめ、無人再起動によるサービス影響を避ける安全側の判断とする。「イントラネット Microsoft 更新サービスの場所を指定する」に検出・統計両方で`http://wsus-01.corp.example.test:8530`を設定する。「クライアント側ターゲティングを有効にする」の対象グループ名は`Servers`とし、WSUSコンソール側のグループ名と一致させる。検出頻度は既定のまま変更しない(FR-04、SIT-04)。
7. **コンピューターグループ・承認ルール**: `すべてのコンピューター`配下に`Servers`グループを手動作成(ADのOUとは別概念)、その下にサブグループ`Pilot`を作成し`wsus-01`自身を所属させる。自動承認ルール「Critical and Security Updates - Pilot Auto-Approve」(分類: Critical/Security Updates、製品: Windows Server 2022、対象: Pilot)を作成するが、無人承認を避けるためスケジュール化はせず手動実行にとどめる。他は手動承認とする(FR-05、NFR-08、SIT-05、SIT-06)。
8. **クリーンアップ・バックアップ登録**: `Invoke-WsusServerCleanup`を毎週日曜03:00(Asia/Tokyo)にタスクスケジューラへ登録する(FR-06、SIT-07)。バックアップは本書後段を参照(FR-07、SIT-08)。
9. **windows_exporter導入**: 署名付きMSIを`Get-FileHash`でSHA256検証のうえ(SUT-04)導入し、`--collectors.enabled`に`cpu, cs, logical_disk, net, os, service, iis`を指定する。バージョンは実機決定時に固定するため現時点`NOT SET`。
10. **中央監視統合(フェーズ2、`BLOCKED`)**: `app_node_exporter_targets`への追記と`site.yml`再適用自体は「済(自動)」だが、[Windows版](../build-package-windows/02-detailed-design.md)・[AD版](../build-package-ad/02-detailed-design.md)と共通の3点(Windows対応Ansible roleの不在、`compose.yaml`のmonitoring networkの`internal: true`制約、Windows向けログ集約経路の不在)が解消するまで`BLOCKED`である。理由付けは両パックと同一とし作り替えない(FR-08、SIT-09)。

動作確認はフェーズ1でSUT-01〜05、SIT-01〜08、SST-01〜06、SNW-01〜09、フェーズ2でSIT-09(`BLOCKED`前提)を実施する。判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とする。

## アクセス制御

Firewallルールは許可送信元を管理元CIDR・内部ネットワークCIDR・中央Prometheus hostのIPのいずれかに限定する。既定はDefault Inbound Blockで、明示的に許可した通信のみを通す。ドメイン参加後のFirewallプロファイルは`Domain`である(AD版・Windows版と同じ挙動)。

| 経路 | 公開範囲 | 認証 |
| --- | --- | --- |
| WinRM(HTTPS) | 管理元CIDR限定 | 証明書 または Kerberos/Negotiate(Basic無効、SST-02) |
| RDP | 既定Disable | Windowsログオン資格情報 + NLA必須(SST-03) |
| WSUSコンテンツ(8530/tcp) | 内部ネットワークCIDR限定 | ネットワーク制限とGPOのクライアント側ターゲティングで管理(SST-04) |
| windows_exporter | 中央Prometheus hostのIPのみ(`NOT SET`) | 認証なし、ネットワーク制限のみ |
| AD認証・名前解決 | 内部ネットワークCIDR限定 | Kerberos/NTLM。[AD版パック](../build-package-ad/02-detailed-design.md)のポート一式を再利用 |

送信はMicrosoft Update同期用HTTPS(443/tcp、宛先は「Microsoft Update関連エンドポイント」にとどめる)と、AD認証・名前解決用の内部ネットワークCIDR向け通信を許可する。プロキシ経由の同期は対象外(直接接続)である。

## ログ・監視設計

Windows Event Log/IISログは中央Lokiへ未送信である(Grafana Alloy for Windows未導入、フェーズ2`BLOCKED`)。一次切り分け順「メトリクス → 直近変更 → ログ → プロセス」はLinux版・Windows版・AD版と共通だが、フェーズ1は次の代替手順による。

- メトリクス: `curl.exe http://localhost:9182/metrics`をローカルから直接確認する(実機ログイン/WinRM経由に限定)。
- 直近変更: [変更・ロールバック計画](08-change-rollback-plan.md)の記録を確認する。
- ログ: `Get-WinEvent`でWindows Event Log(グループポリシー操作ログ含む)、WSUS同期・クリーンアップログ(既定`%ProgramData%\Microsoft\Update Services\LogFiles`)、IISログ(既定`%SystemDrive%\inetpub\logs\LogFiles`)を直接参照する。Lokiでの横断検索は未対応。
- プロセス: `Get-Service WsusService`、`Get-IISAppPool WsusPool`で確認する。
- 承認状況・準拠状況はWSUSコンソールのレポート機能でも確認できる。Windows Server 2016以降ではレポート表示用ランタイムの追加インストールが必要になる場合がある(NFR-08、SIT-06)。

一次切り分けの記録様式は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)を共用する。

## バックアップ・ロールバック

- SUSDB(WID)は、WIDのローカル名前付きパイプ経由でのバックアップ、または`wsus-01`全体をWindows Server Backupでシステム状態含め取得する方式のいずれかを設計として示し、実機で選定する。
- コンテンツストアのフォルダー全体(`D:\WSUS\WSUSContent`)、IISのWSUS管理サイト構成もバックアップ対象とする。格納先は別ボリューム推奨とし、実機で決定するため`NOT SET`である。
- `Invoke-WsusServerCleanup`は毎週日曜03:00(Asia/Tokyo)にタスクスケジューラへ登録する(FR-06、SIT-07)。
- 復元試験(SIT-08)はSUSDB・コンテンツストア・IIS構成それぞれについて別ボリューム/別ホストへ復元し内容一致を確認する試験であり、現時点`NOT RUN`である([検証証跡台帳](../evidence/README.md)参照)。
- Windows対応Ansible roleが無いため、ロールバックは優先順位順に次の手段を使う。
  1. VM/ハイパーバイザーのスナップショット復元(Hyper-Vの`Checkpoint-VM`/`Restore-VMCheckpoint`等)を最優先とし、取得タイミングは変更直前とする。
  2. スナップショットが無ければ、変更前に取得したFirewallルールのエクスポート(`netsh advfirewall export`)、GPOバックアップ(`Backup-GPO`)、IIS設定のエクスポートを個別に戻す。
  3. データ破損時は上記バックアップ設計からの復元を使用する。
- Go/No-Go条件・記録様式は[変更・ロールバック計画](08-change-rollback-plan.md)に[Linux版](../build-package/08-change-rollback-plan.md)・[Windows版](../build-package-windows/08-change-rollback-plan.md)・[AD版](../build-package-ad/08-change-rollback-plan.md)と同じ構造で定義する。承認済み更新の適用確認(SIT-05)、自動承認ルールの動作確認(SIT-06)、クリーンアップの正常終了(SIT-07)、バックアップ・リストア(SIT-08)はいずれも日付付きevidenceへ記録するまで`NOT RUN`である。
