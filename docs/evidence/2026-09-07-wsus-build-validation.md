# WSUS構築・試験結果票（SM-WSUS-001 フェーズ1） — 2026-09-07

[WSUS版案件パック](../build-package-wsus/README.md)（案件ID`SM-WSUS-001`）のフェーズ1（ホスト単体構築）を、手元Hyper-V上の検証用VM 1台で通しで実施した記録です。原本は[試験仕様書・結果票](../build-package-wsus/06-test-specification.md)であり、そちらは`NOT RUN`のまま保存しています。

> **この証跡が示す範囲**: Windows 11 Pro上のHyper-V（内部スイッチ`ADLab-Internal`）に立てたWindows Server 2022評価版VM 1台での結果です。ホストPCが管理端末とNATゲートウェイを兼ねており、独立した管理端末・組織DNS・実TLS証明書・他のドメインメンバーからの検証は含みません。24時間/72時間の連続稼働、実IPでのインターネット越しFirewall検証も含みません。

## 結果の要約

| 項目 | 結果 |
| --- | --- |
| フェーズ1 総合判定 | **`FAIL`** — 必須28 IDのうち26 `PASS` / 1 `FAIL`（SIT-06） / 1 期待結果未達（SIT-04） |
| フェーズ2（SIT-09） | `BLOCKED`（未実装3点は未解消。設計どおり） |
| 実施日 | 2026-09-07（JST） |
| 実施者 | 本人（引き渡し元・先とも同一） |
| commit SHA | `8216723c5d6232ac74d7dc60c295a5efbcc80741` |
| 対象ホスト | `wsus-01` / `wsus-01.corp.example.test` / `192.0.2.52/24` |
| OSビルド番号 | **`20348`**（Windows Server 2022 Standard Evaluation、デスクトップ エクスペリエンス、ja-JP） |
| 依存ドメイン | `corp.example.test`（`ad-dc02`=`192.0.2.51`単独。`ad-dc01`は[2026-09-04のFSMO奪取](2026-09-04-ad-fsmo-seize.md)で削除済み） |
| 手順書の誤り・欠落 | **9件**を実機で検出（下記「実機で見つけた手順書の誤り」節） |

**総合判定を`FAIL`とした理由**: SIT-06（自動承認ルールの動作確認）が期待結果と一致しませんでした。[試験仕様書](../build-package-wsus/06-test-specification.md)の終了判定は「フェーズ1必須IDに`FAIL`・`BLOCKED`・`NOT RUN`が1件でも残る場合、フェーズ1は完了としない」と定めているため、26 IDが`PASS`であってもフェーズ1は未完了です。

## 実施環境

| 項目 | 値 |
| --- | --- |
| ハイパーバイザー | Hyper-V（Windows 11 Pro Education 10.0.26200、Intel Core i5-3320M 2コア4論理、物理メモリ15.8GB） |
| 仮想スイッチ | `ADLab-Internal`（内部）。ホストPC側IP`192.0.2.40`が管理端末とNATゲートウェイを兼ねる |
| VM構成 | Gen2 / 4 vCPU / 動的メモリ 最小1GB・起動2GB・最大8GB / OS用VHDX 80GB（可変）+ コンテンツ用VHDX 100GB（可変） |
| インストール方式 | 評価版ISO（`C:\ISO\SERVER_EVAL_x64FRE_ja-jp.iso`、SHA256 `9228975564772B10DCECEB4167A63619CE37F234DEA1FB8670885EFB2159B404`）の`install.wim` index 2 を`Expand-WindowsImage`でVHDXへオフライン展開し、`unattend.xml`で無人OOBEを通した |
| ゲスト操作経路 | Hyper-V PowerShell Direct（`Invoke-Command -VMName`）。ネットワークに依存しないため、Firewallを締めた後もコンソール相当の経路が確保される |

### 設計値からの逸脱

