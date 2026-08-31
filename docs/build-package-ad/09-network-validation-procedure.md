# ネットワーク実機検証手順

> 💡 **初めて読む方へ**: この文書は実機のネットワークが設計どおりに動いているかを、1項目ずつ確認する手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#09-ネットワーク実機検証手順)を参照してください。

## 1. 目的と証跡の境界

管理端末から `ad-dc01`(Windows Server 2022 Standard、Desktop Experience基準の検証用VM。新規フォレスト・新規ドメイン`corp.example.test`の最初のドメインコントローラー)までを対象に、IP/CIDR、名前解決(Aレコード・SRVレコード)、経路、待受port、LDAP/Kerberos到達性、packet、Windows Defender Firewallを順に確認します。

ANW-01〜09の試験ID定義、フェーズ区分、必須ID判定は[試験仕様書・結果票](06-test-specification.md)を正本とし、本書はその実行手順の詳細だけを扱います。対応するLinux版の手順は[ネットワーク実機検証手順(Linux版)](../build-package/09-network-validation-procedure.md)、Windows版の手順は[ネットワーク実機検証手順(Windows版)](../build-package-windows/09-network-validation-procedure.md)です。

Active Directoryのネットワーク障害(DNS/Kerberos/LDAPの不整合等)を注入・体験できるラボは本リポジトリにまだ無いため、本手順は独立した管理端末と引き渡し対象の`ad-dc01`実機による検証です。対象hostの日付付き結果票([結果票テンプレート](../evidence/templates/network-host-validation-ad.md)参照)を作成しなければ、引き渡し判定では`NOT RUN`を維持します。

`ad-dc01`単体には、実際にこのドメインへ参加するメンバーホストが存在しません。したがって本手順のANW-06・ANW-08で確認できるのは、各ポートへの到達性とFirewallスコープが設計と一致することであり、内部ネットワークCIDR内からの実際の認証・GPO適用そのものの確認ではありません。この境界はANW-09で改めて明記します。

## 2. 安全条件

- 読み取り中心のコマンドで実施し、Firewallルール、route、interfaceを本手順から変更しません。ANW-09で管理元CIDR以外からの拒否を確認する際も、許可ルール自体は変更せず、許可されていないIPからの接続試行によって確認します。
- `pktmon`は15秒程度の短時間、`-p`オプションで1frameあたりの採取byte数をheader中心(例: 128 byte程度)に制限して取得します。`tcpdump`の`-A`/`-X`に相当する、packet本文を可読化するオプションは使用しません。LDAP simple bindは資格情報を平文で含みうるため、本手順のpacket captureはDNS問い合わせ等、資格情報を含まない通信に限定します。
- WinRM(HTTPS)リスナーを許可するFirewallルール、およびAD DS導入時に自動生成されたFirewallルールグループを削除・無効化しません。
- 管理端末IP、対象IP、MAC address、Windowsログオンアカウント名、DSRMパスワード等の秘密値は共有前にマスクします。DSRMパスワードは本手順のどの出力にも記載しません。
- `Get-Credential`で取得した資格情報、`klist`のKerberosチケット内容、`Invoke-WebRequest`/`curl.exe`の認証header、WinRM接続文字列に実パスワード・証明書秘密鍵を直接書かず、認証試験は別の保護されたログで実施します。

## 3. 事前準備

管理端末に PowerShell 7.4系(または組込5.1)があることを確認します。`Resolve-DnsName`、`Test-NetConnection`、`Get-NetFirewallRule`、`pktmon`等はWindows標準搭載であり追加インストールは不要です。`ad-dc01`側は、[構築手順書](05-build-procedure.md)のフェーズ1(フォレスト作成・DC昇格・WinRM HTTPSリスナー設定を含む)が完了していることを前提とします。管理端末の値を実環境に合わせて設定します。

```powershell
$TargetHost   = 'ad-dc01'
$DomainFqdn   = 'corp.example.test'
$TargetFQDN   = 'ad-dc01.corp.example.test'
$TargetIP     = '192.0.2.50'
$ManagementIP = '192.0.2.40'
$WinRmPort    = 5986
$ExporterPort = 9182

Get-Date -Format o
git rev-parse HEAD

$Cred = Get-Credential -Message 'ad-dc01 管理アカウント'
Test-WSMan -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred

Invoke-Command -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred -ScriptBlock {
    $PSVersionTable.PSVersion
    (Get-ComputerInfo).OsBuildNumber
    Get-Service NTDS, DNS, Netlogon, Kdc, W32Time | Select-Object Name, Status
    Get-Command pktmon, Test-Connection, Get-NetFirewallRule, Get-NetTCPConnection, Resolve-DnsName, Test-NetConnection -ErrorAction SilentlyContinue |
        Select-Object Name, Source
}
```

