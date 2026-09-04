# OS・ミドルウェア パラメータシート

値の正本は、フェーズ1(ホスト単体構築)については本パックのPowerShell手順([構築手順書](05-build-procedure.md))、フェーズ2(中央監視統合)については中央側の既存Ansible変数(`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`)です。この表はレビューと引き渡し用の索引であり、中央監視host(論理名 monitor-01)側の設計値は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を正本とします。

「設計値」は本パックの設計文書またはコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値です。実績欄の`NOT RUN`を、設計値から推測して埋めません。フェーズ2の項目は[要件定義書](00-requirements.md)に記載の未実装事項が解消するまで`BLOCKED`または`NOT RUN`であり、値が決まっていても実行結果としては数えません。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-WIN-001` |
| 対象環境 | 検証(基準)。引き渡し時に実環境名へ置換 |
| 対象ホスト | `monitor-win-01`(論理名)。実FQDN / IPは`NOT SET` |
| 中央監視host(既存、変更なし) | `monitor-01`(論理名)。詳細は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を参照 |
| 設定値の正本(フェーズ1) | 本パックのPowerShell手順([構築手順書](05-build-procedure.md))。Ansible role化はされておらず「済(手動)」の範囲 |
| 設定値の正本(フェーズ2) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数(「済(自動)」で追加できる唯一の項目)。その他のフェーズ2項目は「未実装」 |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用手順書バージョン / commit SHA | `NOT SET` — branch名ではなく本リポジトリの40桁commit SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname(論理名) | `monitor-win-01` | `NOT RUN` | 本書 / `hostname`、`Get-ComputerInfo`の`CsName` |
| FQDN(例示) | `monitor-win.example.test`(RFC 2606の例示用ドメイン) | `NOT RUN` | 本書 / `Resolve-DnsName`、`ipconfig /all` |
| IPv4 / prefix(例示) | `192.0.2.30`(TEST-NET-1、RFC 5737の例示用アドレス) | `NOT RUN` | 本書 / `Get-NetIPAddress` |
| default gateway | 環境ごとに決定 | `NOT RUN` | `Get-NetRoute` |
| DNS resolver | 環境ごとに決定 | `NOT RUN` | `Get-DnsClientServerAddress` |
| 管理元CIDR | 例示管理端末IP`192.0.2.40`を含むCIDRを環境ごとに決定 | `NOT RUN` | Windows Defender Firewallルールの送信元(`Get-NetFirewallRule` + `Get-NetFirewallAddressFilter`) |
| 管理アカウント | 系統A: ローカルAdministrator(改名) / 系統B: ドメイングループ | `NOT RUN` | 本書「OS」節 / `whoami` |
| WinRM port | `5986/tcp`(HTTPS) | `NOT RUN` | `winrm enumerate winrm/config/listener` |
| RDP port | `3389/tcp`(既定Disable) | `NOT RUN` | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` |
| timezone | `Asia/Tokyo` | `NOT RUN` | `Get-TimeZone` |
| OSビルド番号 | 実機決定 | `NOT RUN` | `winver` / `Get-ComputerInfo`の`OsBuildNumber` |

## OS

対象OSの構築は2系統。認証方式・Firewallプロファイル・時刻同期先・更新経路が分かれるため、両方を書きます。片方だけ書くと、もう片方の系統で構築したときに手順書と実物がずれます。ツールの実体(Windows Defender Firewall、W32Time、Windows Update)自体は両系統で共通です。

