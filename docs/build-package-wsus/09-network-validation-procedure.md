# ネットワーク実機検証手順

## 1. 目的と証跡の境界

管理端末から`wsus-01`(Windows Server 2022 Standard、Desktop Experience基準の検証用VM。既存ADドメイン`corp.example.test`へメンバーサーバーとして参加させたWSUSサーバー)までを対象に、IP/CIDR、名前解決(`corp.example.test`ゾーンのAレコード・DC探索用SRVレコード)、経路、待受port、TCP/HTTP(WSUS管理サイト・windows_exporter)、packet、Windows Defender Firewallを順に確認します。

SNW-01〜09の試験ID定義、フェーズ区分、必須ID判定は[試験仕様書・結果票](06-test-specification.md)を正本とし、本書はその実行手順の詳細だけを扱います。対応するWindows版の手順は[ネットワーク実機検証手順(Windows版)](../build-package-windows/09-network-validation-procedure.md)、AD版の手順は[ネットワーク実機検証手順(AD版)](../build-package-ad/09-network-validation-procedure.md)です。

`wsus-01`はADドメインへ参加するメンバーサーバーであり、そのドメイン参加・GPO(グループポリシーオブジェクト。ドメイン単位で設定を配布する仕組み)適用・自己登録は既存のドメインコントローラー`ad-dc01`・`ad-dc02`への到達に依存します。したがって本書は`wsus-01`単体だけでなく、`wsus-01`から`ad-dc01`・`ad-dc02`への経路も一部確認しますが、`ad-dc01`・`ad-dc02`自体の詳細な検証項目(ANW-01〜09)は[AD版パック](../build-package-ad/09-network-validation-procedure.md)を正本とし重複させません。

Windows/ADのネットワーク障害を注入・体験できるラボは本リポジトリにまだ無く、その制約は[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)に記載したとおりです。したがって本手順は、ラボを介さない、独立した管理端末と引き渡し対象の`wsus-01`実機による検証です。対象hostの日付付き結果票([結果票テンプレート](../evidence/templates/network-host-validation-wsus.md)参照)を作成しなければ、引き渡し判定では`NOT RUN`を維持します。

本パックは`wsus-01`自身をWSUSクライアントとして自己登録・承認・適用まで一巡させる範囲にとどめ、複数クライアントでの大規模検証は対象外です([要件定義書](00-requirements.md))。本書のSNW-06・SNW-09で確認できるのは、WSUS管理サイト(8530/tcp)への到達性とFirewallスコープが設計と一致することであり、実際の複数クライアントによる同時同期・同時ダウンロードの負荷条件下での挙動ではありません。この境界を、埋まったことにしないでください。

## 2. 安全条件

- 読み取り中心のコマンドで実施し、Firewallルール、route、interfaceを本手順から変更しません。SNW-09で許可CIDR以外からの拒否を確認する際も、許可ルール自体は変更せず、許可されていないIPからの接続試行によって確認します。
- `pktmon`は15秒程度の短時間、1frameあたりの採取byte数をheader中心(例: 128 byte程度)に制限して取得します。`tcpdump`の`-A`/`-X`に相当する、HTTP body等の本文を可読化するオプションは使用しません。WSUS管理サイト(8530)のクライアント通信は既定で匿名アクセスであり資格情報を含みませんが、同一手順を流用してAD認証(Kerberos/LDAP)を対象にすることはせず、header中心の採取という制約は変えません。
- `WinRM-HTTPS-MgmtOnly`(WinRM HTTPSリスナー許可)、`WSUS-Content-InternalOnly`(WSUSコンテンツ許可)、`WindowsExporter-Prometheus-Only`(windows_exporter許可)の各Firewallルール、およびドメイン参加により自動生成されたルールグループを削除・無効化しません。
- 管理端末IP、対象IP、MAC address、Windowsログオンアカウント名は共有前にマスクします。
- `Get-Credential`で取得した資格情報、`Invoke-WebRequest`/`curl.exe`の認証header、WinRM接続文字列に実パスワード・証明書秘密鍵を直接書かず、認証試験は別の保護されたログで実施します。