`192.0.2.0/24`と`.example.test`は[パラメータシート](03-parameter-sheet.md)の例示値です。実行前に`$TargetIP`、`$TargetFQDN`、`$ManagementIP`を実環境の値へ置き換えます。windows_exporter(9182)の許可送信元となる中央Prometheus host(`monitor-01`)のIPは環境ごとに決定するため`NOT SET`のままとし、本書ではANW-06・ANW-08で「中央Prometheus host以外の送信元(本書の管理端末を含む)からは拒否されること」を確認する形で扱います。

`Test-WSMan`が失敗する場合は、コマンドの欠落による`FAIL`ではなく、フェーズ1の構築未完了(フォレスト未作成、WinRMリスナー未設定、証明書不整合等)を疑い`BLOCKED`として前提を整備してから再実行します。管理端末がWindows以外(macOS/Linuxで`pwsh`を実行する場合)は、`Resolve-DnsName`や`Test-NetConnection`など一部cmdletが利用できません。その場合は`dig`/`nslookup`、`nc`など同等の代替コマンドに読み替え、コマンド名を変更した旨を結果票の備考へ記録します。

本書の多くの確認は管理端末から`Invoke-Command`で`ad-dc01`へリモート実行しますが、DNS(ANW-03)やFirewall(ANW-08)の一部は対象ホスト自身のDNSサーバー設定・ルール定義を確認するため、`ad-dc01`上のセッション内で実行する箇所を含みます。

結果の記入先は[ネットワーク実機検証テンプレート(AD版)](../evidence/templates/network-host-validation-ad.md)です。

## 4. ANW-01: interface、IP、CIDR

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetAdapter | Format-Table Name, Status, LinkSpeed
    Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin
}
```

確認点:

- 想定NICが`Up`
- 対象IPとprefix length(例: `192.0.2.50/24`)が[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)、[パラメータシート](03-parameter-sheet.md)と一致
- `PrefixOrigin`が`Manual`(静的固定IP。DCは動的IPを使用しない設計)であること
- 意図しないセグメントのIPアドレスが付与されていない
- loopback `127.0.0.1`が既定で存在

## 5. ANW-02: route と default gateway

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

## 6. ANW-03: DNS 名前解決(Aレコード・SRVレコード)

管理端末と`ad-dc01`自身の両方から、通常のAレコードに加えてSRVレコードを確認します。SRVレコードはドメインメンバーがDCやKDCを検索するために参照する、AD特有の重要なレコードです。

```powershell
# Aレコード
Resolve-DnsName -Name $TargetFQDN -Type A
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Resolve-DnsName -Name $using:TargetFQDN -Type A
    Get-DnsClientServerAddress -AddressFamily IPv4
}

# SRVレコード(LDAP用DC、Kerberos用KDCの検索に使われる)
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainFqdn" -Type SRV
Resolve-DnsName -Name "_kerberos._tcp.dc._msdcs.$DomainFqdn" -Type SRV
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$using:DomainFqdn" -Type SRV
    Resolve-DnsName -Name "_kerberos._tcp.dc._msdcs.$using:DomainFqdn" -Type SRV
}

