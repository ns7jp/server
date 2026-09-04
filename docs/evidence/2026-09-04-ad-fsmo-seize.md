# FSMO役割の奪取(seize)とdc01の完全喪失想定復旧 — 2026-09-04

[DC 1台停止時の可用性試験](2026-09-03-ad-dc-outage-drill.md)で`NOT RUN`としていた最後の項目です。前回は`ad-dc01`を計画停止して復帰させましたが、今回は**復帰させず**、「dc01が復旧不能になった」という想定に切り替え、`ad-dc02`からドメインレベル3役割(PDCエミュレーター、RIDプールマネージャー、インフラストラクチャマスター)を強制的に奪取(seize)し、ADのメタデータから`ad-dc01`を完全に除去、最終的にVM自体も削除しました。

> **この証跡が示す範囲**: 手元Hyper-V上のVM 2台による、正常停止(電源断やハードウェア故障の模擬ではない)からの奪取・メタデータクリーンアップです。実際の電源断・ディスク破損からの復旧、複数DCが同時に失われるケースは含みません。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS** |
| 奪取方法 | `Move-ADDirectoryServerOperationMasterRole -Identity ad-dc02 -OperationMasterRole PDCEmulator,RIDMaster,InfrastructureMaster -Force` |
| 奪取結果 | 5役割すべてが`ad-dc02`に集約(フォレストレベル2役割は[2026-09-03の移譲](2026-09-03-ad-second-dc-replication.md)で既にdc02側) |
| メタデータクリーンアップ | `ntdsutil`(`metadata cleanup`)で`ad-dc01`のサーバーオブジェクトを削除 |
| 削除後の単一DC健全性 | DNS・LDAP・Kerberos・全サービス正常、`nltest`のフラグに全役割が反映 |
| dc01のVM | `Remove-VM`で定義を削除(VHDXファイルは証跡確定まで保持) |

## 事前準備の方針

この試験は不可逆です。奪取した役割を持つdc01を後で復帰させると役割が二重になり、フォレストが壊れます。実施前に、奪取後のdc01の扱いを3択で検討しました。

1. **dc01を完全に削除**(VMごと破棄)
2. メタデータクリーンアップの上でドメインから除外し、VM自体は証跡用に残す
3. dc01を切断したまま保持する

実務で最も一般的な**1(完全削除)**を選択しました。壊れた(あるいは壊れたと想定した)DCは作り直すのが原則であり、奪取後のDCを「いつか使うかもしれない」状態で残すこと自体が、将来の役割二重化事故の温床になるためです。

## 段階1: dc01の停止(復旧不能を模擬)

チェックポイントは取得していません。[可用性試験](2026-09-03-ad-dc-outage-drill.md)と同じ理由で、2台のうち片方だけを過去のスナップショットに戻す操作自体がリスクだからです。

```text
[ホストPC]
Get-VM ad-dc01 | Select Name, State, Uptime → Off, Uptime 00:00:00

Stop-VM -Name ad-dc01 -Force:$false(既に停止済みであることを確認)
Disconnect-VMNetworkAdapter -VMName ad-dc01
Get-VMNetworkAdapter -VMName ad-dc01 → SwitchName 空(未接続)
```

dc01が`Off`かつネットワーク未接続であることを確認してから次に進みました。これにより、誤って電源を入れてしまってもドメインへ影響しないことを担保しています。

## 段階2: dc02からの役割奪取

**dc02のコンソール**で実施しました(生きている側から操作する、という点が通常のtransferと変わりません)。

```text
[奪取前]
netdom query fsmo
  スキーマ マスター              ad-dc02.corp.example.test
  ドメイン名前付けマスター        ad-dc02.corp.example.test
  PDC                            ad-dc01.corp.example.test
  RID プール マネージャー         ad-dc01.corp.example.test
  インフラストラクチャ マスター    ad-dc01.corp.example.test

Move-ADDirectoryServerOperationMasterRole -Identity "ad-dc02" `
    -OperationMasterRole PDCEmulator, RIDMaster, InfrastructureMaster -Force -Confirm:$false

[奪取後]
netdom query fsmo
  スキーマ マスター              ad-dc02.corp.example.test
  ドメイン名前付けマスター        ad-dc02.corp.example.test
  PDC                            ad-dc02.corp.example.test
  RID プール マネージャー         ad-dc02.corp.example.test
  インフラストラクチャ マスター    ad-dc02.corp.example.test

