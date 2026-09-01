# 構築手順書

本書は、[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[パラメータシート](03-parameter-sheet.md)を受けて、monitor-win-01(Windows Server 2022 Standard、Desktop Experience基準)をフェーズ1(ホスト単体構築)の範囲で構築する手順を示します。系統A(ワークグループ)を既定とし、系統B(ADドメイン参加)との差分がある箇所はその都度明記します。

Ansible role化された自動構築経路(`ansible/roles/common`相当のWindows対応role)は存在しません。本書の手順はすべて「済(手動)」であり、対象ホスト上またはWinRM経由でPowerShellを実行して進めます。0〜4節・6〜9節は対象ホスト(monitor-win-01)側の作業、5節のみ中央監視host(monitor-01)側の作業です。5節の`app_node_exporter_targets`変数への追加と`site.yml`再適用だけは「済(自動)」の既存Ansible機能であり、他の節とは性質が異なる点に注意してください。

フェーズ2(中央監視統合の残り、すなわちwindows_exporterのscrape・blackbox probe・ログ集約)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`です。本書はフェーズ2の設計や解除条件そのものは扱わず、[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします。

## 0. 作業前確認

- 対象: monitor-win-01(Windows Server 2022 Standard、Desktop Experience基準)検証用VM 1台
- 対象VMの初回作業はWinRMがまだ有効化されていないため、ハイパーバイザーのVMコンソール(またはローカルコンソール)から直接ログオンして行います。WinRM HTTPS経由の管理は2節で有効化した後にのみ成立します
- 対象IPアドレス(例示: `192.0.2.30`)、例示FQDN(`monitor-win.example.test`)、管理端末IP(例示: `192.0.2.40`)、作業時間帯、ロールバック条件(VM/ハイパーバイザーのスナップショット取得タイミング)を記録済み
- 本パックはAnsible role化されていないため、Linux版のような対象commit SHA固定によるコード配備管理はありません。ただし、本パック文書側の版(このリポジトリの`git rev-parse HEAD`)は事後の突合のため記録しておきます
- 実値の秘密情報(証明書秘密鍵、ローカルAdministratorの新しいパスワード等)をIssue、PR、端末ログへ貼りません
- [要件定義書](00-requirements.md)と[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go条件を確認済み
- 本書はフェーズ1(ホスト単体構築)の範囲のみを扱うこと、5節の中央側コマンドを実行してもフェーズ2のscrapeは`compose.yaml`の`monitoring`ネットワークの制約が解消するまで成立しないことを再確認済み

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
Test-WSMan -ComputerName "monitor-win.example.test" -UseSSL -ErrorAction SilentlyContinue
```

上記`Test-WSMan`が失敗する(応答なし/拒否)ことを、2節・3節の作業前のベースラインとして記録します。2節でWinRM HTTPSリスナーを有効化し、3節でFirewallを管理元CIDR限定で許可した後に、あらためて同じコマンドで疎通を確認します。

## 2. Windows Server初期設定とWinRM有効化

本節はVMコンソールから対象ホストへ直接ログオンして実行します(WinRMがまだ有効化されていないため)。

```powershell
# コンピューター名の設定(再起動を伴います)
Rename-Computer -NewName "monitor-win-01" -Restart
```

再起動後、再度コンソールへログオンし、続きを実行します。

```powershell
# timezone設定
Set-TimeZone -Id "Tokyo Standard Time"
Get-TimeZone

# ローカルAdministratorの既定名からの変更(系統Aのみ。新しい名称は実機決定時にNOT SETを埋め、
# 実際の値はこのリポジトリではなく秘密値台帳へ記録します。以下は手順の例です)
Rename-LocalUser -Name "Administrator" -NewName "<環境ごとに決定する管理者アカウント名>"

# Windows Update設定の確認(既定: Microsoft Updateから直接、自動ダウンロード・手動再起動)
# ポリシーで上書きしている場合は下記キーに値が入ります。系統Bはこの節をWSUS/グループポリシー側の
# 設定確認に読み替えます
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue

# PowerShell 7.4系の追加導入(対象ホスト側)
winget install --id Microsoft.PowerShell --source winget
pwsh -Command '$PSVersionTable.PSVersion'
```

続けて、WinRM HTTPSリスナーを作成します。系統Aは自己署名証明書、系統Bは内部CA発行証明書を使う設計ですが、以下は系統Aの例です。

```powershell
# WinRM HTTPS用の証明書(系統A: 自己署名。系統Bは内部CAが発行したものに読み替え)
$cert = New-SelfSignedCertificate -DnsName "monitor-win.example.test" `
  -CertStoreLocation Cert:\LocalMachine\My -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(2)
$cert.Thumbprint

# WinRM HTTPSリスナーの作成
winrm quickconfig -transport:https -force

# 既存のHTTPリスナーが残っている場合は削除し、HTTPS専用にする
Get-ChildItem WSMan:\localhost\Listener |
  Where-Object { (Get-Item "$($_.PSPath)\Transport").Value -eq "HTTP" } |
  ForEach-Object { Remove-Item -Path $_.PSPath -Recurse -Force }

# Basic認証を無効化し、Negotiateのみを許可する(NFR-03)
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

winrm enumerate winrm/config/listener
```

系統A(自己署名証明書)の場合、管理端末が証明書を信頼できるようエクスポート・配布します。ネットワーク経由の配布は3節でFirewallを開けた後になるため、初回はUSBメモリやハイパーバイザーの共有フォルダなど、ネットワークを介さない方法で管理端末へ持ち出します。

```powershell
# 対象ホスト側: 証明書のエクスポート(秘密鍵は含めない)
Export-Certificate -Cert $cert -FilePath C:\temp\monitor-win-01-winrm.cer
```

```powershell
# 管理端末側: 信頼済みルートへのインポート(自己署名証明書を許容する場合のみ)
Import-Certificate -FilePath .\monitor-win-01-winrm.cer -CertStoreLocation Cert:\LocalMachine\Root
```

この時点ではFirewallが未設定のため、管理端末からの`Test-WSMan`はまだ成立しません。疎通確認は3節末で実施します。

## 3. Windows Defender FirewallとRDPの締め

引き続き対象ホスト側で実行します。

```powershell
# 系統A: Firewallプロファイルの確認・設定(既定Public。検証用途に応じてPrivateへ変更可)
Get-NetConnectionProfile
# 系統Bの場合はドメイン参加により既定でDomainプロファイルになります

# Default Inbound Block(既定)の確認
Get-NetFirewallProfile | Select-Object Name, DefaultInboundAction, DefaultOutboundAction, Enabled

# WinRM(HTTPS)を管理元CIDR限定で許可
New-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly" -Direction Inbound `
  -Protocol TCP -LocalPort 5986 -Action Allow `
  -RemoteAddress 192.0.2.40/32 -Profile Public

# quickconfigが自動生成した既定ルール(全許可)が有効な場合は無効化し、上記の限定ルールへ一本化する
Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne (Get-NetFirewallRule -DisplayName "WinRM-HTTPS-MgmtOnly").Name } |
  Disable-NetFirewallRule

# RDPは既定Disable(NFR-04)
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Disable-NetFirewallRule
Get-NetFirewallRule -DisplayGroup "リモート デスクトップ" | Select-Object DisplayName, Enabled

# 障害時に一時的にRDPを許可する場合のルール(平時は Enabled:False で登録しておき、必要時のみ有効化)
New-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -Direction Inbound `
  -Protocol TCP -LocalPort 3389 -Action Allow -RemoteAddress 192.0.2.40/32 `
  -Profile Public -Enabled False
```

ここまでで管理端末からのWinRM HTTPS疎通が成立するはずです。管理端末側で確認します。

```powershell
# 管理端末側
Test-WSMan -ComputerName "monitor-win.example.test" -UseSSL

$cred = Get-Credential   # 2節で設定したローカルAdministrator相当の資格情報
Enter-PSSession -ComputerName "monitor-win.example.test" -UseSSL -Credential $cred
```

`Test-WSMan`が成功し、管理元CIDR以外からは同じ接続が失敗すること(WNW-09相当)は、[ネットワーク実機検証手順](09-network-validation-procedure.md)で別途正式に確認します。本節での確認はあくまで作業継続のための疎通チェックです。

## 4. IIS・windows_exporter・Windows Server Backupの導入

以降はWinRMのリモートセッション(`Enter-PSSession`)からでも、コンソールからでも実行できます。

### 4.1 IIS

```powershell
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Common-Http, Web-Mgmt-Console
Get-WindowsFeature -Name Web-* | Where-Object Installed

# 検証用サイトのhealth用エンドポイント(既定コンテンツルート配下。サイト名・パスは実装時に決定)
Set-Content -Path 'C:\inetpub\wwwroot\healthz.html' -Value 'OK' -Encoding ascii
Invoke-WebRequest -Uri 'http://localhost/healthz.html' -UseBasicParsing | Select-Object StatusCode

# Firewall: IISは内部/管理ネットワークのみ許可(一般公開しない)
New-NetFirewallRule -DisplayName "IIS-HTTP-Internal" -Direction Inbound `
  -Protocol TCP -LocalPort 80 -Action Allow -RemoteAddress 192.0.2.40/32 -Profile Public
New-NetFirewallRule -DisplayName "IIS-HTTPS-Internal" -Direction Inbound `
  -Protocol TCP -LocalPort 443 -Action Allow -RemoteAddress 192.0.2.40/32 -Profile Public
```

管理元CIDR以外を含む「内部/管理ネットワーク」の実際の範囲は環境ごとに決定するため、上記`192.0.2.40/32`は例示管理端末のみを許可する最小構成です。より広い内部ネットワークを許可する場合は、その範囲をパラメータシートの実機記入欄へ記録します。

### 4.2 windows_exporter(ハッシュ検証を含む)

```powershell
# バージョンは実機決定時にGitHub Releasesで確認して固定します(現時点でNOT SET)
$version = "<NOT SET: 実機決定時にGitHub Releasesで確認するバージョン番号>"
$msiUrl  = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
$msiPath = "C:\temp\windows_exporter.msi"

Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

# 公開SHA256とのハッシュ一致確認(WUT-03)。期待値はGitHub Releasesのchecksumファイルから取得し、
# ここでの値を推測・仮置きしません
$expectedHash = "<NOT SET: 実機決定時に公開されているSHA256>"
$actualHash = (Get-FileHash -Path $msiPath -Algorithm SHA256).Hash

if ($actualHash -ne $expectedHash) {
    throw "windows_exporter MSIのハッシュが一致しません。expected=$expectedHash actual=$actualHash"
}

# collectorはcpu, cs, logical_disk, net, os, service, system, iisを有効化
Start-Process msiexec.exe -ArgumentList `
  "/i `"$msiPath`" ENABLED_COLLECTORS=cpu,cs,logical_disk,net,os,service,system,iis /qn" -Wait

Get-Service windows_exporter
Get-CimInstance Win32_Service -Filter "Name='windows_exporter'" |
  Select-Object Name, StartName, State, PathName

# ローカルからの疎通確認(中央Prometheusはフェーズ2まで到達不可のため、この時点ではローカル確認のみ)
curl.exe http://localhost:9182/metrics | Select-String "windows_cs_hostname"

# Firewall: 中央Prometheus hostのIPのみ許可(認証なし。値は環境ごとに決定するためNOT SET箇所を埋める)
New-NetFirewallRule -DisplayName "WindowsExporter-Prometheus-Only" -Direction Inbound `
  -Protocol TCP -LocalPort 9182 -Action Allow `
  -RemoteAddress "<NOT SET: 中央Prometheus hostのIPアドレス>" -Profile Public
```

`windows_exporter`は既定`LocalSystem`アカウントで動作します。最小権限化はWST-03で継続課題として記録し、本手順では是正しません。上記のバージョン・SHA256・実行アカウントの実測値は[パラメータシート](03-parameter-sheet.md)の実機記入欄へ記録します。

Firewallルールで許可していても、この時点では中央Prometheusコンテナ側が`compose.yaml`の`monitoring`ネットワーク(`internal: true`)の制約により到達できません。したがってこの節で確認できるのは「対象ホスト上でwindows_exporterサービスが起動し、ローカルから`/metrics`が200で返る」ことまでであり、中央Prometheusからのscrape成立(WIT-03)はフェーズ2まで`BLOCKED`のままです。

### 4.3 Windows Server Backup

```powershell
Install-WindowsFeature -Name Windows-Server-Backup

$policy = New-WBPolicy

# バックアップ格納先は別ボリューム推奨(実機で決定するためNOT SET)
$target = New-WBBackupTarget -VolumePath "<NOT SET: バックアップ格納先ボリューム>"
Add-WBBackupTarget -Policy $policy -Target $target

# IISサイトの内容・設定を対象に追加
Add-WBFileSpec -Policy $policy -FileSpec (New-WBFileSpec -FileSpec "C:\inetpub")

# 毎日03:30(Asia/Tokyo)のスケジュールを登録(Set-WBPolicyの適用でTask Schedulerへ自動登録されます)
Set-WBSchedule -Policy $policy -Schedule "03:30"
Set-WBPolicy -Policy $policy

Get-WBPolicy
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Backup\*"
```

保持世代は14日(Linux版の`backup_retention_days`と同じ値)です。Windows Server Backupの世代管理はストレージ容量に応じた自動ローテーションのため、保持世代の実測確認は`wbadmin get versions`の出力件数と日付範囲で行います。

ロールバック用に、変更前時点でのFirewallルール・IIS設定のエクスポートも取得しておきます(8節で使用)。

```powershell
$stamp = Get-Date -Format yyyyMMdd
netsh advfirewall export "C:\Backup\firewall-$stamp.wfw"
& "$env:windir\system32\inetsrv\appcmd.exe" add backup "pre-change-$stamp"
```

## 5. 中央監視への統合(既存Ansible機能)

本節のみ、中央監視host(monitor-01)側、または[Linux版構築手順書](../build-package/05-build-procedure.md)1〜2節で準備済みのAnsible実行環境で行います。`app_node_exporter_targets`変数へWindowsホストを1行追加し、`site.yml`を再適用するだけの「済(自動)」の作業です。

```yaml
# ansible/inventory/group_vars/monitor/vars.yml など、app_node_exporter_targetsを定義している変数ファイル
app_node_exporter_targets:
  - address: "192.0.2.30:9182"
    host: "monitor-win-01"
    environment: "lab"
```

```bash
cd ansible
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"

# 意図した差分(windows targetの追加分)のみであることを確認(WUT-02)
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff

# 中央host側へ適用
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

適用後、中央PrometheusのTargets画面またはAPIで状態を確認します。

```bash
curl -s http://localhost:9090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.host=="monitor-win-01")'
```

`app_node_exporter_targets`への追加と`site.yml`の再適用自体は正常に完了し、Prometheusの設定ファイル(`prometheus.yml`)にはWindowsホストのtargetが反映されます。しかし`compose.yaml`の`monitoring`ネットワークが`internal: true`であるため、Prometheusコンテナは対象ホストの9182/tcpへ到達できず、上記APIの`health`は`unhealthy`または`up=0`のままです。これは[基本設計書](01-basic-design.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)に記載のとおり想定内であり、WIT-03は`BLOCKED`のまま記録します。「設定への追加が完了したこと」と「scrapeが成立すること」を区別し、後者をPASSと誤記しません。

また、現状のjob名`linux-node`へWindowsホストを混ぜる形になるため、job名が実態と合わなくなる点も残存課題として証跡に残します。

## 6. 構築後確認

対象ホスト側でサービス・Firewall・待受portを確認します。

```powershell
Get-Service windows_exporter, W3SVC, WinRM | Select-Object Name, Status, StartType

Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action | Format-Table -AutoSize

Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -in 5986, 80, 443, 9182 |
  Select-Object LocalAddress, LocalPort, State

Get-NetFirewallProfile | Select-Object Name, DefaultInboundAction, Enabled

winrm enumerate winrm/config/listener

# 証跡用にホストのビルド番号を採録
Get-ComputerInfo | Select-Object CsName, OsName, OsBuildNumber, WindowsProductName
```

管理端末側からも確認します。

```powershell
Invoke-WebRequest -Uri "https://monitor-win.example.test/healthz.html" -UseBasicParsing |
  Select-Object StatusCode
Test-WSMan -ComputerName "monitor-win.example.test" -UseSSL
```

フェーズ1の必須試験(WUT-01, WUT-02, WUT-05, WIT-01, WIT-02, WIT-04, WIT-08, WIT-09, WIT-10, WST-01〜WST-06, WNW-01〜WNW-09)の判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とし、実行結果はコマンド出力とあわせて日付付きevidenceへ保存します。

実ホストのIP、route、DNS、待受、HTTP、Windows Defender Firewallの確認は、本節の簡易確認とは別に[ネットワーク実機検証手順](09-network-validation-procedure.md)(WNW-01〜09)に従って個別の結果票へ記録します。

## 7. 障害・復旧試験(WIT-08)

フェーズ2のアラート通知(WIT-07)は中央Prometheusからのscrapeが前提のため`BLOCKED`です。本節の「検知」は、対象ホスト上またはWinRM経由での手動確認に限定し、その時刻をもって計測します。

1. 事前状態を確認します。

```powershell
Get-Service windows_exporter, W3SVC
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:9182/metrics
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost/healthz.html
```

2. windows_exporterサービスを停止します(検知開始時刻を記録)。

```powershell
Stop-Service windows_exporter
Get-Service windows_exporter
```

3. 停止を確認した時刻(検知時刻)を記録し、復旧させます。

```powershell
Start-Service windows_exporter
Get-Service windows_exporter
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:9182/metrics
```

4. 正常化を確認した時刻を記録し、検知から復旧・正常化までの時間(RTO)を算出します。

5. 同様にIIS(`W3SVC`)についても演習します。

```powershell
Stop-Service W3SVC
Get-Service W3SVC

Start-Service W3SVC
Get-Service W3SVC
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost/healthz.html
```

6. 検知時刻、復旧時刻、RTO、実行したコマンドと実出力を[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)の様式で日付付きevidenceへ保存します。フェーズ2導入後にGrafana / Loki経由の検知(WIT-07相当)を追加した場合は、本節の手動確認による計測値と区別して記録します。

## 8. ロールバック

Windows対応Ansible roleが無いため、Linux版のようなcommit SHA基準の再配備によるロールバックは使えません。[変更・ロールバック計画](08-change-rollback-plan.md)および[詳細設計書](02-detailed-design.md)「バックアップ・ロールバック」節に定義した優先順位に従います。

1. **最優先: VM/ハイパーバイザーのスナップショット復元。**

```powershell
# Hyper-Vの例。取得タイミングは変更直前
Get-VMCheckpoint -VMName "monitor-win-01"
Restore-VMCheckpoint -VMName "monitor-win-01" -Name "<変更前に取得したチェックポイント名>" -Confirm:$false
```

2. **スナップショットが無い場合: 4.3節で取得した個別エクスポートの復元。**

```powershell
netsh advfirewall import "C:\Backup\firewall-<yyyyMMdd>.wfw"
& "$env:windir\system32\inetsrv\appcmd.exe" restore backup "pre-change-<yyyyMMdd>"
```

3. **データ破損時: Windows Server Backupからの復元。**

```powershell
wbadmin get versions
wbadmin start recovery -version:<復元対象のバージョンタイムスタンプ> -itemtype:File `
  -items:C:\inetpub -recoveryTarget:C:\inetpub -notrestoresecurity
```

いずれの手段を使った場合も、ロールバック後は6節の構築後確認と、影響範囲に応じた試験を再実行します。Go / No-Go条件、実施結果の記録様式は[変更・ロールバック計画](08-change-rollback-plan.md)を正本とします。

## 9. 作業終了

- 結果票、実行ログ、画面、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)を保存します
- 一時的なFirewall許可とテストデータを削除します

```powershell
Remove-NetFirewallRule -DisplayName "RDP-Temp-MgmtOnly" -ErrorAction SilentlyContinue
Remove-Item C:\temp\windows_exporter.msi -ErrorAction SilentlyContinue
Remove-Item C:\temp\monitor-win-01-winrm.cer -ErrorAction SilentlyContinue
```

- 未解決事項をIssue化します
- [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、フェーズ1・フェーズ2を区別したうえで、計画対実績、実行時間、対象ホストのビルド番号、設計差異、障害、残存リスクを記入します
- 報告書の試験集計と個別結果票の件数が一致することを確認します
- [引き渡しチェックリスト](07-handover-checklist.md)を確認し、フェーズ1必須試験に`NOT RUN` / `BLOCKED`が残る場合は受領可にしません。フェーズ2(WIT-03, WIT-05, WIT-06, WIT-07, WIT-11)は、[要件定義書](00-requirements.md)に記載の3点の未実装事項が解消するまで`BLOCKED`として明記し、理由と解除条件を残します