## 3. 事前準備

管理端末に PowerShell 7.4系(または組込5.1)があることを確認します。`pktmon`、`Get-NetAdapter`、`Get-NetFirewallRule`、`Resolve-DnsName`等はWindows Server標準搭載であり追加インストールは不要です。`wsus-01`側は、[構築手順書](05-build-procedure.md)のフェーズ1(ドメイン参加、WSUSロール導入、GPO`WSUS-Client-Policy`の作成・リンク、WinRM HTTPSリスナー設定、`WsusPool`チューニングを含む)が完了していることを前提とします。管理端末の値を実環境に合わせて設定します。

```powershell
$TargetHost   = 'wsus-01'
$DomainFqdn   = 'corp.example.test'
$TargetFQDN   = 'wsus-01.corp.example.test'
$TargetIP     = '192.0.2.52'
$ManagementIP = '192.0.2.40'
$AdDc01IP     = '192.0.2.50'
$AdDc02IP     = '192.0.2.51'
$WinRmPort    = 5986
$WsusPort     = 8530
$ExporterPort = 9182
$ClientWsPath = '/ClientWebService/client.asmx'   # WSUS既定のクライアントWebサービス、匿名アクセス可

Get-Date -Format o
git rev-parse HEAD

$Cred = Get-Credential -Message 'wsus-01 管理アカウント(CORP\<アカウント名>)'
Test-WSMan -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred

Invoke-Command -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred -ScriptBlock {
    $PSVersionTable.PSVersion
    $Info = Get-ComputerInfo
    $Info.OsBuildNumber, $Info.CsPartOfDomain, $Info.CsDomain
    Get-Service WsusService, W3SVC -ErrorAction SilentlyContinue | Select-Object Name, Status
    Get-Command pktmon, Test-Connection, Get-NetFirewallRule, Get-NetTCPConnection, Resolve-DnsName, Test-NetConnection -ErrorAction SilentlyContinue |
        Select-Object Name, Source
}
```

`192.0.2.0/24`と`corp.example.test`は[パラメータシート](03-parameter-sheet.md)の例示値です。実行前に`$TargetIP`、`$TargetFQDN`、`$ManagementIP`を実環境の値へ置き換えます。windows_exporter(9182)の許可送信元となる中央Prometheus host(`monitor-01`)のIPは環境ごとに決定するため`NOT SET`のままとし、本書ではSNW-06・SNW-08で「中央Prometheus host以外の送信元(本書の管理端末を含む)からは拒否されること」を確認する形で扱います。

`$Cred`はドメインアカウント(`CORP\<アカウント名>`)を指定します。管理端末がドメイン参加済みであればKerberosで、ワークグループのままであればNTLM(Negotiate経由)で認証されます。Basic認証は無効化する設計(SST-02)のため、有効なドメインアカウントかつ`WSUS Administrators`または`Administrators`ローカルグループのメンバーである資格情報を用意します。

`Test-WSMan`が失敗する場合は、コマンドの欠落による`FAIL`ではなく、フェーズ1の構築未完了(ドメイン未参加、WinRMリスナー未設定、証明書不整合等)を疑い`BLOCKED`として前提を整備してから再実行します。管理端末がWindows以外(macOS/Linuxで`pwsh`を実行する場合)は、`Resolve-DnsName`や`Test-NetConnection`など一部cmdletが利用できません。その場合は`dig`/`nslookup`、`nc`、`curl`など同等の代替コマンドに読み替え、コマンド名を変更した旨を結果票の備考へ記録します。

結果の記入先は[WSUS実ホスト ネットワーク検証結果票](../evidence/templates/network-host-validation-wsus.md)です。

