# 2台目DC追加とレプリケーション実測 — 2026-09-03

[基本設計書](../build-package-ad/01-basic-design.md)3.4節の発展構成「2台目のDC追加とレプリケーション実測」を、[phase1-hardened](2026-09-02-work-result-SM-AD-001.md)の`ad-dc01`に対して実施した記録です。同じ演習で、前日の[System State復元演習](2026-09-02-ad-restore-drill.md)が`ad-dc01`のSYSVOLに残していた欠損を**2件**発見・修復し、さらに[LAB-12](2026-09-02-ad-restore-drill.md)の「セキュリティ設定はGPOで管理する」という是正が新規DCに対して実際に機能することを検証しました。

> **2台目を建てる価値**: この演習で見つかった欠陥3件(SYSVOLの`scripts`欠損、Default Domain Policyの`gpt.ini`欠損、2設定がGPO化されていなかったこと)は、**すべて単一DC構成では無症状**でした。冗長化は可用性のためだけでなく、「設定が正しく配信されているか」を検証する手段でもあります。

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
| dc02の要塞化 | **フェーズ1相当の設定を完了**。WinRM HTTPS・Firewall 3プロファイルBlock・AD関連5ルールグループのスコープ限定・RDP無効・SMBv1無効・windows_exporter(0.31.8)・System Stateバックアップ(日次03:30登録+単発27分4秒) |
| **GPOによる設定継承** | **検証成功**。LDAP署名必須・チャネルバインディング・DSアクセス監査の3設定が、dc02側で一切のレジストリ編集なしにGPO経由で適用された。ただしそこに至る過程で、Default Domain Policyの`gpt.ini`が両DCで欠損しdc02にGPOが1件も届いていなかったこと(LAB-20)を発見・修復 |
| バックアップの実動確認 | 日次03:30のスケジュール実行が**実際に動作していた**ことをdc01で確認(`LastTaskResult: 0`)。ただし実行時刻は起動後のキャッチアップで10:44、所要時間は他の負荷と競合し24分17秒→**63分48秒**に伸びた(LAB-22) |

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

### 7. dc02のフェーズ1相当設定

昇格直後の`ad-dc02`に、dc01と同じ[構築手順書](../build-package-ad/05-build-procedure.md)の要塞化を適用しました。

| 項目 | 手順書の該当節 | 結果 |
| --- | --- | --- |
| WinRM HTTPSリスナー(自己署名証明書)・Basic認証無効・HTTP無効 | 6.1 | 完了。ホストPCから`New-PSSession -UseSSL`で接続成立 |
| Windows Firewall 3プロファイル既定Block(`ActiveStore`で確認) | 7.2 | 完了 |
| AD関連5ルールグループの`RemoteAddress`スコープ限定 | 7.2 | 完了 |
| RDP無効 | 7.3 | 完了(`fDenyTSConnections: 1`、3389リッスンなし) |
| SMBv1無効 | 7.3 | 完了(`Get-WindowsOptionalFeature`: Disabled) |
| LDAP署名必須・チャネルバインディング・DSアクセス監査 | 7.1 / 7.3 | **GPO経由で自動適用**(下記8節) |
| windows_exporter(ad/dns collector) | 8 | 完了。dc01と同一バージョン・同一手順 |
| System Stateバックアップ | 9.1 | 完了。日次03:30を登録し、単発実行**27分4秒**で成功 |

windows_exporterはdc02がインターネットに出られないため、ホストPCで再取得してSHA256を照合し、`Copy-Item -ToSession`で転送してから導入しました(dc01と同じ運用)。転送後にゲスト側でもハッシュを再計算し、転送中の破損がないことを確認しています。

```text
Get-Service windows_exporter        → Running / Automatic
Win32_Service.StartName             → LocalSystem
Get-Package Version                 → 0.31.8   (dc01と同一。公式sha256sums.txtと一致)
9182/tcp Listen                     → 1件
windows_ad_* / windows_dns_* の行数 → 167
```

実行アカウントが`LocalSystem`である点はdc01と同じで、最小権限化はAST-07相当の継続課題として据え置きです。中央Prometheusからのscrape(AIT-09)はフェーズ2まで`BLOCKED`のため、確認はローカルからの`/metrics`取得までです。