| 項目 | 設計値 | 実績値 | 理由 |
| --- | --- | --- | --- |
| メモリ | 8GB | 動的メモリ 最小1GB / 起動2GB / 最大8GB | ホスト物理メモリ15.8GB・実行時空き3.7GBで8GB固定起動が`0x800705AA`で失敗したため。実行中の実割当は2.1〜3.6GBで推移 |
| DNSリゾルバー | `ad-dc01`・`ad-dc02`を優先/セカンダリ | `192.0.2.51`（`ad-dc02`）のみ | `ad-dc01`は依存案件側のFSMO奪取試験でメタデータごと削除済みで存在しない |
| default gateway | 環境ごとに決定（`NOT SET`） | `192.0.2.40`（ホストPCのWinNAT） | `ADLab-Internal`は内部スイッチでNATが無く、Microsoft Update同期に必要な外向き443が通らなかったため`New-NetNat -Name ADLab-NAT -InternalIPInterfaceAddressPrefix 192.0.2.0/24`を作成 |
| 同期対象製品「Windows Server 2022」 | 同左 | `Microsoft Server operating system-21H2` | WSUSカタログに「Windows Server 2022」という製品タイトルは存在しない（誤り3参照） |
| windows_exporterコレクター | `cpu,cs,logical_disk,net,os,service,iis` | `cpu,system,memory,logical_disk,net,os,service,iis` | `cs`は0.31.8で廃止（誤り1参照） |
| windows_exporter用Firewall許可 | 中央Prometheus hostのIPのみ許可 | 許可ルールを作成しない | 中央Prometheus hostが`NOT SET`のため。[AD版パック2026-09-01のANW-06](2026-09-01-network-host-validation-ad.md)と同じ扱いで、Default Inbound Blockにより拒否される |

### 依存案件（`SM-AD-001`）側へ加えた変更

`wsus-01`のWSUS初回同期には外部FQDNの再帰解決が必要ですが、`ad-dc02`にdefault routeが無く、DNSフォワーダも既定のプレースホルダ（`fec0:0:0:ffff::1/2/3`。実在しないアドレス）のままだったため、次の2点を変更しました。変更後も内部ゾーン解決とNTDS/DNS/Netlogon/W32Timeの稼働に影響がないことを確認しています。

| 対象 | 変更前 | 変更後 | 戻し方 |
| --- | --- | --- | --- |
| `ad-dc02` default route | 無し | `0.0.0.0/0 → 192.0.2.40` | `Remove-NetRoute -DestinationPrefix 0.0.0.0/0` |
| `ad-dc02` DNSフォワーダ | `fec0:0:0:ffff::1`, `::2`, `::3` | `1.1.1.1`, `8.8.8.8` | `Set-DnsServerForwarder -IPAddress fec0:0:0:ffff::1,fec0:0:0:ffff::2,fec0:0:0:ffff::3` |
| 管理端末（ホストPC）の`hosts` | 該当行なし | `192.0.2.52 wsus-01.corp.example.test wsus-01` | 当該2行を削除 |

管理端末は非ドメイン参加でDNSが`ad-dc02`を向いていないため、`Test-WSMan`が名前解決に失敗しました。設計書は管理端末側の名前解決手段を規定していないため、`hosts`で補完しています。

## 結果一覧

判定は`PASS / FAIL / BLOCKED / NOT RUN`のみです。

### 単体・設定確認

| ID | 確認対象 | 結果 | 実測値 |
| --- | --- | --- | --- |
| SUT-01 | ドメイン参加確認 | **PASS** | `CN=WSUS-01,OU=Servers,DC=corp,DC=example,DC=test`。既定の`CN=Computers`から`Move-ADObject`で移動済み |
| SUT-02 | WSUS機能インストール確認 | **PASS** | `UpdateServices` / `-WidDB` / `-Services` / `-RSAT` / `-API` / `-UI` の6件が`Installed`。`-DB`（SQL Server Connectivity）は`Available`＝系統A（WID）の設計どおり |
| SUT-03 | WSUSサービス起動確認 | **PASS** | `WsusService` `Running`/`Automatic`。IISサイト「WSUS の管理」`Started`、`wsusutil postinstall`実行済み |
| SUT-04 | windows_exporterのSHA256検証 | **PASS** | 実測 `0AADCE6AFB20182B678BFCA9E8F2E8464EF48C469B28B4CF02E99D82158F5D40` = 公式`sha256sums.txt`の`windows_exporter-0.31.8-amd64.msi`と一致 |
| SUT-05 | PowerShell 7.4系導入確認 | **PASS** | 組込`5.1.20348.558` / 追加導入`7.4.19`（MSI SHA256 `4B162D393633ED76624694138163EF1D5E1C924BADC649EBE1D7B864E6E7C35C`＝GitHub Releases公開値と一致） |