## 4. SNW-01: interface、IP、CIDR

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetAdapter | Format-Table Name, Status, LinkSpeed
    Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin
}
```

確認点:

- 想定NICが`Up`
- 対象IPとprefix length(例: `192.0.2.52/24`)が[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)、[パラメータシート](03-parameter-sheet.md)と一致
- `PrefixOrigin`が`Manual`(静的固定IP。サーバー用途のため動的IPを使用しない設計)であること
- 意図しないセグメントのIPアドレスが付与されていない
- loopback `127.0.0.1`が既定で存在

## 5. SNW-02: routeとdefault gateway

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix |
        Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric
}
Test-NetConnection -ComputerName $TargetIP -TraceRoute
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Test-NetConnection -ComputerName $using:ManagementIP -TraceRoute
    Test-NetConnection -ComputerName $using:AdDc01IP -TraceRoute
    Test-NetConnection -ComputerName $using:AdDc02IP -TraceRoute
}
```

確認点:

- default route(`0.0.0.0/0`)の`NextHop`と`InterfaceAlias`が設計値に一致
- 対象subnetは想定interfaceへ向く
- `wsus-01`から`ad-dc01`・`ad-dc02`双方への経路が成立する(片方のみに固定した経路設計になっていない。[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)2節のとおり、DC探索は`ad-dc01`・`ad-dc02`のどちらが応答してもよい設計であるため)
- `Test-NetConnection -TraceRoute`のhop数・経路が想定どおり

外向き通信を許可しない閉域環境では、外部ホストへの到達成功を要求しません。ここでは経路選択の出力だけを確認し、閉域という設計理由を記録します。

## 6. SNW-03: DNS名前解決(corp.example.testゾーン)

管理端末と`wsus-01`自身の両方から、`wsus-01`自身のAレコードに加え、ドメイン参加済みホストがDC(ドメインコントローラー)を検索するために参照するSRVレコードを確認します。`wsus-01`はDNSサーバーそのものではないため、`ad-dc01`側の検証([AD版](../build-package-ad/09-network-validation-procedure.md)ANW-03)とは異なり、自身のDNSクライアント設定が`ad-dc01`・`ad-dc02`のいずれかを向いていることを併せて確認します。

```powershell
# Aレコード
Resolve-DnsName -Name $TargetFQDN -Type A
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Resolve-DnsName -Name $using:TargetFQDN -Type A
    Get-DnsClientServerAddress -AddressFamily IPv4
}

# SRVレコード(DC・KDC探索用)
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainFqdn" -Type SRV
Resolve-DnsName -Name "_kerberos._tcp.dc._msdcs.$DomainFqdn" -Type SRV

# wsus-01自身からのDCロケーター動作確認
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    nltest /dsgetdc:$using:DomainFqdn
    Get-Service Netlogon | Select-Object Name, Status
}
```

確認点:

- `wsus-01.corp.example.test`のAレコードが対象IP(例: `192.0.2.52`)と一致(ADドメイン参加によりAD統合DNSゾーンへ自動登録される想定。[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)参照)
- `Get-DnsClientServerAddress`が`ad-dc01`・`ad-dc02`のいずれか(または両方)のIPを指している(`wsus-01`自身は`127.0.0.1`ではない。DNSサーバー機能を持たないメンバーサーバーであるため)
- `_ldap._tcp.dc._msdcs.corp.example.test`・`_kerberos._tcp.dc._msdcs.corp.example.test`のSRVレコードが、`ad-dc01`・`ad-dc02`いずれかの`NameTarget`とport(`389`/`88`)を返す
- `nltest /dsgetdc`が成功し、応答したDC名を確認できる
- 管理端末と`wsus-01`自身、双方の結果が一致

SRVレコードが見つからない、または`nltest`が失敗する場合は、ドメイン未参加・Netlogonサービス停止・DNS動的更新の未反映を切り分けます(13節参照)。`nltest`には問い合わせ先を指定するオプションがなく、実行した端末自身のDNSクライアント設定で解決するため、管理端末がドメイン参加していない環境では`nltest`を`wsus-01`上のセッション内で実行し、管理端末側は`Resolve-DnsName -Server <ad-dc01のIP>`で代替します。