# 補足: SRVレコードに基づくDC/KDCロケーターの動作確認
nltest /dsgetdc:$DomainFqdn
nltest /dsgetdc:$DomainFqdn /KDC
```

確認点:

- `_ldap._tcp.dc._msdcs.corp.example.test`のSRVレコードが、`NameTarget`に`ad-dc01.corp.example.test`、`Port`に`389`を返す
- `_kerberos._tcp.dc._msdcs.corp.example.test`のSRVレコードが、`NameTarget`に`ad-dc01.corp.example.test`、`Port`に`88`を返す
- Aレコードの`IPAddress`が対象IP(例: `192.0.2.50`)と一致
- `Get-DnsClientServerAddress`が`127.0.0.1`(自ホストのAD統合DNS)を優先していること([パラメータシート](03-parameter-sheet.md)の設計値)
- `nltest /dsgetdc`、`nltest /dsgetdc /KDC`がいずれも`ad-dc01`をDC/KDCとして返す
- 管理端末と`ad-dc01`自身、双方の結果が一致

SRVレコードが見つからない場合は、AIT-02(必須サービス確認)のNetlogonサービスの状態と、動的更新設定(`ipconfig /registerdns`による再登録)を切り分けます。

## 7. ANW-04: ICMP 疎通

```powershell
Test-Connection -ComputerName $TargetIP -Count 4
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Test-Connection -ComputerName '127.0.0.1' -Count 4
    Test-Connection -ComputerName $using:ManagementIP -Count 4
}
```

ICMPをFirewall方針で遮断する環境では、ping失敗だけでサービス障害と判定しません。packet lossと方針を記録し、TCP/LDAP到達性試験(ANW-06)へ進みます。

## 8. ANW-05: 待受port

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort |
        Format-Table LocalAddress, LocalPort, OwningProcess

    53, 88, 135, 389, 445, 464, 3268, 5986, 9182 | ForEach-Object {
        Get-NetTCPConnection -State Listen -LocalPort $_ -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort
    }

    # 636(LDAPS)・3269(GC LDAPS)はAD CS未導入(対象外)のため待受しないことを確認する対象
    Get-NetTCPConnection -State Listen -LocalPort 636, 3269 -ErrorAction SilentlyContinue

    Get-NetUDPEndpoint | Where-Object LocalPort -in 53, 88, 464 |
        Format-Table LocalAddress, LocalPort

    # RDPは既定Disableのため、何も返らないことを確認する
    Get-NetTCPConnection -State Listen -LocalPort 3389 -ErrorAction SilentlyContinue
}
```

確認点:

- `53`(DNS)、`88`(Kerberos)、`135`(RPCエンドポイントマッパー)、`389`(LDAP)、`445`(SMB)、`464`(Kerberosパスワード変更)、`3268`(Global Catalog LDAP)、`5986`(WinRM HTTPS)、`9182`(windows_exporter)がいずれも待受
- `53`、`88`、`464`はTCPに加えUDPでも待受
- `636`(LDAPS)・`3269`(Global Catalog LDAPS)は、AD CS(証明書サービス)が本パックの対象外でありDCにサーバー認証証明書が配布されないため、`Install-ADDSForest`直後は**待受しないことがPASS**です。Firewallの許可設定自体は[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)のとおり自動生成されますが、証明書が無い限りリスナー自体が起動しません。理由の詳細は[パラメータシート](03-parameter-sheet.md)「公開ポート」節を参照してください
- `3389`(RDP)は既定Disableのため、`Get-NetTCPConnection`が何も返さない
- 想定しない`0.0.0.0`の外部向けlistenerがない

`Get-NetTCPConnection`の`OwningProcess`はPIDです。`Get-Process -Id <PID>`で対応serviceを確認できますが、共有用evidenceでは必要な行だけ残します。

## 9. ANW-06: TCP/LDAP到達性

`Test-NetConnection`でLDAP(389)、Kerberos(88)、DNS(53)、WinRM(5986)への到達性を確認します。windows_exporter(9182)は、中央Prometheus host以外からは拒否される設計であることを、管理端末からの接続試行で確認します。

```powershell
# (1) 内部ネットワークCIDR相当の到達性確認(LDAP/Kerberos/DNS)
Test-NetConnection -ComputerName $TargetFQDN -Port 389
Test-NetConnection -ComputerName $TargetFQDN -Port 88
Test-NetConnection -ComputerName $TargetFQDN -Port 53

# (2) 管理元CIDR相当の到達性確認(WinRM HTTPS)
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort

# (3) 管理端末(中央Prometheus hostではない)からwindows_exporterへの到達性確認
Test-NetConnection -ComputerName $TargetFQDN -Port $ExporterPort
```

期待結果:

- (1)(2)は`TcpTestSucceeded : True`(管理端末が内部ネットワークCIDR・管理元CIDRに含まれる前提)
- (3)は`TcpTestSucceeded : False`または接続拒否(windows_exporterの許可送信元は中央Prometheus hostのIPのみであり、管理端末を含むそれ以外からは拒否される設計のため)