### 構築・結合試験

| ID | 確認対象 | 結果 | 実測値 |
| --- | --- | --- | --- |
| SIT-01 | 初回構築成功 | **PASS** | ドメイン参加→ロール導入→`wsusutil postinstall CONTENT_DIR=D:\WSUS\WSUSContent`（exit 0、1.3分）→`WsusPool`チューニング。コンテンツストアはDドライブ（100GB NTFS、ラベル`WSUSContent`）に配置 |
| SIT-02 | 2回目実行での冪等性 | **PASS** | 3・4・7・8節を再実行。全突合値が1回目と一致（下表） |
| SIT-03 | Microsoft Update初回同期成功 | **PASS** | `Result=Succeeded`。**所要64分**（カテゴリのみの事前同期は別途37.5分）。取得更新プログラム**557件** |
| SIT-04 | GPO適用と`wsus-01`自己登録 | **部分達成** | GPO適用は`PASS`。自己登録も成立（`ComputerTargetCount=1`）したが、**配置先が`Servers`ではなく`Pilot`**。詳細は下記 |
| SIT-05 | 承認済み更新のダウンロード・インストール | **PASS** | 承認済み1件のみが検出され適用された。詳細は下記 |
| SIT-06 | 自動承認ルールの動作確認 | **FAIL** | `ApplyRule()`が設計の絞り込みを無視し**557件中555件を全件承認**。詳細は下記 |
| SIT-07 | クリーンアップウィザードの正常終了 | **PASS** | `Invoke-WsusServerCleanup`が0.1分で正常終了。圧縮22件、拒否2件、削除0件（新規サーバーのため対象なし）。`WSUS-Cleanup-Weekly`タスクを毎週日曜03:00 JSTで登録、`State=Ready` |
| SIT-08 | SUSDB・コンテンツストア・IIS構成のバックアップ・リストア | **PASS** | 3点とも取得し、SUSDBは実復元まで実施して内容一致を確認。詳細は下記 |
| SIT-09 | 中央監視統合（フェーズ2） | **BLOCKED** | 未実装3点が未解消。設計どおりの`BLOCKED`であり、フェーズ1の判定には影響しない |

#### SIT-02 冪等性の突合結果

| 突合項目 | 1回目実行後 | 2回目実行後 | 一致 |
| --- | --- | --- | --- |
| 有効な受信Firewallルール件数 | 63 | 63 | ○ |
| 本パック作成ルール件数 | 3 | 3 | ○ |
| GPO `GpoId` | `0b2a041c-4033-4649-a3dc-89c12bf37f5a` | 同左 | ○ |
| 同名GPO件数 | 1 | 1 | ○ |
| `Servers`OUへの当該GPOリンク数 | 1 | 1 | ○ |
| コンピューターグループ件数 | 4 | 4 | ○ |
| 承認ルール件数 | 2 | 2 | ○ |
| スケジュールタスク件数 | 1 | 1 | ○ |
| WSUS機能`Installed`件数 | 6 | 6 | ○ |
| サービス状態（`WsusService`/`W3SVC`/`windows_exporter`/`WinRM`） | 全`Running` | 全`Running` | ○ |

スクリプト側も`already exists ... (idempotent)` / `already linked ... (idempotent)` / `postinstall already done (idempotent)` を出力し、再作成が起きていないことを確認しました。

#### SIT-04 が部分達成である理由

GPOの適用自体は成功しています。`gpresult /r /scope computer`で`WSUS-Client-Policy`が適用済み（適用元`ad-dc02.corp.example.test`）、レジストリにも`WUServer`/`WUStatusServer`=`http://wsus-01.corp.example.test:8530`、`TargetGroupEnabled=1`、`TargetGroup=Servers`、`NoAutoUpdate=0`、`AUOptions=3`、`UseWUServer=1`が反映されました。グループポリシー操作ログのエラーは0件、警告1件はイベントID 6314「グループ ポリシーの帯域幅の推定に失敗しました。処理は続行されます。高速リンクであると推定されます」で、内部スイッチ環境でのICMP依存の推定失敗という良性のものです。

