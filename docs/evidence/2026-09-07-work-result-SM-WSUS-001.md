# 作業結果・引き渡し報告書 — SM-WSUS-001 フェーズ1（2026-09-07）

[作業結果・引き渡し報告書(原本)](../build-package-wsus/11-work-result-report.md)を複製し、2026-09-07に手元Hyper-Vで実施したフェーズ1（ホスト単体構築）の実績を記入したものです。原本は`NOT RUN`のまま保存しています。

試験の詳細は[WSUS構築・試験結果票](2026-09-07-wsus-build-validation.md)、ネットワーク検証は[ネットワーク検証結果票](2026-09-07-network-host-validation-wsus.md)を正本とします。

## 1. 文書・作業管理

| 項目 | 値 |
| --- | --- |
| 案件 ID | `SM-WSUS-001` |
| 依存案件 ID | `SM-AD-001`（既存ADドメイン`corp.example.test`） |
| 変更 ID / チケット | ラボ作業のため発行なし |
| 作業目的 | 既存ADドメインへWSUSサーバーを1台追加し、GPOによる更新プログラムの集中管理を実現する（フェーズ1の範囲） |
| 対象環境 / ホスト | 検証（ラボ）/ `wsus-01` = `wsus-01.corp.example.test` = `192.0.2.52/24` |
| 対象フェーズ | フェーズ1のみ（フェーズ2は`BLOCKED`） |
| 作業者 / 確認者 | 本人（引き渡し元・先とも同一） |
| 作業実績日時 | 2026-09-07 13:12〜18:30（JST）、約5時間20分 |
| 対象ホストのビルド番号 | **`20348`**（Windows Server 2022 Standard Evaluation、デスクトップ エクスペリエンス、ja-JP） |
| 変更前の状態識別子 | Hyper-Vチェックポイント`pre-wsus-role`（2026-09-07 15:00:54）。それ以前は`pre-domain-join`（14:36、統合済み） |
| ドメイン参加状態 | `CN=WSUS-01,OU=Servers,DC=corp,DC=example,DC=test` |
| WSUSロール / コンテンツストア空き容量 | `UpdateServices`ほか6機能`Installed`（系統A=WID、`WID Connectivity`有効・`SQL Server Connectivity`は`Available`のまま）。`D:\WSUS\WSUSContent`、D:は100GB中99.3GB空き |
| windows_exporter バージョン / SHA256 | `0.31.8` / `0AADCE6AFB20182B678BFCA9E8F2E8464EF48C469B28B4CF02E99D82158F5D40` |
| 中央inventory適用commit SHA | `NOT SET`（フェーズ2未着手） |
| 適用手順書の版 | `8216723c5d6232ac74d7dc60c295a5efbcc80741` |
| **作業結果** | **`NOT READY`** |
| 関連 Issue / PR | 本作業で作成予定 |

## 2. 作業前判定

| 確認項目 | 判定 | 証跡 / 備考 |
| --- | --- | --- |
| 対象、影響範囲、停止時間が合意済み | PASS | ラボ作業。停止許容時間の制約なし |
| ADドメイン`corp.example.test`が稼働中 | **PASS（条件付き）** | `ad-dc02`（`192.0.2.51`）単独で稼働。`ad-dc01`は[2026-09-04のFSMO奪取](2026-09-04-ad-fsmo-seize.md)でメタデータごと削除済みのため**設計が前提とする2台構成ではない** |
| 管理端末からWinRM(HTTPS)が利用可能 | PASS | `Test-WSMan`成功（ただし`hosts`による名前解決の補完が必要だった） |
| RDP一時許可またはコンソール等の代替接続手段を確認 | PASS | Hyper-V PowerShell Direct（ネットワーク非依存）を全作業で使用。Firewallを締めた後も操作可能なことを実証 |
| コンテンツストア用のDドライブ(100GB以上)が確保済み | PASS | 100GB可変VHDXを別ディスクとして接続、NTFS・ラベル`WSUSContent`で初期化 |
| 変更前後の状態識別子を固定 | PASS | チェックポイント`pre-domain-join`→`pre-wsus-role`（1世代維持。新規取得→旧世代統合の順） |
| VM/ハイパーバイザーのスナップショット取得可否 | PASS | 取得・統合とも実施済み |
| Windows Server Backupの直近バージョンを確認 | **NOT RUN** | Windows Server Backup機能は導入せず、SUSDBは`BACKUP DATABASE`、コンテンツは`robocopy`、IIS構成は`appcmd`/`Backup-WebConfiguration`で取得する方式を選定した |
| Go / No-Go 条件を確認 | PASS | ホストC:の空き容量を継続監視し、12GB割れで中断する条件を設定 |

