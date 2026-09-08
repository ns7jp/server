# WSUS実ホスト ネットワーク検証結果票 — 2026-09-07

[実行手順](../build-package-wsus/09-network-validation-procedure.md)（SNW-01〜09）に沿って`wsus-01`で実施した記録です。様式は[テンプレート](templates/network-host-validation-wsus.md)に従います。構築・試験全体の結果は[WSUS構築・試験結果票](2026-09-07-wsus-build-validation.md)を参照してください。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | **`PASS`**（SNW-01〜09 の 9/9） |
| 実施日時（JST） | 2026-09-07 17:00〜18:00 |
| 実施者 | 本人 |
| 対象環境 / host | 検証（ラボ）/ `wsus-01` = `wsus-01.corp.example.test` = `192.0.2.52/24` |
| 管理端末 | ホストPC（非ドメイン参加）、`vEthernet (ADLab-Internal)` = `192.0.2.40/24` |
| commit SHA | `8216723c5d6232ac74d7dc60c295a5efbcc80741` |
| ホストのビルド番号 | `20348`（Windows Server 2022 Standard Evaluation、デスクトップ エクスペリエンス、ja-JP） |
| ドメイン参加状態 | `CsPartOfDomain=True` / `CsDomain=corp.example.test` |
| PowerShell バージョン | 組込 `5.1.20348.558` / 追加導入 `7.4.19` |
| WSUSロール / コンテンツストア | `UpdateServices`ほか6機能`Installed`（系統A=WID）。`D:\WSUS\WSUSContent`、D:は100GB NTFS |
| windows_exporter | `0.31.8` / SHA256 `0AADCE6AFB20182B678BFCA9E8F2E8464EF48C469B28B4CF02E99D82158F5D40` |
| 構成図・IP表の版 | [04-network-ip-plan.md](../build-package-wsus/04-network-ip-plan.md) |

秘密値のマスク方針: ローカル管理者アカウント名（改名済み）は秘匿し、prefix length・bind address・port・判定に必要な値は残しています。IPはRFC 5737の例示用アドレス（TEST-NET-1）そのままです。

### 依存環境の前提差分

`ad-dc01`（`192.0.2.50`）は[2026-09-04のFSMO奪取試験](2026-09-04-ad-fsmo-seize.md)でADメタデータごと削除済みで存在しません。したがって[ネットワーク設計](../build-package-wsus/04-network-ip-plan.md)2節が求める「`ad-dc01`・`ad-dc02`双方への到達性」は、**`ad-dc02`単独への到達性として読み替えて**判定しています。DCロケーターがSRVレコードで動的にDCを選ぶ設計自体は成立しており、片方に固定した経路設計にはなっていません。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SNW-01 | interface / IP / CIDR | `Get-NetAdapter`, `Get-NetIPAddress` | 設計値と一致 | **PASS** | 下記 |
| SNW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 想定 gateway / interface / 経路 | **PASS** | 下記 |
| SNW-03 | DNS（corp.example.testゾーン） | `Resolve-DnsName`, `nltest` | Aレコード・SRVが想定どおり解決 | **PASS** | 下記 |
| SNW-04 | ICMP | `Test-Connection` | 方針どおりの疎通 | **PASS** | 下記 |
| SNW-05 | 待受port | `Get-NetTCPConnection -State Listen` | 5986/8530/9182 待受、3389 非待受 | **PASS** | 下記 |
| SNW-06 | TCP / HTTP | `Invoke-WebRequest` / `curl.exe` | 8530は内部CIDRから到達、9182は拒否 | **PASS** | 下記 |
| SNW-07 | packet capture | `pktmon` | 経路を説明可能、本文は非採録 | **PASS** | 下記 |
| SNW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`, `Get-NetFirewallRule` | プロファイル`Domain`・許可ルールが設計と一致 | **PASS** | 下記 |
| SNW-09 | end-to-end | 許可CIDR内外からの接続試行 | 許可外は拒否 | **PASS** | 下記 |

## 実出力

### SNW-01 interface / IP / CIDR

期待値: 想定NICが`Up`、`192.0.2.52/24`、`PrefixOrigin=Manual`（静的固定IP）、意図しないセグメントのIPがない。

```text
Name   Status LinkSpeed MacAddress
----   ------ --------- ----------
イーサネット Up     10 Gbps   00-15-5D-0B-06-0E