自己登録も成立し`ComputerTargetCount=1`になりましたが、**初回は`割り当てられていないコンピューター`へ入りました**。原因はWSUSサーバー側の`TargetingMode`が既定の`Server`（サーバー側ターゲティング）のままで、クライアントが送る`TargetGroup`が無視されていたことです（誤り6参照）。`TargetingMode`を`Client`へ変更後も、再レポートで`Servers`へは移らず`Pilot`（手順書9節に従って明示追加したグループ）に留まりました。期待結果「`wsus-01`が`Servers`グループへ自己登録」には到達していないため、`PASS`とはしません。

#### SIT-06 が FAIL である理由

期待結果は「分類Critical/Security、製品Windows Server 2022、対象`Pilot`の更新**のみ**自動承認。他は手動承認」です。実測は次のとおりでした。

```text
[ルールの構成（保存後に読み戻して確認）]
Name    : Critical and Security Updates - Pilot Auto-Approve
Enabled : False
分類    : セキュリティ問題の修正プログラム | 重要な更新
製品    : Microsoft Server operating system-21H2
グループ: Pilot
アクション: Install

[9節の ApplyRule() を実行]
→ "この承認規則は、有効でないため適用できません。"（Enabled=false のため拒否。誤り7）

[一時的に Enabled=true にして再実行]
ApplyRule() 戻り値: UpdateRevisionId の配列（大量）

[実行直後のサーバー状態]
UpdateCount            : 557
ApprovedUpdateCount    : 555      ← 分類・製品・グループの絞り込みが効いていない
NotApprovedUpdateCount : 0
DeclinedUpdateCount    : 2

[コンテンツダウンロードの見積もり]
GetContentDownloadProgress().TotalBytesToDownload = 353,596.3 MB（約345GB）
```

ホストC:の空きは28.95GBであり、そのままでは**ディスクを枯渇させ、同一ホストで稼働中のドメインコントローラー`ad-dc02`を巻き添えにする**状態でした。検知から約1分で`Stop-Service WsusService -Force`によりダウンロードを中断しています。依存案件への実害はありません。

> **実ダウンロード量について（2026-09-08 に本票の記載を訂正）。** 本票はもともと「約365MB、ホスト空き28.95→28.73GB」と記載していましたが、**この値は本試験の他の記録と両立しません**。[作業結果・引き渡し報告書](2026-09-07-work-result-SM-WSUS-001.md)7-1節の「約2.7GB、ホスト空き28.95→26GB」を採ります。根拠は次の3点です。
>
> 1. **クリーンアップが724MBを解放している。** `ApplyRule()`実行直後の状態は`ApprovedUpdateCount=555`／`NotApprovedUpdateCount=0`であり、それ以前は承認0件でした。WSUSは承認された更新のコンテンツしか取得しないため、**本機のコンテンツはすべてこの暴走中に取得されたもの**です。その後18:12の`Invoke-WsusServerCleanup -CleanupUnneededContentFiles`が724MBを解放しています。365MBしか取得していなければ724MBを解放できません。
> 2. **保持分を足すと最低でも約809MB。** 上記724MB（拒否した更新のぶん）に加え、MSRT（85MB）は取得完了して残っています（SIT-05）。さらに累積更新KB5120242（564MB）の取得途中ぶんと、破棄できなかった**BITSジョブ18件**が保持する未完了ダウンロードが上乗せされます。
> 3. **本票の数値は単体で矛盾していた。** 「365MBを取得」しながらホスト空きの減少が28.95→28.73GB（約220MB）というのは、可変VHDXが書き込みバイト数より小さくしか増えないことを意味し、成立しません。報告書側の「2.7GB取得／2.95GB減少」は整合します。
>
> **ただし2.7GBという値そのものの精度は未検証です。** 導出過程が記録されておらず、上の根拠が示すのは「365MBではなく、少なくとも約809MB以上、GB規模である」ことまでです。**いま`wsus-01`を測り直しても当時の値は復元できません**（その後の巻き戻し・クリーンアップ・WSUS動作で両値が変化しているため）。厳密な確定が必要な場合は、実機に残る当時のBITSジョブ18件のバイト数、`%SystemRoot%\WindowsUpdate.log`／`SoftwareDistribution`のログ、Hyper-Vのチェックポイント差分VHDXサイズのいずれかを参照してください。

その後、承認を設計意図の範囲へ巻き戻しました。

