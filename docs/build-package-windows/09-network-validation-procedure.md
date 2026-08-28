# ネットワーク実機検証手順

## 1. 目的と証跡の境界

管理端末から monitor-win-01(Windows Server 2022 Standard、Desktop Experience基準の検証用VM)、および中央監視host monitor-01(既存Linux、変更なし)までを対象に、IP/CIDR、名前解決、経路、待受port、HTTP、packet、Windows Defender Firewallを順に確認します。

WNW-01〜09の試験ID定義、フェーズ区分、必須ID判定は[試験仕様書・結果票](06-test-specification.md)を正本とし、本書はその実行手順の詳細だけを扱います。対応するLinux版の手順は[ネットワーク実機検証手順(Linux版)](../build-package/09-network-validation-procedure.md)です。

Windows/Linux混在のネットワーク障害を注入・体験できるラボは本リポジトリにまだ無く、その制約は[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)に記載したとおりです。したがって本手順は、ラボを介さない、独立した管理端末と引き渡し対象のmonitor-win-01実機による検証です。対象hostの日付付き結果票([結果票テンプレート](../evidence/templates/network-host-validation-windows.md)参照)を作成しなければ、引き渡し判定では`NOT RUN`を維持します。

## 2. 安全条件

- 読み取り中心のコマンドで実施し、Firewallルール、route、interfaceを本手順から変更しません。WNW-09で管理元CIDR以外からの拒否を確認する際も、許可ルール自体は変更せず、許可されていないIPからの接続試行によって確認します。
- `pktmon`は15秒程度の短時間、`-p`オプションで1frameあたりの採取byte数をheader中心(例: 128 byte程度)に制限して取得します。`tcpdump`の`-A`/`-X`に相当する、HTTP body等の本文を可読化するオプションは使用しません。
- WinRM(HTTPS)リスナーを許可するFirewallルールを削除・無効化しません。
- 管理端末IP、対象IP、MAC address、Windowsログオンアカウント名は共有前にマスクします。
- `Get-Credential`で取得した資格情報、`Invoke-WebRequest`/`curl.exe`の認証header、WinRM接続文字列に実パスワード・証明書秘密鍵を直接書かず、認証試験は別の保護されたログで実施します。

## 3. 事前準備

管理端末に PowerShell 7.4系(または組込5.1)があることを確認します。`pktmon`、`Get-NetAdapter`、`Get-NetFirewallRule`等はWindows Server標準搭載であり追加インストールは不要です。monitor-win-01側は、[構築手順書](05-build-procedure.md)のフェーズ1(WinRM HTTPSリスナー設定を含む)が完了していることを前提とします。管理端末の値を実環境に合わせて設定します。

```powershell
$TargetHost   = 'monitor-win-01'
$TargetFQDN   = 'monitor-win.example.test'
$TargetIP     = '192.0.2.30'
$ManagementIP = '192.0.2.40'
$WinRmPort    = 5986
$ExporterPort = 9182
$HealthPath   = '/healthz'   # 例示。実際の監視対象サイトのhealth用エンドポイントへ置き換える

Get-Date -Format o
git rev-parse HEAD

$Cred = Get-Credential -Message 'monitor-win-01 管理アカウント'
Test-WSMan -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred

Invoke-Command -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred -ScriptBlock {
    $PSVersionTable.PSVersion
    (Get-ComputerInfo).OsBuildNumber
    Get-Command pktmon, Test-Connection, Get-NetFirewallRule, Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Select-Object Name, Source
}
```

`192.0.2.0/24`と`.example.test`は記入例です。実行前に`$TargetIP`、`$TargetFQDN`、`$ManagementIP`を実環境の値へ置き換えます。中央監視host(monitor-01)側のIPは環境ごとに決定するため`NOT SET`のままとし、[パラメータシート](03-parameter-sheet.md)の実機記入欄を参照します。

FQDNを付与しない環境では`$TargetFQDN`を`NOT APPLICABLE`とし、理由を結果票へ書きます。`Test-WSMan`が失敗する場合は、コマンドの欠落による`FAIL`ではなく、フェーズ1の構築未完了(WinRMリスナー未設定、証明書不整合等)を疑い`BLOCKED`として前提を整備してから再実行します。

管理端末がWindows以外(macOS/Linuxで`pwsh`を実行する場合)は、`Resolve-DnsName`や`Test-NetConnection`など一部cmdletが利用できません。その場合は`dig`/`nslookup`、`nc`、`curl`など同等の代替コマンドに読み替え、コマンド名を変更した旨を結果票の備考へ記録します。

結果の記入先は[ネットワーク実機検証テンプレート(Windows版)](../evidence/templates/network-host-validation-windows.md)です。

