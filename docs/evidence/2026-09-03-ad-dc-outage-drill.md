# DC 1台停止時の可用性試験 — 2026-09-03

[基本設計書](../build-package-ad/01-basic-design.md)3.4節の発展課題「単一障害点(SPOF)」の検証として、[2台目DC追加](2026-09-03-ad-second-dc-replication.md)で構築した2台構成のうち`ad-dc01`を計画停止し、`ad-dc02`単独でどこまで機能が継続し、どこが縮退するかを実測しました。同じ演習でdc01を復帰させ、ディレクトリとして完全復旧するまでの所要時間(RTO相当)も測定しています。

> **この証跡が示す範囲**: 手元Hyper-V上のVM 2台による、片方の**正常停止**(ゲストOS内からのシャットダウン)からの復旧です。電源断・ハードウェア障害・FSMO役割の**奪取**(seize)は含みません。役割の奪取は、dc01が復旧不能な場合の最終手段として別途扱う課題です。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS** |
| 停止方法 | `Stop-VM -Name ad-dc01 -Force:$false`(ゲストOS内からの正常シャットダウン) |
| 停止所要時間 | 11秒(18:09:53指示 → 18:10:04 State:Off確認) |
| **dc01停止中のdc02単独での継続性** | DNS・LDAP・Kerberos・GC・新規オブジェクト作成、いずれも継続 |
| **dc01停止中に縮退した機能** | PDCエミュレータ/RIDマスターへの明示接続(GPMC等)が失敗。`-Server`をdc02に切り替えれば継続可能 |
| dc01復帰: サービス復旧まで | 4分51秒(起動18:31:07 → 全サービスRunning 18:35:58) |
| **dc01復帰: ディレクトリ完全収束まで(狭義RTO)** | **18分31秒**(起動18:31:07 → `repadmin`失敗0/5 18:49:38) |
| 復旧の転換点 | DNSサービス再起動だけでは自然収束せず、`repadmin /syncall /AdeP`による**強制再同期が必要**だった |

## 試験の設計

FSMO役割は[2台目DC追加の証跡](2026-09-03-ad-second-dc-replication.md)6節で分割済みです。

| 役割 | 保持DC |
| --- | --- |
| スキーママスター、ドメイン名前付けマスター(フォレストレベル) | `ad-dc02` |
| PDCエミュレーター、RIDプールマネージャー、インフラストラクチャマスター(ドメインレベル) | `ad-dc01` |

したがって**dc01の停止 = ドメインレベル3役割の喪失**という構図になり、「単純に1台減る」以上の意味を持つ試験になります。

チェックポイントは事前に取得していません。理由は次のとおりです。

- 停止・起動のみで破壊的操作を含まないため、事前の安全網が本質的に不要
- **2台のうち片方だけをスナップショットで過去に戻す操作自体がリスク**(USNロールバックの温床になりうる。Hyper-VのVM-GenerationIDで検知・保護はされるが正常系ではない)
- [復元演習](2026-09-02-ad-restore-drill.md)LAB-11で経験したとおり、差分チェーンを深くすること自体がホストのI/Oリスクになる

「安全網としてスナップショットを取る」判断が、この場面ではむしろ危険を増やす例です。

## 段階1: ベースライン取得

dc02のコンソールで、両DCが健全であることを確認してから試験用ユーザーを作成しました。

```text
Get-ADDomainController -Filter *  → AD-DC01(192.0.2.50)、AD-DC02(192.0.2.51)、いずれもGC
repadmin /replsummary(コンソール実行) → 双方向、失敗 0/5、エラー 0
w32tm /query /status → 階層1、参照ID 0x564D5450("VMTP"、Hyper-V統合サービス経由のホスト時刻)

New-ADUser avail-test-before → SID ...-2101
```

> ⚠️ **WinRM越しの`repadmin`はダブルホップで誤った結果を返す**。当初ホストPCからWinRM経由でdc02へ接続し`repadmin`を実行したところ、`エラー 110 - ad-dc01.corp.example.test`と表示され、片方向(AD-DC01のみ)しか出ませんでした。WinRMセッションの資格情報は次のホップ(dc02→dc01のRPC接続)へ委任されないため、dc02は自分自身の複製情報しか集められません。**同じ`repadmin`を対象機のコンソールで直接実行すると、双方向・失敗0の正しい結果が得られました。** 監視・診断コマンドはWinRM越しではなく対象機のコンソールで実行するべきという教訓です。

