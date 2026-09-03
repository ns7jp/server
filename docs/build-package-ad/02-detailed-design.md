# 詳細設計書

> 💡 **初めて読む方へ**: この文書はコンポーネントごとの実装と「正常性の見分け方」を描く文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#02-詳細設計書)を参照してください。

本書は[基本設計書](01-basic-design.md)を受けて、`ad-dc01`(Windows Server 2022 Standard、Desktop Experience基準)側のコンポーネント構成・配備手順・アクセス制御・ログ監視・バックアップ/ロールバックを定義します。中央監視host(論理名`monitor-01`)側の構成は変更しません。フェーズ1(ホスト単体構築)とフェーズ2(中央監視統合)の区分は[要件定義書](00-requirements.md)のとおりで、フェーズ2は「未実装」3点が解消するまで`BLOCKED`です。

## コンポーネント設計

| コンポーネント | 実装 | 依存先 | 正常性確認 |
| --- | --- | --- | --- |
| Active Directory Domain Services(NTDS) | `Install-ADDSForest`による新規フォレスト・新規ドメイン作成(`corp.example.test`、NetBIOS名`CORP`)。ディレクトリデータベース(`ntds.dit`)は既定パス(`C:\Windows\NTDS`)に配置 | Windows Defender Firewall(AD DS関連自動生成ルール)、host OS | フェーズ1: `Get-Service NTDS`が`Running`(AIT-02)。`netdom query fsmo`で5役割すべて`ad-dc01`(FR-05、AIT-05) |
| AD統合DNS | `Install-ADDSForest`の`-InstallDns:$true`でDNSサーバー役割を同時導入。フォレスト全体で複製されるAD統合ゾーンとして構成 | Active Directory Domain Services(NTDS)、Windows Defender Firewall(DNS Serviceルールグループ、内部ネットワークCIDR) | フェーズ1: `Resolve-DnsName`でAレコード・SRVレコード(`_ldap._tcp.dc._msdcs.corp.example.test`等)が解決(FR-03、AIT-03) |
| Netlogon / KDC(Kerberos) | AD DS導入により自動的に有効化されるサービス。Netlogonはドメイン参加・セキュアチャネルの基盤、KDC(Kerberos Key Distribution Center)は認証チケットの発行を担う | NTDS、W32Time(Kerberosの既定許容時刻差5分の前提)、Windows Defender Firewall(Kerberos Key Distribution Centerルールグループ) | フェーズ1: `Get-Service Netlogon,Kdc`がともに`Running`(AIT-02) |
| W32Time | PDCエミュレータを権威時刻源として構成。`w32tm /config /manualpeerlist:"time.windows.com,0x8 ntp.nict.jp,0x8" /syncfromflags:manual /reliable:yes /update`で外部NTPと同期 | 外部NTPソースへの送信到達性(123/udp)、Windows Defender Firewall | フェーズ1: `Get-Service W32Time`が`Running`(AIT-02)。`w32tm /query /status`で同期状態を確認(NFR-10、ANW-04) |
| Windows Defender Firewall | Default Inbound Blockを維持。AD DS導入時の自動生成ルールグループ(Active Directory Domain Services、DNS Service、Kerberos Key Distribution Center、File Replication等)のスコープを内部ネットワークCIDRへ、WinRM/windows_exporterを個別スコープへ限定 | host OS標準機能(追加依存なし) | フェーズ1: `Get-NetFirewallRule`でEnabled=trueのルールの許可Portと送信元が設計と一致(AST-08) |
| WinRMリスナー | HTTPSリスナー+証明書(自己署名または内部CA)。既定のHTTPリスナーを無効化しHTTPS専用にする。Basic認証は無効化 | 証明書ストア、Windows Defender Firewall(5986許可、管理元CIDR限定) | フェーズ1: `winrm enumerate winrm/config/listener`でHTTPSのみ、Basic無効を確認(FR-01、AST-01) |
| windows_exporter | 署名付きMSI導入、Windowsサービス(既定`LocalSystem`)。`--collectors.enabled`で`ad,dns,cpu,logical_disk,net,os,service,system`を有効化 | Windows Defender Firewall(9182許可、中央Prometheus hostのIPのみ)、host OS | フェーズ1: `curl.exe http://localhost:9182/metrics`がローカルで200。フェーズ2: 中央Prometheus Targets画面で`up{job="linux-node", host="ad-dc01"}=1`(FR-09、AIT-09、`BLOCKED`) |
| System Stateバックアップ / ADごみ箱 | Windows Server Backup機能(`wbadmin`)によるSystem Stateバックアップ。`Enable-ADOptionalFeature`で「Recycle Bin Feature」を有効化 | バックアップ格納先ボリューム、Task Scheduler、フォレスト機能レベル(WinThreshold。Windows Server 2008 R2以上が条件のため既に充足) | フェーズ1: `wbadmin get versions`に記録(FR-06、AIT-06)。`Restore-ADObject`で削除前と同じ属性で復元(FR-06、AIT-07) |
| 中央Prometheus(フェーズ2、`BLOCKED`) | 既存Compose上のPrometheus(コード変更なし)。scrape対象は`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数で管理 | `app_node_exporter_targets`変数、windows_exporter(9182到達には`compose.yaml`のnetwork拡張が必要) | フェーズ2: `up{job="linux-node", host="ad-dc01"}=1`(FR-09、AIT-09、`BLOCKED`: monitoring networkの`internal: true`制約が解消するまで) |
| 中央Grafana / Alertmanager / Loki(変更なし) | 既存provisioning / route・inhibit設定 / filesystem store(変更なし) | 中央Prometheus、中央Loki | 既存のまま`/api/health`、`/-/ready`、`/ready`が正常(AD追加による変更なし) |

## 配備設計

フェーズ1はAnsible role化されていないため、[構築手順書](05-build-procedure.md)のPowerShell手順による「済(手動)」が中心です。

1. **OS初期設定(済・手動)**: コンピューター名(`ad-dc01`相当)、timezone(`Asia/Tokyo`)、ローカルAdministratorの既定名からの変更、PowerShell 7.4系の追加導入、静的固定IPの割り当て、Windows Updateの設定を行います。フォレスト作成前は他のADに参加しないワークグループ状態です。
2. **Firewall設定(済・手動)**: Windows Defender FirewallをDefault Inbound Blockで確認し、WinRM(5986/tcp、管理元CIDR限定)を先行して許可します。AD DS関連ポート群(DNS/Kerberos/LDAP/SMB/RPC等)は次項の`Install-ADDSForest`実行時に自動生成されるルールグループのスコープを、内部ネットワークCIDRへ限定します。RDP(3389/tcp)は既定Disableのままとします。WinRM HTTPSリスナー用証明書もこの段階で作成・バインドします。
3. **AD DS導入とフォレスト作成(済・手動)**: 初回のみ、ハイパーバイザーのコンソールから対象ホストへ直接ログオンして実行します。`Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools`でAD DS役割を導入し、`Import-Module ADDSDeployment`のうえ`Install-ADDSForest`で新規フォレスト・新規ドメイン(`corp.example.test`、NetBIOS名`CORP`)を作成します(FR-02、AIT-01)。DSRM Administratorパスワードは秘密値台帳で管理する実値を対話的に入力し、このリポジトリのどの文書にも記載しません。`-ForestMode`/`-DomainMode`には`WinThreshold`を指定しますが、これはWindows Server 2016機能レベルを指す名称であり、「2022機能レベル」という値は存在しません。Microsoftは2016以降、新しいフォレスト/ドメイン機能レベルを追加していないため、Windows Server 2022のDCであっても指定可能な最上位の機能レベルは`WinThreshold`(=2016)です。初めてADを構築する人がつまずきやすい点なので、ここで明記します。完了後は自動的に再起動されます。再起動後は`Get-DnsClientServerAddress`で自ホストのDNSクライアント設定を確認し、`127.0.0.1`(自分自身のAD統合DNS)を優先参照していることを確認・是正します(AIT-02)。既に昇格済みの`ad-dc01`に対して`Install-ADDSForest`相当を誤って再実行した場合は、既存ドメインを破壊せず明確なエラーで安全に失敗することを確認します(NFR-02、AIT-11)。
4. **OU/GPO/パスワードポリシー設計(済・手動)**: `New-ADOrganizationalUnit`で`_Tier0-Admins`、`Servers`、`Workstations`、`Employees`、`Groups`、`ServiceAccounts`の6つのOUをドメイン直下に作成し、`ProtectedFromAccidentalDeletion`を有効化します(`Users`という名前のOUは既定の`CN=Users`コンテナと衝突して作成できないため、初版の`Employees`(`Users`配下)という設計は取り下げました)。既定ドメインGPO(Default Domain Policy)は専用GPOへ分離せず直接編集する方式を取り、`Set-ADDefaultDomainPasswordPolicy`で最小長14文字、複雑性要件、最長パスワード有効期間90日、パスワード履歴24世代、ロックアウトしきい値10回/観察10分/ロックアウト10分を設定します(FR-04、NFR-07、AIT-04、AST-03)。`Servers-Baseline`、`Workstation-Baseline`は適用対象オブジェクトが本パックに無いため、[パラメータシート](03-parameter-sheet.md)のとおり設計のみで未実装です。
5. **セキュリティ強化(済・手動)**: LDAP署名/チャネルバインディングを、Default Domain Controllers Policyのセキュリティオプション「LDAP サーバー署名必須 = 署名必須」「LDAP サーバー チャネル バインディング トークンの要件 = 常に」で必須化し、再起動で反映します(2023年3月のMicrosoft強制適用ガイダンスADV190023相当、NFR-05、AST-04)。レジストリ`LDAPServerIntegrity`の直接編集は、同GPOが既定で「なし」を定義しているためGP更新で上書きされます(2026-09-02実機確認)。`LdapEnforceChannelBinding`はGPOに既定の定義が無いためレジストリ編集でも残りますが、**その値は新規に追加したDCへ引き継がれない**ため、こちらもGPOで設定します(2026-09-03実機確認)。`Disable-WindowsOptionalFeature -FeatureName SMB1Protocol`でSMBv1を無効化します(NFR-06、AST-05)。ディレクトリサービスの変更監査は、同じGPOの「高度な監査ポリシーの構成 → DS アクセス → ディレクトリ サービスの変更の監査」で成功・失敗の両方を有効化します(NFR-09、AST-06)。`auditpol /set`による直接設定は、そのDC上では有効になりますが**後から追加するDCへ引き継がれません**(2026-09-03実機確認)。`auditpol /get`は確認用に使います。`Domain Admins`等の特権グループのメンバーは、フォレスト作成直後の既定管理者アカウントのみに保ち、Tier0の考え方を崩しません(NFR-08、AST-07)。
6. **windows_exporter導入(済・手動)**: GitHub Releasesの署名付きMSIをダウンロードし、`Get-FileHash`で公開SHA256との一致を確認したうえでインストールします。`--collectors.enabled`には`ad,dns,cpu,logical_disk,net,os,service,system`を指定します([Windows版パック](../build-package-windows/02-detailed-design.md)の`cs`・`iis`の代わりに、AD DS向けの`ad`・`dns`を有効化する点が差分です)。サービスが起動することを確認します(既定`LocalSystem`、最小権限化はAST-07相当の継続課題として記録)。バージョンは実機決定時に固定するため現時点では`NOT SET`です。
7. **バックアップ設定(済・手動)**: Windows Server Backup機能を導入し、Task Schedulerへ毎日03:30(Asia/Tokyo)実行の`wbadmin enable backup`タスクを登録します(保持14世代)。`Enable-ADOptionalFeature -Identity "Recycle Bin Feature"`でADごみ箱を有効化します(フォレスト機能レベルがWindows Server 2008 R2以上であることが条件で、`WinThreshold`は満たします)。詳細は本書「バックアップ・ロールバック」を参照してください(FR-06)。
8. **中央監視統合(フェーズ2・大部分が未実装、`BLOCKED`)**: `app_node_exporter_targets`への`ad-dc01`の1行追加と中央host側での`site.yml`再適用は「済(自動)」で今すぐ実行できますが、次の3点が解消するまでフェーズ2全体は`BLOCKED`です。1点目は、`ansible/roles`配下にWindows対応role(`common_windows`等)が無く、AD DS自体の構築・設定変更をAnsibleで自動化できないことです(本書の配備設計1〜7がすべて「済(手動)」であるのはこのためです)。2点目は、`compose.yaml`のmonitoring networkが`internal: true`であり、Prometheusコンテナが同じDockerホスト外の実machine(`ad-dc01`)のwindows_exporter(既定9182/tcp)へ到達できないことです。到達には、たとえばPrometheusサービスのみを`internal`でない追加の管理用bridge network(例: remote-targets)へ接続する`compose.yaml`変更が必要ですが未実装です。3点目は、Windows Event Log/ADディレクトリサービス監査ログを既存Lokiへ送る経路(Grafana Alloy for Windowsの導入、Lokiのpush APIをloopback以外からも安全に受け付けるための認証・network設計)が無いことです。これら3点は[Windows版パック](../build-package-windows/02-detailed-design.md)と共通の制約です。
9. **動作確認**: フェーズ1はAUT-01〜04、AIT-01〜08、AIT-10、AIT-11、AST-01〜08、ANW-01〜09を実施します。フェーズ2はAIT-09を実施しますが、上記8の解消までいずれも`BLOCKED`です。判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とします。

## アクセス制御

WinRM/AD DS関連ポート/windows_exporterのFirewallルールは、許可送信元を管理元CIDR・内部ネットワークCIDR・中央Prometheus hostのIPのいずれかに限定します。既定はDefault Inbound Blockであり、明示的に許可した通信のみを通します。Firewallプロファイルは、`ad-dc01`が昇格し正しくドメインコントローラーとして認識された後は`Domain`です。昇格直後はNLA(Network Location Awareness)がネットワークカテゴリを`Domain`と正しく認識するまで一時的に`Public`扱いになることがあるため、[構築手順書](05-build-procedure.md)で確認手順を含めます。SELinuxに相当する追加の強制アクセス制御機構は既定では使用しません(該当なし)。

| 経路 | 公開範囲 | 認証 |
| --- | --- | --- |
| WinRM(HTTPS) | 管理元CIDR限定 | 証明書 または Kerberos/Negotiate(Basic無効) |
| RDP | 既定Disable。一時許可時のみ管理元CIDR | Windowsログオン資格情報 + NLA必須 |
| AD DS関連ポート(DNS 53、Kerberos 88/464、RPC 135/動的RPC、LDAP 389/636、SMB 445、Global Catalog 3268/3269) | 内部ネットワークCIDR限定(将来のドメインメンバー) | Kerberos/NTLM(サービス自体の認証。到達範囲はFirewallで別途制限) |
| windows_exporter | 中央Prometheus hostのIPのみ | 認証なし、ネットワーク制限のみ(Linuxのnode-exporterと同じ思想) |
| 中央Prometheus/Grafana/Alertmanager/Loki | 既存Linux版設計のまま変更なし | [../build-package/02-detailed-design.md](../build-package/02-detailed-design.md)参照 |

## ログ・監視設計

現時点ではWindows Event Log/ADディレクトリサービスの変更監査ログは中央Lokiへ送られていません(Grafana Alloy for Windows未導入のため、フェーズ2、`BLOCKED`)。導入後の設計方針はLinux版・Windows版を踏襲します。

- 固定値だけをLokiラベルにし、IP、ユーザー名、オブジェクトの識別子は本文へ残します。
- アラートにはseverity、summary、description、runbook URLを持たせます(中央Alertmanager側、変更なし)。
- アラート通知先の秘密値は中央側の既存の仕組み(`compose.slack.yaml.example`とローカルsecret)のまま注入し、AD側で新たな秘密値の注入経路は追加しません。

アラート確認時の切り分け順「メトリクス → 直近変更 → ログ → プロセス」はLinux版・Windows版と共通ですが、AD側はログ集約(フェーズ2)が未実装のため、フェーズ1時点では次の代替手順で一次切り分けを行います。

- メトリクス: windows_exporterのメトリクスを`curl.exe http://localhost:9182/metrics`でローカルから直接確認します(中央Prometheusが未到達のため、フェーズ2実装までは実機ログイン/WinRM経由の直接確認に限定されます)。
- 直近変更: [変更・ロールバック計画](08-change-rollback-plan.md)の記録を確認します。
- ログ: `Get-WinEvent`またはイベントビューアーでWindows Event Log(Directory Service、DNS Server、System等のログ)を直接参照します。ディレクトリサービスの変更監査(AST-06)の確認もこの経路で行い、Lokiでの横断検索は未対応です。
- プロセス: `Get-Service`でディレクトリサービス関連サービス(NTDS、DNS、Netlogon、Kdc、W32Time)の状態を確認します。

