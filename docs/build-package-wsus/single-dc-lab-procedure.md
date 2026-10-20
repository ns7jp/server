# 単一DCラボでWSUSを新規構築する代替手順

[案件パック](README.md) / [立ち上げと受け入れ](10-host-bringup-and-acceptance.md)

**状態: NOT RUN。** 本書は、稼働するAD DS・DNSが1台だけの新しい検証用ドメインに、WSUSをメンバーサーバーとして追加する経路です。既定の`ad-dc01`・`ad-dc02`による2DC設計は変更しません。2DCの片方が停止した環境を、単一DC環境として扱ってはいけません。

この経路を選ぶ場合、00・03・04・05・06・09・10の**DC台数・名前・DNS・実行場所に関する指定は本書の代替を優先**します。それ以外のWSUS設定、容量、権限、Firewall、承認前の検証、停止条件は既存手順を使います。単一DCでの結果を、2DCの冗長性・フェイルオーバーや過去の総合`FAIL`解消の証拠にはしません。

## 1. 実値と開始条件を確定する

次の表をローカルの新しい結果票へコピーします。実値や確認結果が未確定なら`BLOCKED`で止め、過去のVM名・IP・画像から補いません。値が決まっても、未実行の判定は`NOT RUN`のままです。

| 項目 | 計画値 / 確認結果 |
| --- | --- |
| 構成区分・対象文書SHA・実施者・日時 | `single-dc-lab` / NOT SET / NOT RUN |
| 実在DCのVM名・OSホスト名・FQDN・IPv4 | NOT SET |
| ドメインDNS名・NetBIOS名・DN | NOT SET |
| `Servers` OUのDNと存在確認 | NOT SET / NOT RUN |
| 新規WSUSのVM名・OSホスト名・FQDN | NOT SET |
| WSUSのIPv4/prefix・gateway・NIC名 | NOT SET |
| 管理端末IPv4・管理元CIDR・内部ネットワークCIDR | NOT SET |
| DCとWSUSを同時稼働させるメモリ・C:/D:容量 | NOT RUN |
| コンソール復旧・変更前チェックポイント・作業時間帯 | NOT SET |

実在DCの対話コンソールで以下を読み取り、結果を保存します。

```powershell
Get-Date -Format o
hostname
Get-Service NTDS, DNS, Netlogon, KDC | Select-Object Name, Status, StartType
dcdiag /q
$LASTEXITCODE
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DistinguishedName, PDCEmulator
Get-ADDomainController -Filter * | Select-Object HostName, IPv4Address, IsReadOnly
Get-ADOrganizationalUnit -Filter 'Name -eq "Servers"' |
    Select-Object DistinguishedName
```

開始条件は、再起動後に4サービスが`Running`、`dcdiag /q`に異常出力がなく終了0、DC一覧が計画と一致する書き込み可能な1台、ドメインと`Servers` OUが確認できることです。DCが2台以上登録されている、OUがない、名前解決できない場合は`BLOCKED`です。AD側の構築・復旧を別作業で終えてから戻ります。本書のためにDCを停止・削除したり、GPOをDCのOUへ広げたりしません。

[立ち上げ手順8.2a](10-host-bringup-and-acceptance.md)のUbuntu観測終了→AD確認→WSUSの順序と、8.3の実割り当て8GB・D:100GB以上などの条件も満たします。メモリ確認の`Get-VM`・`Get-VHD`には表の実VM名を使い、唯一のDCは稼働を維持します。旧`lab-base01`の停止や旧`pre-wsus-role`への巻き戻しを開始条件にはしません。

## 2. 共通の置換とセッション準備

既存手順の例示値は、実行する前に次の対応で置き換えます。ドメインとWSUS名が異なる場合はDNSだけを直して終わらせず、証明書・WinRM・GPO・WSUS URL・OU・資格情報のドメイン部分もそろえます。

| 既存文書の表記 | 単一DC経路で使う値 |
| --- | --- |
| `corp.example.test` / `CORP` / `DC=corp,DC=example,DC=test` | 確認したドメインDNS名 / NetBIOS名 / DN |
| `OU=Servers,DC=corp,DC=example,DC=test` | 確認した`Servers` OU DN |
| `wsus-01` / `wsus-01.corp.example.test` / `.52` | 実WSUSホスト名 / FQDN / IPv4 |
| `ad-dc01`・`ad-dc02` / `.50`・`.51` | 実在DC1台のホスト名・FQDN・IPv4。DNS配列に架空の第2DCを残さない |
| `http://wsus-01.corp.example.test:8530` | 実WSUS FQDNの同じport・pathのURL |
| 管理端末`.40`・NIC名・prefix・CIDR・gateway | 結果票に確定した実値 |

各端末・再起動後の新しいPowerShellセッションで、使う変数を次のブロックから設定し直します。資格情報は含めず、実値入りのコピーは公開しません。