(3)が拒否になることは本設計では`PASS`です。中央Prometheus host自体からの実際のscrape到達性は、[要件定義書](00-requirements.md)に記載のフェーズ2未実装3点(`compose.yaml`の`monitoring`network制約を含む)が解消するまでAIT-09として`BLOCKED`であり、本項目はFirewallスコープの設計確認にとどまります。

## 10. ANW-07: packet capture

LDAP simple bind等の資格情報を含む通信を採取対象にしないため、本項目はDNS問い合わせ(port 53)をサンプル通信として使用します。端末A(管理端末から対象ホストへのリモート実行)でheaderのみを短時間キャプチャし、その15秒以内に端末Bから問い合わせを実行します。

端末A:

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    pktmon filter add -p 53
    pktmon start --etw -p 128 --file-name C:\Windows\Temp\anw07.etl
    Start-Sleep -Seconds 15
    pktmon stop
    pktmon format C:\Windows\Temp\anw07.etl -o C:\Windows\Temp\anw07.txt
    pktmon filter remove
}
```

端末B(上記15秒の間に実行):

```powershell
Resolve-DnsName -Name $TargetFQDN -Type A -Server $TargetIP
```

採取後、結果テキストを取得します。

```powershell
$Session = New-PSSession -ComputerName $TargetFQDN -UseSSL -Credential $Cred
Copy-Item -FromSession $Session -Path C:\Windows\Temp\anw07.txt -Destination .
Remove-PSSession $Session
```

`-p 128`は1frameあたりの採取byte数を128 byteに制限し、header中心の情報のみを残すための指定です。LDAP(389)やKerberos(88)のtraceが必要な場合は`pktmon filter add -p 389`等へ変更できますが、LDAP simple bind等の資格情報を含みうる通信そのものは、本手順の安全条件(2節)に基づき採取しません。query/responseのみ見えて応答がなければDNSサービス(`Get-Service DNS`)を、`ad-dc01`にpacket自体が届かなければ上流firewall/route を調べます。

## 11. ANW-08: Windows Defender Firewall

AD DS導入時に自動生成されたルールグループ(Active Directory Domain Services、DNS Service、Kerberos Key Distribution Center、File Replication、Windows Remote Management)のスコープが、内部ネットワークCIDR・管理元CIDRの設計と一致することを確認します。

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction

    $Groups = 'Active Directory Domain Services', 'DNS Service', 'Kerberos Key Distribution Center', 'File Replication', 'Windows Remote Management'
    foreach ($Group in $Groups) {
        Get-NetFirewallRule -DisplayGroup $Group -Enabled True |
            Get-NetFirewallAddressFilter |
            Select-Object -Property @{n = 'DisplayGroup'; e = { $Group } }, RemoteAddress
    }

    Get-NetFirewallRule -DisplayGroup 'リモート デスクトップ'
}
```

確認点:

- `DefaultInboundAction`が`Block`
- `Active Directory Domain Services`、`DNS Service`、`Kerberos Key Distribution Center`、`File Replication`の各グループのスコープ(`RemoteAddress`)が内部ネットワークCIDRと一致
- `Windows Remote Management`グループのスコープが管理元CIDRと一致
- `3389/tcp`(RDP)の許可ルールが既定でDisable(`Enabled: False`)
- windows_exporterの許可ルールのスコープが中央Prometheus hostのIPのみ(それ以外は拒否。ANW-06(3)の結果と一致)
- 想定しない許可ルールがない

DC昇格直後はネットワークカテゴリがNLA(Network Location Awareness)によって`Domain`と認識されるまで一時的に`Public`扱いになることがあります。プロファイルが想定と異なる場合は、[構築手順書](05-build-procedure.md)のネットワークカテゴリ確認手順に従って是正してから再確認します。

## 12. ANW-09: end-to-end(管理元CIDR外からのWinRM拒否と、内部ネットワークCIDRの確認範囲)

管理元CIDR外からのWinRM(HTTPS)接続が拒否されることを実機確認します。

許可されたCIDR内の端末から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
Test-WSMan -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred
```

許可CIDR外の端末(またはそれを模擬した経路)から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
```