## 3. 計画対実績

| 工程 | 実績時刻 / 所要 | 結果 | 差異・備考 |
| --- | --- | --- | --- |
| VM立ち上げ | 13:12〜13:26 / 14分 | PASS | ISOの`install.wim` index 2を`Expand-WindowsImage`でVHDXへオフライン展開（8.8分）、`unattend.xml`で無人OOBE。**設計値8GBメモリでは起動できず**、動的メモリ 最小1GB/起動2GB/最大8GBへ変更 |
| 初期設定（2.1節） | 13:26〜13:45 / 19分 | PASS | ホスト名・静的IP・DNS・timezone・PowerShell 7.4.19・RSAT/GPMC・WinRM HTTPS。インストーラはホスト側でSHA256検証後`Copy-Item -ToSession`で転送（AD版2026-09-01と同じ方式） |
| ドメイン参加（2.2節） | 14:50〜14:58 / 8分 | PASS | `Add-Computer`→再起動→`Move-ADObject`で`Servers`OUへ。Aレコードは動的更新で自動登録 |
| Firewall・RDP（3節） | 13:52〜13:56 / 4分 | PASS | 手順書に無いWSUSロール自動生成ルール（8530/Any・8531/Any）の無効化が別途必要だった |
| WSUSロール導入（4節） | 15:01〜15:06 / 5分 | PASS | `wsusutil postinstall` exit 0、1.3分 |
| IIS・exporter（5節） | 15:06〜15:12 / 6分 | PASS | **`cs`コレクター廃止によりサービスが起動せず**、コレクター一覧を修正して再インストール |
| 同期設定（6節） | 15:12〜16:10 / 58分 | PASS | カテゴリのみの同期に37.5分。`-UpdateServer`パラメーター不在、製品名・分類名の不一致で3回の修正が必要だった |
| GPO作成（7節） | 16:09〜16:12 / 3分 | PASS | 手順書に無い`TargetingMode=Client`への変更が別途必要だった |
| グループ・承認ルール（8節） | 16:12〜16:20 / 8分 | PASS | 承認ルールの分類・製品指定を英語タイトル→GUID／実製品名へ修正 |
| 本番同期（9節） | 16:10〜17:14 / **64分** | PASS | `Result=Succeeded`、557件取得 |
| 冪等性（SIT-02） | 17:50〜17:58 / 8分 | PASS | 全突合値が1回目と一致 |
| 承認・適用一巡（SIT-05/06） | 18:00〜18:22 / 22分 | **FAIL（SIT-06）** | `ApplyRule()`が555件を全件承認し345GBのダウンロードを開始。中断・巻き戻しに約20分を要した |
| クリーンアップ（SIT-07） | 17:20 / 0.1分、18:12 / 0.6分 | PASS | 2回実行。2回目で724MBの不要コンテンツを解放 |
| バックアップ・復元（SIT-08） | 18:06〜18:30 | PASS | SUSDB 269.4MB/38.4秒、`RESTORE VERIFYONLY`成功、別DB名・別ボリュームへの復元と内容突合を実施 |
| ネットワーク検証（SNW-01〜09） | 17:00〜18:00 | PASS | 9/9 |

## 4. 試験集計

[試験仕様書・結果票](../build-package-wsus/06-test-specification.md)のフェーズ1必須28 IDに対する集計です。

| 区分 | 対象ID | PASS | FAIL | BLOCKED | NOT RUN |
| --- | --- | --- | --- | --- | --- |
| 単体・設定確認 | SUT-01〜05 | 5 | 0 | 0 | 0 |
| 構築・結合試験（フェーズ1） | SIT-01〜08 | 6 | 1 | 0 | 1※ |
| セキュリティ試験 | SST-01〜06 | 6 | 0 | 0 | 0 |
| ネットワーク実機検証 | SNW-01〜09 | 9 | 0 | 0 | 0 |
| **フェーズ1 合計** | **28** | **26** | **1** | **0** | **1** |
| 構築・結合試験（フェーズ2） | SIT-09 | 0 | 0 | 1 | 0 |

