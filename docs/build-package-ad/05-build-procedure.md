# 構築手順書

> 💡 **初めて読む方へ**: この文書は実際にコマンドを打ち込んでサーバーを構築する、本パックの中で最も長く技術的な文書です。まず[案件パック 初心者ガイド](beginner-guide.md#05-構築手順書)で全体の流れを確認してから読むと迷いにくくなります。

本書は、[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を受けて、`ad-dc01`(Windows Server 2022 Standard、Desktop Experience基準)を新規フォレスト・新規ドメイン(`corp.example.test`、NetBIOS名`CORP`)の最初のドメインコントローラーとして、フェーズ1(ホスト単体構築)の範囲で構築する手順を示します。[Windows版パック](../build-package-windows/05-build-procedure.md)と異なり、本書はIISの導入を扱いません。ADはWeb監視対象ではないため、4節以降はActive Directory Domain Services(AD DS)そのものの導入・設計に手順の中心を置きます。

Ansible role化された自動構築経路(`ansible/roles/common`相当のWindows対応role)は存在しません。本書の手順はすべて「済(手動)」であり、対象ホスト上またはWinRM経由でPowerShellを実行して進めます。0〜9節・11〜15節は対象ホスト(`ad-dc01`)または管理端末側の作業、10節のみ中央監視host(`monitor-01`)側の作業です。10節の`app_node_exporter_targets`変数への追加と`site.yml`再適用だけは「済(自動)」の既存Ansible機能であり、他の節とは性質が異なる点に注意してください。

フェーズ2(中央監視統合の残り、すなわちwindows_exporterのscrape・ログ集約)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`です。本書はフェーズ2の設計や解除条件そのものは扱わず、[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします。

## 0. 作業前確認

- 対象: `ad-dc01`(新規フォレスト・新規ドメインの最初のドメインコントローラー)検証用VM 1台。本手順はまだドメインが存在しない状態から新規フォレストを作成する前提です。対象VMが既に何らかのドメインへ昇格済みでないことを、作業開始前に必ず確認してください(誤って既存ドメインに対して本手順を再実行しないための最初の確認であり、13節AIT-11の考え方につながります)
- 対象VMの初回作業はWinRMがまだ有効化されていないため、ハイパーバイザーのVMコンソール(またはローカルコンソール)から直接ログオンして行います。WinRM HTTPS経由の管理は2節で有効化した後にのみ成立します
- 対象IPアドレス(`192.0.2.50/24`)、対象ホストの正式なコンピューターFQDN(`ad-dc01.corp.example.test`。ドメイン参加前の現時点ではまだDNSに登録されていませんが、2節のWinRM証明書はこの昇格後FQDNを先取りして発行します)、ドメインFQDN(`corp.example.test`)、NetBIOS名(`CORP`)、管理端末IP(例示: `192.0.2.40`)、内部ネットワークCIDR、作業時間帯を記録済みであること
- DSRM(ディレクトリサービス復元モード)Administratorパスワードを、Git管理外の秘密値台帳で安全に生成・保管済みであること。実値はこのリポジトリのどの文書にも記載しません。パスワードの強度基準そのものの設計確認はAUT-02(このリポジトリの文書レビュー)で行い、値そのものは記載・確認しません
- ロールバック条件(VM/ハイパーバイザーのスナップショット取得タイミングを含む)を[変更・ロールバック計画](08-change-rollback-plan.md)で確認済みであること。フォレスト作成(4節)はこのVMにとって後戻りが難しい変更であるため、**フォレスト作成の直前**にスナップショットを取得するタイミングを本節で必ず合意してください
- 本パックはAnsible role化されていないため、Linux版のような対象commit SHA固定によるコード配備管理はありません。ただし、本パック文書側の版(このリポジトリの`git rev-parse HEAD`)は事後の突合のため記録しておきます
- 実値の秘密情報(DSRMパスワード、証明書秘密鍵、ローカルAdministratorの新しいパスワード等)をIssue、PR、端末ログへ貼りません
- [要件定義書](00-requirements.md)と[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go条件を確認済みであること
- 本書はフェーズ1(ホスト単体構築)の範囲のみを扱うこと、10節の中央側コマンドを実行してもフェーズ2のscrapeは`compose.yaml`の`monitoring`ネットワークの制約が解消するまで成立しないことを再確認済み

## 1. 管理端末の準備

管理端末はWindows / Linux / macOSのいずれでも構いません。本パックはPowerShell 7(`pwsh`、クロスプラットフォーム)を管理端末側の共通実行環境とし、将来Ansibleの`ansible.windows` collectionを使う場合にも同じ端末を流用できるようにします。

```powershell
# PowerShell 7の導入(Windows管理端末の例。winget未導入の場合はMSIパッケージを使用)
winget install --id Microsoft.PowerShell --source winget
pwsh -Command '$PSVersionTable.PSVersion'
```

```bash
# この案件パックの取得
git clone https://github.com/ns7jp/server.git
cd server-monitor
git rev-parse HEAD
```

```powershell
# WinRM設定確認(現時点でのベースライン)
# 対象ホストは2節でHTTPSリスナーを有効化するまで未構成のため、この時点での接続確認は失敗して正常です
Test-WSMan -ComputerName "ad-dc01.corp.example.test" -UseSSL -ErrorAction SilentlyContinue
```

上記`Test-WSMan`が失敗する(応答なし/拒否)ことを、2節・3節の作業前のベースラインとして記録します。2節でWinRM HTTPSリスナーを有効化し、3節でFirewallを管理元CIDR限定で許可した後に、あらためて同じコマンドで疎通を確認します。

## 2. Windows Server初期設定とWinRM有効化

本節はVMコンソールから対象ホストへ直接ログオンして実行します(WinRMがまだ有効化されていないため)。

```powershell
# コンピューター名の設定(再起動を伴います)
Rename-Computer -NewName "ad-dc01" -Restart
```

再起動後、再度コンソールへログオンし、続きを実行します。

```powershell
# 固定IPの設定(DCは動的IPを使用しません)。default gatewayは環境ごとに決定します
New-NetIPAddress -InterfaceAlias "イーサネット" -IPAddress 192.0.2.50 -PrefixLength 24 `
  -DefaultGateway "<NOT SET: 環境ごとに決定するdefault gateway>"

# この時点ではAD DS/DNSがまだ無いため、Windows Update等のために一時的な外部DNSを指定します。
# 4節でAD DSとDNSサーバー機能を導入した後、自分自身(127.0.0.1)へ切り替えます
Set-DnsClientServerAddress -InterfaceAlias "イーサネット" -ServerAddresses "<NOT SET: 環境ごとに決定する一時的な外部DNS>"

Get-NetIPAddress -InterfaceAlias "イーサネット" -AddressFamily IPv4

# timezone設定
Set-TimeZone -Id "Tokyo Standard Time"
Get-TimeZone

# ローカルAdministratorの既定名からの変更。新しい名称は実機決定時にNOT SETを埋め、
# 実際の値はこのリポジトリではなく秘密値台帳へ記録します。以下は手順の例です。
# なお、この変更は昇格後にDSRM(ディレクトリサービス復元モード)でのログオンに使う
# ローカル資格情報にも関わるため、4節で入力するDSRM Administratorパスワードとあわせて
# 秘密値台帳で一元管理してください
Rename-LocalUser -Name "Administrator" -NewName "<環境ごとに決定する管理者アカウント名>"

# Windows Update設定の確認(既定: Microsoft Updateから直接、自動ダウンロード・手動再起動)
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue

# PowerShell 7.4系の追加導入(対象ホスト側)。
# Windows Server 2022はWinGet(App Installer)が既定で導入されていません(OS標準でWinGetが
# 使えるのはWindows Server 2025以降)。そのため対象ホスト側は、管理端末側(1節)のようなwinget経由では
# 導入できず、GitHub Releasesの公式MSIパッケージを使います。バージョンは実機決定時にGitHub Releasesで
# 確認して固定してください(現時点でNOT SET)
$PwshMsiVersion = "<NOT SET: 実機決定時にGitHub Releasesで確認するPowerShell 7.4系のバージョン番号>"
$PwshMsiUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshMsiVersion/PowerShell-$PwshMsiVersion-win-x64.msi"
Invoke-WebRequest -Uri $PwshMsiUrl -OutFile C:\temp\pwsh-installer.msi
Start-Process msiexec.exe -ArgumentList "/i C:\temp\pwsh-installer.msi /qn /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1" -Wait
pwsh -Command '$PSVersionTable.PSVersion'
```

続けて、WinRM HTTPSリスナーを作成します。証明書のDNS名には、4節のフォレスト作成後に`ad-dc01`が実際に名乗ることになる正式なコンピューターFQDN`ad-dc01.corp.example.test`を先取りして使います。この時点ではまだ`corp.example.test`ドメイン自体が存在せずDNSにも登録されていませんが、自己署名証明書の発行やWinRM接続そのものにはDNSでの事前登録は不要です(管理端末側は3節のFirewall許可後、対象IP`192.0.2.50`への直接接続、またはこのFQDNを管理端末のhostsファイルへ一時的に登録して接続します)。

証明書を発行したら、`winrm quickconfig`による自動選択に任せず、この証明書の拇印(Thumbprint)を明示的に指定してHTTPSリスナーを作成します。`winrm quickconfig -transport:https`はコンピューター名に一致する証明書を内部的に検索する仕様のため、コンピューター名(`ad-dc01`)とは異なるFQDNで証明書を発行した場合に一致する証明書を見つけられず、リスナーが作成されないことがあります。拇印を明示すればこの曖昧さを避けられます。

```powershell
# WinRM HTTPS用の自己署名証明書(DNS名は昇格後の正式なコンピューターFQDN)
$cert = New-SelfSignedCertificate -DnsName "ad-dc01.corp.example.test" `
  -CertStoreLocation Cert:\LocalMachine\My -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(2)
$cert.Thumbprint

# 既存のHTTP/HTTPSリスナーが残っている場合は削除してから作り直す
Get-ChildItem WSMan:\localhost\Listener |
  ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force }

# WinRM HTTPSリスナーを、上記証明書の拇印を明示して作成する(quickconfigの自動選択に任せない)
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
  -CertificateThumbPrint $cert.Thumbprint -Force

# Basic認証を無効化し、Negotiateのみを許可する(NFR-03、AST-01)
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

winrm enumerate winrm/config/listener
```

自己署名証明書のため、管理端末が証明書を信頼できるようエクスポート・配布します。ネットワーク経由の配布は3節でFirewallを開けた後になるため、初回はUSBメモリやハイパーバイザーの共有フォルダなど、ネットワークを介さない方法で管理端末へ持ち出します。

```powershell
# 対象ホスト側: 証明書のエクスポート(秘密鍵は含めない)
Export-Certificate -Cert $cert -FilePath C:\temp\ad-dc01-winrm.cer
```

```powershell
# 管理端末側: 信頼済みルートへのインポート(自己署名証明書を許容する場合のみ)
Import-Certificate -FilePath .\ad-dc01-winrm.cer -CertStoreLocation Cert:\LocalMachine\Root
```

この時点ではFirewallが未設定のため、管理端末からの`Test-WSMan`はまだ成立しません。疎通確認は3節末で実施します。

## 3. Windows Defender FirewallとRDPの締め

引き続き対象ホスト側で実行します。この時点ではAD DS機能をまだ導入していないため、AD DS関連の自動生成Firewallルールグループはまだ存在しません(これらは4節でAD-Domain-Services機能を導入した際に自動的に作成されます)。本節で作成するのはWinRM許可ルールのみです。

```powershell
# Firewallプロファイルの確認
Get-NetConnectionProfile

# Default Inbound Block(既定)の確認
Get-NetFirewallProfile | Select-Object Name, DefaultInboundAction, DefaultOutboundAction, Enabled

# WinRM(HTTPS)を管理元CIDR限定で許可
New-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly" -Direction Inbound `
  -Protocol TCP -LocalPort 5986 -Action Allow `
  -RemoteAddress 192.0.2.40/32 -Profile Any

# quickconfigが自動生成した既定ルール(全許可)が有効な場合は無効化し、上記の限定ルールへ一本化する
Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne (Get-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly").Name } |
  Disable-NetFirewallRule

# RDPは既定Disable(NFR-04、AST-02)
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Disable-NetFirewallRule
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Select-Object DisplayName, Enabled

# 障害時に一時的にRDPを許可する場合のルール(平時は Enabled:False で登録しておき、必要時のみ有効化)
New-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -Direction Inbound `
  -Protocol TCP -LocalPort 3389 -Action Allow -RemoteAddress 192.0.2.40/32 `
  -Profile Any -Enabled False
```

ここまでで管理端末からのWinRM HTTPS疎通が成立するはずです。管理端末側で確認します。`corp.example.test`のDNSゾーンはまだ存在しないため、`ad-dc01.corp.example.test`を名前解決させるには、管理端末の hosts ファイルへ`192.0.2.50 ad-dc01.corp.example.test`を一時的に追記してください(4節でAD統合DNSが稼働した後は、この hosts エントリを削除して通常のDNS解決に戻します)。

```powershell
# 管理端末側
Test-WSMan -ComputerName "ad-dc01.corp.example.test" -UseSSL

$cred = Get-Credential   # 2節で設定したローカルAdministrator相当の資格情報
Enter-PSSession -ComputerName "ad-dc01.corp.example.test" -UseSSL -Credential $cred
```

`Test-WSMan`が成功し、管理元CIDR以外からは同じ接続が失敗すること(ANW-09相当)は、[ネットワーク実機検証手順](09-network-validation-procedure.md)で別途正式に確認します。本節での確認はあくまで作業継続のための疎通チェックです。

## 4. Active Directory Domain Servicesの導入と新規フォレスト作成

**本節はVMコンソールから対象ホストへ直接ログオンして実行します。** 3節でWinRM HTTPS経由の疎通を確認しましたが、`Install-ADDSForest`はネットワークスタック(DNSクライアント設定等)を再構成したうえで自動的に再起動するため、リモートのWinRMセッション経由で実行すると、処理の途中でセッションが切断され状態が確認できなくなる恐れがあります。フォレスト作成そのものは、必ずコンソールセッションから行ってください。

```powershell
# AD DS役割の導入
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# 新規フォレストの作成
Import-Module ADDSDeployment
$SafeModePwd = Read-Host -AsSecureString "DSRM Administratorパスワードを入力"
Install-ADDSForest -DomainName "corp.example.test" -DomainNetbiosName "CORP" `
  -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns:$true `
  -SafeModeAdministratorPassword $SafeModePwd -Force:$true
```

`-ForestMode`/`-DomainMode`に指定している`WinThreshold`は、Windows Server 2016のフォレスト/ドメイン機能レベルを指す内部名称です。「2022」という機能レベル値は存在しません。この点の理由は[詳細設計書](02-detailed-design.md)を参照してください。

`Install-ADDSForest`が完了すると、対象ホストは自動的に再起動されます。再起動後、コンソールから`CORP\<2節で設定した管理者アカウント名>`(ドメイン管理者)として再ログオンし、続きを実行します。

```powershell
# 昇格後必須サービス確認(AIT-02)
Get-Service NTDS, DNS, Netlogon, Kdc, W32Time | Select-Object Name, Status, StartType
```

すべて`Running`であることを確認します。1つでも`Running`でないサービスがある場合は、後続の節に進まず[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ状況を記録し、原因切り分けを行ってください。

新規フォレストの唯一のドメインコントローラーである`ad-dc01`は、既定でPDCエミュレータを含むFSMO 5役割すべてを保持します(役割保持者の正式な確認は11節でAIT-05として行います)。PDCエミュレータはドメイン内の時刻同期の基準となるため、ここで外部NTPを権威時刻源として設定します(NFR-10)。

```powershell
w32tm /config /manualpeerlist:"time.windows.com,0x8 ntp.nict.jp,0x8" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /query /source
w32tm /query /status
```

続けて、自ホストのDNSクライアント設定を自分自身(AD統合DNS)へ向けます。`InstallDns:$true`により多くの場合は自動設定されますが、確認・是正のコマンドとして明示します。

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4
Set-DnsClientServerAddress -InterfaceAlias "イーサネット" -ServerAddresses 127.0.0.1
Get-DnsClientServerAddress -AddressFamily IPv4
```

次に、ネットワークカテゴリ(NLA、Network Location Awareness)が正しく`DomainAuthenticated`と認識されているかを確認します。[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)に記載のとおり、DCは昇格直後、NLAの再判定が完了するまで一時的に`Public`扱いのままになることがあります。

```powershell
Get-NetConnectionProfile
```

`NetworkCategory`が`DomainAuthenticated`以外(`Public`等)のままの場合、多くの環境では対象ホストを再起動すると是正されます。再起動しても是正されない場合は、ネットワークアダプタとプロファイルの関連付けを個別に調査する必要があるため、[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ記録してください。ネットワークカテゴリが`Public`のままだと、AD DS関連の自動生成Firewallルール(既定プロファイル: Domain/Private/Public)自体は動作しますが、想定外のプロファイルスコープで解釈される可能性があるため、次の手順に進む前に必ず是正します。

最後に、AD-Domain-Services機能の導入によって自動生成されたFirewallルールグループのスコープ(許可送信元)を、内部ネットワークCIDRへ絞り込みます(AST-08)。既定では、これらのルールは送信元アドレスを限定せず作成されるため、手動で絞り込む作業が必要です。

```powershell
$internalCidr = "<NOT SET: 環境ごとに決定する内部ネットワークCIDR>"

foreach ($group in @(
    "Active Directory Domain Services",
    "DNS Service",
    "Kerberos Key Distribution Center",
    "File Replication"
)) {
    Get-NetFirewallRule -DisplayGroup $group | Set-NetFirewallRule -RemoteAddress $internalCidr
}

Get-NetFirewallRule -DisplayGroup "Active Directory Domain Services" |
  Select-Object DisplayName, Enabled, Direction, Action
```

この時点で、管理端末からのWinRM HTTPS接続をあらためて確認しておきます(3節で開通させた設定が昇格後も維持されていることの確認)。

```powershell
# 管理端末側
Test-WSMan -ComputerName "ad-dc01.corp.example.test" -UseSSL
```

## 5. AD統合DNSの確認

AD DS導入時に作成されたAD統合DNSゾーンで、DC自身のAレコードと、クライアントがドメインコントローラーを探す際に使うSRVレコードが正しく登録されていることを確認します(AIT-03)。

```powershell
Resolve-DnsName -Name ad-dc01.corp.example.test -Type A -Server 127.0.0.1
Resolve-DnsName -Name _ldap._tcp.dc._msdcs.corp.example.test -Type SRV -Server 127.0.0.1
Resolve-DnsName -Name _kerberos._tcp.dc._msdcs.corp.example.test -Type SRV -Server 127.0.0.1
```

Aレコードが`ad-dc01`の実IP(`192.0.2.50`)を指し、いずれのSRVレコードも`ad-dc01.corp.example.test`をターゲットとして返すことを確認します。これらのレコードは`Install-ADDSForest`実行時に`InstallDns:$true`とNetlogonサービスによって自動的に登録されるため、本節は手動でレコードを作成する手順ではなく、自動登録結果の確認手順です。

## 6. OU・グループポリシー・パスワードポリシーの設計適用

[パラメータシート](03-parameter-sheet.md)「OU・グループポリシー設計」節の設計に従い、OUを親から順に作成します。既定の`CN=Users`コンテナと同名の`Users`ですが、これは別物のOUとして新規作成する点に注意してください。

```powershell
New-ADOrganizationalUnit -Name "_Tier0-Admins" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Servers" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Workstations" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Users" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Employees" -Path "OU=Users,DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "Groups" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true
New-ADOrganizationalUnit -Name "ServiceAccounts" -Path "DC=corp,DC=example,DC=test" -ProtectedFromAccidentalDeletion $true

Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
```

続けて、既定ドメインGPO(Default Domain Policy)のパスワードポリシーを設計値(NFR-07)に設定します。

```powershell
Set-ADDefaultDomainPasswordPolicy -Identity corp.example.test -MinPasswordLength 14 `
  -ComplexityEnabled $true -MaxPasswordAge "90.00:00:00" -PasswordHistoryCount 24 `
  -LockoutThreshold 10 -LockoutDuration "00:10:00" -LockoutObservationWindow "00:10:00"

Get-ADDefaultDomainPasswordPolicy
```

`Get-ADDefaultDomainPasswordPolicy`の出力値が[パラメータシート](03-parameter-sheet.md)の設計値と一致することを確認します。さらに、ポリシー未満の弱いパスワードで`New-ADUser`を実行すると拒否されることを確認します(AIT-04)。

```powershell
# 弱いパスワードでのユーザー作成が拒否されることを確認
try {
    New-ADUser -Name "test-weak-pw" -Path "OU=Employees,OU=Users,DC=corp,DC=example,DC=test" `
      -AccountPassword (ConvertTo-SecureString "abc12345" -AsPlainText -Force) -Enabled $true
    Write-Warning "弱いパスワードでのユーザー作成が拒否されませんでした。パスワードポリシーの設定を再確認してください。"
}
catch {
    $_.Exception.Message
}

# 対照として、ポリシーを満たす強いパスワードでは作成できることも確認する
New-ADUser -Name "test-strong-pw" -Path "OU=Employees,OU=Users,DC=corp,DC=example,DC=test" `
  -AccountPassword (ConvertTo-SecureString "<NOT SET: 14文字以上・複雑性要件を満たすテスト用パスワード>" -AsPlainText -Force) -Enabled $true
Get-ADUser -Filter { Name -eq "test-strong-pw" }

# 検証用アカウントは確認後に削除する
Remove-ADUser -Identity "test-strong-pw" -Confirm:$false
Remove-ADUser -Identity "test-weak-pw" -Confirm:$false -ErrorAction SilentlyContinue
```

弱いパスワードでの`New-ADUser`が例外で失敗し、強いパスワードでは成功することの両方を確認できて初めて、AIT-04の期待結果(設計値と一致し、弱いパスワードは拒否される)を満たしたと判断します。

## 7. セキュリティ強化

### 7.1 LDAP署名・チャネルバインディングの必須化(AST-04)

2023年3月のMicrosoft強制適用ガイダンス(ADV190023)相当の設定を適用します。

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerIntegrity" -Value 2
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LdapEnforceChannelBinding" -Value 2
Restart-Service NTDS -Force
```

`Restart-Service NTDS`は単一のドメインコントローラー上でディレクトリサービスを一時的に停止させます。作業時間帯を[要件定義書](00-requirements.md)の合意どおりに確保したうえで実施してください。設定後、レジストリ値が反映されていることを確認します。

```powershell
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" `
  -Name LDAPServerIntegrity, LdapEnforceChannelBinding
```

いずれも`2`(必須)になっていることを確認します。

### 7.2 SMBv1の無効化(AST-05)

```powershell
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
```

`State`が`Disabled`であることを確認します。

### 7.3 監査ポリシー(AST-06)

ディレクトリサービスの変更に対する監査を、成功・失敗の両方で有効化します(NFR-09)。

```powershell
auditpol /set /subcategory:"ディレクトリ サービスの変更" /success:enable /failure:enable
auditpol /get /subcategory:"ディレクトリ サービスの変更"
```

### 7.4 Domain Adminsメンバーの確認(AST-07)

フォレスト作成直後は`Domain Admins`グループのメンバーが`Administrator`のみであることを確認し、以後もメンバーを最小限に保ちます(NFR-08、Tier0の考え方)。

```powershell
Get-ADGroupMember "Domain Admins" | Select-Object Name, SamAccountName, ObjectClass
```

想定外のメンバーが含まれていないことを確認します。

## 8. windows_exporterの導入

バージョンとSHA256は実機決定時にGitHub Releasesで確認して固定します(現時点でNOT SET)。ハッシュ検証は必須です([Windows版パック](../build-package-windows/05-build-procedure.md)と同じ方針)。

```powershell
$version = "<NOT SET: 実機決定時にGitHub Releasesで確認するバージョン番号>"
$msiUrl  = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
$msiPath = "C:\temp\windows_exporter.msi"

Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

# 公開SHA256とのハッシュ一致確認。期待値はGitHub Releasesのchecksumファイルから取得し、
# ここでの値を推測・仮置きしません
$expectedHash = "<NOT SET: 実機決定時に公開されているSHA256>"
$actualHash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash

if ($actualHash -ne $expectedHash) {
    throw "windows_exporter MSIのハッシュが一致しません。expected=$expectedHash actual=$actualHash"
}

# collectorはad, dns, cpu, logical_disk, net, os, service, systemを有効化
# (Windows版パックのcs・iisの代わりに、AD DS向けのad・dnsを有効化する点が差分)
Start-Process msiexec.exe -ArgumentList `
  "/i `"$msiPath`" ENABLED_COLLECTORS=ad,dns,cpu,logical_disk,net,os,service,system /qn" -Wait

Get-Service windows_exporter
Get-CimInstance Win32_Service -Filter "Name='windows_exporter'" |
  Select-Object Name, StartName, State, PathName

# ローカルからの疎通確認(中央Prometheusはフェーズ2まで到達不可のため、この時点ではローカル確認のみ)
curl.exe http://localhost:9182/metrics | Select-String "windows_ad_" | Select-Object -First 5

# Firewall: 中央Prometheus hostのIPのみ許可(認証なし。値は環境ごとに決定するためNOT SET箇所を埋める)
New-NetFirewallRule -DisplayName "WindowsExporter-Prometheus-Only" -Direction Inbound `
  -Protocol TCP -LocalPort 9182 -Action Allow `
  -RemoteAddress "<NOT SET: 中央Prometheus hostのIPアドレス>" -Profile Any
```

`windows_exporter`は既定`LocalSystem`アカウントで動作します。最小権限化はAST-07相当の継続課題として記録し、本手順では是正しません。上記のバージョン・SHA256・実行アカウントの実測値は[パラメータシート](03-parameter-sheet.md)の実機記入欄へ記録します。

Firewallルールで許可していても、この時点では中央Prometheusコンテナ側が`compose.yaml`の`monitoring`ネットワーク(`internal: true`)の制約により到達できません。したがってこの節で確認できるのは「対象ホスト上でwindows_exporterサービスが起動し、ローカルから`/metrics`が200で返り、`ad`・`dns`collectorのメトリクスが出力される」ことまでであり、中央Prometheusからのscrape成立(AIT-09)はフェーズ2まで`BLOCKED`のままです。

## 9. バックアップ設定

### 9.1 System Stateバックアップの日次スケジュール登録(AIT-06)

```powershell
Install-WindowsFeature -Name Windows-Server-Backup

# バックアップ格納先ボリュームは実機決定時に確定します(現時点でNOT SET)。
# 以降のコマンドはすべて同じ変数を使い、スケジュール登録先と単発実行の確認先がずれないようにします
$BackupTarget = "<NOT SET: バックアップ格納先ボリューム(ドライブ文字またはGUIDパス)。実機決定時に確定>"

# 毎日03:30(Asia/Tokyo)のSystem Stateバックアップを登録
wbadmin enable backup -addtarget:$BackupTarget -schedule:03:30 -systemstate -quiet
```

登録が正しく機能することを、$BackupTargetに対する単発実行で確認します。

```powershell
wbadmin start systemstatebackup -backuptarget:$BackupTarget -quiet
wbadmin get versions
```

`wbadmin get versions`にバックアップが記録されることを確認します。保持14日([Linux版](../build-package/03-parameter-sheet.md)・[Windows版](../build-package-windows/03-parameter-sheet.md)と同じ値)は本パックの目標値であり、`wbadmin enable backup`に世代数や日数を直接指定するパラメータはありません。Windows Server Backupの保持はバックアップ格納先ボリュームの空き容量に応じた自動ローテーションのため、`14日`という値を保証する仕組みそのものは存在しません。保持状況の実測確認は、`wbadmin get versions`の出力件数と最古/最新バックアップの日付範囲を日付付きevidenceへ記録して行い、値を推測で埋めません。

### 9.2 ADごみ箱の有効化

フォレスト機能レベルがWindows Server 2008 R2以上であることが条件です(`WinThreshold`は満たします)。

```powershell
Enable-ADOptionalFeature -Identity "Recycle Bin Feature" -Scope ForestOrConfigurationSet -Target corp.example.test -Confirm:$false
```

有効化は不可逆(一度有効化すると無効化できない)であることに注意してください。有効化後、削除したオブジェクトを一定期間(既定tombstone lifetime、180日)`Restore-ADObject`で復元できます。復元手順の例は次のとおりです。

```powershell
Get-ADObject -Filter { displayName -eq "test-user-for-recycle-bin" } -IncludeDeletedObjects | Restore-ADObject
```

本節はADごみ箱を有効化するところまでを扱います。削除・復元の実機での確認(AIT-06、AIT-07)は[試験仕様書・結果票](06-test-specification.md)の手順に従って別途実施し、結果を日付付きevidenceへ記録します。

### 9.3 ロールバック用の個別エクスポート取得

ロールバック用に、この時点でのFirewallルールとDefault Domain PolicyのGPOバックアップを取得しておきます(14節で使用)。

```powershell
$stamp = Get-Date -Format yyyyMMdd
New-Item -Path "C:\Backup" -ItemType Directory -Force | Out-Null

netsh advfirewall export "C:\Backup\firewall-$stamp.wfw"
Backup-GPO -Name "Default Domain Policy" -Path "C:\Backup\gpo-$stamp"
```

## 10. 中央監視への統合(既存Ansible機能)

本節のみ、中央監視host(`monitor-01`)側、または[Linux版構築手順書](../build-package/05-build-procedure.md)1〜2節で準備済みのAnsible実行環境で行います。`app_node_exporter_targets`変数へ`ad-dc01`を1行追加し、`site.yml`を再適用するだけの「済(自動)」の作業です。

```yaml
# ansible/inventory/group_vars/monitor/vars.yml など、app_node_exporter_targetsを定義している変数ファイル
app_node_exporter_targets:
  - address: "192.0.2.50:9182"
    host: "ad-dc01"
    environment: "lab"
```

```bash
cd ansible
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"

# 意図した差分(ad-dc01 targetの追加分)のみであることを確認
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff

# 中央host側へ適用
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

適用後、中央PrometheusのTargets画面またはAPIで状態を確認します。

```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.host=="ad-dc01")'
```

`app_node_exporter_targets`への追加と`site.yml`の再適用自体は正常に完了し、Prometheusの設定ファイル(`prometheus.yml`)には`ad-dc01`のtargetが反映されます。しかし`compose.yaml`の`monitoring`ネットワークが`internal: true`であるため、Prometheusコンテナは対象ホストの9182/tcpへ到達できず、上記APIの`health`は`unhealthy`または`up=0`のままです。これは[基本設計書](01-basic-design.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)に記載のとおり想定内であり、AIT-09は`BLOCKED`のまま記録します。「設定への追加が完了したこと」と「scrapeが成立すること」を区別し、後者をPASSと誤記しません。

また、現状のjob名`linux-node`へWindowsホストを混ぜる形になるため、job名が実態と合わなくなる点も残存課題として証跡に残します([Windows版パック](../build-package-windows/05-build-procedure.md)と共通の残存課題です)。

## 11. 構築後確認

対象ホスト側でサービス・Firewall・待受port・FSMO・ネットワークカテゴリを一式確認します。

```powershell
Get-Service NTDS, DNS, Netlogon, Kdc, W32Time, windows_exporter, WinRM |
  Select-Object Name, Status, StartType

Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action | Format-Table -AutoSize

# 636(LDAPS)・3269(GC LDAPS)はAD CS未導入(対象外)のため一覧に含めません。
# 待受しないことの確認は09-network-validation-procedure.mdのANW-05で別途行います
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -in 53, 88, 135, 389, 445, 464, 3268, 5986, 9182 |
  Select-Object LocalAddress, LocalPort, State

Get-NetFirewallProfile | Select-Object Name, DefaultInboundAction, Enabled

winrm enumerate winrm/config/listener

# FSMO 5役割の確認(AIT-05)
netdom query fsmo
Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster
Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster

# ネットワークカテゴリ(NLA)の確認
Get-NetConnectionProfile

# 証跡用にホストのビルド番号を採録
Get-ComputerInfo | Select-Object CsName, OsName, OsBuildNumber, WindowsProductName
```

5役割すべてが`ad-dc01`であること、`NetworkCategory`が`DomainAuthenticated`であること、`3389`(RDP)が待受に含まれていないことをあわせて確認します。

管理端末側からも確認します。

```powershell
Test-WSMan -ComputerName "ad-dc01.corp.example.test" -UseSSL
Resolve-DnsName -Name ad-dc01.corp.example.test -Server 192.0.2.50
```

フェーズ1の必須試験(AUT-01〜04、AIT-01〜08、AIT-10〜11、AST-01〜08、ANW-01〜09)の判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とし、実行結果はコマンド出力とあわせて日付付きevidenceへ保存します。

実ホストのIP、route、DNS、待受、LDAP/Kerberos到達性、Windows Defender Firewallの確認は、本節の簡易確認とは別に[ネットワーク実機検証手順](09-network-validation-procedure.md)(ANW-01〜09)に従って個別の結果票へ記録します。

## 12. 障害・復旧試験(AIT-08)

フェーズ2のアラート通知は中央Prometheusからのscrapeが前提のため`BLOCKED`です。本節の「検知」は、対象ホスト上またはWinRM経由での手動確認に限定し、その時刻をもって計測します。単一DC構成では`NTDS`サービスの停止がKerberos(`Kdc`)やNetlogonにも連鎖して認証全体を止めるため、まずは影響範囲がより限定的な`DNS`サービスで演習し、`NTDS`は影響を理解したうえでの追加演習として扱います。

1. 事前状態を確認します。

```powershell
Get-Service DNS, NTDS
Resolve-DnsName -Name ad-dc01.corp.example.test -Server 127.0.0.1
```

2. DNSサービスを停止します(検知開始時刻を記録)。

```powershell
Stop-Service DNS
Get-Service DNS
Resolve-DnsName -Name ad-dc01.corp.example.test -Server 127.0.0.1 -ErrorAction SilentlyContinue
```

3. 停止を確認した時刻(検知時刻)を記録し、復旧させます。

```powershell
Start-Service DNS
Get-Service DNS
Resolve-DnsName -Name ad-dc01.corp.example.test -Server 127.0.0.1
```

4. 正常化を確認した時刻を記録し、検知から復旧・正常化までの時間(RTO)を算出します。

5. 影響範囲を理解したうえで、`NTDS`サービスについても同様に演習します(認証・LDAP照会が一時的に完全停止することを承知のうえで実施してください)。

```powershell
Stop-Service NTDS -Force
Get-Service NTDS, Netlogon, Kdc

Start-Service NTDS
Get-Service NTDS, Netlogon, Kdc
netdom query fsmo
```

6. 検知時刻、復旧時刻、RTO、実行したコマンドと実出力を[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)の様式で日付付きevidenceへ保存します。フェーズ2導入後にGrafana / Loki経由の検知を追加した場合は、本節の手動確認による計測値と区別して記録します。

## 13. 再実行安全性の確認(AIT-11)

本節の目的は、「既に昇格済みの`ad-dc01`に対して構築手順を誤って再実行しても、既存ドメインを破壊しない」という安全装置の存在を確認することです。**この試験の目的は、危険な再実行そのものを実施することを推奨するものではありません。** 本番相当の稼働中`ad-dc01`に対して`Install-ADDSForest`を実際に再実行することは行わないでください。

確認方法は次の2段階とします。

1. **設計・既知動作の確認(必須)**: `Install-ADDSForest`は実行前に前提条件検証(`Test-ADDSForestInstallation`相当の内部チェック)を行い、対象コンピューターが既にドメインコントローラーとして構成されている(AD DSデータベースやSYSVOLが既に存在する等)と判定した場合、フォレスト作成処理そのものを開始せず、エラーとして安全に停止する既知の安全装置が備わっています。これは新しいフォレストとして作成しようとした場合、既存フォレストへ2台目のDCとして参加させようとした場合のいずれについても、既に昇格済みのコンピューターへ無条件に上書きされることを防ぐ設計です。この既知の安全装置の存在を、[詳細設計書](02-detailed-design.md)またはMicrosoft公式ドキュメントの記載と突き合わせて確認し、突合結果を証跡として残します。
2. **実機での確認(任意、実施する場合は使い捨て環境限定)**: 実際にエラーとなることを実機で確認したい場合は、本番相当の`ad-dc01`ではなく、スナップショットから複製した使い捨てのクローンVM(ネットワークから隔離し、既存フォレストへ影響を与えない環境)に対してのみ実施してください。`Install-ADDSForest`(既存設定のまま、または新しいパラメータでの再実行のいずれか)を試み、terminatingエラーで処理が停止することを確認します。エラーメッセージの文言はビルドや実行環境によって異なるため、断定的な文言をこの文書には記載せず、実行した際の実出力をそのまま証跡として保存してください。

万一、想定に反してエラーにならず処理が進行してしまった場合は、直ちに処理を中断し(可能であれば電源断)、[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ状況を記録したうえで、本番相当の`ad-dc01`には絶対に同じ操作を行わないでください。この現象は[要件定義書](00-requirements.md)NFR-02の「再実行安全性」がAD固有の非機能要件であり、Linux版・Windows版パックの「冪等性」とは異なる概念であることの理由でもあります(詳細は[初心者ガイド](beginner-guide.md#5-現場用語ブリッジ)参照)。

## 14. ロールバック

Windows対応Ansible roleが無いため、Linux版のようなcommit SHA基準の再配備によるロールバックは使えません。[変更・ロールバック計画](08-change-rollback-plan.md)および[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節に定義した優先順位に従います。

1. **最優先: VM/ハイパーバイザーのスナップショット復元。** 特にフォレスト作成(4節)は事後の巻き戻しが難しいため、0節で合意したタイミング(フォレスト作成直前)のスナップショットへ戻すことを最優先の手段とします。

```powershell
# Hyper-Vの例。取得タイミングは変更直前
Get-VMCheckpoint -VMName "ad-dc01"
Restore-VMCheckpoint -VMName "ad-dc01" -Name "<変更前に取得したチェックポイント名>" -Confirm:$false
```

2. **スナップショットが無い場合: 9.3節で取得した個別エクスポートの復元。**

```powershell
netsh advfirewall import "C:\Backup\firewall-<yyyyMMdd>.wfw"
Restore-GPO -Name "Default Domain Policy" -Path "C:\Backup\gpo-<yyyyMMdd>" -Domain corp.example.test
```

3. **データ破損時: Windows Server Backupからの復元。** ドメインコントローラー上でSystem Stateを復元するには、対象ホストをDSRM(ディレクトリサービス復元モード)で起動する必要があります。`ad-dc01`はこのフォレストの唯一のドメインコントローラーであり複製元となる他のDCが存在しないため、非権威復元・権威復元の区別が実質的な意味を持ちません(この区別は複数DC環境で、他のDCからのレプリケーションによって復元内容が上書きされることを防ぎたい場合に意味を持ちます)。

```powershell
# DSRMで起動
bcdedit /set safeboot dsrepair
Restart-Computer
```

DSRM Administrator(2節で改名したローカルAdministrator相当、4節で設定したDSRMパスワード)でログオンし、復元を実行します。

```powershell
wbadmin get versions -backupTarget:D:
wbadmin start systemstaterecovery -version:<復元対象のバージョンタイムスタンプ> -backupTarget:D: -quiet
```

復元完了後、通常起動へ戻します。

```powershell
bcdedit /deletevalue safeboot
Restart-Computer
```

いずれの手段を使った場合も、ロールバック後は11節の構築後確認と、影響範囲に応じた試験を再実行します。Go / No-Go条件、実施結果の記録様式は[変更・ロールバック計画](08-change-rollback-plan.md)を正本とします。

## 15. 作業終了

- 結果票、実行ログ、画面、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)を保存します
- 一時的なFirewall許可とテストデータを削除します

```powershell
Remove-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -ErrorAction SilentlyContinue
Remove-Item C:\temp\windows_exporter.msi -ErrorAction SilentlyContinue
Remove-Item C:\temp\ad-dc01-winrm.cer -ErrorAction SilentlyContinue

# 6節で作成した検証用オブジェクトが残っていないか再確認
Get-ADUser -Filter { Name -like "test-*" } -SearchBase "OU=Employees,OU=Users,DC=corp,DC=example,DC=test" `
  -ErrorAction SilentlyContinue | Remove-ADUser -Confirm:$false -ErrorAction SilentlyContinue

# セッション変数上のDSRMパスワードを破棄
$SafeModePwd = $null
```

- 未解決事項をIssue化します
- [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、フェーズ1・フェーズ2を区別したうえで、計画対実績、実行時間、対象ホストのビルド番号、設計差異、障害、残存リスクを記入します
- 報告書の試験集計と個別結果票の件数が一致することを確認します
- [引き渡しチェックリスト](07-handover-checklist.md)を確認し、フェーズ1必須試験に`NOT RUN` / `BLOCKED`が残る場合は受領可にしません。フェーズ2(AIT-09)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`として明記し、理由と解除条件を残します