期待結果は、許可CIDR内からは接続成功(`TcpTestSucceeded : True`)、許可CIDR外からは`TcpTestSucceeded : False`または接続拒否です。許可CIDR外の検証端末を用意できない場合は、`ad-dc01`側の`Get-NetFirewallRule`の送信元設定、および必要に応じて`Get-WinEvent`によるFirewallドロップログから、設計どおりの送信元制限が適用されていることを確認し、その根拠を結果票へ記録します。この場合も推測で`PASS`とせず、確認できた実出力の範囲を明記します。

Firewallルールを一時的に変更して確認した場合は、確認後に元の設定へ戻し、変更前後の状態を結果票に記録します。本手順の安全条件では通常ルール変更を行わない設計のため、変更が必要になった場合はその理由も記録します。

**内部ネットワークCIDRについての確認範囲の境界**: 内部ネットワークCIDRは、将来ドメインに参加する予定のサーバー・クライアントからの到達性を許可する設計です。しかし`ad-dc01`単体の本構築案件には、実際にこのドメインへ参加するメンバーホストが存在しません。したがって、内部ネットワークCIDR内からの実際の認証(Kerberos/NTLM)、GPO適用、SYSVOL/NETLOGON共有への実接続そのものは、この構築案件の範囲では確認できません。ANW-06・ANW-08で確認できるのは、LDAP/Kerberos/DNS等各ポートへの到達性とFirewallスコープが設計と一致することであり、実際のドメインメンバーによる認証・ポリシー適用の成功そのものではありません。[基本設計書](01-basic-design.md)2.4節に記す「monitor-win-01のドメイン参加」のような発展構成を実施して初めて、内部ネットワークCIDR設計の実効性を確認できます。この境界を、埋まったことにしないでください。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| FQDNを解決できない | DNS server / record不整合 | `Resolve-DnsName`、`Get-DnsClientServerAddress` | DNS応答なし、NXDOMAIN、resolver設定差異を分離 |
| SRVレコード(`_ldap._tcp.dc._msdcs`等)が見つからない | Netlogonの動的登録失敗、またはDNSゾーン不整合 | `Resolve-DnsName -Type SRV`、`nltest /dsgetdc`、`Get-Service Netlogon`、`ipconfig /registerdns` | SRV未登録かNetlogon停止かDNSゾーン設定かを分離 |
| IPへ届かない | route / gateway不整合 | `Get-NetRoute`、`Test-Connection` | ICMP方針を確認後、TCPへ進む |
| Kerberosチケットを取得できない(認証エラー、`klist`が空) | 時刻同期のずれ(既定許容5分超)、またはKDC(`Kdc`サービス)停止 | `w32tm /query /status`、`Get-Service Kdc`、`klist` | 時刻ずれかサービス停止かを分離 |
| LDAPバインドに失敗する | LDAP署名/チャネルバインディング要件不一致、またはNTDS停止 | `Test-NetConnection -Port 389`、`Get-Service NTDS`、クライアント側のLDAP設定確認 | クライアント側要件かサービス停止かを分離 |
| WinRMに接続できない(refused/timeout) | listener不在またはFirewall拒否 | `Test-WSMan`、`Get-NetFirewallRule` | listener未設定かFirewall拒否かを分離 |
| connection refused(windows_exporter) | serviceまたはFirewallスコープ不一致 | `Get-Service windows_exporter`、`Get-NetFirewallRule` | service停止か送信元スコープ不一致かを分離 |
| timeout | Firewall / 上流route | `pktmon`、`Get-NetFirewallRule`、security group | packet到着前後で担当境界を分離 |

切り分け時は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全IDを`PASS / FAIL / BLOCKED / NOT RUN`のいずれかで判定した
- [ ] raw logと結果票の日時、commit SHA、環境、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)が一致する
- [ ] packet capture、IP、MAC、hostname、Windowsログオンアカウントの情報を共有前に確認した
- [ ] LDAP simple bind等の資格情報を含む通信をpacket captureに含めていないことを確認した
- [ ] 一時的な`New-PSSession`/`Invoke-Command`セッション、`pktmon`キャプチャプロセスが終了している
- [ ] ANW-09でFirewallルールを一時的に変更した場合は元に戻したことを確認した
- [ ] 内部ネットワークCIDRの実接続確認範囲の境界(1節・ANW-09参照)を結果票に明記した
- [ ] 問題があれば一次記録とIssueを相互リンクした