※ SIT-04は「自己登録は成立したが配置先が`Servers`ではなく`Pilot`」という部分達成であり、期待結果と一致しないため`PASS`として数えていません。集計上は`NOT RUN`ではなく**期待結果未達**として扱い、フェーズ1未完了の理由に含めます。

**フェーズ1判定: `FAIL`。** [試験仕様書](../build-package-wsus/06-test-specification.md)の終了判定「フェーズ1必須IDに`FAIL`・`BLOCKED`・`NOT RUN`が1件でも残る場合、フェーズ1は完了としない」に該当します。

## 5. 差異（設計 対 実績）

| # | 項目 | 設計値 | 実績値 | 理由 |
| --- | --- | --- | --- | --- |
| 1 | VMメモリ | 8GB | 動的 最小1GB/起動2GB/最大8GB | ホスト物理15.8GB・空き3.7GBで8GB固定起動が`0x800705AA`で失敗 |
| 2 | DNSリゾルバー | `ad-dc01`・`ad-dc02` | `ad-dc02`のみ | `ad-dc01`は依存案件側で削除済み |
| 3 | default gateway | 環境ごとに決定 | `192.0.2.40`（ホストPCのWinNAT） | 内部スイッチにNATが無く外向き443が通らないため`New-NetNat`を作成 |
| 4 | 同期対象製品 | Windows Server 2022 | `Microsoft Server operating system-21H2` | WSUSカタログに前者の製品タイトルは存在しない |
| 5 | exporterコレクター | `cpu,cs,logical_disk,net,os,service,iis` | `cpu,system,memory,logical_disk,net,os,service,iis` | `cs`は0.31.8で廃止 |
| 6 | exporter用Firewall許可 | 中央Prometheus hostのIPのみ許可 | 許可ルールを作成しない | 中央Prometheus hostが`NOT SET`。Default Inbound Blockで拒否（AD版2026-09-01と同扱い） |
| 7 | 承認ルールの`Enabled` | `false`のまま保存し`ApplyRule()`で手動実行 | 一時的に`true`にして実行後`false`へ戻す | `Enabled=false`では`ApplyRule()`が拒否される（手順書8節と9節の矛盾） |
| 8 | 承認範囲 | 分類・製品・グループで絞り込み | 555件全件承認された | `ApplyRule()`が絞り込みに従わない（SIT-06 FAIL） |
| 9 | SUSDBバックアップ手段 | WID名前付きパイプ経由 | .NET SqlClient経由 | WID単体構成に`sqlcmd.exe`が同梱されない |
| 10 | 管理端末の名前解決 | 規定なし | `hosts`に静的エントリを追加 | 管理端末が非ドメイン参加でAD統合DNSを引けない |

## 6. 依存案件（SM-AD-001）への変更

`wsus-01`のMicrosoft Update同期には外部FQDNの再帰解決が必要ですが、`ad-dc02`にdefault routeが無く、DNSフォワーダも既定のプレースホルダ（`fec0:0:0:ffff::1/2/3`、実在しないアドレス）のままでした。次の2点を変更しています。

| 対象 | 変更前 | 変更後 | 戻し方 |
| --- | --- | --- | --- |
| `ad-dc02` default route | 無し | `0.0.0.0/0 → 192.0.2.40` | `Remove-NetRoute -DestinationPrefix 0.0.0.0/0` |
| `ad-dc02` DNSフォワーダ | `fec0:0:0:ffff::1/::2/::3` | `1.1.1.1`, `8.8.8.8` | `Set-DnsServerForwarder -IPAddress fec0:0:0:ffff::1,fec0:0:0:ffff::2,fec0:0:0:ffff::3` |

変更後、内部ゾーン解決（`corp.example.test`→`192.0.2.51`）とNTDS/DNS/Netlogon/W32Timeの稼働に影響がないことを確認しています。AD版パックの文書は本変更を反映していないため、別途の更新が必要です。

## 7. 障害・想定外事象

### 7-1. `ApplyRule()`による全件承認と345GBのダウンロード開始（重大）

