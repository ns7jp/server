# AD実ホスト ネットワーク検証結果票 — 2026-09-01〜02

[実行手順](../build-package-ad/09-network-validation-procedure.md)に沿って、手元のHyper-V上に構築した`ad-dc01`(Windows Server 2022 Standard 評価版)を、ホストPCを管理端末として検証した記録です。[テンプレート](templates/network-host-validation-ad.md)の初期値`NOT RUN`を、実出力を見た項目だけ書き換えています。

> **この証跡が示す範囲**: ホストPC(Hyper-V)と、その内部スイッチ上のVM 1台の間の検証です。組織DNS、実際にドメインへ参加するメンバーホスト、中央Prometheus hostからのscrape、外部ゲートウェイを持つ経路は含みません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | `PASS`(ANW-01〜09 すべてPASS。差異5件を下表に記録) |
| 実施日時（JST） | 2026-09-01 17:40 〜 2026-09-02 10:30 頃(ANW-01〜06は9/1、ANW-07〜09は9/2) |
| 実施者 | ns7jp(AI支援セッションで手順を1つずつ実行し、スクリーンショットで結果を確認) |
| 対象環境 / host | `ad-dc01.corp.example.test`(`192.0.2.50/24`)、Hyper-V Generation 2 VM、内部スイッチ`ADLab-Internal` |
| 管理端末 | ホストPC(Windows 11、`192.0.2.40/24`、`vEthernet (ADLab-Internal)`)。ワークグループのまま、ドメイン未参加 |
| commit SHA | 検証時の手順書は`6c2d1cecf21e57e296d5790e77c6ebb5d820f628`(初版)。本結果票と同じPRで手順書の誤りを修正 |
| ホストのビルド番号（`Get-ComputerInfo` の `OsBuildNumber`） | `20348` |
| フォレスト / ドメイン機能レベル（`Get-ADForest` / `Get-ADDomain`） | `Windows2016Forest` / `Windows2016Domain` |
| PowerShell バージョン（組込5.1 / 追加導入7.4系） | 対象host `5.1.20348.558`(組込)。7.4系は未導入 |
| windows_exporter バージョン / SHA256 | `0.31.8` / `0aadce6afb20182b678bfca9e8f2e8464ef48c469b28b4cf02e99d82158f5d40`(amd64.msi。ホストPCでダウンロード・検証し、`Copy-Item -ToSession`で転送後、VM側でも再検証) |
| 構成図・IP 表の版 | [04-network-ip-plan.md](../build-package-ad/04-network-ip-plan.md)(例示値`192.0.2.0/24`をそのまま採用) |
| raw log / screenshot | セッション中のスクリーンショット(リポジトリには採録せず)。本票の「実出力（要点）」は画面から転記 |

