# 2台目DC追加とレプリケーション実測 — 2026-09-03

[基本設計書](../build-package-ad/01-basic-design.md)3.4節の発展構成「2台目のDC追加とレプリケーション実測」を、[phase1-hardened](2026-09-02-work-result-SM-AD-001.md)の`ad-dc01`に対して実施した記録です。同じ演習で、前日の[System State復元演習](2026-09-02-ad-restore-drill.md)が`ad-dc01`のSYSVOLに残していた欠損を発見・修復しました。

> **この証跡が示す範囲**: 同一Hyper-Vホスト・同一内部スイッチ上のVM 2台による、同一サイト内レプリケーションとFSMO移譲です。サイト間レプリケーション、WAN越しの遅延、RODC、役割の**奪取**(seize。移譲元が復旧不能な場合の最終手段)は含みません。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| 判定 | **PASS** |
| 追加DC | `ad-dc02` / `192.0.2.51/24` / Windows Server 2022 Standard 評価版 / Gen2 VM(2 vCPU, 4GB, 40GB) |
| NTDS複製 | `repadmin /replsummary`: 5パーティション、**失敗 0 / 5、エラー 0** |
| SYSVOL複製 | DFSR初期同期成功(イベント`4614`→`4604`)、`DfsrReplicatedFolderInfo State: 4`(Normal) |
| グローバルカタログ | dc01・dc02 とも GC |
| 複製トポロジ | KCCが双方向の接続オブジェクト2件を自動生成 |
| **レプリケーション遅延** | **17.8秒**(dc01で11:46:32.686作成 → dc02で11:46:50.510検出) |
| FSMO移譲 | **実施済み**。フォレストレベル2役割(スキーマ、ドメイン名前付け)を`ad-dc02`へ移譲、所要**0.238秒**。ドメインレベル3役割は`ad-dc01`に残置 |

レプリケーション遅延17.8秒は、サイト内複製の既定である**変更通知の待ち時間15秒**と整合します(15秒 + 転送 + 0.3秒間隔ポーリングの誤差)。

## 構成

| 項目 | ad-dc01(既存) | ad-dc02(新規) |
| --- | --- | --- |
| IP | `192.0.2.50/24` | `192.0.2.51/24` |
| 仮想スイッチ | `ADLab-Internal`(内部) | 同左 |
| ディスク | C: 30GB + D: 20GB(Backup) | C: 40GB(単一) |
| メモリ / vCPU | 4GB / 2 | 4GB / 2 |
| DNS参照先 | `127.0.0.1` | 昇格前: `192.0.2.50` / 昇格後: 自身+dc01 |
| サイト | `Default-First-Site-Name` | 同左 |
| FSMO(移譲後) | PDCエミュレーター、RIDプールマネージャー、インフラストラクチャマスター | スキーママスター、ドメイン名前付けマスター |
| GC | あり | あり |

## 実施手順と実出力

### 1. VM作成・OSインストール

ホストPCで`New-VM -Generation 2`、40GB VHDX、`ADLab-Internal`接続、キャッシュ済みISO(`C:\ISO`)をDVDに接続してブート順1番へ。

### 2. ネットワーク設定とドメイン参加

```text
Get-NetIPAddress: イーサネット 192.0.2.51/24 Preferred
Get-DnsClientServerAddress: イーサネット {192.0.2.50}
Get-TimeZone: Tokyo Standard Time

Test-NetConnection 192.0.2.50 -Port 389 → TcpTestSucceeded: True / PingSucceeded: False
nltest /dsgetdc:corp.example.test →
  DC: \\ad-dc01.corp.example.test / アドレス: \\192.0.2.50
  フラグ: PDC GC DS LDAP KDC TIMESERV WRITABLE DNS_DC DNS_DOMAIN DNS_FOREST CLOSE_SITE FULL_SECRET

Add-Computer -DomainName corp.example.test -NewName "ad-dc02" -Credential <CORP\管理者> -Restart -Force
→ Get-ComputerInfo: CsName=AD-DC02 / CsDomain=corp.example.test / CsDomainRole=MemberServer
```

### 3. 追加DCへの昇格

```powershell
Install-ADDSDomainController -DomainName "corp.example.test" -Credential $Cred `
  -SafeModeAdministratorPassword $SafeModePwd -InstallDns:$true `
  -SiteName "Default-First-Site-Name" -NoGlobalCatalog:$false -Force
```

1回目は前提条件の検証で停止(下記LAB-18)。DSRMパスワードを14文字以上にして再実行し成功。

### 4. NTDS複製の確認