## 7. SNW-04: ICMP疎通

```powershell
Test-Connection -ComputerName $TargetIP -Count 4
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Test-Connection -ComputerName '127.0.0.1' -Count 4
    Test-Connection -ComputerName $using:ManagementIP -Count 4
    Test-Connection -ComputerName $using:AdDc01IP -Count 4
    Test-Connection -ComputerName $using:AdDc02IP -Count 4
}
```

ICMPをFirewall方針で遮断する環境では、ping失敗だけでサービス障害と判定しません。packet lossと方針を記録し、TCP/HTTP試験(SNW-06)へ進みます。`wsus-01`から`ad-dc01`・`ad-dc02`への疎通は、認証・GPO配布の前提条件として特に重要です。

## 8. SNW-05: 待受port

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort |
        Format-Table LocalAddress, LocalPort, OwningProcess

    5986, 8530, 9182 | ForEach-Object {
        Get-NetTCPConnection -State Listen -LocalPort $_ -ErrorAction SilentlyContinue |
            Select-Object LocalAddress, LocalPort
    }

    # RDPは既定Disableのため、何も返らないことを確認する
    Get-NetTCPConnection -State Listen -LocalPort 3389 -ErrorAction SilentlyContinue

    # WID(Windows Internal Database)はローカル名前付きパイプ(MICROSOFT##WIDへのローカル接続)経由のみで
    # TCP/UDPポートを一切使わない設計であることの確認(該当するTCP待受が無いことを示す)
    Get-Item "\\.\pipe\MICROSOFT##WID" -ErrorAction SilentlyContinue
}
```

確認点:

- `5986/tcp`(WinRM HTTPS)、`8530/tcp`(WSUS管理サイト)、`9182/tcp`(windows_exporter)がいずれも待受
- `3389/tcp`(RDP)は既定Disableのため待受していない
- SUSDB(WSUSが使う内部データベース)はWID接続用の名前付きパイプ経由のみであり、追加のネットワークportを持たないという設計([パラメータシート](03-parameter-sheet.md)「データベース方式」節)に矛盾がない
- 想定しない`0.0.0.0`の外部向けlistenerがない

`Get-NetTCPConnection`の`OwningProcess`はPIDです。`Get-Process -Id <PID>`で対応serviceを確認できますが、共有用evidenceでは必要な行だけ残します。

## 9. SNW-06: TCP/HTTP(WSUS管理サイト、windows_exporter)

`wsus-01`自身が同時にWSUSクライアントとして自己登録される設計のため、8530への到達性確認はネットワーク層の話とWSUSクライアント通信そのものの成立可否が重なりやすい項目です。本書で確認するのはネットワーク到達性とFirewallスコープの一致であり、実際のクライアント自己登録・承認・適用の成功可否はSIT-04・SIT-05を正本とします。管理端末は内部ネットワークCIDR・管理元CIDRの双方に含まれる前提とします。

```powershell
# (1) wsus-01自身でWSUS管理サイトのクライアントWebサービスを確認(loopback)
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    (Invoke-WebRequest -Uri "http://127.0.0.1:$using:WsusPort$using:ClientWsPath" -UseBasicParsing).StatusCode
}

# (2) 管理端末からWSUS管理サイトへの到達を確認(内部ネットワークCIDRからの到達は許可設計)
curl.exe --max-time 5 -D - "http://$TargetFQDN`:$WsusPort$ClientWsPath"

# (3) wsus-01自身でwindows_exporterの/metricsを確認(loopback、iisコレクター有効化を含む)
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    (Invoke-WebRequest -Uri "http://127.0.0.1:$using:ExporterPort/metrics" -UseBasicParsing).StatusCode
}

# (4) 管理端末からwindows_exporterへ直接アクセス(設計では中央Prometheus hostのIPのみ許可)
curl.exe --max-time 5 "http://$TargetFQDN`:$ExporterPort/metrics"