IPは文書の例示値(`192.0.2.0/24`、TEST-NET-1)をそのまま使ったため、マスクしていません。MACアドレスはANW-07でマスクしています。DSRMパスワード、Administratorパスワードはどの出力にも含めていません。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| ANW-01 | interface / IP / CIDR | `Get-NetAdapter`, `Get-NetIPAddress` | 設計値と一致 | PASS | 下記 |
| ANW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 想定gateway/interface/経路 | PASS(閉域のためdefault routeなし) | 下記 |
| ANW-03 | DNS(通常レコード+SRVレコード) | `Resolve-DnsName`, `nltest /dsgetdc` | 想定レコードと一致 | PASS(差異#4) | 下記 |
| ANW-04 | ICMP | `Test-Connection` | 方針どおりの疎通 | PASS | 下記 |
| ANW-05 | 待受port | `Get-NetTCPConnection -State Listen` | 設計どおり | PASS(差異#1) | 下記 |
| ANW-06 | TCP/LDAP到達性 | `Test-NetConnection -Port` | 内部CIDRは到達、9182は拒否 | PASS | 下記 |
| ANW-07 | packet capture | `pktmon` | request/responseを説明可能 | PASS(差異#2) | 下記 |
| ANW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`, `Get-NetFirewallRule` | 設計と一致 | PASS(差異#3、#5) | 下記 |
| ANW-09 | end-to-end | 管理元CIDR外からのWinRM接続試行 | 拒否される | PASS | 下記 |

## 実出力

### ANW-01 interface / IP / CIDR

仮説・期待値:

```text
NIC 1本がUp、192.0.2.50/24がManual(静的)、loopback 127.0.0.1/8
```

実行コマンド:

```powershell
Invoke-Command -ComputerName $TargetIP -UseSSL -Credential $Cred -SessionOption $opt -ScriptBlock {
    Get-NetAdapter | Format-Table Name, Status, LinkSpeed
    Get-NetIPAddress -AddressFamily IPv4 | Format-Table InterfaceAlias, IPAddress, PrefixLength, PrefixOrigin
}
```

実出力（要点）:

```text
Name        Status LinkSpeed
イーサネット Up     10 Gbps

InterfaceAlias              IPAddress  PrefixLength PrefixOrigin
イーサネット                 192.0.2.50           24       Manual
Loopback Pseudo-Interface 1 127.0.0.1             8    WellKnown
```

判定 / 設計との差:

```text
PASS。設計値と完全一致。
```

### ANW-02 route / gateway

```text
期待値: 192.0.2.0/24がイーサネットへ向く。閉域ラボ(Hyper-V内部スイッチのみ)のためdefault route(0.0.0.0/0)は存在しない
コマンド: Get-NetRoute -AddressFamily IPv4 / Test-NetConnection -ComputerName 192.0.2.50 -TraceRoute
実出力: 192.0.2.0/24, 192.0.2.50/32, 192.0.2.255/32 → イーサネット(NextHop 0.0.0.0, Metric 256)。0.0.0.0/0 なし。
       TraceRoute: SourceAddress 192.0.2.40 → 192.0.2.50 の1ホップ、PingSucceeded True、RTT 0ms
判定: PASS。default routeが無いのは閉域という設計理由による(外向き通信を要求しない)。
```

### ANW-03 DNS(通常レコード+SRVレコード)

```text
期待値: Aレコード=192.0.2.50、_ldap/_kerberos._tcp.dc._msdcs のSRVが ad-dc01.corp.example.test:389/88 を返す
コマンド: Resolve-DnsName -Name ad-dc01.corp.example.test -Type A -Server 192.0.2.50
         Resolve-DnsName -Name _kerberos._tcp.dc._msdcs.corp.example.test -Type SRV -Server 192.0.2.50
         nltest /dsgetdc:corp.example.test (ホストPC側と ad-dc01 側の両方)
実出力: A: ad-dc01.corp.example.test → 192.0.2.50 (TTL 3600)。ホストPC・ad-dc01 双方で一致
       SRV: _kerberos._tcp.dc._msdcs.corp.example.test → ad-dc01.corp.example.test, Priority 0, Weight 100, Port 88, 192.0.2.50
       nltest (ad-dc01側): DC \\ad-dc01.corp.example.test, アドレス \\192.0.2.50, フラグ PDC GC DS LDAP KDC WRITABLE DNS_DC DNS_DOMAIN DNS_FOREST CLOSE_SITE FULL_SECRET ... 「コマンドは正常に完了しました」(/KDC も同じ)
       nltest (ホストPC側): 「DC 名の取得に失敗しました: Status = 1355 0x54b ERROR_NO_SUCH_DOMAIN」
判定: PASS。ホストPC側のnltest失敗は、ホストPCのDNSクライアント設定がad-dc01を向いていない(ワークグループのまま)ことによる。
     同じレコードを -Server 指定のResolve-DnsNameで取得でき、ad-dc01自身のnltestが成功しているため、DC/DNS側の欠陥ではない(差異#4)。
```

### ANW-04 ICMP

```text
期待値 / Firewall方針: ICMPは遮断しない設計。4/4応答
コマンド: Test-Connection -ComputerName 192.0.2.50 -Count 4 (ホストPC側)
         Test-Connection 127.0.0.1 / 192.0.2.40 -Count 4 (ad-dc01側)
packet loss / RTT: いずれも 0 loss、0〜1 ms
判定: PASS
```

### ANW-05 待受port

```text
期待する待受構成: 53,88,135,389,445,464,3268,5986,9182 待受。3389 非待受。636/3269 は証明書ストアと整合すること
コマンド: 53,88,135,389,445,464,636,3268,3269,3389,5986,9182 | % { Get-NetTCPConnection -State Listen -LocalPort $_ } (真偽表に整形)
         Get-NetUDPEndpoint | ? LocalPort -in 53,88,464
         Get-ChildItem Cert:\LocalMachine\My | Select Subject, Thumbprint, NotAfter, EKU
実出力:
  Port Listen      Port Listen
    53 True        3268 True
    88 True        3269 True   ← 設計は「非待受」を想定
   135 True        3389 False
   389 True        5986 True
   445 True        9182 True   ← windows_exporter 導入後に再確認(導入前は False)
   464 True
   636 True   ← 設計は「非待受」を想定
  UDP: 53 (192.0.2.50, 127.0.0.1, ::1, fe80::…), 88, 464 (192.0.2.50, fe80::…) 待受
  Cert:\LocalMachine\My: Subject CN=ad-dc01.corp.example.test, Thumbprint 9A70AC1425867FCBFB2CFC29C5463C8E6F5351A3,
                          NotAfter 2028/09/01, EKU「クライアント認証, サーバー認証」(WinRM HTTPS用に作成した自己署名証明書)
想定外listener: 636/3269 が待受。原因は上記自己署名証明書をNTDSがLDAPS用に自動採用したこと(差異#1)。
              9182 は初回確認時 False。windows_exporter 未導入(構築手順書8節を未実施)だったため、8節を実施して再確認し True。
判定: PASS。636/3269 は「証明書ストアの状態と待受が整合し説明できる」ため PASS とし、設計書の記述を本PRで修正。
```

### ANW-06 TCP/LDAP到達性

```text
内部ネットワークCIDR内からのLDAP(389)到達: TcpTestSucceeded True (Source 192.0.2.40)
内部ネットワークCIDR内からのKerberos(88)/DNS(53)到達: いずれも True
WinRM(5986): True
windows_exporter loopback応答: ad-dc01 上の curl.exe http://localhost:9182/metrics で windows_ad_address_book_client_sessions 等の windows_ad_* メトリクスを確認
windows_exporter 中央Prometheus host以外からの到達（拒否想定）: 192.0.2.40 → 9182 は「TCP connect failed」、TcpTestSucceeded False
判定: PASS。9182 の拒否は、中央Prometheus host が未決定で専用許可ルールを作っていないため、Default Inbound Block によって落ちている(明示的な拒否ルールは無い)。設計の「中央Prometheus host以外は拒否」と一致。
```

### ANW-07 packet capture

```text
capture対象host / filter: ad-dc01 上で pktmon filter add -p 53 → pktmon start --capture --pkt-size 128 --file-name C:\Windows\Temp\anw07.etl
request時刻: 2026-09-02 10:12:39 JST (ホストPCから Resolve-DnsName -Name ad-dc01.corp.example.test -Type A -Server 192.0.2.50)
観測したSYN/SYN-ACK等(DNSはUDPのため query/response):
  要求: <MAC-A> > <MAC-B>, ethertype IPv4, length 85: 192.0.2.40.50396 > 192.0.2.50.53: 52425+ A? ad-dc01.corp.example.test. (43)
  応答: <MAC-B> > <MAC-A>, ethertype IPv4, length 101: 192.0.2.50.53 > 192.0.2.40.50396: 52425* 1/0/0 A 192.0.2.50 (59)
  同じトランザクションID 52425 で要求と応答が対応。anw07.etl 21,712 byte、anw07.txt 48,428 byte(152イベント)
本文非採録確認: --pkt-size 128 で切り詰め。対象はDNS問い合わせのみで、資格情報を含む通信は採取していない。MACアドレスは <MAC-A>/<MAC-B> にマスク
判定: PASS。初回は手順書初版の構文(--etw -p 128)で .etl が生成されず失敗。pktmon start -h で構文を確認して修正(差異#2)。
```

### ANW-08 Windows Defender Firewall

```text
プロファイル（Domain/Private/Public）と既定Inbound:
  Get-NetFirewallProfile(永続ストア): 3プロファイルとも Enabled True、DefaultInboundAction NotConfigured、DefaultOutboundAction NotConfigured
  Get-NetFirewallProfile -PolicyStore ActiveStore(実効値): 3プロファイルとも DefaultInboundAction Block、DefaultOutboundAction Allow
AD DS自動生成ルールグループのスコープ（内部ネットワークCIDR）:
  Active Directory Domain Services / DNS サービス / Kerberos キー配布センター / DFS レプリケーション / ファイル レプリケーション
  → いずれも RemoteAddress 192.0.2.0/255.255.255.0
WinRM/windows_exporterルールのスコープ:
  WinRM-HTTPS-MgmtOnly → RemoteAddress 192.0.2.40
  リモート デスクトップ 3ルール → Enabled False
  *Exporter* に一致する許可ルール → なし
判定: PASS。DefaultInboundAction は永続ストアでは NotConfigured と表示されるが、実効値は Block(差異#3)。
     ルールグループ名は日本語版OSの表示名で指定した(差異#5)。
```

### ANW-09 end-to-end

```text
管理元CIDR内からのWinRM接続: Invoke-Command ... { whoami } → corp\administrator。TcpClient(Source 192.0.2.40) → 192.0.2.50:5986 Connected True
管理元CIDR外からのWinRM接続（拒否想定）: ホストPCの vEthernet に 192.0.2.41 を一時追加し、.NET TcpClient で送信元を 192.0.2.41 にバインドして接続
  192.0.2.41 → 192.0.2.50:5986 Connected False(5秒timeout)
  192.0.2.41 → 192.0.2.50:389  Connected True(対照。同じ送信元でも内部CIDR全体が許可のLDAPは届く=拒否の理由は経路ではなくWinRMルールのスコープ)
  確認後 Remove-NetIPAddress で 192.0.2.41 を削除し、192.0.2.40 のみに戻したことを Get-NetIPAddress で確認。ad-dc01 側のFirewallは変更していない
内部ネットワークCIDRの範囲設計の妥当性確認（実接続ホストなし）: ドメインメンバーは存在しないため、内部CIDRからの認証・GPO適用・SYSVOL参照は未確認。
  ANW-06/08/09 で確認できたのは「内部CIDR内の送信元から各ポートに到達でき、Firewallスコープが設計どおり」までであり、この境界を埋まったことにしない
判定: PASS
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| #1 LDAPS(636)/GC LDAPS(3269)が待受 | 設計書は「AD CS未導入なので待受しない」と記載していたが、両ポートとも`Listen`。`Cert:\LocalMachine\My`にWinRM HTTPS用自己署名証明書(`CN=ad-dc01.corp.example.test`、サーバー認証EKU)があり、NTDSがこれをLDAPSに自動採用した | 設計書の前提が誤り。動作上の実害はない(クライアントはこの証明書を信頼しないため実用LDAPSにはならない) | 記録のみ | 本PRで[03](../build-package-ad/03-parameter-sheet.md)・[04](../build-package-ad/04-network-ip-plan.md)・[06](../build-package-ad/06-test-specification.md)・[09](../build-package-ad/09-network-validation-procedure.md)・テンプレートを「証明書ストアと整合すればPASS」に修正 |
| #2 `pktmon start`の構文誤り | 手順書初版の`pktmon start --etw -p 128`では`.etl`が生成されない。`--etw`は存在せず、`start`の`-p`は`--provider`。正しくは`--capture --pkt-size 128` | ANW-07が手順書どおりでは実行不能 | `pktmon start -h`で確認し修正して再実行 | 本PRで[09](../build-package-ad/09-network-validation-procedure.md)を修正 |
| #3 `DefaultInboundAction`が`NotConfigured`表示 | `Get-NetFirewallProfile`は永続ストアの値を返し、未設定OSでは`NotConfigured`。`-PolicyStore ActiveStore`で`Block`。実動作もBlock(ANW-06(3)で実証) | 手順書・仕様書の期待値`Block`が表示と一致せず、読み手が誤判定しうる | `-PolicyStore ActiveStore`で再確認 | 本PRで[05](../build-package-ad/05-build-procedure.md)・[07](../build-package-ad/07-handover-checklist.md)・[09](../build-package-ad/09-network-validation-procedure.md)にActiveStore指定を追加 |
| #4 ホストPC側`nltest /dsgetdc`が`ERROR_NO_SUCH_DOMAIN` | 管理端末がワークグループのままで、DNSクライアント設定が`ad-dc01`を向いていない。`nltest`には問い合わせ先の指定がない | 管理端末側の構成による。DC/DNSの欠陥ではない | `Resolve-DnsName -Server`と`ad-dc01`側`nltest`で確認 | 本PRで[09](../build-package-ad/09-network-validation-procedure.md)ANW-03に注記追加 |
| #5 Firewallルールグループ名がロケール依存 | 日本語版では`DNS サービス`/`Kerberos キー配布センター`/`ファイル レプリケーション`/`DFS レプリケーション`。手順書の英語名は`ObjectNotFound` | 構築手順書AST-08の絞り込みと検証手順ANW-08が手順書どおりでは実行不能 | `Get-NetFirewallRule \| Select -ExpandProperty DisplayGroup -Unique`で実名を確認 | 本PRで[04](../build-package-ad/04-network-ip-plan.md)・[05](../build-package-ad/05-build-procedure.md)・[09](../build-package-ad/09-network-validation-procedure.md)を修正 |

検証手順(ANW)の範囲外だが、同じ構築セッションで見つけた構築手順書の誤りも本PRで修正した:

- `New-ADOrganizationalUnit -Name "Users"`がドメイン直下の既定`CN=Users`コンテナと衝突して作成できない。`Employees`をドメイン直下へ変更([03](../build-package-ad/03-parameter-sheet.md)、[05](../build-package-ad/05-build-procedure.md)、[02](../build-package-ad/02-detailed-design.md)、[08](../build-package-ad/08-change-rollback-plan.md))
- windows_exporterの導入(構築手順書8節)を飛ばしてANW-05へ進んだため9182が非待受だった。閉域のDCからはGitHubへ到達できないため、ホストPCでダウンロード・ハッシュ検証し`Copy-Item -ToSession`で転送、VM側でも再検証してからインストールした。この方式は「本番DCをインターネットに出さない」運用にも合う

問題の切り分けは[トラブルシュート一次記録テンプレート](templates/troubleshooting-worklog.md)の方式(仮説→反証→実出力)で行い、推測でPASSにしていない。

## 終了判定

- 必須: ANW-01〜09 → すべて`PASS`
- 上記差異は設計との差を承認して残すものではなく、手順書・設計書側の誤りとして本PRで修正した。実機の構成は変更していない(ANW-09の一時IPはホストPC側で、確認後に削除)
- 一時的な`New-PSSession`は`Remove-PSSession`で終了、`pktmon`は`stop`と`filter remove`を実行、`anw07.etl`/`anw07.txt`は削除済み
- 内部ネットワークCIDRの実接続確認(ドメインメンバーからの認証・GPO適用)は本ラボでは`NOT RUN`(ANW-09参照)