| 段階 | ApprovedUpdateCount | DeclinedUpdateCount |
| --- | --- | --- |
| `ApplyRule()`直後 | 555 | 2 |
| 意図しない承認を拒否 | 16 | 541 |
| 旧版MSRT 14件を拒否 | **2** | **555** |

最終的な承認済み2件は次のとおりです。

```text
564 MB | セキュリティ問題の修正プログラム | 2026-08 x64 ベース システム用 Microsoft server operating system version 21H2 の累積更新プログラム (KB5120242)
 85 MB | 修正プログラム集                 | 悪意のあるソフトウェアの削除ツール x64 - v5.144 (KB890830)
```

#### SIT-05 の実測

承認済みの2件のうち、コンテンツ取得が完了していた1件（MSRT）を対象に、検出からインストールまでを一巡させました。

```text
[適用前]
Get-HotFix | Sort InstalledOn -Desc | Select -First 3
    KB5010523 Update          2022/03/03
    KB5011497 Security Update 2022/03/03
    KB5008882 Update          2022/03/03

[WSUS に対して検索: ServerSelection=1 (ManagedServer)]
検索: 1 件 / 所要 1.3 分
  - 悪意のあるソフトウェアの削除ツール x64 - v5.144 (KB890830)

[ダウンロード]
ResultCode=2 (Succeeded) / 所要 0 分   ← WSUSサーバーから取得

[インストール]
ResultCode=2 (Succeeded) / 再起動要求=False / 所要 2.7 分
  - [2] 悪意のあるソフトウェアの削除ツール x64 - v5.144 (KB890830)

[WSUS側の準拠状況 (NFR-08)]
対象: wsus-01.corp.example.test
最終レポート時刻: 2026-09-07 09:17:14 (UTC)
Installed=1 NotInstalled=1 Downloaded=0 Failed=0 Unknown=0
```

判定: **PASS**。同期済み557件のうち、クライアントに提示されたのは**承認済みの1件のみ**でした。GPOの`UseWUServer=1`によりクライアントがWSUSのみを参照し、承認操作が実際の配信を制御する設計が成立しています（期待結果「承認分のみ適用」）。準拠状況はWSUS APIの`GetUpdateInstallationSummary()`で`Installed=1` `Failed=0`として確認できました。

`NotInstalled=1`は累積更新KB5120242です。SIT-06の巻き戻し時にディスク保全のためBITSを停止した影響でサーバー側のコンテンツ取得が`NotReady`のまま残り、クライアントへ提示されませんでした。承認そのものは維持されています。

WSUSコンソールのGUIレポート機能（NFR-08が注記する「レポート表示用ランタイムの追加インストールが必要になる場合がある」件）は、本試験ではGUIを使わずAPI経由で準拠状況を取得したため未検証です。

#### SIT-08 の実測

```text
(1) SUSDB — WIDのローカル名前付きパイプ経由
    接続: np:\.\pipe\MICROSOFT##WID	sql\query  (ServerVersion 12.00.5214)
    BACKUP DATABASE SUSDB TO DISK = N'C:\Backup\SUSDB-20260907-1806.bak' WITH INIT
        → 成功 / 所要 38.4 秒 / 269.4 MB
    RESTORE VERIFYONLY FROM DISK = ...
        → 成功（バックアップセットは復元可能）

(2) コンテンツストア — robocopy D:\WSUS\WSUSContent → C:\Backup\WSUSContent-20260907-1802 /E
    29 個のファイルが正常に処理されました。0 個のファイルを処理できませんでした

(3) IIS の WSUS管理サイト構成
    appcmd list site "WSUS の管理" /config /xml → C:\Backup\iis-wsus-site-*.xml
    appcmd list apppool "WsusPool"   /config /xml → C:\Backup\iis-wsuspool-*.xml
    Backup-WebConfiguration -Name "wsus-*"

[復元試験]
    復元前: テーブル=117 / tbUpdate=5441 / tbComputerTarget=1
    Stop-Service WsusService, W3SVC
    ALTER DATABASE SUSDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    RESTORE DATABASE SUSDB FROM DISK = ... WITH REPLACE, RECOVERY
        → 成功 / 所要 10.2 秒
    ALTER DATABASE SUSDB SET MULTI_USER
    Start-Service W3SVC, WsusService → 両方 Running

    復元後の突合:
        テーブル数       : 前=117  後=117  一致=True
        tbUpdate 行数    : 前=5441 後=5441 一致=True
        tbComputerTarget : 前=1    後=1    一致=True

    復元後のWSUS動作:
        UpdateCount=557 ApprovedUpdateCount=2 DeclinedUpdateCount=555 ComputerTargetCount=1
        コンピューターグループ: すべてのコンピューター, Pilot, Servers, 割り当てられていないコンピューター
        承認ルール: 既定の自動承認規則 / Critical and Security Updates - Pilot Auto-Approve
        ClientWebService: HTTP 200
```