| 項目 | 内容 |
| --- | --- |
| 発生時刻 | 2026-09-07 18:0x |
| 事象 | 設計上の絞り込み（分類=重要な更新+セキュリティ、製品=`Microsoft Server operating system-21H2`、対象=`Pilot`）を設定した承認ルールの`ApplyRule()`が、同期済み557件中**555件を全件承認**。WSUSが**353,596MB（約345GB）**のコンテンツダウンロードを開始した |
| 検知方法 | `GetContentDownloadProgress().TotalBytesToDownload`の確認 |
| 影響 | ホストC:の空きは28.95GBであり、放置すればディスク枯渇により同一ホストで稼働中のドメインコントローラー`ad-dc02`を巻き添えにする状態だった |
| 対処 | 検知から約1分で`Stop-Service WsusService -Force`によりダウンロードを中断。その後、意図しない承認を段階的に拒否（555→16→2件）し、`Invoke-WsusServerCleanup -CleanupUnneededContentFiles`で724MBの不要コンテンツを解放 |
| 実害 | 実ダウンロード量 約2.7GB、ホストC:の空きは28.95→26GB。**依存案件への実害なし** |
| RTO | 検知〜ダウンロード停止 約1分、承認範囲の巻き戻し完了まで約20分 |

**判断の誤り**: 承認実行前に「非置換のServer 2022向け更新が5件しかないため`ApplyRule()`は数件規模」と見積もりましたが、実際の`ApplyRule()`はその絞り込みに従いませんでした。**承認前に`GetContentDownloadProgress()`でダウンロード見積もりを取るべきでした。** 手順書9節にもこの見積もり手順がありません。

### 7-2. 作業中のドメインコントローラー停止

| 項目 | 内容 |
| --- | --- |
| 発生時刻 | 2026-09-07 17:29:51 |
| 事象 | `ad-dc02`がシャットダウン統合コンポーネント経由で正常シャットダウンされた（強制=false）。同時刻帯に`lab-base01`の起動・停止操作も記録されており、Hyper-Vマネージャーからの手動操作と判断 |
| 影響 | `wsus-01`のGPOコマンドレットがAD到達不可で失敗、外部名前解決も停止（`ad-dc02`がフォワーダ役のため）。WSUSサービス自体は継続稼働 |
| 対処 | 利用者へ確認のうえ`Start-VM ad-dc02`。NTDS/DNS/Netlogon/W32Timeの`Running`を確認して作業再開 |
| 失われた作業 | なし |

### 7-3. その他

- **BITSジョブが削除できない**: 7-1の巻き戻し時、`Remove-BitsTransfer`・`bitsadmin /reset /allusers`のいずれでも18件のジョブを破棄できませんでした（所有者が`NetworkService`のため）。`WsusService`と`BITS`の停止でダウンロード自体は止まっており実害はありませんが、ジョブは残存しています。
- **PowerShellスクリプトの文字コード**: 手順書のコードブロックをBOM無しUTF-8の`.ps1`として保存すると、PowerShell 5.1のja-JP環境ではShift-JISとして解釈され、日本語コメント中のバイト列が文字列リテラルを破壊して`CommandNotFoundException`になります。BOM付きUTF-8での保存が必要です。
- **`Get-Content`のエイリアス衝突**: 試験スクリプトで見出し用に定義した関数`H`が、PowerShell組込エイリアス`h`（`Get-History`）と衝突しました。エイリアスは関数より優先されます。

## 8. 手順書への修正提案

[WSUS構築・試験結果票](2026-09-07-wsus-build-validation.md)「実機で見つけた手順書の誤り」に9件を記載しました。優先度順は次のとおりです。

| 優先 | # | 該当 | 影響 |
| --- | --- | --- | --- |
| 高 | 8 | 05 9節 | 承認前のダウンロード量見積もりと暴走時の停止手順がない。ディスク枯渇で他システムを巻き込む |
| 高 | 6 | 05 7節 | `TargetingMode=Client`への変更手順がなく、FR-04（クライアント側ターゲティング）が成立しない |
| 高 | 7 | 05 8節・9節 | `Enabled=false`と`ApplyRule()`が矛盾し、9節が必ず失敗する |
| 中 | 2 | 05 6節 | `-UpdateServer`パラメーターが存在せず、6節がエラーで停止する |
| 中 | 3 | 05 6節・8節、03 | 製品名が実在せず、同期対象にWindows Server 2022が入らない |
| 中 | 4 | 05 6節・8節 | 分類の英語リテラルがja-JP環境で0件マッチ |
| 中 | 1 | 05 5.2節 | `cs`コレクター廃止でwindows_exporterが起動しない |
| 中 | 5 | 05 3節・5節 | ロール自動生成の全許可ルールを無効化する手順がなく、SST-01/SST-04が満たせない |
| 低 | 9 | 03 | `sqlcmd`不在によりバックアップ手順が実行できない |