```text
repadmin /replsummary (11:23:54)
  ソース DSA   最大デルタ  失敗/合計  エラー
  AD-DC01      07m:58s     0 / 5      0
  宛先 DSA     最大デルタ  失敗/合計  エラー
  AD-DC02      07m:58s     0 / 5      0

Get-ADReplicationConnection: 接続オブジェクト2件(AD-DC01→AD-DC02、AD-DC02→AD-DC01、いずれもKCC自動生成)
```

### 5. レプリケーション遅延の実測

dc02側で`-Server localhost`を指定してポーリングし、dc01で作成したOUが自分自身のディレクトリに現れるまでを測定しました(`-Server`を省略するとdc01へ問い合わせてしまい、複製を測ったことになりません)。

```text
created on dc01 at:  11:46:32.686   (New-ADOrganizationalUnit "ReplTest2-114632")
detected on dc02 at: 11:46:50.510   (Get-ADOrganizationalUnit -Server localhost)
差分: 17.8秒
```

1回目の計測(`ReplTest-114239`)は、ポーリング開始から作成までの待機時間を含んでしまい65.5秒と出ました。作成時刻を基準にし直した2回目が上記の値です。**測定の起点を「相手が変更した瞬間」に合わせないと、複製時間ではなく自分の待ち時間を測ることになります。**

### 6. FSMO役割の移譲

5つのFSMO役割のうち、**フォレスト全体に関わる2つ**(スキーマ マスター、ドメイン名前付けマスター)を`ad-dc02`へ移譲し、**ドメイン内で頻繁に使われる3つ**(PDCエミュレーター、RIDプールマネージャー、インフラストラクチャマスター)は`ad-dc01`に残しました。フォレストレベルとドメインレベルで分けるのは、片方のDCが失われても残る役割が偏らないようにするためです。

```powershell
Move-ADDirectoryServerOperationMasterRole -Identity "ad-dc02" `
    -OperationMasterRole SchemaMaster, DomainNamingMaster -Confirm:$false
```

```text
=== 移譲前 (netdom query fsmo) ===
スキーマ マスター              ad-dc01.corp.example.test
ドメイン名前付けマスター        ad-dc01.corp.example.test
PDC                            ad-dc01.corp.example.test
RID プール マネージャー         ad-dc01.corp.example.test
インフラストラクチャ マスター    ad-dc01.corp.example.test

elapsed: 00:00:00.2376642

=== 移譲後 ===
スキーマ マスター              ad-dc02.corp.example.test
ドメイン名前付けマスター        ad-dc02.corp.example.test
PDC                            ad-dc01.corp.example.test
RID プール マネージャー         ad-dc01.corp.example.test
インフラストラクチャ マスター    ad-dc01.corp.example.test

Get-ADDomainController:
  AD-DC01  {PDCEmulator, RIDMaster, InfrastructureMaster}
  AD-DC02  {SchemaMaster, DomainNamingMaster}
```

移譲後、両DCが同じ認識を持っていることを問い合わせ先を変えて確認しました。

```text
Get-ADForest -Server ad-dc02  → SchemaMaster / DomainNamingMaster = ad-dc02.corp.example.test
Get-ADDomain -Server ad-dc02  → PDCEmulator / RIDMaster / InfrastructureMaster = ad-dc01.corp.example.test

repadmin /replsummary (13:16:13)
  ソース DSA   最大デルタ  失敗/合計  エラー
  AD-DC01      22m:34s     0 / 5      0
  AD-DC02      22m:13s     0 / 5      0
  宛先 DSA     最大デルタ  失敗/合計  エラー
  AD-DC01      22m:13s     0 / 5      0
  AD-DC02      22m:34s     0 / 5      0