| 項目 | 系統A: ワークグループ(本パックの既定) | 系統B: ADドメイン参加(参考) | 正本 |
| --- | --- | --- | --- |
| 想定用途 | 個人ラボ・小規模検証 | 実務のエンタープライズ想定(このADドメイン自体の構築は対象外。既存ADに参加させる場合の差分のみ) | 本書 |
| 管理アカウント | ローカルAdministrator(既定名から変更して運用) | ドメイングループ(例: `CORP\ServerAdmins`) | 「ユーザー・グループ・権限」節 |
| WinRM認証 | HTTPSリスナー + 証明書(自己署名 or 内部CA)。Basic / Negotiateの平文相当は無効化 | Kerberos / Negotiate(ドメイン参加により既定で強化される) | WinRMリスナー設定 |
| Firewallプロファイル | Public(検証用途に応じてPrivateへ変更可) | Domain | `Get-NetFirewallProfile` |
| 時刻同期 | W32Time、外部NTP(`time.windows.com`など) | ドメイン階層(PDCエミュレータ経由、`w32tm /query /source`で確認) | `Get-Service W32Time` |
| 更新 | Windows Update(Microsoft Updateから直接、自動ダウンロード・手動再起動が既定) | WSUSまたはグループポリシー経由の集中管理 | Windows Update設定 |

両系統に共通する項目は次のとおりです。

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| OS | Windows Server 2022 Standard、Desktop Experience(基準)。Server Coreは構成の対応を検討中 | 本書 |
| PowerShell | 組込5.1 + PowerShell 7.4系を追加導入(将来のAnsible `ansible.windows` collection利用の前提) | `$PSVersionTable` / `pwsh -v` |
| Firewall実装 | Windows Defender Firewall(`netsh advfirewall`または`New-NetFirewallRule`) | `Get-NetFirewallRule` |
| Antivirus | Windows Defender Antivirus(既定有効) | `Get-MpComputerStatus` |
| 追加の強制アクセス制御機構 | 該当なし(SELinuxに相当する機構は既定では使用しない) | — |
| 自動更新の適用単位 | 系統A: ホスト単位。系統B: WSUS / グループポリシーによる中央管理 | 上表参照 |

## ユーザー・グループ・権限

| 項目 | 設定値 | 理由 | 正本 |
| --- | --- | --- | --- |
| ローカルAdministrator名 | 既定名(`Administrator`)から変更して運用。実際の名称は`NOT SET`(実機決定時に秘密値台帳へ記録) | 既定名のまま残すと自動化された総当たり攻撃の的になりやすいため | 系統Aのみ該当。本書「OS」節 |
| windows_exporterサービス実行アカウント | 既定`LocalSystem` | MSIインストーラの既定のまま。最小権限化はWST-03で継続課題として記録 | `Get-CimInstance Win32_Service`の`StartName` |
| IIS匿名認証アカウント(IUSR) | 既定のまま使用(用途に応じて変更を検討) | 検証用サイトのため既定認証で運用開始 | IIS管理コンソール / `Get-WebConfiguration` |
| ドメイン管理グループ(系統Bのみ) | 例: `CORP\ServerAdmins` | 個人アカウントでなくグループで権限管理するため | 既存AD側の設計(対象外、差分のみ記載) |
| ローカルAdministrators群への追加 | 管理担当者のみ、最小人数 | 過剰な管理者権限の付与を避けるため | `Get-LocalGroupMember Administrators` |
| RDPログオン許可ユーザー | 既定Disableのため対象なし。一時有効化時のみ管理元アカウントを許可 | RDPは既定Disable(NFR-04) | `Get-LocalGroupMember "Remote Desktop Users"` |

## ディスク・ファイルシステム

本パックはOS既定インストール時の単一ボリューム(Cドライブ)構成を基準とします。追加ボリュームを設計する場合のみ、実機記入欄を含めて本節を拡張します。

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| ファイルシステム | NTFS | 本書 |
| ボリューム構成 | OS既定インストール時の単一ボリューム(Cドライブ)を基準。追加ボリュームの要否は用途に応じて個別設計 | `Get-Volume` |
| ボリューム縮小 | **禁止**(Linux版のLVM`shrink: false`相当の方針を踏襲。`Resize-Partition`等での縮小運用は行わない) | 本書 |
| 既存データのあるディスクの再利用 | **拒否**(初期化前提。既存パーティションの上書き運用はしない) | 本書 |
| ディスク暗号化(BitLocker等) | 本パックの範囲外 | `NOT SET` |

### 実機記入欄(ディスク)

| 項目 | 値 | 記録日 |
| --- | --- | --- |
| 対象ボリューム | `NOT RUN` | — |
| サイズ | `NOT RUN` | — |
| ファイルシステム | `NOT RUN` | — |
| ドライブレター / マウントポイント | `NOT RUN` | — |
| 空き容量 | `NOT RUN` | — |