Get-ADDomainController -Filter * | Select Name, OperationMasterRoles
  AD-DC01  {}
  AD-DC02  {SchemaMaster, DomainNamingMaster, PDCEmulator, RIDMaster...}
```

dc01が到達不能(停止・切断済み)の状態で`-Force`を実行したため、これは正しい**seize**として成立しています。コマンド自体は即座に完了しました。

## 段階3: メタデータクリーンアップ

`ntdsutil`は生きているDC(dc02)から実行する対話型ツールです。**PowerShellのプロンプトに直接サブコマンドを入力するとコマンドとして認識されずエラーになる**ため、`ntdsutil`を起動してプロンプトが切り替わったことを確認しながら、1行ずつ入力しました。

```text
ntdsutil
metadata cleanup
connections
  connect to server ad-dc02
  → ad-dc02 に結合しています... ローカルでログオンしているユーザーの資格情報を使って ad-dc02 に接続しました
quit
select operation target
  list domains → 0 - DC=corp,DC=example,DC=test
  select domain 0
  list sites → 0 - CN=Default-First-Site-Name,...
  select site 0
  list servers in site
    0 - CN=AD-DC01,CN=Servers,...
    1 - CN=AD-DC02,CN=Servers,...
  select server 0
    → サーバー - CN=AD-DC01,... (選択内容を確認してから続行)
quit
remove selected server
  → 選択されたサーバーから FSMO 役割を転送/強制処理しています。
  → 選択されたサーバーのために FRS メタデータを削除しています。
     "...AD-DC01,OU=Domain Controllers,..." 下で FRS メンバーを検索しています。
     "...AD-DC01,OU=Domain Controllers,..." 下のサブツリーを削除しています。
     "...AD-DC01,CN=Servers,..." 上の FRS 設定の削除に失敗しました。原因は次のとおりです: "要素が見つかりません。"
     メタデータのクリーンアップは続行されます。
  → "...AD-DC01,CN=Servers,..." をサーバー "ad-dc02" から削除しました
quit
quit
```

`list servers in site`で表示された番号(`0`=AD-DC01、`1`=AD-DC02)を確認してから`select server 0`を実行し、選択内容が確かにAD-DC01であることを画面で確認してから`remove selected server`(最も破壊的な操作)に進みました。生きているdc02を誤って選択・削除する事故を避けるための確認手順です。

### FRS関連の失敗メッセージについて

`FRS 設定の削除に失敗しました。原因は次のとおりです: "要素が見つかりません。"`という行が出ましたが、**これはエラーではなく想定どおりの挙動です**。`ntdsutil`のメタデータクリーンアップは、互換性のため常にレガシーな`FRS`(File Replication Service)関連オブジェクトの削除を試みますが、このドメインはフォレスト作成時から一貫して**DFSR**(DFS Replication)でSYSVOLを複製しています。FRSのメンバーオブジェクトはそもそも存在しないため「要素が見つかりません」となり、処理はスキップされて続行されました。DFSRベースのドメインで`ntdsutil`メタデータクリーンアップを行う際に定型的に出るメッセージです。

`ntdsutil`自身も「選択されたサーバーから FSMO 役割を転送/強制処理しています」と表示していましたが、5役割は段階2で既に奪取済みだったため、これは`ntdsutil`側の安全策としての再確認であり、実質的な変更は発生していません。

## 段階4: 削除直後の残響と収束確認

`remove selected server`直後、`dcdiag /q`が2件の失敗を報告しました。

```text
AD-DC02 はテスト DFSREvent に失敗しました
  エラー イベント ID: 0xC0000583
  生成日時: 09/04/2026 10:58:07
  イベント文字列: Active Directory ドメイン サービスは、次のディレクトリ サービスの相互認証の
                サービス プリンシパル名(SPN)を構築できませんでした。
AD-DC02 はテスト KccEvent に失敗しました
```

これは[可用性試験](2026-09-03-ad-dc-outage-drill.md)LAB-23、[2台目DC追加](2026-09-03-ad-second-dc-replication.md)LAB-19と同型の、**直近24時間の残留ログをdcdiagが機械的に拾うパターン**でした。KCC(複製トポロジ管理)が、たった今削除されたAD-DC01への接続情報をまだ解消しきっていない一瞬の残響と考えられます。断定せず、実際に再発しているかを確認しました。

```text
90秒待機後(現在時刻 11:05:59):
  dcdiag /q → 同じ 10:58:07 の1件のみ。新規発生なし
  Get-WinEvent 'Directory Service' -MaxEvents 10 | Where TimeCreated -gt (現在-5分)
    → 0件(直近5分以内の新規イベントなし)