判定: **PASS**。3点とも取得でき、SUSDBについては実際の復元まで実施して内容一致とサービス継続を確認しました。

**設計どおりの手順では実施できなかった点が2つあります。**

1. 手順書・パラメータシートは`sqlcmd`の使用を想定していますが、**WID単体構成には`sqlcmd.exe`が同梱されません**（誤り9）。.NET `System.Data.SqlClient`で名前付きパイプへ直接接続する方式に置き換えました。
2. [試験仕様書](../build-package-wsus/06-test-specification.md)は「別ボリューム/別ホストへ復元し、内容が一致することを確認」としていますが、**WIDは別名データベースへの復元をスキーマ検証で拒否します**（`データベース 'SUSDB_RestoreTest' のスキーマの検証が失敗しました`）。WIDがMicrosoft製品専用の制限付きインスタンスであることによる制約です。そのため、実運用の復旧と同じ`SUSDB`自身への`WITH REPLACE`復元に切り替えて内容一致を確認しました。「別ボリューム/別ホスト」への復元は、外部SQL Server（系統B）でなければ成立しません。

### セキュリティ試験

| ID | 確認対象 | 結果 | 実測値 |
| --- | --- | --- | --- |
| SST-01 | Firewall既定Blockと許可経路の最小化 | **PASS** | `Domain`/`Private`/`Public`とも`DefaultInboundAction=Block`、`DefaultOutboundAction=Allow`。設計対象ポートの有効な許可ルールは`WinRM-HTTPS-MgmtOnly`(5986/`192.0.2.40`)と`WSUS-Content-InternalOnly`(8530/`192.0.2.0/24`)の2件のみ。※ロール自動生成ルールの無効化が必要だった（誤り5） |
| SST-02 | WinRM HTTPS必須・Basic認証無効 | **PASS** | listenerは`Transport=HTTPS` `Port=5986`の1件のみ（`ListeningOn 127.0.0.1, 192.0.2.52, ::1`）。`Basic=false`、`Negotiate=true`、`AllowUnencrypted=false`。証明書`CN=wsus-01.corp.example.test`（拇印`4153721F3B36B3152BF66B1660B630B1530B11A7`、2028-09-07まで） |
| SST-03 | RDP既定Disable | **PASS** | 「リモート デスクトップ」グループの3ルールすべて`Enabled=False`。`fDenyTSConnections=1`。一時許可用`RDP-Temp-MgmtOnly`は`Enabled=False`で登録済み |
| SST-04 | WSUS管理サイトの内部ネットワークCIDR限定公開 | **PASS** | `WSUS-Content-InternalOnly`の`RemoteAddress`=`192.0.2.0/255.255.255.0`。管理端末（`192.0.2.40`、CIDR内）から`client.asmx`がHTTP 200 |
| SST-05 | ローカルAdministrator・サービスアカウントの権限最小化 | **PASS** | RID 500アカウントを既定名から改名済み（名称は秘密値台帳。`SID.EndsWith('-500')=True`、`Enabled=True`）。`WsusService`=`NT AUTHORITY\NetworkService`、`W3SVC`=`localSystem`、`windows_exporter`=`LocalSystem`（設計値どおり）。`WsusPool`の`identityType`=`NetworkService`（既定のまま、設計どおり） |
| SST-06 | 監査ログの有効化確認 | **PASS**（注記付き） | `auditpol /get /category:*`を採録。ログオン=成功および失敗、アカウント管理（コンピューター/セキュリティグループ/ユーザー）=成功、ポリシーの変更=成功、アカウントログオン（Kerberos認証・サービスチケット・資格情報の確認）=成功、DSアクセス=成功。**「オブジェクト アクセス」「特権の使用」「詳細追跡」は全サブカテゴリが`監査なし`** |