InterfaceAlias              IPAddress  PrefixLength PrefixOrigin
--------------              ---------  ------------ ------------
イーサネット                      192.0.2.52           24       Manual
Loopback Pseudo-Interface 1 127.0.0.1             8    WellKnown
```

判定: **PASS**。NICは1枚のみで`Up`、対象IP/prefixが設計値と一致、`PrefixOrigin=Manual`、loopbackが既定で存在。意図しないセグメントのIPはありません。

補足: 初回の`New-NetIPAddress`直後は`AddressState`が`Tentative`→`Invalid`と遷移し、直後に読むとアドレスが見えません。8秒後に`Preferred`へ確定しました。重複アドレス検出（DAD）の途中を読んだだけで、設定の失敗ではありません。

### SNW-02 route と default gateway

```text
DestinationPrefix  NextHop    InterfaceAlias              RouteMetric
-----------------  -------    --------------              -----------
0.0.0.0/0          192.0.2.40 イーサネット                              256
127.0.0.0/8        0.0.0.0    Loopback Pseudo-Interface 1         256
192.0.2.0/24       0.0.0.0    イーサネット                              256
192.0.2.52/32      0.0.0.0    イーサネット                              256
224.0.0.0/4        0.0.0.0    イーサネット                              256
255.255.255.255/32 0.0.0.0    イーサネット                              256

--- TraceRoute to 192.0.2.40 (管理端末 / NATゲートウェイ) ---
PingSucceeded : True
TraceRoute    : {192.0.2.40}

--- TraceRoute to 192.0.2.51 (ad-dc02) ---
PingSucceeded : True
TraceRoute    : {192.0.2.51}

--- 管理端末 -> wsus-01 ---
PingSucceeded : True
TraceRoute    : {192.0.2.52}
```

判定: **PASS**。default routeのNextHopは`192.0.2.40`（ホストPCのWinNAT）、対象subnet`192.0.2.0/24`は想定interfaceへ向いています。同一セグメントのため全経路が1ホップです。

設計書のdefault gatewayは`NOT SET`（環境ごとに決定）であり、本ラボでは管理端末とNATゲートウェイを同一ホストが兼ねています。実運用では管理端末とゲートウェイは別であるべきで、この構成はラボ固有です。

### SNW-03 DNS名前解決（corp.example.testゾーン）

```text
--- wsus-01 自身のDNSクライアント設定 ---
InterfaceAlias ServerAddresses
-------------- ---------------
イーサネット      {192.0.2.51}

--- Aレコード（対象ホスト自身から） ---
Name                      Type IPAddress
----                      ---- ---------
wsus-01.corp.example.test    A 192.0.2.52

--- SRVレコード（DC・KDC探索用） ---
_ldap._tcp.dc._msdcs.corp.example.test      SRV ad-dc02.corp.example.test  389
_kerberos._tcp.dc._msdcs.corp.example.test  SRV ad-dc02.corp.example.test   88

--- DCロケーター動作確認 ---
nltest /dsgetdc:corp.example.test
           DC: \\ad-dc02.corp.example.test
      アドレス: \\192.0.2.51
ドメイン GUID: a8f267be-f218-4f28-8f2b-26b94b4c59d5
 DC サイト名: Default-First-Site-Name
        フラグ: PDC GC DS LDAP KDC TIMESERV GTIMESERV WRITABLE DNS_DC DNS_DOMAIN DNS_FOREST CLOSE_SITE FULL_SECRET WS DS_8 DS_9 DS_10 KEYLIST
コマンドは正常に完了しました
Netlogon: Running

--- 管理端末から（AD統合DNSを明示指定） ---
Resolve-DnsName wsus-01.corp.example.test -Server 192.0.2.51 → A 192.0.2.52
```

判定: **PASS**。Aレコードはドメイン参加による動的更新で自動登録されています（`Register-DnsClient`後に確認）。DNSクライアントは`192.0.2.51`を指しており、`127.0.0.1`ではありません（メンバーサーバーとして正しい）。SRVレコードは`ad-dc02`のport 389/88を返し、`nltest`のフラグに全FSMO役割が反映されています。管理端末と対象ホストの結果は一致しました。

管理端末はドメイン参加していないため、手順書の注記どおり`Resolve-DnsName -Server <DCのIP>`で代替しています。加えて、`Test-WSMan`がFQDNを解決できず失敗したため、管理端末の`hosts`へ`192.0.2.52 wsus-01.corp.example.test`を追加しました。

### SNW-04 ICMP疎通

```text
--- wsus-01 から ---
127.0.0.1  : replies=4/4
192.0.2.40 : replies=4/4   (管理端末 / NATゲートウェイ)
192.0.2.51 : replies=4/4   (ad-dc02)
192.0.2.50 : replies=0/2   (ad-dc01。FSMO奪取試験で削除済みのため到達不可が期待値)