バックアップ格納先の`D:`(20GB)は、OSインストール後にVHDXを追加して割り当てました。その際にDVDドライブが`D:`を占有していた件はLAB-21に記録しています。

System Stateバックアップはdc01と同じ設定・同じ手順で登録し、単発実行まで確認しました。

```text
wbadmin enable backup -addtarget:D: -schedule:03:30 -systemstate -quiet
  ベア メタル回復: 含まない / システム状態のバックアップ: 含む
  バックアップのボリューム: (C:)(選択されたファイル), (EFIシステムパーティション)(選択されたファイル)
  詳細設定: VSS バックアップ オプション(コピー)
  バックアップを格納する場所: D: / バックアップを実行する時刻: 03:30
  → 「スケジュールしたバックアップが有効になりました」

Get-ScheduledTaskInfo → NextRunTime: 2026/09/04 3:30:30   (dc01と同一)

Measure-Command { wbadmin start systemstatebackup -backuptarget:D: -quiet }
  → 27分04秒444 (TotalMinutes 27.074)

wbadmin get versions
  バックアップ時間: 2026/09/03 15:58
  バックアップ対象: 固定ディスク ラベル付き D:
  バージョン識別子: 09/03/2026-06:58        (UTC表記。JST 15:58)
  回復可能: ボリューム、ファイル、アプリケーション、システム状態
```

所要時間はdc01の単独実行(24分17秒)と同水準です。dc01で63分48秒かかった回(9節)との差は、並行していた他の負荷の有無で説明できます。今回はバックアップ中にホスト側で重い操作を行わず、VMコンソールで実行しました(WinRM越しの実行はLAB-15で切断を経験しているため使いません)。

`Measure-Command`はスクリプトブロックの標準出力を破棄するため、実行中はコンソールに進捗が一切表示されません。停止したように見えますが正常です。進捗を見る場合は、別途ホストPCから`Microsoft-Windows-Backup`ログのイベント`1`(開始)・`4`(成功)と`D:`の空き容量を読み取ります(短い読み取りのみのためWinRM越しで問題ありません)。

### 8. GPOによる設定継承の検証

**この節がこの演習で最も価値のある部分です。** [復元演習](2026-09-02-ad-restore-drill.md)のLAB-12で「セキュリティ設定はレジストリ直編集ではなくGPOで管理すべき」と結論づけましたが、その正しさは1台のDCでは検証できません。**新しく追加したDCに、何も手作業せずに設定が届くか**が本当の答え合わせです。

#### 検証の結果

| 設定 | dc01 | dc02 | 適用経路 |
| --- | --- | --- | --- |
| `LDAPServerIntegrity`(LDAP署名必須) | 2 | **2** | GPO(Default Domain Controllers Policy) |
| `LdapEnforceChannelBinding`(チャネルバインディング) | 2 | **2** | 同上 |
| ディレクトリ サービスの変更 監査 | 成功および失敗 | **成功および失敗** | 同上(高度な監査ポリシーの構成) |
| GPグループポリシー適用イベント | 8004(成功) | **8004(成功)** | — |

dc02では**一度もレジストリを直接編集していません**。dc01側でGPOに設定を入れただけで、複製を経て届きました。

ただし、ここに至るまでに2つの前提を潰す必要がありました。

#### 前提1: そもそもdc02にGPOが1件も適用されていなかった(LAB-20)

最初の確認で、dc02は`LDAPServerIntegrity: 1`(署名なし)、チャネルバインディング未設定、監査なしでした。切り分けの順序は次のとおりです。

```text
(1) dc02は正しいOUにあるか
    Get-ADComputer ad-dc02 → DistinguishedName: CN=AD-DC02,OU=Domain Controllers,DC=corp,...  → 正常
(2) GPOは適用されているか
    gpresult /r → 適用されたGPOの一覧が空
    secedit /export /cfg → LDAPServerIntegrity の行なし
(3) GPO側に設定は入っているか(配信元の確認)
    Get-GPOReport -Xml → Select-String で見つからず
    → しかしSYSVOL上の実体を直接読むと存在した:
      MACHINE\Microsoft\Windows NT\SecEdit\GptTmpl.inf
      → MACHINE\System\CurrentControlSet\Services\NTDS\Parameters\LDAPServerIntegrity=4,2
```