## 4. WNW-01: interface、IP、CIDR

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetAdapter | Format-Table Name, Status, LinkSpeed
    Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength
}
```

確認点:

- 想定NICが`Up`
- 対象IPとprefix length(例: `192.0.2.30/24`)がIPアドレス表([ネットワーク設計・IPアドレス表](04-network-ip-plan.md)、[パラメータシート](03-parameter-sheet.md))と一致
- 意図しないセグメントのIPアドレスが付与されていない
- loopback `127.0.0.1`が既定で存在

## 5. WNW-02: route と default gateway

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix |
        Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric
}
Test-NetConnection -ComputerName $TargetIP -TraceRoute
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Test-NetConnection -ComputerName $using:ManagementIP -TraceRoute
}
```

確認点:

- default route(`0.0.0.0/0`)の`NextHop`と`InterfaceAlias`が設計値に一致
- 対象subnetは想定interfaceへ向く
- `Test-NetConnection -TraceRoute`のhop数・経路が想定どおり

外向き通信を許可しない閉域環境では、外部ホストへの到達成功を要求しません。ここでは経路選択の出力だけを確認し、閉域という設計理由を記録します。

## 6. WNW-03: DNS 名前解決

管理端末と対象Windows Serverの両方から確認します。

```powershell
Resolve-DnsName -Name $TargetFQDN -Type A
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Resolve-DnsName -Name $using:TargetFQDN -Type A
    Get-DnsClientServerAddress -AddressFamily IPv4
}
```

確認点:

- `Resolve-DnsName`のAnswerと問い合わせ先DNS server
- 管理端末とWindows Server双方の結果が一致
- split DNSを使う場合、双方で想定どおりのaddressが返る

## 7. WNW-04: ICMP 疎通

```powershell
Test-Connection -ComputerName $TargetIP -Count 4
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Test-Connection -ComputerName '127.0.0.1' -Count 4
    Test-Connection -ComputerName $using:ManagementIP -Count 4
}
```

ICMPをFirewall方針で遮断する環境では、ping失敗だけでサービス障害と判定しません。packet lossと方針を記録し、TCP/HTTP試験へ進みます。

## 8. WNW-05: 待受port

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort |
        Format-Table LocalAddress, LocalPort, OwningProcess
    Get-NetTCPConnection -State Listen -LocalPort $using:ExporterPort -ErrorAction SilentlyContinue
}
```

確認点:

- `5986/tcp`(WinRM)、`80/tcp`・`443/tcp`(IIS)、`9182/tcp`(windows_exporter)が設計どおり待受
- `3389/tcp`(RDP)は既定Disableのため待受していない
- 想定しない`0.0.0.0`の外部向けlistenerがない

`Get-NetTCPConnection`の`OwningProcess`はPIDです。`Get-Process -Id <PID>`で対応serviceを確認できますが、共有用evidenceでは必要な行だけ残します。

## 9. WNW-06: TCP / HTTP

対象Windows Server自身での応答(loopback)と、管理端末からの到達性(設計上許可される経路と許可されない経路)を分けて確認します。

```powershell
# (1) 対象ホスト自身でIISのhealthエンドポイントを確認(loopback)
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Invoke-WebRequest -Uri "http://127.0.0.1$using:HealthPath" -UseBasicParsing
}

# (2) 管理端末からIISのhealthエンドポイントを確認(内部/管理ネットワークからの到達は許可設計)
curl.exe --max-time 5 -D - "http://$TargetIP$HealthPath"

# (3) 対象ホスト自身でwindows_exporterの/metricsを確認(loopback、collector稼働自体の確認)
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    (Invoke-WebRequest -Uri "http://127.0.0.1:$using:ExporterPort/metrics" -UseBasicParsing).StatusCode
}

# (4) 管理端末からwindows_exporterの/metricsへ直接アクセス(設計では中央Prometheus hostのIPのみ許可)
curl.exe --max-time 5 "http://$TargetIP`:$ExporterPort/metrics"
```

期待結果:

- (1)(3)はいずれも200(対象ホスト自身では両serviceが正しく応答している)
- (2)は200(IISは内部/管理ネットワークからの到達を許可する設計)
- (4)は接続拒否またはtimeout([パラメータシート](03-parameter-sheet.md)のアクセス制御表のとおり、windows_exporterは中央Prometheus hostのIPのみ許可する設計のため)

(4)が接続拒否になることは本設計では`PASS`です。中央Prometheus host自体からのscrape到達性は、`compose.yaml`の`monitoring`network制約が解消するまでフェーズ2`BLOCKED`であり、本項目とは別に[試験仕様書・結果票](06-test-specification.md)のWIT-03で扱います。`curl.exe`の出力に認証headerを含めないでください。

## 10. WNW-07: packet capture

端末A(管理端末の別ウィンドウ、対象ホストへのリモート実行)でheaderのみを短時間キャプチャし、その15秒以内に端末Bからhealth checkを実行します。

端末A:

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    pktmon filter add -p 80
    pktmon start --etw -p 128 --file-name C:\Windows\Temp\wnw07.etl
    Start-Sleep -Seconds 15
    pktmon stop
    pktmon format C:\Windows\Temp\wnw07.etl -o C:\Windows\Temp\wnw07.txt
    pktmon filter remove
}
```