## windows_exporter・IIS

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| windows_exporterインストール方式 | GitHub Releasesの署名付きMSI。導入前に`Get-FileHash`と公開SHA256の一致を確認(WUT-03) | [構築手順書](05-build-procedure.md) |
| windows_exporterバージョン | `NOT SET`(実機決定時にGitHub Releasesの署名付きMSIとそのSHA256を記録して固定する。`compose.yaml`のDocker API proxyのdigest固定と同じ考え方) | 「実機記入欄」参照 |
| 有効化collector | `--collectors.enabled=cpu,cs,logical_disk,net,os,service,system,iis` | [構築手順書](05-build-procedure.md) |
| 実行アカウント | 既定`LocalSystem`(最小権限化はWST-03で継続課題) | 「ユーザー・グループ・権限」節参照 |
| listen | `0.0.0.0:9182`(Windows Defender Firewallで中央Prometheus hostのIPのみ許可、認証なし) | Windows Defender Firewallルール |
| IIS機能 | `Web-Server`機能のうち`Web-Common-Http`、`Web-Mgmt-Console` | `Get-WindowsFeature` |
| IIS監視対象サイト | 検証用サイト1件。health用エンドポイントを提供(サイト名・パスは実装時に決定) | [構築手順書](05-build-procedure.md) |
| PowerShell | 組込5.1 + PowerShell 7.4系追加導入 | 「OS」節参照 |

### ソフトウェア・バージョン基準

| 対象 | 設定値 | 正本 |
| --- | --- | --- |
| OS | Windows Server 2022 Standard、Desktop Experience(基準)。Server Coreは対応検討中 | 本書「OS」節 |
| PowerShell | 組込5.1 + PowerShell 7.4系 | 同上 |
| windows_exporter | `NOT SET`(実機決定時にMSIとSHA256を固定) | 本節 |
| IIS | Windows付属Web-Server機能(`Web-Common-Http`、`Web-Mgmt-Console`) | 本節 |
| Grafana Alloy for Windows | 導入すれば既存`compose.yaml`のAlloyと合わせv1.16.1系を基準にする設計だが、現時点では未実装 | [詳細設計書](02-detailed-design.md) |
| Windows Server Backup | OS付属機能(`wbadmin`) | 「監視・ログ」節 |

windows_exporterは実機決定時にバージョンとSHA256ハッシュをこの表と実機記入欄へ記録し、以後のバージョンアップはWUT-03のハッシュ検証を経て行います。IIS・PowerShellはOS付属またはOS対応バージョンを使うため、個別のversion pinningは行いません。

## 監視・ログ

フェーズ2(中央監視統合)のうち、ログ集約(WIT-06)は[要件定義書](00-requirements.md)に記載の未実装事項(Grafana Alloy for Windows未導入)が解消するまで`BLOCKED`です。windows_exporter scrape(WIT-03)はDockerホスト↔対象ネットワーク間の実L3到達性・windows_exporter側Firewall許可(いずれも`NOT SET`)が確立するまで`BLOCKED`です。blackbox probe(WIT-05)はコード側の制約(`prometheus.yml.j2`のprobe対象汎用化)が解消済みのため、対象ホスト未構築による`NOT RUN`です。値自体は設計として決まっていますが、実行結果としては数えません。