(3)で一度「GPOに設定が入っていない」と誤判定しました。`Get-GPOReport`のXMLに対する検索が空だったためですが、**XMLレポートは設定の表示名で記述されるため、レジストリキー名で検索しても一致しません**。SYSVOL上の`GptTmpl.inf`を直接読んで初めて`=4,2`(4=DWORD、2=必須)の存在を確認できました。配信元は正常で、受信側の問題だと確定します。

決定的な証拠はdc02のイベントログにありました。

```text
Get-WinEvent -LogName 'Microsoft-Windows-GroupPolicy/Operational'
  ID 7257 エラー: グループ ポリシー オブジェクトのダウンロードに失敗
    GPO: {31B2F340-016D-11D2-945F-00C04FB984F9}  (Default Domain Policy)
```

**1つのGPOのダウンロードに失敗すると、その回のポリシー適用サイクル全体が中断します。** Default Domain Policyが読めないため、Default Domain Controllers Policyにも到達していませんでした。

原因は`gpt.ini`の欠損です。両DCで確認しました。

```text
dc01: C:\Windows\SYSVOL\domain\Policies\{31B2F340-...}\
        → MACHINE, USER のみ。GPT.INI と GptTmpl.inf が存在しない
dc02: 同上(dc01から複製されたため同じ状態)

{6AC1786C-...} (Default Domain Controllers Policy) は両DCとも GPT.INI・GptTmpl.inf とも完存
```

`gpt.ini`はGPOのバージョン番号だけを持つ小さなファイルですが、**クライアントはこれを読めないとGPO本体を取得できません**。ADオブジェクト側のバージョン(`DS: 4`)は残っており、SYSVOL側だけが欠けている食い違いの状態でした。

これも[09-02の復元演習](2026-09-02-ad-restore-drill.md)の巻き添えです。LAB-19の`scripts`フォルダー欠損とまったく同じ構図で、**単一DCでは既に適用済みのローカルポリシーが残るため無症状**、2台目を追加して初めて露見しました。

パスワードポリシー(最小長14文字など)は`Get-ADDefaultDomainPasswordPolicy`で確認したところ設定値が生きていました。これはドメインオブジェクトの属性として保持されるため、SYSVOL側のファイル欠損とは独立しています。「効いているように見えたので気づけなかった」理由でもあります。

修復はdc01での`gpt.ini`再作成です。ADオブジェクト側のバージョン(`4`)に合わせました。

```powershell
$gpoPath = 'C:\Windows\SYSVOL\domain\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}'
$iniPath = Join-Path $gpoPath 'gpt.ini'
if (Test-Path $iniPath) { "already exists - aborting"; return }
"[General]`r`nVersion=4" | Out-File -FilePath $iniPath -Encoding ASCII -NoNewline
Add-Content -Path $iniPath -Value "" -Encoding ASCII
```

```text
再作成後: gpt.ini 22バイト
Get-GPO "Default Domain Policy" → DS: 4 / Sysvol: 4  (一致)
DFSRでdc02へ複製 → dc02で gpupdate /force
→ イベント 7257 が消え、8004(ポリシー適用成功)に変わる
→ Ldapserverintegrity: 2 が継承された
```

#### 前提2: 残る2設定はそもそもGPO化されていなかった

`LdapEnforceChannelBinding`とDSアクセス監査は、dc01では[LAB-12](2026-09-02-ad-restore-drill.md)の是正対象に含めておらず、レジストリ直編集と`auditpol`直実行のままでした。dc01では効いていましたが、**dc02には何も届きません**。GPMCで両方をDefault Domain Controllers Policyへ移しました。

| 設定 | GPMCでの位置 |
| --- | --- |
| ドメイン コントローラー: LDAP サーバー チャネル バインディング トークンの要件 = 常に | コンピューターの構成 → ポリシー → Windows の設定 → セキュリティの設定 → **ローカル ポリシー → セキュリティ オプション** |
| ディレクトリ サービスの変更の監査 = 成功、失敗 | 同 → **高度な監査ポリシーの構成 → システム監査ポリシー - ローカル グループ ポリシー オブジェクト → DS アクセス** |