--- 管理端末から ---
192.0.2.52 : replies=4/4
```

判定: **PASS**。ICMPは遮断方針ではないため、疎通成功をそのまま判定に使えます。`192.0.2.50`の無応答は、依存案件側で当該ホストが削除済みであることと整合します。

### SNW-05 待受port

```text
--- 設計対象ポートの待受真偽 ---
 5986 : True    (WinRM HTTPS)
 8530 : True    (WSUS管理サイト HTTP)
 9182 : True    (windows_exporter)
 3389 : False   (RDP。既定Disable)

--- 待受一覧（抜粋） ---
LocalAddress LocalPort OwningProcess
::                  80             4   ← IIS Default Web Site
::                 135           388
192.0.2.52         139             4
::                 445             4
::                5986             4
::                8530             4
::                8531             4   ← WSUS管理サイト HTTPS（ロールが自動作成）
::                9182          2428
::               47001             4

--- WID が名前付きパイプのみでTCPポートを持たないことの確認 ---
Name
----
MICROSOFT##WID\tsql\query
```

判定: **PASS**。設計が要求する3ポートが待受、3389は非待受です。SUSDBはWID接続用の名前付きパイプ経由のみで、追加のネットワークportを持ちません（[パラメータシート](../build-package-wsus/03-parameter-sheet.md)「データベース方式」節と矛盾なし）。

注記: 80（IIS Default Web Site）と8531（WSUS管理サイトHTTPS）はロール導入により自動的に待受状態になります。いずれも設計の許可経路ではないため、Firewallの許可ルールを作らない（8531についてはロールが自動生成したルールを無効化した）ことで外部からは到達できません。「想定しない外部向けlistenerがない」という確認点は、待受の有無ではなくFirewall許可の有無で満たしています。

### SNW-06 TCP / HTTP（WSUS管理サイト、windows_exporter）

```text
(1) wsus-01 自身（loopback）
    http://127.0.0.1:8530/ClientWebService/client.asmx  → HTTP 200
    http://127.0.0.1:9182/metrics                        → HTTP 200
    windows_iis_* のメトリクス行数: 233
    例: windows_iis_anonymous_users_total{site="WSUS の管理"} 7
        windows_exporter_build_info{... version="0.31.8"} 1

(2) 管理端末 → WSUS管理サイト 8530（内部ネットワークCIDR内。到達=期待）
    Test-NetConnection 192.0.2.52 -Port 8530 → TcpTestSucceeded : True
    curl http://wsus-01.corp.example.test:8530/ClientWebService/client.asmx        → HTTP 200
    curl http://wsus-01.corp.example.test:8530/SimpleAuthWebService/SimpleAuth.asmx → HTTP 200
    curl http://wsus-01.corp.example.test:8530/selfupdate/wuident.cab               → HTTP 200

(4) 管理端末 → windows_exporter 9182（中央Prometheus host以外。拒否=期待）
    Test-NetConnection 192.0.2.52 -Port 9182 → TcpTestSucceeded : False
    curl http://wsus-01.corp.example.test:9182/metrics → HTTP 000 / curl exit code 28 (timeout)

(5) WsusPool チューニング
    idleTimeout   : 00:00:00
    queueLength   : 2000
    privateMemory : 0
    State         : Started
```

判定: **PASS**。(1)(2)は200、(4)は接続拒否（timeout）、(5)は設計値と一致しました。

(4)が拒否されるのは、中央Prometheus hostのIPが`NOT SET`のため9182の許可ルールを作成しておらず、Default Inbound Blockで落ちているためです。明示的な拒否ルールはありません。設計の「windows_exporterは中央Prometheus hostのIPのみ許可」と一致します（[AD版パック2026-09-01のANW-06](2026-09-01-network-host-validation-ad.md)と同じ扱い）。

### SNW-07 packet capture

WSUS管理サイト（8530）のクライアントWebサービスは既定で匿名アクセスであり資格情報を含まないため、本項目のサンプル通信に使用しました。

```text
[対象ホスト側]
pktmon filter remove
pktmon filter add WSUS8530 -p 8530
pktmon start --capture --pkt-size 128 --file-name C:\Windows\Temp\snw07.etl

    パケット フィルター:
         # 名前        ポート
         1 WSUS8530     8530

    収集されたデータ: パケット カウンター、パケット キャプチャ
    ログ ファイル: C:\Windows\Temp\snw07.etl

[キャプチャ中に管理端末から送信]
    request 1 -> HTTP 200
    request 2 -> HTTP 200
    request 3 -> HTTP 200
    request 4 -> HTTP 200