```powershell
$LabDcFqdn = 'NOT SET'
$LabDcIP = 'NOT SET'
$LabDomainFqdn = 'NOT SET'
$LabServersOuDn = 'NOT SET'
$LabWsusHost = 'NOT SET'
$LabWsusFqdn = 'NOT SET'
$LabWsusIP = 'NOT SET'
$LabWsusNic = 'NOT SET'
$LabManagementIP = 'NOT SET'
$labValues = @($LabDcFqdn, $LabDcIP, $LabDomainFqdn, $LabServersOuDn,
    $LabWsusHost, $LabWsusFqdn, $LabWsusIP, $LabWsusNic, $LabManagementIP)
if (@($labValues | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -eq 'NOT SET' }).Count) {
    throw 'BLOCKED: 結果票の実値を設定してから開始する'
}
```

## 3. 構築手順の分岐

[05 構築手順](05-build-procedure.md)は以下の代替を適用して0〜9・11〜14節へ進みます。**単一DC経路では2DC前提の0節やDNS設定をそのまま実行しません。** 10節のフェーズ2は引き続き`BLOCKED`です。

| 元の節 | 代替する前提・操作と実行場所 |
| --- | --- |
| 0 作業前確認 | 両DC・6OUの完成条件を、本書1節の実在DC1台・AD DNS・`Servers` OUの確認へ置換。その他の権限・資源・Go/No-Go条件は維持 |
| 1 管理端末 | ADのSOA照会先を実DCのIP、DC疎通先を実FQDNへ変更。非ドメイン参加端末ではSOA照会に`-Server $LabDcIP`を明示 |
| 2.1 WSUSコンソール | ホスト名・固定IP等を実値へ置換。**DNS設定の3行は下の単一DC用ブロックへ置換**。WinRM証明書等の残りの準備は継続 |
| 2.2 WSUSコンソール | `Add-Computer`のドメイン名を実値へ置換して参加・再起動。再ログオン時のNetBIOS名も実値を使用 |
| 2.2 ADオブジェクト操作 | 実DCの対話コンソールへ移り、下のOU配置ブロックを実行。その後WSUSへ戻ってDNS・WinRMを確認 |
| 7 GPO作成・リンク | WSUS側の`TargetingMode=Client`設定はWSUS上。`Install-WindowsFeature -Name GPMC`から`Set-GPRegistryValue`までのGPO操作は実DCの対話コンソールで、OU DNとWSUS URLを実値へ置換。リンク先は`Servers` OUだけ |
| 7 GPO適用結果 | **WSUSコンソールへ戻り**、既存の`gpupdate`・`gpresult`・GroupPolicyログ・レジストリ・自己登録確認を実施。DC自身の適用結果を`SIT-04`の合格にしない |
| 11 構築後確認 | ADオブジェクト確認だけ実DCで実行。サービス・IIS・Firewall・WSUS APIはWSUS、到達性確認は管理端末で実行 |
| 12 障害試験 / 13 Firewall・データ復旧 | サービス・IIS・`netsh advfirewall export/import`・SUSDB・コンテンツ操作は**WSUS上**。今回のWSUS用バックアップを使用 |
| 13 GPOの保全・復旧 | `Backup-GPO`・`Restore-GPO`はGPMCを準備した**実DCの対話コンソール**で実行。DC側のGPOバックアップ保存先とIDを別記し、WSUS側の保存先と混同しない。混在する元のコードブロック全体をDCへ移さない |
| 13 VMチェックポイント | **Hyper-Vホスト上**で、新規WSUSの実VM名と今回のチェックポイントを指定。実DCのVM全体は復元しない |
| 14 終了 | 一時Firewall許可・インストーラ等の後片付けはWSUS側。実行場所ごとの記録・GPO保全先・残件を結果票へ残す |

### 3.1 WSUSのDNSを実在する1台へ向ける