「高度な監査ポリシーの構成」は`ローカル ポリシー`の**子ではなく兄弟**で、`セキュリティの設定`直下の最下部にあります。さらに配下に「システム監査ポリシー - ローカル グループ ポリシー オブジェクト」という中間ノードが1段挟まるため、探し当てにくい位置です。

適用後、両DCで`gpupdate /force`を実行し、上表の一致を確認しました。

#### この検証が意味すること

- **「GPOで管理する」は、2台目を建てて初めて実証できる。** 1台のDCでは、レジストリ直編集とGPO管理の結果は見分けがつきません
- **設定が効いていることと、設定が正しく配信されていることは別問題。** dc01は3設定とも意図どおり動いていましたが、うち2つは新しいDCに引き継がれない状態でした
- **GPOのダウンロード失敗は1件でも全体を止める。** 「一部のGPOだけ効かない」ではなく「何も適用されない」形で出ます

### 9. スケジュールバックアップの実動確認

[work-result](2026-09-02-work-result-SM-AD-001.md)で登録した日次03:30のSystem Stateバックアップ(AIT-06)が、実際に自動実行されていたことをdc01のイベントログで確認しました。登録時点では「登録できた」までしか確認できていなかった項目です。

```text
Microsoft-Windows-Backup ログ / System ログ(6005)

2026/09/02 14:16:00  Backup ID 1   バックアップ開始(手動実行)
2026/09/02 14:40:17  Backup ID 4   成功         → 所要 24分17秒
2026/09/03 10:36:44  System 6005   OS起動
2026/09/03 10:44:21  Backup ID 1   バックアップ開始(スケジュール実行)
2026/09/03 11:48:09  Backup ID 4   成功         → 所要 63分48秒

wbadmin get versions → 2世代(09/02 14:16、09/03 10:44)
D:(20GB) 使用14GB / 空き6GB

Get-ScheduledTask -TaskPath '\Microsoft\Windows\Backup\' | Get-ScheduledTaskInfo
  TaskName       : Microsoft-Windows-WindowsBackup
  LastRunTime    : 2026/09/03 10:43:43
  LastTaskResult : 0            (成功)
  NextRunTime    : 2026/09/04 3:30:30
```

タスクの起動(10:43:43)からバックアップ本体の開始イベント(10:44:21)までは38秒で、両者は同じ実行を指しています。`NextRunTime`が翌日の03:30に戻っているため、キャッチアップ実行してもスケジュール自体はずれません。

読み取れることが3点あります。

- **スケジュール登録は機能している。** 09/03 10:44の実行は手動で起動していません
- **03:30ではなく起動7分半後に走った。** ラボのVMは03:30に停止していたため、Windows Server Backupのタスクがキャッチアップ実行しました。登録の不具合ではなく、常時起動でない環境での正常な振る舞いです。**24時間稼働でない環境ではバックアップ時刻は保証されない**という前提の確認になります
- **所要時間が24分17秒→63分48秒(2.6倍)に伸びた。** この時間帯(10:44〜11:48)は同一ホスト上でdc02の昇格・DFSR初期同期・チェックポイントのマージが並行していました。因果を断定はできませんが、他に説明のつく変化がありません。**バックアップ枠は他の負荷と競合しない時間帯に取る必要がある**ことを示す実測値です

保持14日という目標値については、現時点で2世代・14GB使用/20GBのため、この容量では14日分は入りません。[パラメータシート](../build-package-ad/03-parameter-sheet.md)記載のとおり、Windows Server Backupに世代数・日数を指定するパラメータは存在せず、格納先の空き容量に応じた自動ローテーションです。**目標値を満たすには格納先容量の見積もりが必要**であり、本ラボの20GBでは不足します。

## インシデントと欠陥(LAB-16〜22)

[復元演習](2026-09-02-ad-restore-drill.md)のLAB-11〜15に続く番号です。