dc02の時刻同期元が`VMTP`(Hyper-Vホスト時刻)である点は、本来PDCエミュレーター以外のDCがドメイン階層に従ってPDCから時刻を取るべき原則からの逸脱です。仮想化されたDCでよく起きる構成上の逸脱で、Kerberosの時刻許容差(既定5分)に余裕があるため今回の試験には影響しませんでしたが、実務では是正対象になります。今回の主目的ではないため、別途の課題として記録するにとどめます。

## 段階2: dc01の正常停止

```text
[ホストPC]
Get-VM ad-dc01 | Select Name, State, Uptime → Running / 07:33:36
T0 = 2026-09-03 18:09:53
Stop-VM -Name ad-dc01 -Force:$false
→ 18:10:04  State: Off  (11秒で正常終了)
```

## 段階3: dc02単独での継続性確認

dc02のコンソールで、認証・DNS・LDAP・ディレクトリ更新の一連を確認しました。

```text
Resolve-DnsName corp.example.test -Type A          → 成功
Resolve-DnsName _ldap._tcp.dc._msdcs... -Type SRV   → 成功
nltest /dsgetdc:corp.example.test                   → 成功
389(LDAP)/88(Kerberos)/3268(GC) いずれもListen中

New-ADUser avail-test-during → SID ...-2102(dc01停止中に新規作成、成功)
Get-ADUser avail-test-before → 取得成功(停止前の複製が正しく行き渡っていたことの確認)
```

dc01停止中でも、DNS・LDAP・Kerberos・グローバルカタログ・新規オブジェクト作成は**すべて継続**しました。

## 段階4: 縮退した機能の確認

### 予想が外れた点: `netdom query fsmo`は失敗しなかった

当初「FSMO保持者への問い合わせは失敗するはず」と予想しましたが、実際には成功し、dc01が持つ3役割も正しく表示されました。

```text
netdom query fsmo(dc01停止中に実行)
  スキーマ マスター          ad-dc02.corp.example.test
  ドメイン名前付けマスター    ad-dc02.corp.example.test
  PDC                        ad-dc01.corp.example.test
  RID プール マネージャー     ad-dc01.corp.example.test
  インフラストラクチャ マスター ad-dc01.corp.example.test
  コマンドは正しく完了しました。
```

理由は、このコマンドが**dc02自身の(既に複製済みの)ADデータベースから役割保持者の属性を読んでいるだけ**で、dc01に実際に接続して生存確認しているわけではないためです。同様に、`avail-test-during`の作成が成功したのも、dc02が**あらかじめ割り当て済みのRIDプール在庫**(`rIDUsedPool: 0`、在庫十分)を使えたためで、RIDマスター(dc01)への問い合わせを伴いませんでした。**メタデータの参照と、実際の機能利用は別物**という教訓です。

### 実際に縮退した機能

メタデータ参照ではなく、実際にdc01への到達が必要な操作で確認し直しました。

```text
Measure-Command { Get-GPO -All -Server 'ad-dc01.corp.example.test' -ErrorAction SilentlyContinue }
  → 27.15秒(TotalSeconds 27.1527982)
$Error[0].Exception.Message
  → RPC サーバーを利用できません。(HRESULTからの例外:0x800706BA)

Get-GPO -All -Server 'ad-dc02.corp.example.test' | Select DisplayName, Owner
  → 成功。Default Domain Policy / Default Domain Controllers Policy とも取得

dcdiag /test:ridmanager /v
  → [AD-DC01] DsBindWithSpnEx() が失敗しました。エラー 1722 が発生しました。(RPC_S_SERVER_UNAVAILABLE)
  → AD-DC02 はテスト Connectivity に合格しました
  → AD-DC02 はテスト RidManager に失敗しました
```

`0x800706BA`(`RPC_S_SERVER_UNAVAILABLE`)は、TCP到達性はあっても応答するRPCサービスがいないことを示す典型的なエラーです。27秒という値は既定のRPCタイムアウトに近く、GUIツール(GPMC、Active Directory ユーザーとコンピューターなど)でこれが起きると「操作が固まったように見える」体感になります。