| 項目 | 設定値(設計) | 状態 | 正本 |
| --- | --- | --- | --- |
| windows_exporter scrape interval | 中央の既存`linux-node` jobの設定(15秒)を流用予定 | `BLOCKED`(WIT-03。Dockerホスト↔対象ネットワーク間の実接続・windows_exporter側Firewall許可が確立するまで) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets` |
| blackbox probe interval | 中央の既存blackbox jobの設定(30秒)を流用予定 | `NOT RUN`(WIT-05。`prometheus.yml.j2`の`app_blackbox_probe_targets`によるprobe対象汎用化は実装済み。対象ホスト未構築のため未実施) | [Linux版パラメータシート](../build-package/03-parameter-sheet.md) |
| ログ集約 | Grafana Alloy for Windows経由で既存Lokiへ集約する設計のみ | `BLOCKED`(WIT-06。Alloy for Windows未導入のため) | [詳細設計書](02-detailed-design.md) |
| 可用性SLO / latency SLO | Windows対象ホスト個別の数値目標は未設定 | `NOT SET`(フェーズ2有効化後に既存[SLO](../slo.md)へ統合予定) | — |

### バックアップ設計

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| バックアップ機能 | Windows Server Backup機能(`wbadmin`) | [構築手順書](05-build-procedure.md) |
| バックアップ対象 | IISサイトの内容・設定(`web.config`等)、Firewallルールのエクスポート(`netsh advfirewall export`)、windows_exporterのサービス定義 | 同上 |
| スケジュール | 毎日03:30(Asia/Tokyo)、Task Schedulerに登録 | 同上 |
| 保持世代 | 14日(Linux版の`backup_retention_days`と同じ値) | 同上 |
| 復元試験方法 | 別ボリューム / 別ホストへ復元し、内容が一致することを確認(WIT-09) | [試験仕様書・結果票](06-test-specification.md) |

## 配備パス・サービス

| 対象 | 設計値 | 確認方法 |
| --- | --- | --- |
| windows_exporterインストール先 | MSI既定パス(`C:\Program Files\windows_exporter\`を想定。実機で確定) | `Get-Service windows_exporter` / インストーラログ |
| windows_exporterサービス名 | `windows_exporter` | `Get-Service` |
| IISコンテンツルート | `NOT SET`(実装時に決定。既定は`C:\inetpub\wwwroot\`配下) | IIS管理コンソール / `Get-Website` |
| IISログ格納先 | 既定`C:\inetpub\logs\LogFiles`(変更しなければ既定のまま) | `Get-WebConfigurationProperty` |
| バックアップ格納先 | `NOT SET`(別ボリューム推奨。実機で決定) | Windows Server Backup管理コンソール / `wbadmin get disks` |
| Task Schedulerタスク名(バックアップ) | `NOT SET`(実装時に決定) | `Get-ScheduledTask` |
| 主要ログ | Windows Event Log(Application / System / Security)、IISログ | `Get-WinEvent` / IISログファイル |

## 公開ポート

| Port | Service | Bind / 許可範囲 | 用途 |
| --- | --- | --- | --- |
| 5986/tcp | WinRM(HTTPS) | 管理元CIDR限定 | 構築・運用管理 |
| 3389/tcp | RDP | 既定Disable。一時許可時のみ管理元CIDR限定 | 障害時の代替アクセス |
| 80/tcp, 443/tcp | IIS | 内部 / 管理ネットワークのみ。一般公開しない | 監視対象サイト |
| 9182/tcp | windows_exporter | 中央Prometheus hostのIPのみ許可(認証なし、Linuxのnode-exporterと同じ思想) | host metrics |

## 実機記入欄

下表は引き渡し対象hostごとの記入欄なので、未指定の現時点では`NOT RUN`を維持します。記録時は[検証証跡台帳](../evidence/README.md)の様式に従い、日付付きのevidenceファイルへ分けて記録します。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OSビルド番号(`winver` / `Get-ComputerInfo`の`OsBuildNumber`) | `NOT RUN` | — | — |
| OS系統(系統A: ワークグループ / 系統B: ADドメイン参加) | `NOT RUN` | — | — |
| CPU / memory / disk | `NOT RUN` | — | — |
| ディスク構成(`Get-Volume` / `Get-Disk`) | `NOT RUN` | — | — |
| Windows Defender Firewallの許可範囲(`Get-NetFirewallRule`) | `NOT RUN` | — | — |
| Windows Defenderの状態(`Get-MpComputerStatus`) | `NOT RUN` | — | — |
| windows_exporter version / SHA256 | `NOT RUN` | — | — |
| PowerShell version(`$PSVersionTable`) | `NOT RUN` | — | — |
| 適用手順書バージョン / commit SHA | `NOT RUN` | — | — |