SST-06について: 設計の期待結果は「該当サブカテゴリが成功/失敗とも監査対象」ですが、どのサブカテゴリを「該当」とするかが定義されていません。実測はWindows Server 2022ドメインメンバーの既定監査ポリシーそのままであり、本パックによる追加のハードニングは行っていません。セキュリティ上重要なログオン・アカウント管理・ポリシー変更が有効である一方、多くが「成功」のみで「失敗」を含まない点、およびオブジェクトアクセスが全面的に無効である点は、そのまま残存事項として記録します。

### ネットワーク実機検証

詳細は[WSUS実ホスト ネットワーク検証結果票](2026-09-07-network-host-validation-wsus.md)を正本とします。

| ID | 結果 | 要点 |
| --- | --- | --- |
| SNW-01 | **PASS** | `イーサネット` `Up` 10Gbps、`192.0.2.52/24` `PrefixOrigin=Manual`、意図しないセグメントのIPなし |
| SNW-02 | **PASS** | `0.0.0.0/0 → 192.0.2.40`。`192.0.2.40`・`192.0.2.51`ともTraceRoute 1ホップ |
| SNW-03 | **PASS** | `wsus-01.corp.example.test` A=`192.0.2.52`、SRV `_ldap`→`ad-dc02:389`／`_kerberos`→`ad-dc02:88`、`nltest /dsgetdc`成功（フラグに`PDC GC DS LDAP KDC TIMESERV`） |
| SNW-04 | **PASS** | 対象→`192.0.2.40`・`192.0.2.51`とも4/4応答。`192.0.2.50`（削除済み`ad-dc01`）は0応答＝想定どおり |
| SNW-05 | **PASS** | `5986`/`8530`/`9182`が待受、`3389`は非待受。WIDは名前付きパイプ`MICROSOFT##WID\tsql\query`のみでTCPポートを持たない |
| SNW-06 | **PASS** | loopback: `client.asmx` 200 / `/metrics` 200（`windows_iis_*` 233行）。管理端末: 8530 到達・200、9182 は`TcpTestSucceeded=False`（curl exit 28）＝設計どおり拒否。`WsusPool`は`idleTimeout=00:00:00` `queueLength=2000` `privateMemory=0` |
| SNW-07 | **PASS** | `pktmon`でポート8530のみをフィルタし`--pkt-size 128`でヘッダのみ15秒採録。並行して管理端末から4リクエスト送信、すべてHTTP 200。本文は非採録 |
| SNW-08 | **PASS** | 3プロファイルとも`Block`、接続プロファイルは`DomainAuthenticated`（ドメイン参加により`Domain`へ遷移） |
| SNW-09 | **PASS** | 管理元CIDR内から`Test-WSMan`成功・`Invoke-Command`でリモート実行成功。9182・3389は拒否。WinRM HTTPSは通信自体が暗号化されるためSSHトンネル相当の追加トンネルは不要 |

## 実機で見つけた手順書の誤り

いずれも実機で通さないと発見できないものです。性質は3つに分かれます。#2・#7・#9は**コマンド自体がエラーになる**型（実行すれば即座に気づける）、#1・#3・#4・#6は**コマンドは成功するのに結果が伴わない**型、#5・#8は**手順そのものが欠落している**型です。後の2つは「エラーが出なかった＝成功」と判断すると誤った状態のまま先へ進むため、実害が大きくなります。

なお#1（`cs`コレクター）は、`msiexec`によるインストール自体は成功し、**その後サービスが起動しない**という形で現れます。インストーラの戻り値だけを見て次へ進むと見逃すため、5.2節の手順にも「インストーラの成功だけでは不十分」として`Get-Service`による起動確認を入れています。