| ID | 事象 | 最初の仮説 | 実際に見たもの | 原因 | 対応 |
| --- | --- | --- | --- | --- | --- |
| LAB-16 | 新規VMを起動したが`CPUUsage: 0`のまま2分経過、`Heartbeat: NoContact` | VMのハング / ISOの指定ミス | `BootOrder`はDVD→ネットワーク→HDDで正しい。`State: Running`だがCPUを使っていない | Gen2 VMの「Press any key to boot from CD or DVD」を数秒で逃し、次のブートデバイス(PXE)へ進んで停止していた | コンソールを**先に開いてから**`Restart-VM`し、プロンプト表示中にキーを連打 |
| LAB-17 | dc02からdc01へ`Test-NetConnection`が`DestinationHostUnreachable` | IP設定ミス / 仮想スイッチの不一致 | 両VMとも`ADLab-Internal`・`{Ok}`、dc02のIPは`Preferred`、`arp -a`にdc01のMACが**動的**で存在。dc01の`Uptime`が4分33秒 | dc01がまだ起動途中だった。ネットワーク設定の問題ではない | dc01の起動完了後に再実行し成功 |
| LAB-18 | `Install-ADDSDomainController`が前提条件の検証で失敗 | パラメータ誤り | 「ディレクトリ サービス復元モードのパスワードが短すぎます。パスワード ポリシーで設定されている長さの条件に合いません」 | **DSRMパスワードにもドメインのパスワードポリシー(AIT-04で設定した最小長14文字)が適用される** | 14文字以上で再実行。検証段階で停止したためADへの変更はなし |
| LAB-19 | 昇格後、dc02に`NETLOGON`共有が作られず`dcdiag`の`NetLogons`/`DFSREvent`が失敗 | DFSR初期同期の未完了 | DFSRは`4604`(初期複製完了)・`State: 4`(Normal)で正常。しかし**dc01の`C:\Windows\SYSVOL\domain`に`scripts`フォルダーが存在しない**(`DfsrPrivate`と`Policies`のみ)。dc01では`NETLOGON`共有だけが残っていた | 前日のSystem State非権威復元でdc01のSYSVOLから`scripts`が失われていた。単一DCでは既存の共有定義が残るため症状が出ず、**2台目を追加して初めて顕在化**した | dc01で`New-Item C:\Windows\SYSVOL\domain\scripts`を作成 → DFSRがdc02へ複製 → dc02で`Restart-Service Netlogon` → `NETLOGON`共有が作成され`dcdiag /test:netlogons /test:advertising /q`が無出力(合格) |

| LAB-20 | dc02にGPOが1件も適用されない(`gpresult /r`の適用GPO一覧が空) | 複製の遅延 / OU配置ミス / 権限 | dc02は`OU=Domain Controllers`に正しく存在。GPO側の`GptTmpl.inf`には`LDAPServerIntegrity=4,2`が存在。dc02のGPイベントに**7257(GPOのダウンロード失敗)**、対象は`{31B2F340-...}`(Default Domain Policy) | Default Domain Policyの`gpt.ini`が**両DCで欠損**。09-02のSystem State非権威復元の巻き添え。**GPOのダウンロードが1件失敗すると適用サイクル全体が中断する**ため、Default Domain Controllers Policyにも到達していなかった | dc01で`gpt.ini`(`[General]`/`Version=4`)を再作成しADオブジェクト側の版数と一致させる → DFSRでdc02へ複製 → dc02で`gpupdate /force` → 7257が消え**8004**(成功)に変化 |
| LAB-21 | 後付けディスクへの`New-Partition -DriveLetter D`が`The requested access path is already in use` | `Initialize-Disk`の失敗 / ディスク番号の誤り | `Get-Disk -Number 1`は`GPT`/`Online`で正常。`Get-Volume`にD:が**CD-ROM**として存在(マウント中のインストールISO) | DVDドライブがD:を先に占有していた。dc01は最初からVHDX 2本構成でD:が固定ディスクに割り当たっていたため発生しなかった | ホストで`Set-VMDvdDrive -Path $null`→`Remove-VMDvdDrive`(OSインストール済みでISO不要) → ゲストでD:を割り当て。[構築手順書](../build-package-ad/05-build-procedure.md)9.1節に注記を追加 |
| LAB-22 | 日次03:30のスケジュールバックアップが03:30に実行されていない | 登録の失敗 | Backupイベント`1`(開始)が**10:44:21**、Systemイベント`6005`(OS起動)が**10:36:44**。`4`(成功)まで到達 | ラボのVMが03:30に停止していたため、Windows Server Backupのタスクが起動後にキャッチアップ実行した。登録自体は正常 | 是正不要。**常時起動でない環境ではバックアップ実行時刻は保証されない**ことを前提として記録 |

