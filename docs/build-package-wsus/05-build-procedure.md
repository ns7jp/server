# 構築手順書

本書は、[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を受けて、`wsus-01`(Windows Server 2022 Standard、Desktop Experience基準)を既存ADドメイン`corp.example.test`(AD版パック、案件ID`SM-AD-001`が正本)へメンバーサーバーとして参加させ、フェーズ1(ホスト単体構築)の範囲でWSUS(Windows Server Update Services。Microsoft製の更新プログラム集中配信サーバー)を構築する手順を示す。

Windows対応Ansible role(`ansible/roles/common`相当のもの)は存在しないため、本書の手順はすべて「済(手動)」であり、対象ホスト上またはWinRM経由でPowerShellを実行して進める。0〜9節・11〜14節は対象ホスト(`wsus-01`)または管理端末側の作業、10節のみ中央監視host(`monitor-01`)側の作業である。フェーズ2(中央監視統合の残り)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`である。本書はフェーズ2の設計や解除条件そのものは扱わず、[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とする。

本書に記載のコマンドはすべて「手順」であり、実行結果ではない。実行日時・実出力・判定は本書に書き込まず、[試験仕様書・結果票](06-test-specification.md)の様式に従って日付付きevidenceへ記録する。

## 0. 作業前確認

- 対象: `wsus-01`(Windows Server 2022 Standard、Desktop Experience基準)検証用VM 1台。[AD版パック](../build-package-ad/00-requirements.md)の`ad-dc01`・`ad-dc02`が既に稼働し、ドメイン`corp.example.test`のAD統合DNS、`Servers`OUを含む6OU構成が存在することを前提とする(未構築の場合は本書を開始しない)。
- 対象VMの初回作業はWinRMがまだ有効化されていないため、ハイパーバイザーのVMコンソール(またはローカルコンソール)から直接ログオンして行う。WinRM HTTPS経由の管理は2節で有効化した後にのみ成立する。
- 対象IPv4/prefix(例示`192.0.2.52/24`。TEST-NET-1、RFC 5737の例示用アドレス。`ad-dc01`=`192.0.2.50/24`、`ad-dc02`=`192.0.2.51/24`と同一レンジで、重複を避けるため`.52`を使用)、管理端末IP(例示`192.0.2.40`)、管理元CIDR、内部ネットワークCIDR(いずれも環境ごとに`NOT SET`)、コンテンツストア用Dドライブ(100GB以上)の確保、作業時間帯、ロールバック条件(VM/ハイパーバイザーのスナップショット取得タイミング)を記録済みであること。
- ドメイン参加操作に使うアカウントが、常用アカウントではなくドメイン参加権限を持つ適切な権限のアカウントであること([AD版パック](../build-package-ad/03-parameter-sheet.md)のTier0の考え方を踏襲)。
- 本パックはAnsible role化されていないため、Linux版のような対象commit SHA固定によるコード配備管理は無い。ただし、本パック文書側の版(このリポジトリの`git rev-parse HEAD`)は事後の突合のため記録しておく。
- 実値の秘密情報(ローカルAdministratorの新しいパスワード、ドメイン参加アカウントの資格情報等)をIssue、PR、端末ログへ貼らない。
- [要件定義書](00-requirements.md)と[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go条件を確認済みであること。
- 本書はフェーズ1(ホスト単体構築)の範囲のみを扱うこと、10節の中央側コマンドを実行してもフェーズ2のscrapeは`compose.yaml`の`monitoring`ネットワークの制約が解消するまで成立しないことを再確認済み。

## 1. 管理端末の準備

管理端末はWindows / Linux / macOSのいずれでも構わない。本パックはPowerShell 7(`pwsh`、クロスプラットフォーム)を管理端末側の共通実行環境とする。

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
# 既存ADドメインへの到達性ベースライン確認(SM-AD-001が前提として稼働していること)
Resolve-DnsName -Name corp.example.test -Type SOA -ErrorAction SilentlyContinue
Test-Connection -ComputerName "ad-dc01.corp.example.test" -Count 2 -ErrorAction SilentlyContinue

# WinRM設定確認(現時点でのベースライン)。wsus-01は2節でHTTPSリスナーを有効化するまで未構成のため、
# この時点での接続確認は失敗して正常である
Test-WSMan -ComputerName "wsus-01.corp.example.test" -UseSSL -ErrorAction SilentlyContinue
```

上記`Test-WSMan`が失敗する(応答なし/拒否)ことを、2節・3節の作業前のベースラインとして記録する。2節でWinRM HTTPSリスナーを有効化し、3節でFirewallを管理元CIDR限定で許可した後に、あらためて同じコマンドで疎通を確認する。

## 2. Windows Server初期設定とドメイン参加

本節はVMコンソールから対象ホストへ直接ログオンして実行する(WinRMがまだ有効化されていないため)。

### 2.1 初期設定・WinRM有効化

```powershell
# コンピューター名の設定(再起動を伴う)
Rename-Computer -NewName "wsus-01" -Restart
```

再起動後、再度コンソールへログオンし、続きを実行する。

```powershell
# 固定IPの設定。default gatewayは環境ごとに決定する
New-NetIPAddress -InterfaceAlias "イーサネット" -IPAddress 192.0.2.52 -PrefixLength 24 `
  -DefaultGateway "<NOT SET: 環境ごとに決定するdefault gateway>"

# DNSは既存ADドメインのDC(ad-dc01・ad-dc02)を優先/セカンダリで指定する。
# ドメイン参加・GPO配布・後続のAレコード自動登録には、この時点でAD統合DNSへ向いている必要がある
Set-DnsClientServerAddress -InterfaceAlias "イーサネット" -ServerAddresses "192.0.2.50", "192.0.2.51"
Get-NetIPAddress -InterfaceAlias "イーサネット" -AddressFamily IPv4

# timezone設定
Set-TimeZone -Id "Tokyo Standard Time"
Get-TimeZone

# ローカルAdministratorの既定名からの変更。新しい名称は実機決定時にNOT SETを埋め、
# 実際の値はこのリポジトリではなく秘密値台帳へ記録する(ドメイン参加後のドメイン管理者アカウントとは別物)
Rename-LocalUser -Name "Administrator" -NewName "<環境ごとに決定する管理者アカウント名>"

# PowerShell 7.4系の追加導入。Windows Server 2022はWinGetが既定で無いため、
# GitHub Releasesの公式MSIを使う(バージョンは実機決定時に確認して固定、現時点NOT SET)
# ダウンロード・証明書エクスポートの一時置き場(既定では存在しないため先に作成する)
New-Item -Path C:\temp -ItemType Directory -Force | Out-Null

$PwshMsiVersion = "<NOT SET: 実機決定時にGitHub Releasesで確認するバージョン番号>"
$PwshMsiUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshMsiVersion/PowerShell-$PwshMsiVersion-win-x64.msi"
Invoke-WebRequest -Uri $PwshMsiUrl -OutFile C:\temp\pwsh-installer.msi
Start-Process msiexec.exe -ArgumentList "/i C:\temp\pwsh-installer.msi /qn /norestart ENABLE_PSREMOTING=1" -Wait
pwsh -Command '$PSVersionTable.PSVersion'

# ドメイン参加後にGet-ADComputer/Move-ADObjectをwsus-01自身で使えるようにする
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

続けて、WinRM HTTPSリスナーを作成する。証明書のDNS名には、ドメイン参加後に確定する正式なFQDN`wsus-01.corp.example.test`を先取りして使う(AD統合DNSゾーンは既存のため、`corp.example.test`自体はこの時点で既に存在している。ドメイン参加前のこの時点ではまだ`wsus-01`個別のAレコードが登録されていないだけである)。

```powershell
$cert = New-SelfSignedCertificate -DnsName "wsus-01.corp.example.test" `
  -CertStoreLocation Cert:\LocalMachine\My -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(2)
$cert.Thumbprint

# 既存リスナーを削除してから、証明書の拇印を明示してHTTPSリスナーを作成する
Get-ChildItem WSMan:\localhost\Listener | ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force }
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * `
  -CertificateThumbPrint $cert.Thumbprint -Force

# Basic認証を無効化し、Negotiateのみを許可する(NFR-03、SST-02)
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false
winrm enumerate winrm/config/listener

# 秘密鍵を含まない形でエクスポートし、管理端末側へ持ち出す(ネットワーク未開通のため、
# USBメモリやハイパーバイザーの共有フォルダなど、ネットワークを介さない方法で行う)
Export-Certificate -Cert $cert -FilePath C:\temp\wsus-01-winrm.cer
```