```

新規のエラーが発生していないことを確認し、一過性の残響であったと判断しました。

## 段階5: 単一DC健全性の最終確認

```text
repadmin /replsummary → ソース DSA・宛先 DSA とも空(複製相手が存在しない、単一DCとして正しい状態)

Resolve-DnsName corp.example.test -Type A → 192.0.2.51(正常解決)

nltest /dsgetdc:corp.example.test
  DC: \\ad-dc02.corp.example.test / アドレス: \\192.0.2.51
  フラグ: PDC GC DS LDAP KDC TIMESERV WRITABLE DNS_DC DNS_DOMAIN DNS_FOREST
          CLOSE_SITE FULL_SECRET WS DS_8 DS_9 DS_10 KEYLIST

Test-NetConnection localhost -Port 389 → TcpTestSucceeded: True

Get-Service NTDS, DNS, Netlogon, Kdc, W32Time → すべて Running

Get-DnsServerResourceRecord -ZoneName corp.example.test |
  Where HostName -match 'ad-dc01' -or RecordData -match '192.0.2.50'
  → 該当なし(dc01由来のDNSレコードは残っていない)
```

`nltest`の`フラグ`に`PDC`・`DNS_DC`・`DNS_DOMAIN`・`DNS_FOREST`を含む全役割が反映されており、`ad-dc02`単独でDC・GC・DNS・KDCの全機能を担えていることを確認しました。

## 段階6: dc01 VMの削除

```text
[ホストPC]
Get-VMHardDiskDrive -VMName ad-dc01 | Select Path
  C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\ad-dc01.vhdx
  C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\ad-dc01-backup.vhdx

Remove-VM -Name ad-dc01 -Confirm:$false
Get-VM ad-dc01 -ErrorAction SilentlyContinue → 無出力(VM定義の削除完了)
```

VM定義は削除しましたが、VHDXファイル自体は`Remove-VM`だけでは消えません。証跡確定後に別途削除する運用としました。

## 学び

- **transferとseizeの操作コマンドは同じ**。`Move-ADDirectoryServerOperationMasterRole`に`-Force`を付けるかどうかだけの違いで、実行者はどちらが起きたかを意識して使い分ける必要がある。今回は移譲元が既に停止・切断されていたため、正しくseizeとして成立した
- **`ntdsutil`は対話型シェルであり、サブコマンドをPowerShellへ直接貼り付けても動かない**。起動してプロンプトの変化を確認しながら1行ずつ進める必要がある。複数行の一括貼り付けは処理が追いつかず一部が無視されることがある
- **`remove selected server`は最も破壊的な操作**。直前の`select server <番号>`の出力で対象が本当に削除したいDCかを必ず確認してから進める。番号を誤ると生きているDCを削除しかねない
- **FRS関連の失敗メッセージは、DFSRベースのドメインでは正常**。「要素が見つかりません」は「そもそもFRSを使っていない」ことの裏返しであり、エラーとして扱わない
- **メタデータクリーンアップ直後のdcdiag失敗は、KCCの残響であることが多い**。新規発生の有無を数分待って確認してから判断する。このラボで4回目([09-02復元](2026-09-02-ad-restore-drill.md)、[09-03 LAB-19](2026-09-03-ad-second-dc-replication.md)、[09-03 LAB-23](2026-09-03-ad-dc-outage-drill.md)、今回)遭遇した同型パターンであり、dcdiagの当該テストは「直近24時間の警告・エラーの有無」だけを機械的に見る仕様であることの一貫した実証になった
- **奪取後の元DCは、絶対に元の構成のまま復帰させてはいけない**。役割の二重保持を防ぐため、完全削除・メタデータクリーンアップ・ネットワーク切断保持のいずれかで確実に無力化する

## 現在の状態

- `ad-dc02`単独のフォレスト構成。5役割すべて保持、DC・GC・DNS・KDCとして正常稼働
- `ad-dc01`のVM定義は削除済み。VHDXファイル2本はディスク上に残置(証跡確定後に削除予定)
- これにより[基本設計書](../build-package-ad/01-basic-design.md)3.4節で`NOT RUN`としていたFSMO奪取試験は完了。同節に記載していた発展課題(2台目DC追加・可用性試験・FSMO奪取)はすべて実施済みとなった