## 9. 残存リスク

| リスク | 影響 | 現状の扱い |
| --- | --- | --- |
| SIT-06が`FAIL` | 自動承認ルールが設計どおり動作せず、意図しない大量承認が起こりうる | 未解決。`ApplyRule()`のセマンティクス調査が必要 |
| SIT-04が期待結果未達 | クライアント側ターゲティングによる`Servers`グループへの自動配置が確認できていない | 未解決。`TargetingMode=Client`変更後も`Pilot`に留まる |
| 中央Prometheus hostが`NOT SET` | windows_exporterの許可ルールを作成できず、フェーズ2の到達性が未確定 | フェーズ2で実IP確定後に対応 |
| HTTPS化（8531）未実施 | WSUSクライアント通信が平文HTTP | 内部CA未導入のため対象外・次点課題。8531の許可ルールは無効化済み |
| 監査ポリシーがOS既定のまま | オブジェクトアクセス・特権の使用・詳細追跡が無効 | 本パックの範囲外として記録 |
| BITSジョブ18件が残存 | 将来`BITS`起動時にダウンロードが再開する可能性 | 承認済みは2件のみのため影響は限定的だが、要監視 |
| ホストリソースの逼迫 | ホストC:の空きが約19GB、物理メモリ15.8GB | 24時間/72時間の連続稼働は未検証 |
| 評価版ライセンス | 180日で失効 | 期限管理が必要 |

## 10. 引き渡し

| 項目 | 内容 |
| --- | --- |
| 対象ホストの状態識別子 | Hyper-Vチェックポイント`pre-wsus-role`（2026-09-07 15:00:54）、`OsBuildNumber 20348` |
| 設計・パラメータ | `docs/build-package-wsus/`（本作業の指摘を未反映） |
| 試験結果・実行ログ | [構築・試験結果票](2026-09-07-wsus-build-validation.md)、[ネットワーク検証結果票](2026-09-07-network-host-validation-wsus.md) |
| 中央inventory変更 | `NOT SET`（フェーズ2未着手） |
| backup / restore手順 | 本報告書3節・[結果票](2026-09-07-wsus-build-validation.md)のSIT-08節。`sqlcmd`ではなく.NET SqlClientを使う点に注意 |
| 秘密値の受け渡し | ローカル管理者アカウント名（改名済み）とそのパスワード、ドメイン管理者の資格情報は本人のローカル秘密値メモのみ。**このリポジトリのどの文書にも実値を記載していない**。WinRM証明書の秘密鍵はVM内ストアのみ（拇印`4153721F3B36B3152BF66B1660B630B1530B11A7`） |
| ロールバック方法 | `Restore-VMCheckpoint -VMName wsus-01 -Name pre-wsus-role`。依存案件側の変更は本報告書6節の「戻し方」欄 |
| 未解決事項 | 本報告書8節（手順書修正9件）・9節（残存リスク） |

## 11. 完了・受領判定

| 判定項目 | 結果 |
| --- | --- |
| フェーズ1必須28 IDがすべて`PASS` | **未達**（26 PASS / 1 FAIL / 1 期待結果未達） |
| フェーズ2（SIT-09）が解除条件とともに`BLOCKED`と明記 | 達成 |
| 実行日時・環境・ビルド番号・実行コマンド・実出力・判定が証跡として保存 | 達成 |
| 秘密値の受け渡し方法とロールバック方法が記録 | 達成 |
| 名前解決・経路・待受・HTTP疎通・Firewallを確認し出力を保存 | 達成 |
| **引き渡し判定** | **`NOT READY`** |

フェーズ1の必須試験に`FAIL`が1件、期待結果未達が1件残っているため、[引き渡しチェックリスト](../build-package-wsus/07-handover-checklist.md)の受領可条件を満たしません。本パックの引き渡し判定は`NOT READY`のままとします。

構築手順そのものは、9件の誤りを修正すれば通しで実行できることを実証しました。SIT-04・SIT-06の2点は手順書の修正だけでは解決せず、WSUSのクライアント側ターゲティングと承認ルール適用の挙動を実機で追加調査する必要があります。