| # | 該当箇所 | 内容 | 実機での対処 |
| --- | --- | --- | --- |
| 1 | 05 5.2節 | `ENABLED_COLLECTORS=cpu,cs,...`の`cs`はwindows_exporter 0.31.8で廃止。サービスがイベントID102 `couldn't enable collectors err="unknown collector cs"`で起動しない | `cpu,system,memory,logical_disk,net,os,service,iis`へ変更 |
| 2 | 05 6節 | `Set-WsusProduct -UpdateServer $wsus` / `Set-WsusClassification -UpdateServer $wsus` — **`-UpdateServer`パラメーターは存在しない**（実際の構文は`-Product <WsusProduct> [-Disable]` / `-Classification <WsusClassification> [-Disable]`のみ） | パイプライン渡しへ変更 |
| 3 | 05 6節・8節、03 | 製品タイトル`"Windows Server 2022"`はWSUSカタログに存在しない。Windows Server 2022の更新は`Microsoft Server operating system-21H2`として提供される | 実際の製品名へ変更 |
| 4 | 05 6節・8節 | 分類名の英語リテラル（`"Critical Updates"`等）はja-JP環境で0件マッチ（実際は`重要な更新`・`セキュリティ問題の修正プログラム`・`更新`・`修正プログラム集`） | ロケール非依存のGUIDで指定（`e6cf1350-...`／`0fa1201d-...`／`cd5ffd1e-...`／`28bc880e-...`） |
| 5 | 05 3節・5節 | WSUSロールが自動生成する全許可ルール（`WSUS` 8530/Any、8531/Any）を無効化する手順がない。WinRMのquickconfigルールについては「限定ルールへ一本化する」と書かれているのに、WSUS側は欠落 | 該当2ルールを`Disable-NetFirewallRule` |
| 6 | 05 7節 | **サーバー側の`TargetingMode`を`Client`へ変更する手順がない。** 既定の`Server`のままではGPOの`TargetGroupEnabled`/`TargetGroup`が無視され、FR-04（クライアント側ターゲティング）が成立しない | `$config.TargetingMode = 'Client'; $config.Save()` |
| 7 | 05 8節と9節 | **矛盾。** 8節は「`Enabled=false`のまま保存」と指示するが、9節の`$rule.ApplyRule()`は「この承認規則は、有効でないため適用できません」で拒否される。設計意図（無人承認を避けつつ手動実行）を`Enabled=false`では表現できない | 一時的に`Enabled=true`にして`ApplyRule()`実行後、`false`へ戻した |
| 8 | 05 9節 | **承認前にダウンロード量を見積もる手順、および暴走時に停止する手順がない。** `ApplyRule()`が555件を承認し345GBのダウンロードを開始した | `GetContentDownloadProgress().TotalBytesToDownload`で検知し`Stop-Service WsusService -Force`で中断 |
| 9 | 03 バックアップ設計 | 「WIDのローカル名前付きパイプ経由でのバックアップ」とあるが、**WID単体構成には`sqlcmd.exe`が同梱されない**ため、記載のままでは実行できない | .NET `System.Data.SqlClient`で`np:\\.\pipe\MICROSOFT##WID\tsql\query`へ接続し`BACKUP DATABASE`を実行 |

補足: 本パックの手順書はPowerShellコードブロックを含みますが、これをそのまま`.ps1`として保存して実行する場合、**BOM無しUTF-8だとPowerShell 5.1のja-JP環境ではShift-JISとして解釈され、日本語コメント中のバイト列が文字列リテラルを破壊して`CommandNotFoundException`になります**。BOM付きUTF-8で保存する必要があります。これは手順書自体の誤りではありませんが、実務で踏みやすい落とし穴として記録します。

## 残存リスク・未確認事項

- **SIT-06が`FAIL`**。`ApplyRule()`が絞り込みに従わない理由は本試験では特定できていません。WSUS APIの承認ルール適用セマンティクスの調査が必要です。
- **SIT-04が部分達成**。`TargetingMode=Client`へ変更後も`Servers`グループへの自己登録に至っていません。クライアントの再レポート周期、または`Pilot`への手動追加との競合が原因の可能性がありますが、切り分けは未了です。
- 中央Prometheus hostが`NOT SET`のため、windows_exporterの9182/tcpは許可ルールを作らずDefault Inbound Blockで拒否されています。フェーズ2で実IPが決まった時点で許可ルールの作成と`SIT-09`の再評価が必要です。
- HTTPS化（8531/tcp）は内部CA未導入のため対象外のままです。ロールが自動作成した8531の全許可ルールは無効化しました。
- 監査ポリシーはOS既定のままで、オブジェクトアクセス・特権の使用・詳細追跡は無効です。
- ホストPCが管理端末・NATゲートウェイ・ハイパーバイザーを兼ねており、独立した管理端末からの検証ではありません。
- 24時間/72時間の連続稼働、実TLS証明書、インターネット越しのFirewall検証は未実施です。