[停止]
pktmon stop → ログをフラッシュ、メタデータを結合
```

判定: **PASS**。`--pkt-size 128`によりヘッダのみを採録し、本文は採録していません。フィルターをポート8530に限定しているため、他の通信は含まれません。キャプチャ中に送った4リクエストがすべてHTTP 200で応答しており、管理端末→`wsus-01`:8530のrequest/responseの経路を説明できます。

### SNW-08 Windows Defender Firewall

```text
--- プロファイル（ActiveStore） ---
Name    Enabled DefaultInboundAction DefaultOutboundAction
----    ------- -------------------- ---------------------
Domain     True                Block                 Allow
Private    True                Block                 Allow
Public     True                Block                 Allow

--- 接続プロファイル ---
InterfaceAlias NetworkCategory
-------------- ---------------
イーサネット      DomainAuthenticated

--- 設計対象ポートの有効な受信許可ルール ---
DisplayName               Port Remote                  Profile
-----------               ---- ------                  -------
WinRM-HTTPS-MgmtOnly      5986 192.0.2.40                  Any
WSUS-Content-InternalOnly 8530 192.0.2.0/255.255.255.0     Any

--- 平時は無効のルール ---
RDP-Temp-MgmtOnly         3389 192.0.2.40   Enabled=False
リモート デスクトップ - シャドウ / ユーザー モード(TCP/UDP) すべて Enabled=False
```

判定: **PASS**。ドメイン参加により接続プロファイルが`DomainAuthenticated`へ遷移し、3プロファイルとも`DefaultInboundAction=Block`です。許可ルールは設計どおりWinRM（管理元CIDR限定）とWSUSコンテンツ（内部ネットワークCIDR限定）の2件のみになりました。

**この状態に到達するには、手順書に無い作業が必要でした。** WSUSロール導入時に自動生成される許可ルール`WSUS`が、8530と8531の両方について`RemoteAddress=Any`で有効になっており、そのままでは設計の「内部ネットワークCIDR限定」を満たしません。手順書はWinRMのquickconfigルールについては「限定ルールへ一本化する」と明記していますが、WSUSロール側の同種ルールには触れていません。実機では両方を`Disable-NetFirewallRule`で無効化しています。

### SNW-09 end-to-end（WinRM HTTPSの非対称性）

```text
(a) 管理元CIDR内（192.0.2.40）からのWinRM HTTPS — 成功=期待
    Test-WSMan -ComputerName wsus-01.corp.example.test -UseSSL -Authentication Negotiate -Credential <domain>
        ProtocolVersion : http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd
        ProductVendor   : Microsoft Corporation
        ProductVersion  : OS: 10.0.20348 SP: 0.0 Stack: 3.0

    Invoke-Command -ComputerName wsus-01.corp.example.test -UseSSL -Credential <domain>
        → リモート実行成功: WSUS-01 / corp\<domain admin> / 17:23:12

(b) WinRM 5986 TCP到達性
    Test-NetConnection 192.0.2.52 -Port 5986 → TcpTestSucceeded : True

(c) windows_exporter 9182（中央Prometheus host以外。拒否=期待）
    Test-NetConnection 192.0.2.52 -Port 9182 → TcpTestSucceeded : False

(d) RDP 3389（既定Disable。拒否=期待）
    Test-NetConnection 192.0.2.52 -Port 3389 → TcpTestSucceeded : False
```

判定: **PASS**。管理元CIDR内からのWinRM HTTPSは成立し、許可対象外の9182・3389は拒否されました。

WinRM HTTPSは通信自体がTLSで暗号化されるため、[Linux版パック](../build-package/09-network-validation-procedure.md)のSSHトンネルに相当する追加のトンネルは不要です。この非対称性を確認しました。証明書は自己署名（`CN=wsus-01.corp.example.test`、拇印`4153721F3B36B3152BF66B1660B630B1530B11A7`）を管理端末の`LocalMachine\Root`へインポートして信頼させています。実TLS証明書での検証は未実施です。

## 未確認・限界

- 管理端末・NATゲートウェイ・ハイパーバイザーをホストPC 1台が兼ねており、独立した管理端末からの検証ではありません。
- 管理元CIDR**外**からの接続試行は、内部スイッチ上に第3のホストが無いため実施していません。`RemoteAddress`の値が設計と一致することの確認に留めています。
- 実DNS・実TLS証明書・インターネット越しのFirewall検証は未実施です（評価版ISO + 内部スイッチ構成の制約）。
- `ad-dc01`が存在しないため、DC 2台への冗長経路の同時確認はできていません。
- 8531（HTTPS）はロールにより待受状態ですが、内部CA未導入のため設計上は対象外であり、許可ルールを無効化して到達不可としています。HTTPS化そのものの検証は未実施です。