一次切り分けの記録様式は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)を共用します。

## バックアップ・ロールバック

- Windows Server Backup機能(`wbadmin`)を導入し、System State(AD DSデータベース`ntds.dit`、SYSVOL、レジストリ等一式)、Firewallルールのエクスポート(`netsh advfirewall export`)をバックアップ対象とします。
- スケジュールは毎日03:30(Asia/Tokyo)、Task Schedulerに登録します。保持世代は14日([Linux版](../build-package/03-parameter-sheet.md)・[Windows版](../build-package-windows/03-parameter-sheet.md)と同じ値)です。
- System Stateバックアップからの復元試験(AIT-06)は権威復元/非権威復元の違いを含めて確認する試験であり、AD ごみ箱によるオブジェクト単位の復元試験(AIT-07)とは別に管理します。現時点でAIT-06、AIT-07はいずれも`NOT RUN`です([検証証跡台帳](../evidence/README.md)参照)。
- ADごみ箱は`Enable-ADOptionalFeature -Identity "Recycle Bin Feature"`で有効化し、tombstone lifetime(既定180日)の間、削除オブジェクトを`Restore-ADObject`で復元できます。
- Windows対応Ansible roleが無いため、[Linux版](../build-package/02-detailed-design.md)のような「直前commitへ戻して`deploy.yml`を再適用する」commit SHA基準の再配備は使えません。構成変更のロールバックは優先順位順に次の3段階の手段を使います。
  1. VM/ハイパーバイザーのスナップショット復元(Hyper-Vの`Checkpoint-VM`/`Restore-VMCheckpoint`、VMware等)を最優先の手段とします。取得タイミングは変更直前で、特にフォレスト作成やFSMO操作等の取り消しが困難な変更の前は必須とします。
  2. スナップショットが無い場合は、変更前に取得したFirewallルールのエクスポート(`netsh advfirewall export`)、レジストリの該当キー(LDAP署名/チャネルバインディング等)のエクスポートを個別に戻します。
  3. データ破損時はWindows Server Backupからの復元(上記バックアップ設計を参照。System Stateの権威復元/非権威復元)を使用します。
- Go/No-Go条件、実施結果記録の様式は[変更・ロールバック計画](08-change-rollback-plan.md)に[Linux版](../build-package/08-change-rollback-plan.md)・[Windows版](../build-package-windows/08-change-rollback-plan.md)と同じ構造で定義します。
- サービス停止復旧演習(FR-07、AIT-08)と、上記ロールバック手段の実施結果(スナップショット復元/個別エクスポート復元/Windows Server Backup復元)は別試験として扱い、それぞれ日付付きのevidenceへ記録するまで`NOT RUN`です。