端末B(上記15秒の間に実行):

```powershell
curl.exe --max-time 5 "http://$TargetIP$HealthPath"
```

採取後、結果テキストを取得します。

```powershell
$Session = New-PSSession -ComputerName $TargetFQDN -UseSSL -Credential $Cred
Copy-Item -FromSession $Session -Path C:\Windows\Temp\wnw07.txt -Destination .
Remove-PSSession $Session
```

`-p 128`は1frameあたりの採取byte数を128 byteに制限し、header中心の情報のみを残してHTTP body等の本文を可読化しないための指定です。標準手順は`pktmon filter add -p 80`でIISのhealth checkに絞ります。SYN/SYN-ACKのみ見えて応答がなければlistener/host firewallを、Windows Server側にpacket自体が届かなければ上流firewall/security group/routeを調べます。

## 11. WNW-08: Windows Defender Firewall

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction
    Get-NetFirewallRule -Direction Inbound -Enabled True |
        Format-Table DisplayName, Profile, Action
    Get-NetFirewallRule -DisplayGroup 'リモート デスクトップ'
}
```

確認点:

- 有効プロファイルは系統A(ワークグループ)では`Public`、系統B(ADドメイン参加)では`Domain`
- `DefaultInboundAction`が`Block`
- 許可ルールは`5986/tcp`(WinRM)、`80/443/tcp`(IIS)、`9182/tcp`(windows_exporter)の3経路のみで、経路ごとに送信元CIDRが個別制限されている
- `3389/tcp`(RDP)の許可ルールが既定でDisable(`Enabled: False`)
- 想定しない許可ルールがない

## 12. WNW-09: end-to-end(WinRM HTTPSの非対称性)

Linux版のNW-09は、管理portを外部公開せず運用者がSSHトンネル経由で利用できることを確認する試験でした。Windows版はこれと構造が異なります。WinRM(HTTPS)は通信自体がTLSで暗号化されているため、Linux版のSSHトンネルに相当する追加のトンネルはそもそも不要です。その代わりWindows版で正本となるのは、管理元CIDR以外からの接続がWindows Defender Firewallによって拒否されることの実機確認であり、ネットワーク層のFirewallルール(WNW-08で確認した内容)がend-to-endの到達制御の最終防衛線になります。

許可されたCIDR内の端末から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
curl.exe --max-time 5 -D - "http://$TargetIP$HealthPath"
```

許可CIDR外の端末(またはそれを模擬した経路)から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
```

期待結果は、許可CIDR内からは接続成功(`TcpTestSucceeded : True`)、許可CIDR外からは`TcpTestSucceeded : False`または接続拒否です。許可CIDR外の検証端末を用意できない場合は、対象Windows Server側の`Get-NetFirewallRule`の送信元設定、および必要に応じて`Get-WinEvent`によるFirewallドロップログから、設計どおりの送信元制限が適用されていることを確認し、その根拠を結果票へ記録します。この場合も推測で`PASS`とせず、確認できた実出力の範囲を明記します。

Firewallルールを一時的に変更して確認した場合は、確認後に元の設定へ戻し、変更前後の状態を結果票に記録します。本手順の安全条件では通常ルール変更を行わない設計のため、変更が必要になった場合はその理由も記録します。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| FQDNを解決できない | DNS server / record不整合 | `Resolve-DnsName`、`Get-DnsClientServerAddress` | DNS応答なし、NXDOMAIN、resolver設定差異を分離 |
| IPへ届かない | route / gateway不整合 | `Get-NetRoute`、`Test-Connection` | ICMP方針を確認後、TCPへ進む |
| WinRMに接続できない(refused/timeout) | listener不在またはFirewall拒否 | `Test-WSMan`、`Get-NetFirewallRule` | listener未設定かFirewall拒否かを分離 |
| connection refused(IIS/exporter) | serviceまたはapp pool停止 | `Get-Service W3SVC`、`Get-NetTCPConnection -State Listen` | service停止またはbind設定を確認 |
| timeout | Firewall / 上流route | `pktmon`、`Get-NetFirewallRule`、security group | packet到着前後で担当境界を分離 |
| HTTP 503 | app pool停止 | IISマネージャー / `Get-WebAppPoolState` | app poolの状態、recycle設定を確認 |

切り分け時は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全IDを`PASS / FAIL / BLOCKED / NOT RUN`のいずれかで判定した
- [ ] raw logと結果票の日時、commit SHA、環境、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)が一致する
- [ ] packet capture、IP、MAC、hostname、accountの情報を共有前に確認した
- [ ] 一時的な`New-PSSession`/`Invoke-Command`セッション、`pktmon`キャプチャプロセスが終了している
- [ ] WNW-09でFirewallルールを一時的に変更した場合は元に戻したことを確認した
- [ ] 問題があれば一次記録とIssueを相互リンクした