# (5) WsusPoolチューニング設定の確認(アイドルタイムアウト0・キュー長2000・プライベートメモリ制限0)
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    Get-IISAppPool WsusPool | Select-Object Name, State
    Get-ItemProperty "IIS:\AppPools\WsusPool" -Name processModel.idleTimeout, queueLength, recycling.periodicRestart.privateMemory
}
```

期待結果:

- (1)(3)はいずれも200(`wsus-01`自身では両serviceが正しく応答している)
- (2)は200(WSUS管理サイトは内部ネットワークCIDRからの到達を許可する設計)
- (4)は接続拒否またはtimeout([パラメータシート](03-parameter-sheet.md)のアクセス制御表のとおり、windows_exporterは中央Prometheus hostのIPのみ許可する設計のため)
- (5)は`idleTimeout`が`00:00:00`、`queueLength`が`2000`、`recycling.periodicRestart.privateMemory`が`0`

(4)が接続拒否になることは本設計では`PASS`です。中央Prometheus host自体からの実際のscrape到達性は、`compose.yaml`の`monitoring`ネットワーク制約が解消するまでフェーズ2`BLOCKED`であり、本項目とは別に[試験仕様書・結果票](06-test-specification.md)のSIT-09で扱います。`curl.exe`の出力に認証headerを含めないでください。

## 10. SNW-07: packet capture

WSUS管理サイト(8530)のクライアントWebサービスは既定で匿名アクセスであり資格情報を含まないため、本項目のサンプル通信として使用します。端末A(管理端末の別ウィンドウ、対象ホストへのリモート実行)でheaderのみを短時間キャプチャし、その15秒以内に端末Bから(2)相当のリクエストを実行します。

端末A:

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    pktmon filter remove
    pktmon filter add -p 8530
    pktmon start --capture --pkt-size 128 --file-name C:\Windows\Temp\snw07.etl
    Start-Sleep -Seconds 15
    pktmon stop
    pktmon format C:\Windows\Temp\snw07.etl -o C:\Windows\Temp\snw07.txt
    pktmon filter remove
    Get-Item C:\Windows\Temp\snw07.etl, C:\Windows\Temp\snw07.txt | Select-Object Name, Length
}
```

`pktmon start`の採取開始は`--capture`、1frameあたりの採取byte数は`--pkt-size <bytes>`で指定します。[AD版パック](../build-package-ad/09-network-validation-procedure.md)ANW-07節に記録のとおり、同じWindows Server 2022(build 20348)で`-p`をETWプロバイダー指定の短縮形と誤用する構文ミスが実機検証で見つかっているため、本書では修正済みのこの構文をあらかじめ採用します。`pktmon`の状態メッセージはOS言語で出力されることがあり、PowerShellリモーティング経由では文字化けする場合があるため、成功判定は表示文言ではなく`.etl`ファイルの存在とサイズで行います。

端末B(上記15秒の間に実行):

