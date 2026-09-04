# OS・WSUS パラメータシート

> 💡 **初めて読む方へ**: この文書はOS・ドメイン参加・WSUS(Windows Server Update Services)の具体的な設定値を一覧にした表である。「設計値」と「実績値」の違いは[初心者ガイド](beginner-guide.md#03-パラメータシート)で先に確認してほしい。

値の正本は、フェーズ1(ホスト単体構築)については本パックのPowerShell手順([構築手順書](05-build-procedure.md))、フェーズ2(中央監視統合)については中央側の既存Ansible変数(`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`)である。この表はレビューと引き渡し用の索引であり、既存ADドメイン(`ad-dc01`・`ad-dc02`)側の設計値は[AD版パラメータシート](../build-package-ad/03-parameter-sheet.md)、中央監視host(論理名 monitor-01)側の設計値は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を正本とする。

「設計値」は本パックの設計文書またはコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値である。実績欄の`NOT RUN`を、設計値から推測して埋めない。フェーズ2の項目は[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`であり、値が決まっていても実行結果としては数えない。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-WSUS-001` |
| 対象環境 | 検証(基準)。引き渡し時に実環境名へ置換 |
| 対象ホスト | `wsus-01`(論理名)。FQDNは`wsus-01.corp.example.test`(ADドメイン参加により確定)。実IPは`NOT SET` |
| 依存パック(既存ADドメイン、変更なし) | `SM-AD-001`。`ad-dc01`・`ad-dc02`、ドメイン`corp.example.test`。詳細は[AD版パラメータシート](../build-package-ad/03-parameter-sheet.md) |
| 中央監視host(既存、変更なし) | `monitor-01`(論理名)。詳細は[Linux版パラメータシート](../build-package/03-parameter-sheet.md) |
| 設定値の正本(フェーズ1) | 本パックのPowerShell手順([構築手順書](05-build-procedure.md))。Ansible role化はされておらず「済(手動)」の範囲 |
| 設定値の正本(フェーズ2) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数(「済(自動)」で追加できる唯一の項目)。その他のフェーズ2項目は「未実装」 |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用手順書バージョン / commit SHA | `NOT SET` — branch名ではなく本リポジトリの40桁commit SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname(論理名) | `wsus-01` | `NOT RUN` | 本書 / `hostname`、`Get-ComputerInfo`の`CsName` |
| FQDN | `wsus-01.corp.example.test`(ADドメイン参加のため、AD統合DNSゾーン`corp.example.test`に自動登録される) | `NOT RUN` | `Resolve-DnsName` / `whoami /fqdn` |
| IPv4 / prefix(例示) | `192.0.2.52/24`(TEST-NET-1、RFC 5737の例示用アドレス。[AD版パック](../build-package-ad/03-parameter-sheet.md)の`ad-dc01`=`192.0.2.50/24`、`ad-dc02`=`192.0.2.51/24`と同一レンジで、重複を避けるため`.52`を使用) | `NOT RUN` | 本書 / `Get-NetIPAddress` |
| IPアドレスの割り当て方式 | 静的固定IP | `NOT RUN` | `Get-NetIPAddress` |
| default gateway | 環境ごとに決定 | `NOT RUN` | `Get-NetRoute` |
| DNSリゾルバー | AD統合DNS(`ad-dc01`・`ad-dc02`)を優先/セカンダリで指定 | `NOT RUN` | `Get-DnsClientServerAddress` |
| 管理元CIDR(WinRM/RDP用) | 例示管理端末IP`192.0.2.40`を含むCIDRを環境ごとに決定 | `NOT RUN` | Windows Defender Firewallルールの送信元 |
| 内部ネットワークCIDR(WSUSコンテンツ・AD認証用) | [AD版パック](../build-package-ad/03-parameter-sheet.md)で定義した概念をそのまま使用。将来ドメインへ参加するすべてのホストが所属しうる範囲、環境ごとにNOT SET | `NOT RUN` | Windows Defender Firewallルールの送信元 |
| WinRM port | `5986/tcp`(HTTPS) | `NOT RUN` | `winrm enumerate winrm/config/listener` |
| RDP port | `3389/tcp`(既定Disable) | `NOT RUN` | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` |
| timezone | `Asia/Tokyo` | `NOT RUN` | `Get-TimeZone` |
| OSビルド番号 | 実機決定 | `NOT RUN` | `winver` / `Get-ComputerInfo`の`OsBuildNumber` |

## OS

| 項目 | 設定値 | 理由 | 正本 |
| --- | --- | --- | --- |
| OS | Windows Server 2022 Standard、Desktop Experience(基準) | GUI管理コンソール(WSUSコンソール含む)を前提とするため。Server Coreは検討課題として対象外 | 本書 |
| PowerShell | 組込5.1 + PowerShell 7.4系を追加導入([Windows版パック](../build-package-windows/03-parameter-sheet.md)・[AD版パック](../build-package-ad/03-parameter-sheet.md)と同じ方針) | 将来のAnsible `ansible.windows` collection利用の前提 | `$PSVersionTable` / `pwsh -v` |
| CPU / メモリ / OSボリューム(C:)/ コンテンツストア(D:) | 4 vCPU / メモリ8GB / C:80GB / D:100GB以上 | 他パック(2 vCPU / 4GB / 60GB)より重い理由: WSUSはMicrosoft Update全メタデータの取得、WID(Windows Internal Database)によるインデックス処理、IIS(同梱Webサーバー機能)による大容量コンテンツ配信を1台で担うため | 本書 / [要件定義書](00-requirements.md) |
| Firewall実装 | Windows Defender Firewall(`netsh advfirewall`または`New-NetFirewallRule`) | 既定機構で完結させるため | `Get-NetFirewallRule` |
| Firewallプロファイル | ドメイン参加により既定で`Domain`([AD版パック](../build-package-ad/03-parameter-sheet.md)・[Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ挙動) | ドメインコントローラーへ到達できるインターフェースは自動的に`Domain`プロファイルへ分類されるため | `Get-NetFirewallProfile` |
| Antivirus | Windows Defender Antivirus(既定有効) | 追加導入せず既定機構を使う | `Get-MpComputerStatus` |
| 追加の強制アクセス制御機構 | 該当なし(SELinuxに相当する機構は既定では使用しない) | — | — |

## ドメイン参加・GPO設定値

| 項目 | 設計値 | 実績値 | 正本 |
| --- | --- | --- | --- |
| 参加先ドメイン | `corp.example.test`([AD版パック](../build-package-ad/README.md)が正本、既存・変更なし) | `NOT RUN` | `Get-ADDomain` |
| 参加コマンド | `Add-Computer -DomainName corp.example.test -Restart` | `NOT RUN` | [構築手順書](05-build-procedure.md) |
| コンピューターオブジェクトの配置先 | 既定の`CN=Computers`コンテナではなく、`OU=Servers,DC=corp,DC=example,DC=test`(AD版パックが定義した6OU構成のうちの1つ)へ`Move-ADObject`で明示的に移動 | `NOT RUN` | `Get-ADComputer wsus-01 -Properties DistinguishedName` |
| GPO名 | `WSUS-Client-Policy`(新規作成) | `NOT RUN` | `Get-GPO -Name WSUS-Client-Policy` |
| GPOリンク先 | `Servers`OUのみ。ドメイン直下・`_Tier0-Admins`OUへは広げすぎない設計判断 | `NOT RUN` | `Get-GPInheritance -Target "OU=Servers,DC=corp,DC=example,DC=test"` |
| 「自動更新を構成する」 | 有効、オプション3(自動ダウンロードを行い、インストールの通知を行う)。オプション4(自動インストール・自動再起動)は選ばない。無人再起動によるサービス影響を避ける安全側の設計判断 | `NOT RUN` | `gpresult /h` の出力、または対象ホストのレジストリ確認 |
| 「イントラネット Microsoft 更新サービスの場所を指定する」 | 有効。検出サービスの場所・統計サーバーの場所の両方に`http://wsus-01.corp.example.test:8530`を設定 | `NOT RUN` | 同上 |
| 「クライアント側ターゲティングを有効にする」 | 有効。対象グループ名`Servers`。WSUSコンソール側で作成するコンピューターグループ名と一致させる必要がある | `NOT RUN` | 同上 |
| 自動更新の検出頻度 | 既定値のまま変更しない | — | — |
| GPO適用の即時反映コマンド | `gpupdate /force` | `NOT RUN` | 対象ホスト |
| GPO適用状況の確認コマンド | `gpresult /r /scope computer`(または`/h`でHTMLレポート出力) | `NOT RUN` | 対象ホスト |
| GPO適用確認ログ | イベントログ「グループポリシー操作ログ」(`Microsoft-Windows-GroupPolicy/Operational`) | `NOT RUN` | `Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational"` |

ここでの「対象グループ名`Servers`」はAD側のOUではなく、WSUSコンソール内で別途作成するコンピューターグループの名前である。両者を混同しやすい点は「コンピューターグループ・承認ルール」節で扱う。

## ユーザー・グループ・権限

| 項目 | 設定値 | 理由 | 正本 |
| --- | --- | --- | --- |
| ローカルAdministrator名 | 既定名(`Administrator`)から変更して運用。実際の名称は`NOT SET`(実機決定時に秘密値台帳へ記録) | 既定名のまま残すと自動化された総当たり攻撃の的になりやすいため | 本書「OS」節 |
| ドメイン参加操作アカウント | ドメイン参加操作権限を持つAD側アカウント(ドメインAdministrator、または委任された権限を持つアカウント) | Tier0の考え方([AD版パック](../build-package-ad/03-parameter-sheet.md))を踏襲し、常用アカウントでの参加は避ける | `Get-ADUser` |
| `WSUS Administrators`ローカルグループ | WSUSロール導入時に自動作成。メンバーは最小限(既定でローカル`Administrators`が含まれる) | WSUSコンソール操作権限の範囲を限定するため | `Get-LocalGroupMember "WSUS Administrators"` |
| `WSUS Reporters`ローカルグループ | WSUSロール導入時に自動作成。参照専用(レポート閲覧のみ)の権限用。本パックでは未使用 | 参照専用ロールを分離できる余地を残すため | `Get-LocalGroupMember "WSUS Reporters"` |
| IISアプリケーションプール(`WsusPool`)の実行アカウント | 既定(Network Service)のまま使用 | コンテンツディレクトリへのアクセスとWSUS APIの認証に必要な既定値のため、変更しない | `Get-IISAppPool WsusPool`のProcessModel |
| windows_exporterサービス実行アカウント | 既定`LocalSystem` | MSIインストーラーの既定のまま。最小権限化は継続課題として記録 | `Get-CimInstance Win32_Service`の`StartName` |
| RDPログオン許可ユーザー | 既定Disableのため対象なし。一時有効化時のみ管理元アカウントを許可 | RDPは既定Disable(NFR-04) | `Get-LocalGroupMember "Remote Desktop Users"` |

## ディスク・ファイルシステム

本パックは、他パック(2 vCPU / 4GB / 60GB単一ボリューム基準)より重い最小構成を要求する。OSボリューム(C:)とコンテンツストア専用ボリューム(D:)を分離する設計とする。

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| ファイルシステム | NTFS(C:・D:とも) | 本書 |
| OSボリューム(C:) | 80GB以上 | `Get-Volume` |
| コンテンツストア専用ボリューム(D:) | 100GB以上。OSボリュームとは分離し、Cドライブにコンテンツストアを置かない | 同上 |
| コンテンツストアの配置パス | `D:\WSUS\WSUSContent` | [構築手順書](05-build-procedure.md) |
| ボリューム縮小 | **禁止**([Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ方針。`Resize-Partition`等での縮小運用は行わない) | 本書 |
| 既存データのあるディスクの再利用 | **拒否**(初期化前提。既存パーティションの上書き運用はしない) | 本書 |
| ディスク暗号化(BitLocker等) | 本パックの範囲外 | `NOT SET` |

### 実機記入欄(ディスク)

| 項目 | 値 | 記録日 |
| --- | --- | --- |
| C:(OSボリューム)サイズ / 空き容量 | `NOT RUN` | — |
| D:(コンテンツストア)サイズ / 空き容量 | `NOT RUN` | — |
| ファイルシステム | `NOT RUN` | — |
| ドライブレター / マウントポイント | `NOT RUN` | — |
| `D:\WSUS\WSUSContent`配下の実使用容量(初回同期後) | `NOT RUN` | — |

## WSUSロール・IIS・WID

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| ロールインストールコマンド | `Install-WindowsFeature -Name UpdateServices -IncludeManagementTools`(WSUS本体機能とWID接続用サブ機能を同時に有効化。系統A) | [構築手順書](05-build-procedure.md) |
| データベース方式 | 系統A: WID(Windows Internal Database。既定・本パックの基準)。系統B(外部SQL Server)は差分のみ記載し対象外。詳細は[基本設計書](01-basic-design.md)2.1節 | 同上 |
| WID接続方式 | ローカル名前付きパイプ(`MICROSOFT##WID`への接続)経由のみ。ネットワークポートを使わない | 同上 |
| WSUS管理サイト | IISの既定サイト(80/443)とは別の専用サイト。既定ポート`8530/tcp`(HTTP)・`8531/tcp`(HTTPS)。WSUS 3.0 SP2以降の標準仕様であり、旧バージョンが80/443を使っていたことと混同しない | 同上 |
| 本パックの既定 | HTTP(`8530/tcp`)。HTTPS化(`8531/tcp`、証明書配布)は、内部CA(AD証明書サービス)がこのラボに存在しないため対象外・次点課題 | [要件定義書](00-requirements.md) |
| コンテンツストア配置先 | `D:\WSUS\WSUSContent`(OSボリュームとは別のDドライブ配下。Cドライブに置かない) | [構築手順書](05-build-procedure.md) |
| 「更新プログラムをこのサーバーに保存する」 | 有効(ローカル保存)。これにより承認操作が実際の配信を制御できるようになる | 同上 |
| コンテンツディレクトリ初期化コマンド | `wsusutil.exe postinstall CONTENT_DIR=D:\WSUS\WSUSContent`。ロールインストール後、管理コンソールを初めて開く前に実行が必要。忘れるとコンソール起動時にエラーになる、実務でよくあるつまずき | 同上 |
| IISアプリケーションプール名 | `WsusPool` | `Get-IISAppPool WsusPool` |
| WsusPool アイドルタイムアウト | `0`分(アイドル後のプール停止による直後のクライアント同期失敗を避ける、運用上広く知られた設定) | 同上 |
| WsusPool キュー長 | `2000`程度(既定の1000から引き上げ。多数クライアントの同時アクセスによる503エラーを避ける) | 同上 |
| WsusPool プライベートメモリ制限 | `0`(無制限。既定のリサイクルによる同期処理中断を避ける) | 同上 |

### ソフトウェア・バージョン基準

| 対象 | 設定値 | 正本 |
| --- | --- | --- |
| OS | Windows Server 2022 Standard、Desktop Experience(基準) | 本書「OS」節 |
| PowerShell | 組込5.1 + PowerShell 7.4系 | 同上 |
| WSUSロール(UpdateServices) | OS付属機能。個別のversion pinningは行わない | 本節 |
| WID(Windows Internal Database) | OS付属機能。バージョンはOSに付随 | 本節 |
| IIS(WSUS管理サイトのホスト) | OS付属Web-Server機能 | 本節 |
| windows_exporter | `NOT SET`(実機決定時にGitHub ReleasesのMSIとそのSHA256を記録して固定する。[Windows版パック](../build-package-windows/03-parameter-sheet.md)・[AD版パック](../build-package-ad/03-parameter-sheet.md)と同じ考え方) | 「実機記入欄」参照 |
| Windows Server Backup | OS付属機能(`wbadmin`) | 「バックアップ設計」節 |
| WSUSコンソール用レポート表示ランタイム | `NOT SET`(Windows Server 2016以降のWSUSコンソールでレポート機能を使うには、別途レポート表示用ランタイムの追加インストールが必要になる場合がある。NFR-08) | [構築手順書](05-build-procedure.md) |

## 同期設定(製品・分類・言語・スケジュール)

| 項目 | 設計値 | 正本 |
| --- | --- | --- |
| アップストリームサーバー | このWSUSサーバーが最初かつ唯一のWSUSサーバーであるため、レプリカ/ダウンストリーム構成は取らず、Microsoft Updateを直接の同期元とする(スタンドアロン/ルート) | [基本設計書](01-basic-design.md) |
| プロキシ | ラボでは直接接続とし、プロキシ経由の設定は対象外 | 同上 |
| 同期対象言語 | 英語・日本語のみ(不要な言語は同期しない。コンテンツストア容量を抑えるための判断) | WSUSコンソール「オプション」→「更新プログラムファイルと言語」 |
| 同期対象製品 | Windows Server 2022、Windows 11のみ(ラボで検証する製品に絞り、無制限に同期しない) | WSUSコンソール「オプション」→「製品と分類」 |
| 同期対象分類 | Critical Updates、Security Updates、Updates、Update Rollupsのみ。Drivers・Feature Packs等は除外(ドライバー同期はコンテンツが肥大化しやすく、サーバー用途では基本的に不要) | 同上 |
| 同期スケジュール | 毎日01:00(Asia/Tokyo)の自動同期 | WSUSコンソール「オプション」→「同期スケジュール」 |
| 初回同期の所要時間 | 選択した製品・分類のメタデータ取得だけでも相応の時間がかかる。具体的な所要時間は断定しない | [構築手順書](05-build-procedure.md) |

## コンピューターグループ・承認ルール

ADの組織単位(OU)と、WSUSコンソール内の「コンピューターグループ」は別の概念である。初心者が混同しやすいポイントであり、「ドメイン参加・GPO設定値」節の解説も参照すること。

| 項目 | 設計値 | 実績値 | 正本 |
| --- | --- | --- | --- |
| コンピューターグループ`Servers` | 「すべてのコンピューター」の下に手動で作成。GPOのクライアント側ターゲティングの対象グループ名と一致させる | `NOT RUN` | WSUSコンソール「コンピューター」ノード |
| サブグループ`Pilot` | `Servers`の下に作成。段階的展開の受け皿。本パックでは`wsus-01`自身を`Pilot`にも所属させる | `NOT RUN` | 同上 |
| 自動承認ルール名 | `Critical and Security Updates - Pilot Auto-Approve` | `NOT RUN` | WSUSコンソール「オプション」→「自動承認」 |
| 自動承認ルールの条件 | 分類がCritical UpdatesまたはSecurity Updates | `NOT RUN` | 同上 |
| 自動承認ルールの対象製品 | Windows Server 2022 | `NOT RUN` | 同上 |
| 自動承認ルールの対象グループ | `Pilot` | `NOT RUN` | 同上 |
| 自動承認ルールのスケジュール化 | **有効化しない**。手動実行にとどめる。無人承認による意図しない適用を避ける安全側の判断 | `NOT RUN` | 同上 |
| それ以外の更新プログラム | 手動承認 | `NOT RUN` | WSUSコンソール「更新プログラム」ノード |

## 監視・ログ

フェーズ2(中央監視統合)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`である。値自体は設計として決まっているが、実行結果としては数えない。

| 項目 | 設定値(設計) | 状態 | 正本 |
| --- | --- | --- | --- |
| windows_exporter scrape interval | 中央の既存`linux-node` jobの設定(15秒)を流用予定 | `BLOCKED`(SIT-09。Dockerホストと`wsus-01`の実ネットワーク接続・Firewall許可先が未検証のため) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets` |
| ログ集約 | Grafana Alloy for Windows経由で既存Lokiへ集約する設計のみ(WSUS同期・クリーンアップログ、Windows Event Log、IISログを含む) | `BLOCKED`(Alloy for Windows未導入のため) | [詳細設計書](02-detailed-design.md) |
| WSUSコンソールのレポート機能(承認状況・準拠状況の確認) | フェーズ1の範囲で確認可能な設計。Windows Server 2016以降のWSUSコンソールでレポート機能を使うには、別途レポート表示用ランタイムの追加インストールが必要になる場合がある(NFR-08) | 設計のみ、`NOT RUN` | [構築手順書](05-build-procedure.md) |
| 可用性SLO / latency SLO | `wsus-01`個別の数値目標は未設定 | `NOT SET`(フェーズ2有効化後に既存[SLO](../slo.md)へ統合予定) | — |

## バックアップ設計

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| バックアップ対象(1) SUSDB(WID) | WIDのローカル名前付きパイプ経由でのバックアップ、または対象ホスト全体をWindows Server Backupでシステム状態含めて取得する方式のいずれかを設計として示し、実機で選定する | [詳細設計書](02-detailed-design.md) |
| バックアップ対象(2) コンテンツストア | フォルダー全体(`D:\WSUS\WSUSContent`) | 同上 |
| バックアップ対象(3) IIS構成 | WSUS管理サイトの構成一式 | 同上 |
| クリーンアップウィザード相当コマンドレット | `Invoke-WsusServerCleanup` | [構築手順書](05-build-procedure.md) |
| クリーンアップのスケジュール | 毎週日曜03:00(Asia/Tokyo)、Task Schedulerに登録 | 同上 |
| バックアップスケジュール | `NOT SET`(実機で決定) | 同上 |
| バックアップ格納先 | `NOT SET`(別ボリューム推奨。実機で決定) | 同上 |
| 復元試験方法 | SUSDB・コンテンツストア・IIS構成それぞれについて別ボリューム/別ホストへ復元し、内容が一致することを確認する(SIT-08) | [試験仕様書・結果票](06-test-specification.md) |

## 配備パス・サービス

| 対象 | 設計値 | 確認方法 |
| --- | --- | --- |
| WSUSロールインストール先 | OS既定パス(`%ProgramFiles%\Update Services\`を想定。実機で確定) | `Get-WindowsFeature UpdateServices` |
| WSUS管理サイト名 | `WSUS Administration`(ロール導入時にIIS上へ自動作成される既定名) | `Get-Website` |
| コンテンツストア配置先 | `D:\WSUS\WSUSContent` | `wsusutil postinstall`実行ログ / エクスプローラー |
| WSUSサービス名 | `WsusService` | `Get-Service WsusService` |
| windows_exporterインストール先 | MSI既定パス(`C:\Program Files\windows_exporter\`を想定。実機で確定) | `Get-Service windows_exporter` / インストーラログ |
| windows_exporterサービス名 | `windows_exporter` | `Get-Service` |
| クリーンアップ用Task Schedulerタスク名 | `NOT SET`(実装時に決定) | `Get-ScheduledTask` |
| WSUS同期・クリーンアップログ | 既定`%ProgramData%\Microsoft\Update Services\LogFiles\` | エクスプローラー / `Get-Content` |
| IISログ格納先 | 既定`%SystemDrive%\inetpub\logs\LogFiles\`(変更しなければ既定のまま) | `Get-WebConfigurationProperty` |
| 主要ログ | Windows Event Log(Application / System / Security / グループポリシー操作ログ)、WSUS同期・クリーンアップログ、IISログ | `Get-WinEvent` / 各ログファイル |

## 公開ポート

| Port | Proto | Service | 方向 | 許可範囲(設計) | 用途 |
| --- | --- | --- | --- | --- | --- |
| 5986 | TCP | WinRM(HTTPS) | 受信 | 管理元CIDR限定 | 構築・運用管理 |
| 8530 | TCP | WSUS管理サイト(HTTP、本パックの既定) | 受信 | 内部ネットワークCIDR限定 | WSUSコンテンツ配信・クライアント通信・コンソールAPI |
| 8531 | TCP | WSUS管理サイト(HTTPS) | 受信 | 対象外・次点課題(`NOT SET`。内部CA未導入) | HTTPS化した場合のみ |
| 9182 | TCP | windows_exporter | 受信 | 中央Prometheus hostのIPのみ許可(認証なし、値は`NOT SET`) | host / IISメトリクス |
| 3389 | TCP | RDP | 受信 | 既定Disable。一時許可時のみ管理元CIDR限定 | 障害時の代替アクセス |

### 送信(アウトバウンド)

| 宛先 | Port | Proto | 用途 |
| --- | --- | --- | --- |
| Microsoft Update関連エンドポイント(個別FQDNは列挙しない) | 443 | TCP(HTTPS) | Microsoft Updateとの同期(毎日01:00) |
| 内部ネットワークCIDR([AD版パック](../build-package-ad/03-parameter-sheet.md)が定義したポート一式を再利用) | 53, 88, 123, 135, 389, 445, 464等 | TCP/UDP | AD認証(Kerberos/LDAP)・名前解決・SYSVOL経由のGPO配布 |

Windows Defender Firewallは既定Default Inbound Blockとし、上表の受信経路のみを個別に許可する。ドメイン参加によりFirewallプロファイルは既定で`Domain`になる([AD版パック](../build-package-ad/03-parameter-sheet.md)・[Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ注記)。

## 実機記入欄

下表は引き渡し対象hostごとの記入欄なので、未指定の現時点では`NOT RUN`を維持する。記録時は[検証証跡台帳](../evidence/README.md)の様式に従い、日付付きのevidenceファイルへ分けて記録する。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OSビルド番号(`winver` / `Get-ComputerInfo`の`OsBuildNumber`) | `NOT RUN` | — | — |
| ドメイン参加確認(`Get-ADComputer wsus-01`のDistinguishedName) | `NOT RUN` | — | — |
| WSUS機能インストール確認(`Get-WindowsFeature UpdateServices`) | `NOT RUN` | — | — |
| WSUSサービス起動確認(`Get-Service WsusService`) | `NOT RUN` | — | — |
| `wsusutil postinstall`実行結果 | `NOT RUN` | — | — |
| 初回同期の所要時間・取得コンテンツ量 | `NOT RUN` | — | — |
| GPO適用・`wsus-01`自己登録確認(WSUSコンソール`Servers`グループ) | `NOT RUN` | — | — |
| 自動承認ルールの動作確認結果 | `NOT RUN` | — | — |
| クリーンアップウィザード実行結果 | `NOT RUN` | — | — |
| SUSDB・コンテンツストアのバックアップ/リストア所要時間 | `NOT RUN` | — | — |
| CPU / memory / disk(ラボVMの割り当て値) | `NOT RUN` | — | — |
| ディスク構成(`Get-Volume` / `Get-Disk`) | `NOT RUN` | — | — |
| Windows Defender Firewallの許可範囲(`Get-NetFirewallRule`) | `NOT RUN` | — | — |
| windows_exporter version / SHA256 | `NOT RUN` | — | — |
| PowerShell version(`$PSVersionTable`) | `NOT RUN` | — | — |
| 適用手順書バージョン / commit SHA | `NOT RUN` | — | — |