### 縮退の全体像

| 機能 | dc01停止の影響 | 根拠 |
| --- | --- | --- |
| FSMO保持者の照会(メタデータ参照) | 影響なし | `netdom query fsmo`成功 |
| 認証・DNS・LDAP・GC(dc02単独) | 継続 | 段階3で全項目成功 |
| 新規オブジェクト作成 | 継続(RIDプール在庫がある間) | `rIDUsedPool: 0`、在庫十分 |
| PDCエミュレータへの明示接続(GPMC等) | **失敗** | `0x800706BA`、27秒タイムアウト |
| RIDマスターへの直接問い合わせ(`dcdiag ridmanager`) | **失敗** | エラー1722、RidManagerテスト不合格 |
| 同操作をdc02明示指定に切替 | 回避可能 | `Get-GPO -Server ad-dc02`成功 |

**認証基盤としての中核機能(DNS・LDAP・Kerberos・GC・オブジェクト作成)はdc01が落ちても止まらない**一方、**PDCエミュレータ・RIDマスター固有の操作は明確に失敗する**が、**管理ツールの接続先を明示的に切り替えれば作業は継続できる**、という実務上重要な結果です。

## 段階5: dc01の復帰と収束時間の実測

```text
[ホストPC]
Start-VM -Name ad-dc01
```

Uptimeから逆算した起動完了時刻: **18:31:07**(18:58:32時点でUptime 00:27:25.4)

```text
18:31:24  System  1014  警告  名前 _ldap._tcp.dc._msdcs.corp.example.test の名前解決は、
                              構成されたどのDNSサーバーからも応答がなく、タイムアウトしました。
18:31:25  System  1014  警告  名前 wpad の名前解決は、...タイムアウトしました。
18:32:02  repadmin      DNS参照エラー(8524)のため、DSA操作を続行できません。
18:35:58  全サービス(NTDS/DNS/Netlogon/Kdc/W32Time) Running
18:37:04  System  0x422 エラー  グループ ポリシーの処理に失敗。gpt.iniの読み取りに失敗。
18:37:49〜51  System  0x272C エラー×3  DCOMがfec0:0:0:ffff::1/2/3と通信できず(IPv6サイトローカル、未使用アドレス。無関係)
18:38:01  repadmin /replsummary → 失敗 4/5、80%、DNS参照エラー(8524)
18:41:21  Restart-Service DNS 実行後 → 失敗 3/5、60%に改善。nslookupは成功(ad-dc02解決)
18:43:49  60秒待機後も失敗 3/5 のまま横ばい(自然収束せず)
—         repadmin /syncall ad-dc01 /AdeP で複製を強制実行
18:46:32  対象3パーティション(Schema、DomainDnsZones、ForestDnsZones)の成功を確認
18:49:38  repadmin /replsummary → 失敗 0/5、エラー 0(双方向) = 完全復旧
18:53:5x  gpupdate /force /target:computer → 正常完了
18:54:09  System  1014  警告  settings-win.data.microsoft.com(外部/無関係。閉域のため未解決は正常)
18:56:29  直近イベント、DNS SRV解決失敗の再発なし
```

### 起きたこと・原因・対応

**根本原因**: dc01起動直後の短い期間、DNSサービスは`Running`と表示されるが、自身のAD統合ゾーン(`_msdcs`のSRVレコードを含む)の読み込みが完了していない窓があった。この間、dc01は複製相手(dc02)を名前解決できず、AD複製がDNS参照エラー(8524)でブロックされた。

**連鎖**: DNS未解決 → 複製失敗 → SYSVOL/DFSRも複製待ちのため、GPO(`gpt.ini`)の読み取りにも一時的に失敗。いずれも収束後(18:46:32以降)は再発していない。

**転換点**: `Restart-Service DNS`で名前解決自体は復旧した(`nslookup`成功)が、**それだけでは複製は自然収束しなかった**(3/5で12分以上横ばい)。`repadmin /syncall /AdeP`による**強制的な再同期**を実行して初めて収束が進んだ。既定の複製スケジュール(サイト内変更通知や定期ポーリング)を待つ場合、収束にさらに時間がかかっていた可能性がある。