管理端末側で証明書をインポートする。

```powershell
Import-Certificate -FilePath .\wsus-01-winrm.cer -CertStoreLocation Cert:\LocalMachine\Root
```

### 2.2 ドメイン参加とServers OUへの移動

引き続きコンソールから実行する。

```powershell
# corp.example.testへのメンバーサーバー参加(再起動を伴う)
$domainCred = Get-Credential   # ドメイン参加権限を持つアカウント(常用アカウントではない)
Add-Computer -DomainName "corp.example.test" -Credential $domainCred -Restart
```

再起動後、`CORP\<ドメイン参加に使ったアカウント>`として再ログオンし、続きを実行する。

```powershell
# コンピューターオブジェクトを既定のComputersコンテナからServers OUへ明示的に移動する(FR-01)
$computerDn = (Get-ADComputer -Identity "wsus-01").DistinguishedName
Move-ADObject -Identity $computerDn -TargetPath "OU=Servers,DC=corp,DC=example,DC=test"

Get-ADComputer -Identity "wsus-01" -Properties DistinguishedName | Select-Object DistinguishedName

# AD統合DNSゾーンへのAレコード自動登録を確認する(動的更新による自動登録の確認手順であり、
# 手動でレコードを作成する手順ではない)
Resolve-DnsName -Name wsus-01.corp.example.test -Type A -Server 192.0.2.50
```

管理端末側からもWinRM HTTPS疎通を確認しておく(ドメイン参加後も2.1節の設定が維持されていることの確認)。

```powershell
Test-WSMan -ComputerName "wsus-01.corp.example.test" -UseSSL
```

## 3. Windows Defender FirewallとRDPの締め

ドメイン参加により、Firewallプロファイルは既定で`Domain`になる([AD版パック](../build-package-ad/03-parameter-sheet.md)・[Windows版パック](../build-package-windows/03-parameter-sheet.md)と同じ挙動)。