dcdiag /test:knowsofroleholders /q → 無出力(合格)
```

移譲前の`repadmin`はソース・宛先とも`AD-DC01`/`AD-DC02`が1行ずつでしたが、移譲後は**両方が双方向に並んでいます**。dc02が変更を発信する側にもなり、双方向の複製が成立したことを示します。

`Move-ADDirectoryServerOperationMasterRole`は既定で**移譲(transfer)**、つまり両DCが稼働している状態での正常な引き継ぎです。`-Force`を付けると**奪取(seize)**になり、移譲元が復旧不能なときの最終手段になります。奪取した役割を元のDCが持ったまま復帰すると役割が二重になるため、本演習では使用していません。

## インシデントと欠陥(LAB-16〜19)

[復元演習](2026-09-02-ad-restore-drill.md)のLAB-11〜15に続く番号です。

| ID | 事象 | 最初の仮説 | 実際に見たもの | 原因 | 対応 |
| --- | --- | --- | --- | --- | --- |
| LAB-16 | 新規VMを起動したが`CPUUsage: 0`のまま2分経過、`Heartbeat: NoContact` | VMのハング / ISOの指定ミス | `BootOrder`はDVD→ネットワーク→HDDで正しい。`State: Running`だがCPUを使っていない | Gen2 VMの「Press any key to boot from CD or DVD」を数秒で逃し、次のブートデバイス(PXE)へ進んで停止していた | コンソールを**先に開いてから**`Restart-VM`し、プロンプト表示中にキーを連打 |
| LAB-17 | dc02からdc01へ`Test-NetConnection`が`DestinationHostUnreachable` | IP設定ミス / 仮想スイッチの不一致 | 両VMとも`ADLab-Internal`・`{Ok}`、dc02のIPは`Preferred`、`arp -a`にdc01のMACが**動的**で存在。dc01の`Uptime`が4分33秒 | dc01がまだ起動途中だった。ネットワーク設定の問題ではない | dc01の起動完了後に再実行し成功 |
| LAB-18 | `Install-ADDSDomainController`が前提条件の検証で失敗 | パラメータ誤り | 「ディレクトリ サービス復元モードのパスワードが短すぎます。パスワード ポリシーで設定されている長さの条件に合いません」 | **DSRMパスワードにもドメインのパスワードポリシー(AIT-04で設定した最小長14文字)が適用される** | 14文字以上で再実行。検証段階で停止したためADへの変更はなし |
| LAB-19 | 昇格後、dc02に`NETLOGON`共有が作られず`dcdiag`の`NetLogons`/`DFSREvent`が失敗 | DFSR初期同期の未完了 | DFSRは`4604`(初期複製完了)・`State: 4`(Normal)で正常。しかし**dc01の`C:\Windows\SYSVOL\domain`に`scripts`フォルダーが存在しない**(`DfsrPrivate`と`Policies`のみ)。dc01では`NETLOGON`共有だけが残っていた | 前日のSystem State非権威復元でdc01のSYSVOLから`scripts`が失われていた。単一DCでは既存の共有定義が残るため症状が出ず、**2台目を追加して初めて顕在化**した | dc01で`New-Item C:\Windows\SYSVOL\domain\scripts`を作成 → DFSRがdc02へ複製 → dc02で`Restart-Service Netlogon` → `NETLOGON`共有が作成され`dcdiag /test:netlogons /test:advertising /q`が無出力(合格) |

LAB-19は、[復元演習の証跡](2026-09-02-ad-restore-drill.md)で`dcdiag`の`DFSREvent`失敗を「DSRM起動時のNTDS依存サービス起動失敗が System ログに残っているだけ」と判断した点が不十分だったことを示します。当該証跡の判断はこの発見をもって訂正します。**復元後は`dcdiag`の合否だけでなく、SYSVOL配下に`Policies`と`scripts`が揃っているかをファイルシステムで確認すべき**でした。

## 学び

- **単一構成では隠れる不具合がある**。dc01は共有定義が残っていたため、SYSVOLの実体が欠けていても1台では動き続けた。冗長化して初めて「複製元に無いものは複製されない」形で露呈した
- **DSRMパスワードもドメインのパスワードポリシーに従う**。自分で厳しくした設定が、後の作業で自分に返ってくる
- **複製時間の測定は起点の取り方で意味が変わる**。待機時間込みの65.5秒と、実際の伝播17.8秒は別物
- **NTDSとSYSVOLは別々の仕組みで複製される**。`repadmin`が健全でもSYSVOLが壊れていることがあり、両方見る必要がある
- **Gen2 VMのDVDブートは数秒しか待たない**。コンソールを開いてから起動するのが確実

## 現在の状態と後片付け

- テスト用OU(`ReplTest-*`、`ReplTest2-*`)は削除済み
- Hyper-Vチェックポイント: `ad-dc01`に`phase1-hardened`と`before-dc02-promotion`の2世代、`ad-dc02`に`自動チェックポイント`と`before-promotion`の2世代。[LAB-11](2026-09-02-ad-restore-drill.md)の教訓に従い、次の大きな書き込み作業の前に1世代へ統合する
- `ad-dc02`は昇格直後の状態で、フェーズ1相当の設定(WinRM HTTPSリスナー、Firewallスコープ、windows_exporter、System Stateバックアップ)は`NOT RUN`
- FSMO役割の**奪取**(`-Force`によるseize)と、DCを1台停止した状態での可用性試験は`NOT RUN`