**残留ログの扱い**: `dcdiag /q`は「SystemLogテストに失敗」と報告したが、内容を精査すると①GPO読み取り失敗(収束前の一時的事象、収束後は`gpt.ini`読み取り・`gpupdate /force`とも正常)、②DCOM/IPv6エラー(このラボはIPv4のみの設計で`fec0::`は未構成のアドレス、`dcdiag`自身の無関係な内部通信試行)のいずれも、現在の健全性を否定するものではなかった。**`dcdiag`のSystemLogテストは、AD に関係あるかどうかを問わずSystemログの警告・エラーを機械的に拾う仕様のため、必ずタイムスタンプと内容を確認してから判断する必要がある**([復元演習](2026-09-02-ad-restore-drill.md)・[2台目DC追加](2026-09-03-ad-second-dc-replication.md)LAB-19と同種の注意点)。

### 主要指標

| 指標 | 値 |
| --- | --- |
| 停止所要時間 | 11秒 |
| 起動〜サービス復旧(NTDS等Running) | 4分51秒 |
| 起動〜ディレクトリ完全収束(狭義RTO) | **18分31秒** |
| サービス復旧〜完全収束の差 | 13分40秒(「サービスは動いているがまだ複製が信用できない」区間) |

## インシデントと欠陥(LAB-23)

[2台目DC追加](2026-09-03-ad-second-dc-replication.md)のLAB-16〜22に続く番号です。

| ID | 事象 | 最初の仮説 | 実際に見たもの | 原因 | 対応 |
| --- | --- | --- | --- | --- | --- |
| LAB-23 | dc01再起動後、複製がDNS参照エラー(8524)で12分以上詰まったまま自然収束しない | DNSサービスが落ちている | `Get-Service DNS`は`Running`。`Restart-Service DNS`後は`nslookup`成功、しかし`repadmin /replsummary`は3/5失敗で横ばい | DNSサービスは起動していても自身のAD統合ゾーン読み込みが完了しておらず、起動直後の短い窓で複製相手のSRVレコードが引けなかった。DNS復旧後も、既定の複製スケジュールでは再試行が間に合わず自然収束しなかった | `repadmin /syncall ad-dc01 /AdeP`で複製を強制実行し収束(15分25秒で3パーティション成功、18分31秒で完全収束) |

## 学び

- **停止した瞬間から機能低下が始まるわけではない**。認証・DNS・LDAP・GCという中核機能は、残った1台だけで問題なく継続した
- **「役割保持者を聞く」ことと「役割を実際に使う」ことは別物**。`netdom query fsmo`はメタデータ参照のため役割保持DCが落ちていても成功する。実際の機能利用(GPMCの既定PDC接続、RIDマスターへの問い合わせ)で初めて縮退が現れる
- **縮退は回避可能な形で現れることが多い**。GPMC等は`-Server`で接続先DCを明示指定すれば作業を継続できる。管理者がこれを知っているかどうかで、体感の障害範囲が大きく変わる
- **サービスが`Running`になった時点と、ディレクトリとして信用できる時点は別**。この試験では両者に13分40秒の差があった。復旧作業の完了報告は前者だけで判断しない
- **DNSを直しても複製が自然に追いつくとは限らない**。名前解決の復旧後も、既定の複製スケジュールを待つのではなく`repadmin /syncall`で強制的に再試行させることが、実務上の復旧時間短縮につながる
- **`dcdiag`のSystemLogテストは機械的すぎる**。ADに無関係なイベント(このラボでは未使用のIPv6アドレスへのDCOM試行)や、収束前の一時的な残留ログも「失敗」として報告する。タイムスタンプと内容を必ず確認する
- **WinRM越しの診断コマンドはダブルホップで信用できないことがある**。監視・診断は対象機のコンソールで実行するのが確実

## 現在の状態と後片付け

- 試験用ユーザー(`avail-test-before`、`avail-test-during`)は削除済み
- 両DCとも`repadmin /replsummary`失敗0/5、`dcdiag /q`(残留ログ除き)健全
- dc02の時刻同期元がPDCエミュレーター(dc01)ではなくHyper-Vホスト(`VMTP`)である点は未是正。次の課題として記録
- FSMO役割の**奪取**(`-Force`によるseize)と、実際のハードウェア障害(電源断)を模した試験は`NOT RUN`