```powershell
Get-NetConnectionProfile

# Default Inbound Block(既定)の実効値確認。-PolicyStore ActiveStore を付けないと
# 永続ストアの値(未設定なら NotConfigured)が表示され、実効動作と一致しない場合がある
Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name, DefaultInboundAction, DefaultOutboundAction, Enabled

# WinRM(HTTPS)を管理元CIDR限定で許可(2回目実行での重複作成を避けるため存在確認してから作成する。NFR-01、SIT-02)
if (-not (Get-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly" -Direction Inbound `
      -Protocol TCP -LocalPort 5986 -Action Allow -RemoteAddress 192.0.2.40/32 -Profile Any
}

# quickconfig等が生成した全許可ルールが有効な場合は無効化し、上記の限定ルールへ一本化する
Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne (Get-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly").Name } |
  Disable-NetFirewallRule

# RDPは既定Disable(NFR-04、SST-03)
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Disable-NetFirewallRule
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Select-Object DisplayName, Enabled

# 障害時に一時的にRDPを許可するためのルール(平時はEnabled:Falseで登録し、必要時のみ有効化する。NFR-01、SIT-02)
if (-not (Get-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -Direction Inbound `
      -Protocol TCP -LocalPort 3389 -Action Allow -RemoteAddress 192.0.2.40/32 `
      -Profile Any -Enabled False
}
```

管理端末側で疎通を再確認する。

```powershell
Test-WSMan -ComputerName "wsus-01.corp.example.test" -UseSSL
$cred = Get-Credential   # ドメインアカウント(CORP\<アカウント名>)
Enter-PSSession -ComputerName "wsus-01.corp.example.test" -UseSSL -Credential $cred
```

管理元CIDR以外からの接続拒否確認(SNW-09相当)は、[ネットワーク実機検証手順](09-network-validation-procedure.md)で別途正式に行う。ここでは作業継続のための疎通チェックにとどめる。

## 4. WSUSロールのインストールとコンテンツストア設定(コンソール初回起動前のコマンドライン初期化を含む)

以降はWinRMのリモートセッションからでも、コンソールからでも実行できる。

### 4.1 コンテンツストア用ボリュームの確認

コンテンツストア専用のDドライブ(100GB以上)は0節の前提条件でVM/ハイパーバイザー側から確保済みであること。未初期化の場合のみ以下を実行する。

```powershell
Get-Volume | Select-Object DriveLetter, FileSystemLabel, DriveType, SizeRemaining, Size

# 未初期化ディスクがある場合のみ(初期化・パーティション作成は初回のみ)
Get-Disk | Where-Object OperationalStatus -eq "Offline" | Select-Object Number, Size
# Initialize-Disk -Number <番号> -PartitionStyle GPT
# New-Partition -DiskNumber <番号> -UseMaximumSize -DriveLetter D |
#   Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUSContent" -Confirm:$false
```

### 4.2 WSUSロールのインストール

```powershell
# WSUS本体機能とWID接続用サブ機能を同時に有効化する(系統A、FR-02)
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
Get-WindowsFeature -Name UpdateServices* | Where-Object Installed
```

### 4.3 コンテンツディレクトリの初期化(コンソールを開く前に必須)

```powershell
New-Item -Path "D:\WSUS\WSUSContent" -ItemType Directory -Force | Out-Null

# コンソールを初めて開く前に、コマンドラインでコンテンツディレクトリを初期化する。
# これを忘れるとコンソール起動時にエラーになる、実務でよくあるつまずきである
& "$env:ProgramFiles\Update Services\Tools\wsusutil.exe" postinstall CONTENT_DIR=D:\WSUS\WSUSContent
```

`postinstall`の完了後、WSUSサービス(`WsusService`)の起動を確認する(SUT-02、SUT-03)。

```powershell
Get-Service WsusService | Select-Object Name, Status, StartType
Get-Website | Where-Object Name -like "WSUS*"
```

## 5. IIS(WsusPool)チューニングとwindows_exporter導入(ハッシュ検証を含む)

### 5.1 IISアプリケーションプール(WsusPool)チューニング

WSUS運用で運用上広く知られた3つの推奨設定を適用する(NFR-07)。

```powershell
Import-Module WebAdministration

# アイドルタイムアウトを0にする(アイドル後のプール停止による直後のクライアント同期失敗を避ける)
Set-ItemProperty "IIS:\AppPools\WsusPool" -Name processModel.idleTimeout -Value ([TimeSpan]::FromMinutes(0))

# キュー長を既定1000から2000程度へ引き上げる(多数クライアント同時アクセスでの503エラーを避ける)
Set-ItemProperty "IIS:\AppPools\WsusPool" -Name queueLength -Value 2000

# プライベートメモリ制限を0(無制限)にする(既定のリサイクルによる同期処理中断を避ける)
Set-ItemProperty "IIS:\AppPools\WsusPool" -Name recycling.periodicRestart.privateMemory -Value 0

Get-ItemProperty "IIS:\AppPools\WsusPool" -Name processModel.idleTimeout, queueLength, recycling.periodicRestart.privateMemory
```

### 5.2 windows_exporter(ハッシュ検証を含む)

```powershell
# バージョンは実機決定時にGitHub Releasesで確認して固定する(現時点でNOT SET)
$version = "<NOT SET: 実機決定時にGitHub Releasesで確認するバージョン番号>"
$msiUrl  = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
$msiPath = "C:\temp\windows_exporter.msi"

Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

# 公開SHA256とのハッシュ一致確認(SUT-04)。期待値はGitHub Releasesのchecksumファイルから取得し、
# ここでの値を推測・仮置きしない
$expectedHash = "<NOT SET: 実機決定時に公開されているSHA256>"
$actualHash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "windows_exporter MSIのハッシュが一致しません。expected=$expectedHash actual=$actualHash"
}

# WSUS管理サイトがIIS上で動くため、iisコレクターを追加で有効化する
Start-Process msiexec.exe -ArgumentList `
  "/i `"$msiPath`" ENABLED_COLLECTORS=cpu,cs,logical_disk,net,os,service,iis /qn" -Wait

Get-Service windows_exporter
Get-CimInstance Win32_Service -Filter "Name='windows_exporter'" | Select-Object Name, StartName, State, PathName

# ローカルからの疎通確認(中央Prometheusはフェーズ2まで到達不可のため、この時点ではローカル確認のみ)
curl.exe http://localhost:9182/metrics | Select-String "windows_iis_"

# Firewall: 中央Prometheus hostのIPのみ許可(認証なし。値は環境ごとに決定するためNOT SET。
# 2回目実行での重複作成を避けるため存在確認してから作成する。NFR-01、SIT-02)
if (-not (Get-NetFirewallRule -DisplayName "WindowsExporter-Prometheus-Only" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WindowsExporter-Prometheus-Only" -Direction Inbound `
      -Protocol TCP -LocalPort 9182 -Action Allow `
      -RemoteAddress "<NOT SET: 中央Prometheus hostのIPアドレス>" -Profile Any
}

# WSUSコンテンツ(8530/tcp)を内部ネットワークCIDR限定で許可
if (-not (Get-NetFirewallRule -DisplayName "WSUS-Content-InternalOnly" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WSUS-Content-InternalOnly" -Direction Inbound `
      -Protocol TCP -LocalPort 8530 -Action Allow `
      -RemoteAddress "<NOT SET: 環境ごとに決定する内部ネットワークCIDR>" -Profile Any
}
```

`windows_exporter`は既定`LocalSystem`アカウントで動作する。最小権限化は継続課題として記録し、本手順では是正しない。バージョン・SHA256の実測値は[パラメータシート](03-parameter-sheet.md)の実機記入欄へ記録する。

## 6. WSUS初期構成ウィザード(同期元・プロキシ・言語・製品・分類・同期スケジュール)

コンソールを初めて開くと「Windows Server Update Services構成ウィザード」がGUIで表示されるが、本手順はGUI操作を前提とせず、`UpdateServices`モジュールと`Get-WsusServer`が返す設定オブジェクトを使い、ウィザードの各画面に相当する項目をコードで設定する。以降のコードブロックはウィザードの画面順に対応させてコメントしている。

```powershell
Import-Module UpdateServices
$wsus = Get-WsusServer -Name "wsus-01" -PortNumber 8530
$config = $wsus.GetConfiguration()

# 画面「アップストリームサーバーの選択」: このWSUSが最初かつ唯一のため、レプリカ/ダウンストリームは
# 取らず、Microsoft Updateを直接の同期元とする(スタンドアロン/ルート)
$config.SyncFromMicrosoftUpdate = $true

# 画面「プロキシサーバー」: ラボは直接接続のため使用しない
$config.UseProxy = $false

# 「更新プログラムをこのサーバーに保存する」を有効(ローカル保存)にする。
# これにより承認操作が実際の配信を制御できるようになる
$config.HostBinariesOnMicrosoftUpdate = $false

$config.Save()
```

初回のカテゴリ(製品・分類)一覧を取得するには、一度カテゴリのみの同期が必要である。

```powershell
$subscription = $wsus.GetSubscription()
$subscription.StartSynchronizationForCategoryOnly()

# 完了まで待機する。初回は選択した製品・分類のメタデータ取得だけでも相応の時間がかかるため、
# 具体的な所要時間は断定しない
while ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    Start-Sleep -Seconds 30
}
$subscription.GetLastSynchronizationInfo().Result
```

画面「言語の選択」に相当する設定。不要な言語を同期しないことで、コンテンツストア容量を抑える。

```powershell
$config.AllUpdateLanguagesEnabled = $false
$config.SetEnabledUpdateLanguages(@("en", "ja"))
$config.Save()
```

画面「製品の選択」に相当する設定。ラボで検証する製品に絞り、無制限に同期しない。

```powershell
$allProducts = Get-WsusProduct -UpdateServer $wsus
$targetProducts = $allProducts | Where-Object { $_.Product.Title -in @("Windows Server 2022", "Windows 11") }
Set-WsusProduct -UpdateServer $wsus -Product $targetProducts

Get-WsusProduct -UpdateServer $wsus | Where-Object Selected -eq $true |
  Select-Object -ExpandProperty Product | Select-Object Title
```

画面「分類の選択」に相当する設定。ドライバー同期はコンテンツが肥大化しやすく、サーバー用途では基本的に不要なため除外する。

```powershell
$allClass = Get-WsusClassification -UpdateServer $wsus
$targetClass = $allClass | Where-Object {
    $_.Classification.Title -in @("Critical Updates", "Security Updates", "Updates", "Update Rollups")
}
Set-WsusClassification -UpdateServer $wsus -Classification $targetClass

Get-WsusClassification -UpdateServer $wsus | Where-Object Selected -eq $true |
  Select-Object -ExpandProperty Classification | Select-Object Title
```

画面「同期スケジュール」に相当する設定。毎日01:00(Asia/Tokyo)の自動同期とする。

```powershell
$subscription.SynchronizeAutomatically = $true
$subscription.SynchronizeAutomaticallyTimeOfDay = [TimeSpan]"01:00:00"
$subscription.NumberOfSynchronizationsPerDay = 1
$subscription.Save()

$subscription.SynchronizeAutomatically
$subscription.SynchronizeAutomaticallyTimeOfDay
```

対象製品・分類を確定させたうえでの本番同期(全メタデータの取得)は、9節で改めて実行する。

## 7. GPOの作成とクライアント側ターゲティング

設定項目はグループポリシー管理エディターの管理用テンプレート内、Windows Update関連ノードにある項目である。バージョンによってノードの階層が変わることがあるため、正確なメニュー階層は断定せず、設定「項目名」とその実体であるレジストリ値で示す。

```powershell
# GroupPolicyモジュール(New-GPO/New-GPLink/Set-GPRegistryValue)は2.1節のRSAT-AD-PowerShellには
# 含まれないため、GPMC(グループポリシー管理コンソール)を別途導入する
Install-WindowsFeature -Name GPMC
Import-Module GroupPolicy

$gpoName = "WSUS-Client-Policy"

# 2回目実行での重複作成を避けるため、既存GPOがあれば再利用する(NFR-01、SIT-02)
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name $gpoName -Comment "WSUSクライアント設定。Servers OUへのみリンクする"
}

# ドメイン直下や_Tier0-Admins OUへは広げすぎない設計判断として、Servers OUのみへリンクする。
# 既にリンク済みの場合New-GPLinkはエラーになるため、そのエラーだけを許容する
try {
    New-GPLink -Name $gpoName -Target "OU=Servers,DC=corp,DC=example,DC=test" -LinkEnabled Yes
} catch {
    if ($_.Exception.Message -notmatch "already linked") { throw }
}

$auKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
$wuKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# 「自動更新を構成する」を有効にし、オプション3(自動ダウンロードを行い、インストールの通知を行う)を選択する。
# オプション4(自動インストール・自動再起動)ではなく通知にとどめ、無人再起動によるサービス影響を避ける
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "NoAutoUpdate" -Type DWord -Value 0
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "AUOptions" -Type DWord -Value 3
Set-GPRegistryValue -Name $gpoName -Key $auKey -ValueName "UseWUServer" -Type DWord -Value 1

# 「イントラネット Microsoft 更新サービスの場所を指定する」を有効にし、検出サービス・統計サービスの
# 両方にwsus-01.corp.example.testの8530番ポート宛URLを設定する
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "WUServer" -Type String -Value "http://wsus-01.corp.example.test:8530"
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "WUStatusServer" -Type String -Value "http://wsus-01.corp.example.test:8530"

# 「クライアント側ターゲティングを有効にする」を有効にし、対象グループ名をServersとする。
# WSUSコンソール側で作成するコンピューターグループ名(8節)と一致させる必要がある
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "TargetGroupEnabled" -Type DWord -Value 1
Set-GPRegistryValue -Name $gpoName -Key $wuKey -ValueName "TargetGroup" -Type String -Value "Servers"

# 自動更新の検出頻度は既定値のまま変更しない(DetectionFrequencyEnabledは設定しない)
```

`wsus-01`自身もこのGPOの適用対象(`Servers`OU)に含まれるため、即時適用・確認を行う。

```powershell
gpupdate /force /target:computer
gpresult /r /scope computer

# グループポリシー操作ログでエラーが無いことを確認する
Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational" -MaxEvents 20 |
  Select-Object TimeCreated, Id, LevelDisplayName

# レジストリへの反映確認
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ErrorAction SilentlyContinue
```

## 8. コンピューターグループ・承認ルール・クリーンアップウィザードの設定

ADの組織単位(OU)と、WSUSコンソール内の「コンピューターグループ」は別の概念である。7節の`Servers`OUはコンピューターオブジェクトの配置場所、ここで作る`Servers`グループはWSUSが独自に管理するクライアント分類であり、名前が同じでも別の仕組みである点を混同しないこと。

```powershell
$wsus = Get-WsusServer -Name "wsus-01" -PortNumber 8530

# 「すべてのコンピューター」の下にServersグループを手動作成し、GPOのクライアント側
# ターゲティング(7節)の対象グループ名と一致させる。2回目実行での重複作成を避けるため、
# 既存グループがあれば再利用する(NFR-01、SIT-02)
$allComputers = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq "All Computers" }
$serversGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq "Servers" }
if (-not $serversGroup) {
    $serversGroup = $wsus.CreateComputerTargetGroup("Servers", $allComputers)
}

# Serversの下にPilotサブグループを作成する(段階的展開の受け皿)。同様に既存グループを再利用する
$pilotGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq "Pilot" }
if (-not $pilotGroup) {
    $pilotGroup = $wsus.CreateComputerTargetGroup("Pilot", $serversGroup)
}

$wsus.GetComputerTargetGroups() | Select-Object Name, Id
```

自動承認ルールを1件作成する。無人承認による意図しない適用を避けるため、自動実行のスケジュール化は行わず、手動実行にとどめる設計とする。

```powershell
$ruleName = "Critical and Security Updates - Pilot Auto-Approve"

# 2回目実行での重複作成を避けるため、既存ルールがあれば再利用する(NFR-01、SIT-02)
$rule = $wsus.GetInstallApprovalRules() | Where-Object { $_.Name -eq $ruleName }
if (-not $rule) {
    $rule = $wsus.CreateInstallApprovalRule($ruleName)
}

$classifications = $wsus.GetUpdateClassifications() |
  Where-Object { $_.Title -in @("Critical Updates", "Security Updates") }
$products = $wsus.GetUpdateCategories() | Where-Object { $_.Title -eq "Windows Server 2022" }

$rule.SetUpdateClassifications($classifications)
$rule.SetCategories($products)
$rule.SetComputerTargetGroups(@($pilotGroup))

# スケジュール化しない安全側の判断として、ルール自体はEnabled=falseのまま保存し、
# 実行は9節でApplyRule()による手動実行にとどめる
$rule.Enabled = $false
$rule.Save()

$wsus.GetInstallApprovalRules() | Select-Object Name, Enabled
```

それ以外の更新プログラムは手動承認とする(手順は9節で扱う)。

クリーンアップウィザード相当のコマンドレット(`Invoke-WsusServerCleanup`)を、毎週日曜03:00(Asia/Tokyo)にタスクスケジューラへ登録する。

```powershell
$cleanupCommand = 'Import-Module UpdateServices; ' +
  'Invoke-WsusServerCleanup -CleanupObsoleteComputers -CleanupObsoleteUpdates ' +
  '-CleanupUnneededContentFiles -CompressUpdates -DeclineExpiredUpdates -DeclineSupersededUpdates ' +
  '| Out-File -FilePath "C:\WSUS\Logs\cleanup-$(Get-Date -Format yyyyMMdd).log"'

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -Command `"$cleanupCommand`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 03:00
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

New-Item -Path "C:\WSUS\Logs" -ItemType Directory -Force | Out-Null
Register-ScheduledTask -TaskName "WSUS-Cleanup-Weekly" -Action $action -Trigger $trigger `
  -Principal $principal -Description "WSUSサーバークリーンアップウィザード相当(Invoke-WsusServerCleanup)の週次実行"

Get-ScheduledTask -TaskName "WSUS-Cleanup-Weekly"
```

## 9. 初回同期・承認・適用の一巡確認

対象製品・分類・言語を確定させたうえで、本番同期(全メタデータの取得)を実行する。

```powershell
$wsus = Get-WsusServer -Name "wsus-01" -PortNumber 8530
$subscription = $wsus.GetSubscription()
$subscription.StartSynchronization()

while ($subscription.GetSynchronizationStatus() -ne "NotProcessing") {
    Start-Sleep -Seconds 60
}
$subscription.GetLastSynchronizationInfo() | Select-Object Result, EndTime, Error
```

`wsus-01`自身をWSUSクライアントとして登録・検出させる。7節で配布したGPOが適用済みであることを前提とする。

```powershell
gpupdate /force /target:computer

# 更新の検出をすぐに走らせる。UsoClientはWindows 10/Server 2016以降で使われる
# 検出トリガーで、旧来のwuauclt /detectnowに代わるものである
UsoClient.exe StartScan

Start-Sleep -Seconds 60
```

WSUSコンソール側で`wsus-01`が`Servers`グループへ自己登録されていることを確認する(SIT-04)。

```powershell
Get-WsusComputer -UpdateServer $wsus |
  Where-Object FullDomainName -eq "wsus-01.corp.example.test" |
  Select-Object FullDomainName, IPAddress, LastReportedStatusTime
```

クライアント側ターゲティング(7節)による自己登録は、GPOで指定した`Servers`グループへの登録だけであり、`Pilot`サブグループへは自動的には入らない。[パラメータシート](03-parameter-sheet.md)の設計どおり`wsus-01`自身も`Pilot`の検証対象とするため、明示的に`Pilot`グループへ追加する。この手順を省くと、次の自動承認ルールがPilotグループ向けにしか更新を承認しないため、`wsus-01`には何も適用されずSIT-05が成立しない。

```powershell
$wsusComputer = $wsus.GetComputerTargetGroups() |
  Where-Object { $_.Name -eq "Servers" } |
  ForEach-Object { $_.GetComputerTargets() } |
  Where-Object { $_.FullDomainName -eq "wsus-01.corp.example.test" }

# 既にPilotグループへ登録済みの場合はAddComputerTargetがエラーになるため、そのエラーだけを許容する(NFR-01、SIT-02)
try {
    $pilotGroup.AddComputerTarget($wsusComputer)
} catch {
    if ($_.Exception.Message -notmatch "already a member") { throw }
}

$pilotGroup.GetComputerTargets() | Select-Object FullDomainName
```

Pilotグループ向けの自動承認ルール(8節)を手動実行し、対象更新を承認する。

```powershell
$rule = $wsus.GetInstallApprovalRules() | Where-Object Name -eq "Critical and Security Updates - Pilot Auto-Approve"
$rule.ApplyRule()

# それ以外の更新は手動承認の例
Get-WsusUpdate -UpdateServer $wsus -Classification Critical, Security -Approval Unapproved |
  Select-Object -First 5 -Property Title, Id |
  ForEach-Object { Approve-WsusUpdate -UpdateServer $wsus -Update $_.Id -Action Install -TargetGroupName "Pilot" }
```

`wsus-01`側で更新プログラムのダウンロード・インストールを進め、適用結果を確認する(SIT-05)。

```powershell
UsoClient.exe StartDownload
UsoClient.exe StartInstall

Start-Sleep -Seconds 120
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5
Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational" -MaxEvents 20 |
  Select-Object TimeCreated, Id, LevelDisplayName
```

承認状況・準拠状況はWSUSコンソールのレポート機能でも確認できる(NFR-08)。Windows Server 2016以降のWSUSコンソールでレポート機能を使うには、別途レポート表示用ランタイムの追加インストールが必要になる場合があるという、実務でよく知られたつまずきがある。コンソールでレポートタブを開いてエラーが出た場合は、まずこのランタイムの有無を確認する。

## 10. 中央監視への統合(フェーズ2、現状BLOCKEDである理由を明記)

本節のみ、中央監視host(`monitor-01`)側、または[Linux版構築手順書](../build-package/05-build-procedure.md)1〜2節で準備済みのAnsible実行環境で行う。`app_node_exporter_targets`変数へ`wsus-01`を1行追加し、`site.yml`を再適用するだけの「済(自動)」の作業である。

```yaml
# ansible/inventory/group_vars/monitor/vars.yml など、app_node_exporter_targetsを定義している変数ファイル
app_node_exporter_targets:
  - address: "192.0.2.52:9182"
    host: "wsus-01"
    environment: "lab"
```

```bash
cd ansible
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"

# 意図した差分(wsus-01 targetの追加分)のみであることを確認
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

適用後、中央PrometheusのTargets画面またはAPIで状態を確認する。

```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.host=="wsus-01")'
```

`app_node_exporter_targets`への追加と`site.yml`の再適用自体は正常に完了し、`prometheus.yml`には`wsus-01`のtargetが反映される。しかし次の3点が解消するまで、上記APIの`health`は`unhealthy`または`up=0`のままであり、SIT-09は`BLOCKED`のまま記録する。この3点の理由付けは[Windows版パック](../build-package-windows/05-build-procedure.md)・[AD版パック](../build-package-ad/05-build-procedure.md)と同じ扱いであり、本パック独自の理由には作り替えない。

1. `ansible/roles`配下にWindows対応role(`common_windows`等)が無く、Ansibleでの自動構築ができない。
2. `compose.yaml`の`monitoring`ネットワークが`internal: true`であり、Prometheusコンテナは同じDockerホストの外にある実マシン(`wsus-01`)の9182/tcpへ到達できない。
3. Windows Event Log/WSUS同期ログ/IISログを既存Lokiへ送る経路(Grafana Alloy for Windowsの導入等)が無い。

「設定への追加が完了したこと」と「scrapeが成立すること」は別の状態であり、後者を`PASS`と誤記しない。

## 11. 構築後確認

対象ホスト側でサービス・Firewall・待受port・WSUS関連コンポーネントを一式確認する。

```powershell
Get-Service WsusService, W3SVC, windows_exporter, WinRM | Select-Object Name, Status, StartType

Get-IISAppPool WsusPool | Select-Object Name, State
Get-ItemProperty "IIS:\AppPools\WsusPool" -Name processModel.idleTimeout, queueLength, recycling.periodicRestart.privateMemory

Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action | Format-Table -AutoSize

Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -in 5986, 8530, 9182 |
  Select-Object LocalAddress, LocalPort, State

Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name, DefaultInboundAction, Enabled
winrm enumerate winrm/config/listener

# 証跡用にホストのビルド番号を採録
Get-ComputerInfo | Select-Object CsName, OsName, OsBuildNumber, WindowsProductName

# ドメイン参加・OU配置の再確認
Get-ADComputer -Identity "wsus-01" -Properties DistinguishedName | Select-Object DistinguishedName
```

管理端末側からも確認する。

```powershell
Test-WSMan -ComputerName "wsus-01.corp.example.test" -UseSSL
Invoke-WebRequest -Uri "http://wsus-01.corp.example.test:8530/ClientWebService/client.asmx" -UseBasicParsing |
  Select-Object StatusCode
```

フェーズ1の必須試験(SUT-01〜05、SIT-01〜08、SST-01〜06、SNW-01〜09)の判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とし、実行結果はコマンド出力とあわせて日付付きevidenceへ保存する。実ホストのIP、route、DNS、待受、HTTP、Windows Defender Firewallの確認は、本節の簡易確認とは別に[ネットワーク実機検証手順](09-network-validation-procedure.md)(SNW-01〜09)に従って個別の結果票へ記録する。

## 12. 障害・復旧試験

フェーズ2のアラート通知は中央Prometheusからのscrapeが前提のため`BLOCKED`である。本節の「検知」は、対象ホスト上またはWinRM経由での手動確認に限定し、その時刻をもって計測する。

1. 事前状態を確認する。

```powershell
Get-Service WsusService, W3SVC
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8530/ClientWebService/client.asmx
```

2. WSUSサービスを停止する(検知開始時刻を記録)。

```powershell
Stop-Service WsusService
Get-Service WsusService
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8530/ClientWebService/client.asmx
```

3. 停止を確認した時刻(検知時刻)を記録し、復旧させる。

```powershell
Start-Service WsusService
Get-Service WsusService
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8530/ClientWebService/client.asmx
```

4. 正常化を確認した時刻を記録し、検知から復旧・正常化までの時間(RTO)を算出する。

5. IIS(`W3SVC`)についても同様に演習する。WSUS管理サイトはIIS上で動作するため、`W3SVC`の停止はWSUSコンテンツ配信・クライアント通信全体に影響する。

```powershell
Stop-Service W3SVC
Get-Service W3SVC, WsusService

Start-Service W3SVC
Get-Service W3SVC, WsusService
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8530/ClientWebService/client.asmx
```

6. 検知時刻、復旧時刻、RTO、実行したコマンドと実出力を[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)の様式で日付付きevidenceへ保存する。

## 13. ロールバック(VM/ハイパーバイザーのスナップショット復元を主手段とする)

Windows対応Ansible roleが無いため、Linux版のようなcommit SHA基準の再配備によるロールバックは使えない。[変更・ロールバック計画](08-change-rollback-plan.md)および[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節に定義した優先順位に従う。

1. **最優先: VM/ハイパーバイザーのスナップショット復元。**

```powershell
# Hyper-Vの例。取得タイミングは各節の変更直前(特にドメイン参加直前、WSUSロール導入直前)
Get-VMCheckpoint -VMName "wsus-01"
Restore-VMCheckpoint -VMName "wsus-01" -Name "<変更前に取得したチェックポイント名>" -Confirm:$false
```

2. **スナップショットが無い場合: 個別エクスポートの復元。**

事前に、変更前時点でのFirewallルール・GPOバックアップを取得しておく。

```powershell
$stamp = Get-Date -Format yyyyMMdd
New-Item -Path "C:\Backup" -ItemType Directory -Force | Out-Null
netsh advfirewall export "C:\Backup\firewall-$stamp.wfw"
Backup-GPO -Name "WSUS-Client-Policy" -Path "C:\Backup\gpo-$stamp"
```

復元時は次のとおり。

```powershell
netsh advfirewall import "C:\Backup\firewall-<yyyyMMdd>.wfw"
Restore-GPO -BackupId "<Backup-GPOの出力から得たID>" -Path "C:\Backup\gpo-<yyyyMMdd>"
```

3. **データ破損時: SUSDB・コンテンツストアからの復元。**

SUSDB(WID)は、WIDのローカル名前付きパイプ(`\\.\pipe\MICROSOFT##WID`)経由でのバックアップ復元、または対象ホスト全体をWindows Server Backupでシステム状態含めて復元する方式のいずれかを設計として示す(実機で選定)。コンテンツストア(`D:\WSUS\WSUSContent`)は、フォルダー全体のバックアップから復元する。

```powershell
wbadmin get versions
wbadmin start recovery -version:<復元対象のバージョンタイムスタンプ> -itemtype:File `
  -items:D:\WSUS\WSUSContent -recoveryTarget:D:\WSUS\WSUSContent -notrestoresecurity
```

いずれの手段を使った場合も、ロールバック後は11節の構築後確認と、影響範囲に応じた試験を再実行する。Go / No-Go条件、実施結果の記録様式は[変更・ロールバック計画](08-change-rollback-plan.md)を正本とする。

## 14. 作業終了

- 結果票、実行ログ、画面、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)を保存する。
- 一時的なFirewall許可とテストデータを削除する。

```powershell
Remove-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -ErrorAction SilentlyContinue
Remove-Item C:\temp\windows_exporter.msi -ErrorAction SilentlyContinue
Remove-Item C:\temp\pwsh-installer.msi -ErrorAction SilentlyContinue
Remove-Item C:\temp\wsus-01-winrm.cer -ErrorAction SilentlyContinue
```

- 未解決事項をIssue化する。
- [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、フェーズ1・フェーズ2を区別したうえで、計画対実績、実行時間、対象ホストのビルド番号、設計差異、障害、残存リスクを記入する。
- 報告書の試験集計と個別結果票の件数が一致することを確認する。
- [引き渡しチェックリスト](07-handover-checklist.md)を確認し、フェーズ1必須試験に`NOT RUN`/`BLOCKED`が残る場合は受領可にしない。フェーズ2(SIT-09)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`として明記し、理由と解除条件を残す。本パックの引き渡し判定は`NOT READY`であり、実機での構築・試験実績が揃うまで`READY`へ変更しない。
