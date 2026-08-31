# OS・ディレクトリサービス パラメータシート

> 💡 **初めて読む方へ**: この文書はOS・ドメイン・ネットワーク・監視の具体的な設定値を一覧にした表です。「設計値」と「実績値」の違いは[初心者ガイド](beginner-guide.md#03-パラメータシート)で先に確認してください。

値の正本は、フェーズ1(ホスト単体構築)については本パックのPowerShell手順([構築手順書](05-build-procedure.md))、フェーズ2(中央監視統合)については中央側の既存Ansible変数(`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`)です。この表はレビューと引き渡し用の索引であり、中央監視host(論理名`monitor-01`)側の設計値は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を正本とします。

「設計値」は本パックの設計文書またはコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値です。実績欄の`NOT RUN`を、設計値から推測して埋めません。フェーズ2の項目は[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`であり、値が決まっていても実行結果としては数えません。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-AD-001` |
| 対象環境 | 検証(基準)。引き渡し時に実環境名へ置換 |
| 対象ホスト | `ad-dc01`(論理名)。実FQDN / IPは`NOT SET` |
| 中央監視host(既存、変更なし) | `monitor-01`(論理名)。詳細は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を参照 |
| 設定値の正本(フェーズ1) | 本パックのPowerShell手順([構築手順書](05-build-procedure.md))。Ansible role化はされておらず「済(手動)」の範囲 |
| 設定値の正本(フェーズ2) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数(「済(自動)」で追加できる唯一の項目)。その他のフェーズ2項目は「未実装」 |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用手順書バージョン / commit SHA | `NOT SET` — branch名ではなく本リポジトリの40桁commit SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ドメイン

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname(論理名) | `ad-dc01` | `NOT RUN` | 本書 / `hostname`、`Get-ComputerInfo`の`CsName` |
| ドメインFQDN(例示) | `corp.example.test`(RFC 2606の例示用ドメイン`example.test`のサブドメイン) | `NOT RUN` | `Get-ADDomain` / `Resolve-DnsName` |
| NetBIOS名 | `CORP` | `NOT RUN` | `Get-ADDomain`の`NetBIOSName` |
| フォレスト機能レベル | Windows Server 2016(広い互換性を保ちながらAES Kerberos等のセキュリティ機能を使える現実的な最小ライン。引き上げは全DCが対応レベル以上であることを確認してから行う) | `NOT RUN` | `Get-ADForest`の`ForestMode` |
| ドメイン機能レベル | Windows Server 2016 | `NOT RUN` | `Get-ADDomain`の`DomainMode` |
| IPv4 / prefix(例示) | `192.0.2.50/24`(TEST-NET-1、RFC 5737の例示用アドレス。[Windows版パック](../build-package-windows/03-parameter-sheet.md)の`192.0.2.30`と同一レンジ、重複回避のため`.50`を使用) | `NOT RUN` | 本書 / `Get-NetIPAddress` |
| IPアドレスの割り当て方式 | 静的固定IP(DCは動的IPを使用しない) | `NOT RUN` | `Get-NetIPAddress` |
| default gateway | 環境ごとに決定 | `NOT RUN` | `Get-NetRoute` |
| DNSリゾルバー(自ホスト) | `127.0.0.1`(自分自身のAD統合DNSを優先参照) | `NOT RUN` | `Get-DnsClientServerAddress` |
| 管理元CIDR(WinRM/RDP用) | 例示管理端末IP`192.0.2.40`を含むCIDRを環境ごとに決定 | `NOT RUN` | Windows Defender Firewallルールの送信元 |
| 内部ネットワークCIDR(AD DS関連ポート用) | 環境ごとに決定(将来のドメインメンバーが所属しうる範囲) | `NOT RUN` | Windows Defender Firewallルールの送信元 |
| WinRM port | `5986/tcp`(HTTPS) | `NOT RUN` | `winrm enumerate winrm/config/listener` |
| RDP port | `3389/tcp`(既定Disable) | `NOT RUN` | `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"` |
| timezone | `Asia/Tokyo` | `NOT RUN` | `Get-TimeZone` |
| OSビルド番号 | 実機決定 | `NOT RUN` | `winver` / `Get-ComputerInfo`の`OsBuildNumber` |

## OS・DSRM

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| OS | Windows Server 2022 Standard、Desktop Experience(基準)。Server Coreは対応検討中 | 本書 |
| PowerShell | 組込5.1 + PowerShell 7.4系を追加導入([Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ方針) | `$PSVersionTable` / `pwsh -v` |
| DSRM(ディレクトリサービス復元モード)パスワード | 実値は秘密値台帳で管理し、このリポジトリのどの文書にも記載しない。パスワードポリシー(NFR-07)と同等以上の強度を要求 | 秘密値台帳(`NOT SET`) |
| Firewall実装 | Windows Defender Firewall(`netsh advfirewall`または`New-NetFirewallRule`。AD DS導入時に自動生成されるルール群を含む) | `Get-NetFirewallRule` |
| Antivirus | Windows Defender Antivirus(既定有効) | `Get-MpComputerStatus` |
| 追加の強制アクセス制御機構 | 該当なし(SELinuxに相当する機構は既定では使用しない) | — |
| 自動更新 | Windows Update(Microsoft Updateから直接、自動ダウンロード・手動再起動が既定。実務ではWSUS/グループポリシー経由の集中管理を推奨するが本パックの基準ではない) | Windows Update設定 |

## ユーザー・グループ・権限

| 項目 | 設定値 | 理由 | 正本 |
| --- | --- | --- | --- |
| ローカルAdministrator名 | 既定名(`Administrator`)から変更して運用。実際の名称は`NOT SET`(実機決定時に秘密値台帳へ記録) | 既定名のまま残すと自動化された総当たり攻撃の的になりやすいため | `Rename-LocalUser` |
| ドメイン管理者アカウント | `Administrator`(フォレスト作成時に自動作成される既定のドメイン管理者)。日常運用には別途委任された権限を持つアカウントを使い、`Domain Admins`常用は避ける | Tier0(NFR-08)の考え方 | `Get-ADUser` |
| `Domain Admins`グループのメンバー | フォレスト作成直後は`Administrator`のみ。以後もメンバーを最小限に保つ | 特権グループの肥大化を防ぐため | `Get-ADGroupMember "Domain Admins"` |
| windows_exporterサービス実行アカウント | 既定`LocalSystem` | MSIインストーラーの既定のまま。最小権限化はAST-07相当の継続課題として記録 | `Get-CimInstance Win32_Service`の`StartName` |
| RDPログオン許可ユーザー | 既定Disableのため対象なし。一時有効化時のみ管理元アカウントを許可 | RDPは既定Disable(NFR-04) | `Get-LocalGroupMember "Remote Desktop Users"` |

## OU・グループポリシー設計

OU構造は既定の`CN=Users`・`CN=Computers`コンテナをそのまま使わず、GPO適用単位を明確にするため専用のOUへ移行します。

| OUパス | 用途 |
| --- | --- |
| `OU=_Tier0-Admins,DC=corp,DC=example,DC=test` | ドメイン管理者等、最高権限アカウント専用。既定の`CN=Users`から分離し、専用GPOを適用できるようにする |
| `OU=Servers,DC=corp,DC=example,DC=test` | 将来のドメイン参加サーバー用(本パックではオブジェクトなし) |
| `OU=Workstations,DC=corp,DC=example,DC=test` | 将来のドメイン参加クライアント用(本パックではオブジェクトなし) |
| `OU=Employees,OU=Users,DC=corp,DC=example,DC=test` | 一般ユーザーアカウント用 |
| `OU=Groups,DC=corp,DC=example,DC=test` | セキュリティグループ・配布グループ用 |
| `OU=ServiceAccounts,DC=corp,DC=example,DC=test` | サービスアカウント用(gMSA等の発展課題を含む) |

| GPO名 | 適用先 | 内容 | 実装状態 |
| --- | --- | --- | --- |
| Default Domain Policy | ドメインルート | パスワードポリシー(NFR-07)、アカウントロックアウトポリシー | 済(手動)。実務では専用GPOへ分離することが多いが、本パックでは既定GPOを直接編集し、そのトレードオフを[詳細設計書](02-detailed-design.md)に明記する |
| Servers-Baseline(設計のみ) | `OU=Servers` | NLA必須化、監査ポリシー、Windows Updateの集中管理 | 未実装(設計のみ。適用対象サーバーが本パックに無いため) |
| Workstation-Baseline(設計のみ) | `OU=Workstations` | 画面ロック、監査ポリシー、ローカル管理者制限 | 未実装(設計のみ。適用対象クライアントが本パックに無いため) |

## パスワードポリシー(既定ドメインGPO)

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| 最小パスワード長 | 14文字 | `Get-ADDefaultDomainPasswordPolicy` |
| 複雑性要件 | 有効 | 同上 |
| 最長パスワード有効期間 | 90日 | 同上 |
| パスワード履歴 | 24世代を記憶 | 同上 |
| アカウントロックアウトしきい値 | 10回 | 同上 |
| ロックアウト観察ウィンドウ | 10分 | 同上 |
| ロックアウト時間 | 10分 | 同上 |

## windows_exporter

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| インストール方式 | GitHub Releasesの署名付きMSI。導入前に`Get-FileHash`と公開SHA256の一致を確認(AUT-01相当の構築前チェック) | [構築手順書](05-build-procedure.md) |
| バージョン | `NOT SET`(実機決定時にGitHub Releasesの署名付きMSIとそのSHA256を記録して固定する。[Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ考え方) | 「実機記入欄」参照 |
| 有効化collector | `--collectors.enabled=ad,dns,cpu,logical_disk,net,os,service,system`([Windows版パック](../build-package-windows/03-parameter-sheet.md)の`iis`の代わりに、AD DS向けの`ad`・`dns`を有効化する点が差分) | [構築手順書](05-build-procedure.md) |
| 実行アカウント | 既定`LocalSystem`(最小権限化は継続課題) | 「ユーザー・グループ・権限」節参照 |
| listen | `0.0.0.0:9182`(Windows Defender Firewallで中央Prometheus hostのIPのみ許可、認証なし) | Windows Defender Firewallルール |

## 監視・ログ

フェーズ2(中央監視統合)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`です。値自体は設計として決まっていますが、実行結果としては数えません。

| 項目 | 設定値(設計) | 状態 | 正本 |
| --- | --- | --- | --- |
| windows_exporter scrape interval | 中央の既存`linux-node` jobの設定(15秒)を流用予定 | `BLOCKED`(AIT-09。monitoring networkの`internal: true`制約が解消するまで) | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets` |
| ログ集約 | Grafana Alloy for Windows経由で既存Lokiへ集約する設計のみ(AD監査ログ、Directory Serviceイベントログを含む) | `BLOCKED`(Alloy for Windows未導入のため) | [詳細設計書](02-detailed-design.md) |
| 可用性SLO / latency SLO | `ad-dc01`個別の数値目標は未設定 | `NOT SET`(フェーズ2有効化後に既存[SLO](../slo.md)へ統合予定) | — |

### バックアップ設計

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| バックアップ機能 | Windows Server Backup機能(`wbadmin`)によるSystem Stateバックアップ | [構築手順書](05-build-procedure.md) |
| バックアップ対象 | System State(AD DS データベース`ntds.dit`、SYSVOL、レジストリ等一式)、Firewallルールのエクスポート(`netsh advfirewall export`) | 同上 |
| スケジュール | 毎日03:30(Asia/Tokyo)、Task Schedulerに登録 | 同上 |
| 保持世代 | 14日([Linux版](../build-package/03-parameter-sheet.md)・[Windows版](../build-package-windows/03-parameter-sheet.md)と同じ値) | 同上 |
| AD ごみ箱 | `Enable-ADOptionalFeature 'Recycle Bin Feature'`で有効化。tombstone lifetime(既定180日)の間、削除オブジェクトを`Restore-ADObject`で復元可能 | [構築手順書](05-build-procedure.md) |
| 復元試験方法 | System Stateバックアップからの復元(権威復元/非権威復元の違いを含む)と、AD ごみ箱によるオブジェクト単位の復元を区別して確認(AIT-06、AIT-07) | [試験仕様書・結果票](06-test-specification.md) |

## 公開ポート

Windows Defender FirewallでAD DS役割を導入すると、自動的にルールグループ(Active Directory Domain Services、DNS Service、Kerberos Key Distribution Center、File Replication等)が作成されます。以下は許可対象のポートと、本パックが定義する許可範囲(スコープ)です。

| Port | Proto | Service | 用途 | 許可範囲(設計) |
| --- | --- | --- | --- | --- |
| 53 | TCP/UDP | DNS | 名前解決 | 内部ネットワークCIDR |
| 88 | TCP/UDP | Kerberos | 認証 | 内部ネットワークCIDR |
| 123 | UDP | W32Time(NTP) | 時刻同期 | 内部ネットワークCIDR + 上位NTPソース |
| 135 | TCP | RPCエンドポイントマッパー | 複製・管理 | 内部ネットワークCIDR |
| 389 | TCP/UDP | LDAP | ディレクトリ照会 | 内部ネットワークCIDR |
| 445 | TCP | SMB(SYSVOL/NETLOGON) | GPO配布・複製 | 内部ネットワークCIDR |
| 464 | TCP/UDP | Kerberosパスワード変更 | パスワード変更 | 内部ネットワークCIDR |
| 636 | TCP | LDAPS | 暗号化ディレクトリ照会 | 内部ネットワークCIDR(許可範囲は設計済みだが、フェーズ1では待受しない。下記注記参照) |
| 3268 | TCP | Global Catalog LDAP | フォレスト全体検索 | 内部ネットワークCIDR |
| 3269 | TCP | Global Catalog LDAPS | 同上(暗号化) | 内部ネットワークCIDR(636と同じ理由でフェーズ1では待受しない) |
| 49152-65535 | TCP | 動的RPC(AD DS/FRS/DFSR) | 複製等 | 内部ネットワークCIDR |
| 5986 | TCP | WinRM(HTTPS) | 構築・運用管理 | 管理元CIDR限定 |
| 9182 | TCP | windows_exporter | host/ADメトリクス | 中央Prometheus hostのIPのみ許可(認証なし) |
| 3389 | TCP | RDP | 障害時の代替アクセス | 既定Disable。一時許可時のみ管理元CIDR限定 |

[Linux版](../build-package/03-parameter-sheet.md)・[Windows版](../build-package-windows/03-parameter-sheet.md)の管理系サービスは管理元CIDRのみへの限定を基本方針としていましたが、AD DS自体のポート(DNS/Kerberos/LDAP/SMB/RPC等)は将来のドメインメンバー全体から到達できる必要があるため、「内部ネットワークCIDR」という管理元CIDRより広い範囲を別途定義しています。この違いは[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)で詳しく扱います。

**636(LDAPS)・3269(Global Catalog LDAPS)がフェーズ1で待受しない理由**: `Install-ADDSForest`によるフォレスト作成・DC昇格だけでは、LDAP over SSL/TLSは有効になりません。DCがLDAPS(636)・GC LDAPS(3269)で待ち受けるには、DCのFQDN(`ad-dc01.corp.example.test`)を対象としたサーバー認証(Server Authentication)用の証明書が、コンピューターのローカルコンピューター証明書ストアに配置されている必要があります(参考: [LDAP over SSLの有効化に関するMicrosoftの解説](https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/enable-ldap-over-ssl-3rd-certification-authority))。この証明書は通常AD CS(証明書サービス)の自動登録で配布しますが、[要件定義書](00-requirements.md)5節のとおりAD CSは本パックの対象外です。したがって389(LDAP)・3268(GC LDAP、いずれも非暗号化)は`Install-ADDSForest`直後から待受しますが、636・3269はAD CS導入(または手動でのサーバー認証証明書配布)まで待受しません。Firewallの許可設定自体はフェーズ1で行いますが、待受確認(ANW-05)の対象からは外し、AD CS導入後の発展課題として扱います。

## 実機記入欄

下表は引き渡し対象hostごとの記入欄なので、未指定の現時点では`NOT RUN`を維持します。記録時は[検証証跡台帳](../evidence/README.md)の様式に従い、日付付きのevidenceファイルへ分けて記録します。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OSビルド番号(`winver` / `Get-ComputerInfo`の`OsBuildNumber`) | `NOT RUN` | — | — |
| フォレスト / ドメイン機能レベル(`Get-ADForest` / `Get-ADDomain`) | `NOT RUN` | — | — |
| CPU / memory / disk | `NOT RUN` | — | — |
| ディスク構成(`Get-Volume` / `Get-Disk`) | `NOT RUN` | — | — |
| Windows Defender Firewallの許可範囲(`Get-NetFirewallRule`) | `NOT RUN` | — | — |
| FSMO役割保持者(`netdom query fsmo`) | `NOT RUN` | — | — |
| windows_exporter version / SHA256 | `NOT RUN` | — | — |
| PowerShell version(`$PSVersionTable`) | `NOT RUN` | — | — |
| 適用手順書バージョン / commit SHA | `NOT RUN` | — | — |