LAB-19は、[復元演習の証跡](2026-09-02-ad-restore-drill.md)で`dcdiag`の`DFSREvent`失敗を「DSRM起動時のNTDS依存サービス起動失敗が System ログに残っているだけ」と判断した点が不十分だったことを示します。当該証跡の判断はこの発見をもって訂正します。**復元後は`dcdiag`の合否だけでなく、SYSVOL配下に`Policies`と`scripts`が揃っているかをファイルシステムで確認すべき**でした。

## 学び

- **単一構成では隠れる不具合がある**。dc01は共有定義が残っていたため、SYSVOLの実体が欠けていても1台では動き続けた。冗長化して初めて「複製元に無いものは複製されない」形で露呈した
- **DSRMパスワードもドメインのパスワードポリシーに従う**。自分で厳しくした設定が、後の作業で自分に返ってくる
- **複製時間の測定は起点の取り方で意味が変わる**。待機時間込みの65.5秒と、実際の伝播17.8秒は別物
- **NTDSとSYSVOLは別々の仕組みで複製される**。`repadmin`が健全でもSYSVOLが壊れていることがあり、両方見る必要がある
- **Gen2 VMのDVDブートは数秒しか待たない**。コンソールを開いてから起動するのが確実
- **「GPOで管理する」という是正は、2台目を建てて初めて実証できる**。1台のDCではレジストリ直編集とGPO管理の結果は見分けがつかず、dc01で正しく効いていた3設定のうち2つは新しいDCへ引き継がれない状態だった
- **設定が効いていることと、設定が正しく配信されていることは別問題**。前者だけを確認していると、DCを増やした瞬間に差分が出る
- **GPOのダウンロード失敗は1件でも適用サイクル全体を止める**。「一部だけ効かない」ではなく「何も適用されない」形で現れるため、症状から原因GPOを推測できない。イベントログ(`Microsoft-Windows-GroupPolicy/Operational`)を見るのが最短経路
- **`Get-GPOReport`のXMLは設定の表示名で記述される**。レジストリキー名で検索して空だからといって「設定されていない」とは言えない。SYSVOL上の`GptTmpl.inf`を直接読むのが確実
- **バックアップ所要時間は他の負荷で倍以上に伸びる**。同じDC・同じ格納先で24分17秒→63分48秒。バックアップ枠は競合しない時間帯に取る必要がある

## 現在の状態と後片付け

- テスト用OU(`ReplTest-*`、`ReplTest2-*`)は削除済み
- Hyper-Vチェックポイント: `ad-dc01`に`phase1-hardened`と`before-dc02-promotion`の2世代、`ad-dc02`に`自動チェックポイント`と`before-promotion`の2世代。[LAB-11](2026-09-02-ad-restore-drill.md)の教訓に従い、次の大きな書き込み作業の前に1世代へ統合する
- `ad-dc02`のフェーズ1相当設定は**すべて完了**(WinRM HTTPSリスナー、Firewall 3プロファイルBlock、AD関連5ルールグループのスコープ限定、RDP無効、SMBv1無効、LDAP署名/チャネルバインディング/DSアクセス監査(GPO経由)、windows_exporter 0.31.8、System Stateバックアップ)。**2台のDCが同等の設定・監視・バックアップを持つ状態**になった
- `ad-dc02`にバックアップ格納用の`D:`(20GB動的VHDX)を追加済み。DVDドライブは取り外し済み(LAB-21)
- FSMO役割の**奪取**(`-Force`によるseize)と、DCを1台停止した状態での可用性試験は`NOT RUN`