初期固定IP設定後、**WSUSコンソールで**実行します。公開DNSやWSUS自身のloopbackを第2DNSとして足しません（[MicrosoftのメンバーサーバーDNS設定](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/best-practices-for-dns-client-settings#windows-server-member-servers)）。

```powershell
Set-DnsClientServerAddress -InterfaceAlias $LabWsusNic -ServerAddresses @($LabDcIP)
Get-DnsClientServerAddress -InterfaceAlias $LabWsusNic -AddressFamily IPv4
Resolve-DnsName -Name $LabDomainFqdn -Type SOA -Server $LabDcIP
```

設定されたDNSが実DCのIP1件だけで、SOAが対象ドメインのものと確認できてからドメイン参加へ進みます。確認できなければ`BLOCKED`です。

### 3.2 ドメイン参加後のOU配置と名前解決

**実DCの対話コンソールで**実行します。`Servers` OUは1節で準備済みであることが前提です。

```powershell
Get-ADOrganizationalUnit -Identity $LabServersOuDn -Server $LabDcFqdn -ErrorAction Stop
$labComputer = Get-ADComputer -Identity $LabWsusHost -Server $LabDcFqdn -ErrorAction Stop
Move-ADObject -Identity $labComputer.DistinguishedName -TargetPath $LabServersOuDn -Server $LabDcFqdn
Get-ADComputer -Identity $LabWsusHost -Server $LabDcFqdn -Properties DistinguishedName
```

WSUSコンソールへ戻って変数を設定し直し、次を実行します。元手順の固定`.50`への照会をこの照会へ置換します。

```powershell
Resolve-DnsName -Name $LabWsusFqdn -Type A -Server $LabDcIP
nltest /dsgetdc:$LabDomainFqdn
$LASTEXITCODE
```

WSUSのAレコードが実IPと一致し、DC locatorが成功して実DCを返すことを確認します。続けて管理端末から実WSUS FQDNのWinRM HTTPS疎通を確認します。

## 4. ネットワーク試験の代替

[09 ネットワーク手順](09-network-validation-procedure.md)3節の対象・ドメイン・管理端末・資格情報を実値へ置換します。`$AdDc01IP`・`$AdDc02IP`の2変数は使いません。**5〜7節のコードとDC台数に関する期待値は以下へ丸ごと置換**し、残る節は実値で実施します。WSUSコンソールと管理端末の結果を別々に採録します。

### SNW-02 / SNW-04: 実DCとの経路・ICMP

管理端末ではWSUSへの経路と疎通を確認します。

```powershell
Test-NetConnection -ComputerName $LabWsusIP -TraceRoute
Test-Connection -ComputerName $LabWsusIP -Count 4
```

WSUSコンソールでは次を実行します。

```powershell
Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix |
    Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric
Test-NetConnection -ComputerName $LabManagementIP -TraceRoute
Test-NetConnection -ComputerName $LabDcIP -TraceRoute
Test-Connection -ComputerName '127.0.0.1' -Count 4
Test-Connection -ComputerName $LabManagementIP -Count 4
Test-Connection -ComputerName $LabDcIP -Count 4
```

default gateway・NIC・subnet・経路が計画と一致し、実DC1台へ到達することを確認します。ICMPを遮断する設計なら、その方針と失敗を記録して元のSNW-06のTCP/HTTP確認を使います。第2DCへの到達・DC切替はこの経路では未検証です。

### SNW-03: 管理端末とWSUSの両方でDNSを確認する

次の照会を**両端末でそれぞれ**実行します。

```powershell
Resolve-DnsName -Name $LabWsusFqdn -Type A -Server $LabDcIP
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$LabDomainFqdn" -Type SRV -Server $LabDcIP
Resolve-DnsName -Name "_kerberos._tcp.dc._msdcs.$LabDomainFqdn" -Type SRV -Server $LabDcIP
```

さらに**WSUS上だけで**実行します。明示したDNSへの照会だけでなく、WSUS自身のDNSクライアント設定も確認します。

```powershell
Get-DnsClientServerAddress -InterfaceAlias $LabWsusNic -AddressFamily IPv4
Resolve-DnsName -Name $LabWsusFqdn -Type A
nltest /dsgetdc:$LabDomainFqdn
$LASTEXITCODE
Get-Service Netlogon | Select-Object Name, Status
```

両端末のAレコードが実WSUS IP、LDAP/KerberosのSRVが実DCのFQDNとport 389/88を返すこと、WSUSのDNS設定が実DC1件のみ、DC locatorが成功することを確認します。存在しないDCのレコードが返る場合は合格にせず、AD DNS側を調査します。本手順からレコードを推測で削除しません。

## 5. 判定と記録の範囲

[06 試験仕様書](06-test-specification.md)のIDは維持し、結果票に`構成区分=single-dc-lab`と次の期待値差分を記録します。下記以外のフェーズ1必須IDも省略しません。

| ID | 単一DC経路の確認・期待値 |
| --- | --- |
| SUT-01 | 実DCで確認したWSUSのDNが、実ドメインの`Servers` OU配下 |
| SIT-01 / SIT-02 | 本書の分岐を適用した構築・再実行。既存のサービス・設定・重複防止の期待値も維持 |
| SIT-04 | 実DCで作ったGPOが**WSUS上で**適用され、実WSUS自身が`Pilot`へ登録 |
| SNW-01 | 今回のWSUS IP/prefix・NICが計画値と一致 |
| SNW-02 / SNW-04 | WSUS⇔管理端末とWSUS→実DC1台の経路・方針に沿う疎通。本書4節を使用 |
| SNW-03 | 両端末のA/SRV照会、WSUSのDNSクライアント設定・DC locator。本書4節を使用 |

日付付きの新しい[作業結果票](11-work-result-report.md)と[ネットワーク結果票](../evidence/templates/network-host-validation-wsus.md)を作り、実DC名・IP、採用した代替、実出力、未検証の冗長性を残します。原本の`NOT RUN`と過去の結果は上書きしません。

すべての実測がそろっても結論は「単一DC構成のフェーズ1」の範囲に限ります。既定2DC構成の受け入れ、DC冗長性・フェイルオーバー、過去の総合`FAIL`、案件パックの`NOT READY`をこの限定試験だけで変更しません。フェーズ2の`SIT-09`は既存の解除条件を満たすまで`BLOCKED`です。