```powershell
curl.exe --max-time 5 "http://$TargetFQDN`:$WsusPort$ClientWsPath"
```

採取後、結果テキストを取得します。

```powershell
$Session = New-PSSession -ComputerName $TargetFQDN -UseSSL -Credential $Cred
Copy-Item -FromSession $Session -Path C:\Windows\Temp\snw07.txt -Destination .
Remove-PSSession $Session
```

`--pkt-size 128`は1frameあたりの採取byte数を128 byteに制限し、header中心の情報のみを残してHTTP body等の本文を可読化しないための指定です。SYN/SYN-ACKのみ見えて応答がなければ`WsusService`/`W3SVC`/`WsusPool`の状態を、`wsus-01`にpacket自体が届かなければ上流firewall/routeを調べます。AD認証(Kerberos/LDAP)を対象にした採取は、資格情報を含みうるため本手順の対象外とします(2節)。

## 11. SNW-08: Windows Defender Firewall

```powershell
Invoke-Command -ComputerName $TargetFQDN -UseSSL -Credential $Cred -ScriptBlock {
    # -PolicyStore ActiveStore で実効値を見る。付けないと永続ストアの値が表示され、
    # 未設定のOSでは NotConfigured と出る(実効動作はBlock)
    Get-NetFirewallProfile -PolicyStore ActiveStore |
        Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction

    'WinRM-HTTPS-MgmtOnly', 'WSUS-Content-InternalOnly', 'WindowsExporter-Prometheus-Only' | ForEach-Object {
        Get-NetFirewallRule -DisplayName $_ -ErrorAction SilentlyContinue |
            Get-NetFirewallAddressFilter |
            Select-Object -Property @{n = 'DisplayName'; e = { $_.DisplayName } }, RemoteAddress
    }

    Get-NetFirewallRule -DisplayGroup 'リモート デスクトップ' | Format-Table DisplayName, Enabled, Direction
    # 構築手順書の一時許可ルールが残っていないことの確認(既定では存在しない)
    Get-NetFirewallRule -DisplayName 'RDP-Temp-MgmtOnly' -ErrorAction SilentlyContinue
}
```

確認点:

- 有効プロファイルは`Domain`(ドメイン参加により既定でDomainプロファイルとなる。DC/GPOへの到達がNLA(Network Location Awareness)によって未確定な直後は一時的に`Public`扱いになることがあり、その場合は時間を置いて再確認する)
- `DefaultInboundAction`が`Block`(`-PolicyStore ActiveStore`の実効値。永続ストアの`NotConfigured`は「OS既定=Block」を意味し、これ自体はFAILではない)
- `WinRM-HTTPS-MgmtOnly`のスコープが管理元CIDRと一致
- `WSUS-Content-InternalOnly`のスコープが内部ネットワークCIDRと一致
- `WindowsExporter-Prometheus-Only`のスコープが中央Prometheus hostのIPのみ(未決定の環境では、ルール自体が存在しない=既定Blockで拒否されることを確認する)
- `3389/tcp`(RDP)の許可ルールが既定でDisable(`Enabled: False`)、および一時許可ルール`RDP-Temp-MgmtOnly`が残存していない
- 許可経路がこの3つ以外に無い(想定しない許可ルールがない)

## 12. SNW-09: end-to-end(WinRM HTTPSの非対称性)

WinRM(HTTPS)は通信自体がTLSで暗号化されているため、Linux版のSSHトンネルに相当する追加のトンネルはそもそも不要です。Firewallによる送信元CIDR制限は、暗号化済み通信の上に重ねる多層防御(defense in depth)の一枚として機能します。一方、本パックの既定であるWSUS管理サイト(HTTP、8530)は、HTTPS化(8531、証明書配布)を内部CA不在のため対象外・次点課題としているとおり、通信そのものは暗号化されていません。したがってWSUSコンテンツ経路の機密性・アクセス制御は、Firewallによる内部ネットワークCIDR限定だけが実質的な制御であり、WinRMのように暗号化と送信元制限の二重防御にはなっていません。この非対称性を踏まえ、本項目では両経路の拒否確認を行います。

許可されたCIDR内の端末から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
Test-WSMan -ComputerName $TargetFQDN -UseSSL -Port $WinRmPort -Credential $Cred
Test-NetConnection -ComputerName $TargetFQDN -Port $WsusPort
curl.exe --max-time 5 -D - "http://$TargetFQDN`:$WsusPort$ClientWsPath"
```

許可CIDR外の端末(またはそれを模擬した経路)から:

```powershell
Test-NetConnection -ComputerName $TargetFQDN -Port $WinRmPort
Test-NetConnection -ComputerName $TargetFQDN -Port $WsusPort
```

期待結果は、許可CIDR内からは両portとも接続成功(`TcpTestSucceeded : True`)、許可CIDR外からは両portとも`TcpTestSucceeded : False`または接続拒否です。管理元CIDRと内部ネットワークCIDRは別範囲として設計されているため、「管理元CIDR外だが内部ネットワークCIDR内」のような中間の経路がある場合は、WinRM(5986)は拒否・WSUSコンテンツ(8530)は許可という非対称な結果になり得ます。これも設計どおりであり、`FAIL`ではありません。

許可CIDR外の検証端末を用意できない場合は、`wsus-01`側の`Get-NetFirewallRule`の送信元設定、および必要に応じて`Get-WinEvent`によるFirewallドロップログから、設計どおりの送信元制限が適用されていることを確認し、その根拠を結果票へ記録します。この場合も推測で`PASS`とせず、確認できた実出力の範囲を明記します。

Firewallルールを一時的に変更して確認した場合は、確認後に元の設定へ戻し、変更前後の状態を結果票に記録します。本手順の安全条件では通常ルール変更を行わない設計のため、変更が必要になった場合はその理由も記録します。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| FQDNを解決できない | DNS server / record不整合 | `Resolve-DnsName`、`Get-DnsClientServerAddress` | DNS応答なし、NXDOMAIN、resolver設定差異を分離 |
| SRVレコード(`_ldap._tcp.dc._msdcs`等)が見つからない、`nltest /dsgetdc`失敗 | ドメイン未参加、Netlogonの動的登録失敗、DNSゾーン不整合 | `Resolve-DnsName -Type SRV`、`nltest /dsgetdc`、`Get-Service Netlogon` | ドメイン未参加かNetlogon停止かDNSゾーン設定かを分離 |
| IPへ届かない | route / gateway不整合 | `Get-NetRoute`、`Test-Connection` | ICMP方針を確認後、TCPへ進む |
| WinRMに接続できない(refused/timeout) | listener不在またはFirewall拒否 | `Test-WSMan`、`Get-NetFirewallRule` | listener未設定かFirewall拒否かを分離 |
| WSUS管理サイトに接続できない(refused/timeout) | `WsusService`/`W3SVC`停止、または`WsusPool`停止 | `Get-Service WsusService, W3SVC`、`Get-IISAppPool WsusPool` | service停止かapp pool停止かFirewallスコープ不一致かを分離 |
| WSUS管理サイトでHTTP 503 | `WsusPool`の停止・意図しないリサイクル | `Get-IISAppPool WsusPool`、IISログ、`Get-ItemProperty "IIS:\AppPools\WsusPool"` | idleTimeout/queueLength/privateMemory設定が意図どおりか確認 |
| windows_exporterでconnection refused | serviceまたはFirewallスコープ不一致 | `Get-Service windows_exporter`、`Get-NetTCPConnection -State Listen`、`Get-NetFirewallRule` | service停止か送信元スコープ不一致かを分離 |
| GPO(`WSUS-Client-Policy`)が反映されずクライアント設定が届かない | SYSVOL到達不可、時刻同期のずれ、GPO未適用 | `gpresult /r /scope computer`、`Get-WinEvent -LogName "Microsoft-Windows-GroupPolicy/Operational"`、`w32tm /query /status` | ネットワーク層の問題かGPO設計自体の問題かを分離 |
| timeout | Firewall / 上流route | `pktmon`、`Get-NetFirewallRule`、security group | packet到着前後で担当境界を分離 |

切り分け時は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全IDを`PASS / FAIL / BLOCKED / NOT RUN`のいずれかで判定した
- [ ] raw logと結果票の日時、commit SHA、環境、ホストのビルド番号(`winver`または`Get-ComputerInfo`の`OsBuildNumber`)が一致する
- [ ] packet capture、IP、MAC、hostname、accountの情報を共有前に確認した
- [ ] 一時的な`New-PSSession`/`Invoke-Command`セッション、`pktmon`キャプチャプロセスが終了している
- [ ] SNW-09でFirewallルールを一時的に変更した場合は元に戻したことを確認した
- [ ] 複数クライアントでの到達性・負荷確認は対象外であることを結果票に明記した(1節参照。`wsus-01`自身の到達性確認にとどめている)
- [ ] 問題があれば一次記録とIssueを相互リンクした
