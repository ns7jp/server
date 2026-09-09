# 引き渡し対象ホストの立ち上げと受け入れ試験

**`wsus-01`は2026-09-07に実機で構築済みである。** Windows 11 Pro上のHyper-V(内部スイッチ`ADLab-Internal`)へWindows Server 2022評価版VMを立て、フェーズ1を通しで実施した。実績は[構築・試験結果票](../evidence/2026-09-07-wsus-build-validation.md)と[作業結果・引き渡し報告書](../evidence/2026-09-07-work-result-SM-WSUS-001.md)にある。

**ただしフェーズ1の総合判定は`FAIL`のままである。** `SIT-06`が`FAIL`、`SIT-04`が期待結果未達で終わり、[2026-09-08の切り分け](../evidence/2026-09-08-wsus-sit04-sit06-root-cause.md)で両方の原因を特定して[構築手順書](05-build-procedure.md)・[パラメータシート](03-parameter-sheet.md)・[試験仕様書](06-test-specification.md)へ反映したが、**修正後の手順での通し再試験を実施していない**ためである。

したがって本書には用途が2つある。

| 用途 | 読む順 |
| --- | --- |
| ゼロから新しいホストを立ち上げる | 0節から順に |
| 2026-09-07の`wsus-01`でフェーズ1を再試験する | **8節**(何を再試験するか・開始点・事前条件)→ 2〜4節 |

`wsus-01`を1台構築してもなお、次は`NOT RUN`または`BLOCKED`のまま残っている。

- フェーズ1の通し再試験(修正後の手順での`SIT-01`〜`08`再実行)。8節を参照
- ホスト再起動後の永続性(4節)。2026-09-07の証跡に該当する記録がない
- 24時間 / 72時間の連続稼働(5節)。2026-09-07の証跡に「未実施」と明記されている
- 実DNS / 自己署名でない実TLS証明書(WinRM HTTPS用)
- インターネット越しのWindows Defender Firewall(実管理端末からの到達性)。ホストPCが管理端末とNATゲートウェイを兼ねているため未検証
- フェーズ2(中央監視統合)一式(`SIT-09`)

**フェーズ1の範囲は、1台の検証用ホスト(`wsus-01`)を用意すると大半が一度に埋まる。** これに対してフェーズ2は、検証用ホストの有無に関わらず[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible role、Dockerホストと`wsus-01`の実ネットワーク接続・windows_exporterのFirewall許可先の確定、Windows向けログ集約経路)が解消しない限り埋まらない。

本書は、フェーズ1のホストを「用意してから証跡が出るまで」を最短で通すための手順である。フェーズ2の統合手順は[構築手順書](05-build-procedure.md)10節、統合後の判定基準は[試験仕様書・結果票](06-test-specification.md)を参照する。

## 0. 何を用意するか

本パックには、他パックには無い前提が1つ増える。**`wsus-01`は既存ADドメイン(`corp.example.test`)へのメンバーサーバー参加が前提であり、[AD版パック](../build-package-ad/README.md)(案件ID`SM-AD-001`)の`ad-dc01`・`ad-dc02`が稼働していなければ着手できない。** 検証用ホストを選ぶ前に、依存先のドメインが実際に稼働していることを確認する。

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| Azure / AWS EC2などのクラウドWindows Serverインスタンス | 従量課金(OSライセンス込みのため同スペックのLinuxより高め) | 実IP・実DNSがあり、インターネット越しのFirewall検証ができる。AD側の検証環境と同一VNet/VPCに置く必要がある |
| 評価版ISO(180日間有効)によるHyper-V/VMware上のVM | 0円(評価期間限定) | 費用をかけずに機能検証ができるが、期限管理が必要。実IP/実DNSは無い。AD版の検証VMと同一の仮想スイッチに接続する |
| 社内のボリュームライセンス/MSDN経由のWindows Server | 既存契約次第 | 実務に近いが本パックの対象外の契約管理が必要 |

最小構成の目安は**4 vCPU / メモリ8GB / OSボリューム(C:)80GB / コンテンツストア専用ボリューム(D:)100GB以上**である。[Windows版パック](../build-package-windows/10-host-bringup-and-acceptance.md)・[AD版パック](../build-package-ad/10-host-bringup-and-acceptance.md)の基準(2 vCPU / 4GB / 60GB)より重いのは、WSUSがMicrosoft Update全メタデータの取得、WID(Windows Internal Database。同梱の軽量DB機能)によるインデックス処理、IIS(同梱Webサーバー機能)による大容量コンテンツ配信を1台で担うためである。コンテンツストア用のD:ドライブは、VM/ハイパーバイザー側で事前に別ボリュームとして確保しておく(Cドライブへ間借りする構成は対象外)。

[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)では無償のVirtualBox VMが代替案として使えたが、**Windows Serverはライセンス費用が発生するためこの代替が成立しない。** 評価版ISOは180日の期限管理と、実IP/実DNSを使った検証(`SNW-03`、`SNW-09`相当)ができない制約が残る。実IP/実DNSでの検証まで行う場合は、クラウドWindows Serverインスタンスを選ぶ。

OSは[基本設計書](01-basic-design.md)のとおり**Windows Server 2022 Standard(Desktop Experience基準)**とする。Server Coreへの対応は検討課題であり、本パックの手順は基準VM(Desktop Experience)での実行を前提にしている。データベース方式は系統A(WID)を既定とし、系統B(外部SQL Server)は本パックの手順だけでは検証できない(7節参照)。

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておく。あとから思い出せない。

| 項目 | 記入 |
| --- | --- |
| 対象ホスト(用途・OS・スペック) | |
| 依存先ADドメインの稼働確認(`ad-dc01`・`ad-dc02`への疎通、`corp.example.test`のAD統合DNS) | |
| 対象IPv4/prefix(例示`192.0.2.52/24`。`ad-dc01`=`192.0.2.50/24`、`ad-dc02`=`192.0.2.51/24`と重複しない値) | |
| 内部ネットワークCIDR / 管理元CIDRの範囲決定([AD版パック](../build-package-ad/04-network-ip-plan.md)が定義した概念を利用) | |
| コンテンツストア用D:ドライブ(100GB以上)がVM/ハイパーバイザー側で確保済みか | |
| windows_exporterのインストーラのSHA256とダウンロード元、PowerShell 7.4系導入の配布元・SHA256(現時点`NOT SET`) | |
| WinRM HTTPS証明書の準備方法(自己署名 / 内部CA) | |
| 管理端末側にPowerShell 7とWinRM設定が揃っているか | |
| 再起動してよい時間帯 | |
| 接続不能になったときの復旧手段(ハイパーバイザーコンソール等) | |
| 停止許容時間 | |
| RDPを一時的に有効化する運用可否と、その場合の解除担当 | |

**WinRM(HTTPS)だけに依存しない。** [パラメータシート](03-parameter-sheet.md)のとおりRDPは既定Disableのため、WinRM接続に失敗すると通常の経路でログインできなくなる。ハイパーバイザーのコンソール(Hyper-VのVMConnect、クラウドのシリアルコンソール、VMwareのリモートコンソール等)に入れることを、Firewallを締める前に必ず確認しておく。

## 2. 構築

[構築手順書](05-build-procedure.md)をそのまま実行する。Windows対応Ansible roleは存在しないため(要件定義書「未実装」参照)、ここは**すべて「済(手動)」のPowerShell実行**であり、`site.yml`のような自動化された経路ではない。1節で決めた対象IP、内部ネットワークCIDR、管理元CIDRを使い、各コマンドの引数を実際の値に置き換える。

```powershell
# 対象ホストのビルド番号を先に記録する(証跡の必須項目)
Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsBuildNumber

# 05-build-procedure.md の 0〜9節を順に実行
# 0. 作業前確認 / 1. 管理端末の準備 / 2. 初期設定とドメイン参加(Servers OUへの移動を含む)
# 3. Windows Defender FirewallとRDPの締め
# 4. WSUSロールインストールとコンテンツストア設定(wsusutil postinstallによるコマンドライン初期化を含む)
# 5. IIS(WsusPool)チューニングとwindows_exporter導入
# 6. WSUS初期構成ウィザード相当の設定(同期元・言語・製品・分類・同期スケジュール)
# 7. GPO作成とクライアント側ターゲティング
# 8. コンピューターグループ・承認ルール・クリーンアップウィザードの設定
# 9. 初回同期・承認・適用の一巡確認
```

**4節のコンテンツディレクトリ初期化(`wsusutil postinstall`)は、WSUS管理コンソールを初めて開く前に必ず実行する。** これを忘れるとコンソール起動時にエラーになる、実務でよくあるつまずきである。ロール導入直後にコンソールを開いてしまった場合は、いったん閉じてから初期化コマンドを実行し直す。

ドメイン参加(2節)とWSUSロール導入(4節)は、対象ホストの状態を大きく変える操作である。[変更・ロールバック計画兼記録票](08-change-rollback-plan.md)のとおり、実行直前にVM/ハイパーバイザーのスナップショットを取得しておくと、想定外の失敗時に構築前の状態へ戻せる。

### 冪等性の確認(SIT-02)

`acceptance-check.sh`のような自動判定スクリプトが無いため、同一手順を2回目実行した際の「変更が発生しないこと」は手作業で確認する。1回目実行後と2回目実行後で、少なくとも次を比較する。

```powershell
# 1回目実行後に記録しておく
Get-NetFirewallRule | Where-Object Enabled -eq $true | Measure-Object | Select-Object Count
Get-Service WsusService, W3SVC, windows_exporter, WinRM | Select-Object Name, Status, StartType
(Get-GPO -Name "WSUS-Client-Policy").GpoId
$wsus = Get-WsusServer -Name "wsus-01" -PortNumber 8530
$wsus.GetComputerTargetGroups() | Select-Object Name

# 2回目実行後、上記と件数・状態・IDが一致することを確認する
# ルール件数が増えている、GPOやコンピューターグループが重複作成されている場合はSIT-02をFAILとする
```

### 管理元CIDR・内部ネットワークCIDRでFirewallを絞る

[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)のとおり、WinRM(5986/tcp)は管理元CIDR限定、WSUS管理サイト(8530/tcp)は内部ネットワークCIDR限定、windows_exporter(9182/tcp)は中央Prometheus hostのIPのみ許可する。1節で書き出したCIDRの値で、[構築手順書](05-build-procedure.md)3節・5節のFirewallルール作成コマンドの送信元指定を置き換える。**絞る前に、ハイパーバイザーのコンソールで入れることを確認しておく。**

### 中央監視への統合(フェーズ2、現時点はBLOCKED)

[構築手順書](05-build-procedure.md)10節(`app_node_exporter_targets`への追記、中央host側の`site.yml`再適用)は「済(自動)」の範囲であり、フェーズ1のホスト単体構築とは独立に今すぐ試せる。ただしscrapeが実際に成功するかどうか(`SIT-09`)は、[要件定義書](00-requirements.md)の「未実装」3点のうち、Dockerホストと`wsus-01`の実ネットワーク接続・windows_exporterのFirewall許可先(Dockerホストの実IP)の確定が解消するまでBLOCKEDである。フェーズ1の受け入れ試験(3節)にはこの統合作業を含めない。

## 3. 受け入れ試験

[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)には対象ホスト上で実行すると結果票を自動生成する`acceptance-check.sh`があるが、**本パックには同等のスクリプトは存在しない。** [Windows版パック](../build-package-windows/10-host-bringup-and-acceptance.md)・[AD版パック](../build-package-ad/10-host-bringup-and-acceptance.md)と同じく、手動でのPowerShell実行結果を、日付付きのファイルへ手動で記録する運用とし、自動生成スクリプトは今後の課題とする。

[試験仕様書・結果票](06-test-specification.md)のうち、フェーズ1必須ID(合計28 ID)を対象ホスト`wsus-01`上で実行し、期待結果と実出力を照合しながら判定する。

| 区分 | 対象ID |
| --- | --- |
| 単体・設定確認 | `SUT-01`〜`05` |
| 構築・結合試験 | `SIT-01`〜`08`(`SIT-09`はフェーズ2対象のため対象外。[要件定義書](00-requirements.md)の未実装3点が解消するまで`BLOCKED`のまま) |
| セキュリティ試験 | `SST-01`〜`06` |
| ネットワーク実機検証 | `SNW-01`〜`09`([WSUS版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-wsus.md)を使用) |

判定は実施者が期待結果と実出力を照合して記入するため、**自動判定のような機械的な担保はない。** だからこそ、期待結果と一致しない場合や前提が揃わない場合を安易に`PASS`へ書き換えない。[試験仕様書・結果票](06-test-specification.md)の判定値はこの4つだけである。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

Linux版のような`SKIP`判定は無い。確認していない項目は`NOT RUN`のまま残し、前提が揃わず実行自体ができない項目は理由と解除条件を添えて`BLOCKED`とする。

## 4. 再起動後の永続性

**これがフェーズ1手順書だけでは絶対に確認できない項目である。**

再起動の前後で`Get-CimInstance Win32_OperatingSystem`の`LastBootUpTime`を比較する。値が更新されていなければ、実際には再起動していないと判定し`FAIL`とする。

```powershell
# 再起動前(ベースライン)
Get-CimInstance Win32_OperatingSystem | Select-Object CsName, LastBootUpTime
# この時刻を証跡に控えておく

# 再起動
Restart-Computer -Force
# コンソール経由の場合は次のコマンドでも同等
# shutdown /r /t 0

# 再接続後
Get-CimInstance Win32_OperatingSystem | Select-Object CsName, LastBootUpTime
# ベースラインより新しい時刻に更新されていることを確認する
# 更新されていなければ「そもそも再起動していない」と判定しFAILとする
```

`LastBootUpTime`の更新を確認したら、WSUS関連サービスが自動起動していることと、コンテンツ配信を担うIISが復帰していることを確認する。再起動後にサービスが自動起動しない、Firewallルールが消えている、という不具合は再起動前には見えない。

```powershell
# サービスがAutomaticで起動しているか(WID自体はWsusServiceの起動時に内部で接続されるため単独のサービス確認は不要)
Get-Service WsusService, W3SVC, windows_exporter, WinRM | Select-Object Name, Status, StartType

# IISアプリケーションプール(WsusPool)がStartedで復帰しているか
Get-IISAppPool WsusPool | Select-Object Name, State

# Firewallルールが再起動前と同じ件数・内容で残っているか
Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action, Profile

# WinRM(HTTPS)、WSUS管理サイト、windows_exporterへの疎通
Test-NetConnection -ComputerName localhost -Port 5986
Test-NetConnection -ComputerName localhost -Port 8530
curl.exe -s http://localhost:9182/metrics | Select-String "windows_cs_hostname"

# クリーンアップウィザードのTask Schedulerタスクが残っているか
Get-ScheduledTask -TaskName "WSUS-Cleanup-Weekly"
```

## 5. 24時間 / 72時間の連続稼働

WSUSは「サービスが起動していること」と「同期・クリーンアップが設計どおりのスケジュールで動くこと」が別物であるため、両方を分けて確認する。同期スケジュールはTask Schedulerではなく[構築手順書](05-build-procedure.md)6節で設定したSUSDB上の購読設定(`GetSubscription()`が返すオブジェクト)に保持され、クリーンアップウィザードはTask Schedulerタスク(`WSUS-Cleanup-Weekly`)として保持される。この違いを取り違えないこと。

```powershell
# 同期スケジュール設定がSUSDBに保持されたままか(WsusServiceの再起動・ホスト再起動をまたいでも消えない設計値)
$wsus = Get-WsusServer -Name "wsus-01" -PortNumber 8530
$subscription = $wsus.GetSubscription()
$subscription.SynchronizeAutomatically
$subscription.SynchronizeAutomaticallyTimeOfDay
$subscription.GetLastSynchronizationInfo() | Select-Object Result, EndTime

# クリーンアップウィザードのタスクが有効なまま残っているか
Get-ScheduledTask -TaskName "WSUS-Cleanup-Weekly" | Select-Object TaskName, State
```

Windows Serverには`systemd-run`に相当する常駐実行の仕組みがないため、Task Scheduler(`Register-ScheduledTask`)で定期サンプリングを登録し、切断してもサンプリングが継続する形にする。

```powershell
# WSUS管理サイトへの疎通結果を5分間隔でCSVに記録するタスクを登録する例
# (サンプリング処理自体は本パックに同梱スクリプトが無いため、実施者が用意する)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -Command "& { $ok = (Test-NetConnection -ComputerName localhost -Port 8530 -WarningAction SilentlyContinue).TcpTestSucceeded; Add-Content C:\soak-log.csv ((Get-Date -Format o) + \",\" + $ok) }"'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 24)
Register-ScheduledTask -TaskName "wsus-01-soak" -Action $action -Trigger $trigger -RunLevel Highest
```

サンプリング中は次を記録する。72時間の場合は`RepetitionDuration`を`(New-TimeSpan -Hours 72)`に変更する。

- WSUS管理サイトへの疎通が失敗した回数
- 窓の途中で日次01:00(Asia/Tokyo)の自動同期が実行され、`GetLastSynchronizationInfo()`の`EndTime`が更新されたか(72時間窓であれば複数回更新されるはず)
- `Get-CimInstance Win32_OperatingSystem`の`LastBootUpTime`が窓の途中で変化していないか(変化していれば意図しない再起動)
- コンテンツストア(`D:\WSUS\WSUSContent`)の空き容量が窓の開始時から極端に減っていないか
- `Get-WinEvent -LogName System`、`Get-WinEvent -LogName "Microsoft-Windows-WindowsUpdateClient/Operational"`に予期しないエラーが記録されていないか

窓が終わったら`C:\soak-log.csv`とEvent Logの確認結果を、日付付きの証跡ファイルへ手動でまとめる。この集計・整形を自動化するスクリプトは、3節で述べたとおり本パックには存在せず、今後の課題である。

## 6. 証跡の採録

生成・記入したファイルを**自分で読んでから**コミットする。

- [ ] `FAIL`の項目について、原因を理解している(理解できないまま採録しない)
- [ ] `BLOCKED`の項目について、前提条件と解除条件を本文に残している
- [ ] host名 / IP / 秘密値(ローカルAdministratorの変更後パスワード、証明書秘密鍵)が出ていない。自動マスクの仕組みが無いため、公開する証跡は実施者が手動で置き換える
- [ ] [検証証跡台帳](../evidence/README.md)の該当行を`NOT RUN`から更新した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] [試験仕様書・結果票](06-test-specification.md)の**原本は`NOT RUN`のまま**(上書きしない)

## 7. この手順で埋まらないもの

| 項目 | 追加で必要なもの |
| --- | --- |
| フェーズ2(中央監視統合)一式(`SIT-09`) | [要件定義書](00-requirements.md)の「未実装」3点(Windows対応Ansible role、`compose.yaml`の`monitoring`network拡張、Windows向けログ集約経路)の解消 |
| 複数クライアントでの大規模検証 | `wsus-01`自身の自己登録・承認・適用の一巡を超える範囲であり、`ad-dc01`・`ad-dc02`・`monitor-win-01`等をWSUS管理下に追加する展開は本パックの対象外。発展課題として別途検証環境が必要 |
| WSUS通信のHTTPS化(証明書配布、8531番ポート) | 内部CA(AD証明書サービス)。本パックのラボには存在せず、次点課題 |
| 外部SQL Serverへの移行(系統B)、SSRS連携 | 別途SQL Serverインスタンスと、系統Bを前提とした構築手順(本パックは差分のみ記載) |
| レプリカ/ダウンストリームWSUSサーバーによる階層化構成 | 2台目以降のWSUSサーバーホストと、上位/下位関係の設計(本パックは対象外) |
| 自己署名でない実TLS証明書(WinRM HTTPS用) | 内部CA、または独自ドメインとLet's Encrypt相当の仕組み |
| 組織DNS / 上流firewall | 実際の組織ネットワーク |
| クラウドの実費・従量課金の実績 | クラウドアカウントと予算アラートの設定 |
| 物理層(L1) | スイッチ、ケーブル、VLAN対応機器 |

**フェーズ1のホスト1台では埋まらないものを、埋まったことにしない。** フェーズ2は、恒久ホストをいくら用意しても「未実装」3点の解消なしには埋まらない。複数クライアントでの大規模検証・HTTPS化も、本書の手順の延長では確認できない対象外のままである。

## 8. フェーズ1の通し再試験(`NOT RUN`)

2026-09-07のフェーズ1は総合判定`FAIL`で終わっている。[2026-09-08の切り分け](../evidence/2026-09-08-wsus-sit04-sit06-root-cause.md)で`SIT-06`・`SIT-04`の原因を特定し手順書へ反映したが、**修正後の手順で通しの再実行をしていないため判定は据え置き**である。本節はその再試験の進め方をまとめる。

### 8.1 何を再試験するのか

| 区分 | 対象ID | 理由 |
| --- | --- | --- |
| 期待結果そのものが変わった | `SIT-04`、`SIT-06` | `SIT-04`は自己登録先が`Servers`から`Pilot`へ、`SIT-06`は絞り込み0件チェックが期待結果へ加わった |
| 手順が書き換わった節を通る | `SIT-02`、`SIT-05`、`SIT-07` | [構築手順書](05-build-procedure.md)の7・8・9節が書き換わった。`SIT-02`は3・4・7・8節の再実行そのもの |
| 手順は変わらないが通しの一部 | `SIT-01`、`SIT-03`、`SIT-08` | 通しで再実行する以上、これらも新しく採り直す |
| 影響がないことの再確認 | `SUT-01`〜`05`、`SST-01`〜`06`、`SNW-01`〜`09` | GPOの`TargetGroup`変更がこれらへ波及しないことを確認する |
| 対象外 | `SIT-09` | フェーズ2。[要件定義書](00-requirements.md)の未実装3点が解消するまで`BLOCKED`のまま |

**2026-09-07の`PASS`を再試験の結果として流用しない。** 手順が変わった以上、変わった手順で出した結果だけがその手順の実績である。

### 8.2 開始点を選ぶ

| 開始点 | 操作 | 言えること | 言えないこと |
| --- | --- | --- | --- |
| チェックポイント`pre-wsus-role`へ巻き戻す | `Restore-VMCheckpoint -VMName 'wsus-01' -Name 'pre-wsus-role'` | ドメイン参加済みの状態からWSUSロール導入以降を丸ごと再実行できる。初回全同期もやり直しになる | ドメイン参加(`SUT-01`)自体の再実行にはならない |
| 新規VMを作り直す | 0〜2節をそのまま実行 | フェーズ1の全項目を最初から採り直せる | 評価版ISOの期限、ホストの空きメモリとディスクを追加で消費する |
| 巻き戻さず現状から | 9節以降だけ再実行 | `SIT-04`・`SIT-06`の修正後の挙動は確認できる | **`SIT-01`〜`SIT-03`は「初回」ではないため再試験の実績にならない。** 総合判定を動かす根拠には使えない |

`pre-wsus-role`は2026-09-07 15:00:54に取得したチェックポイントで、[作業結果報告書](../evidence/2026-09-07-work-result-SM-WSUS-001.md)がロールバック手段として記録している。**ただし同報告書は「1世代維持(新規取得→旧世代統合)」の運用も記録しており、現存するとは限らない。** 始める前に実物を確認すること。

```powershell
# ホストPC(Windows 11 Pro)側で実行する
Get-VMCheckpoint -VMName 'wsus-01' | Select-Object Name, CreationTime, ParentCheckpointName
```

巻き戻す前に、現在の状態のチェックポイントを別名で取っておく。巻き戻しは`wsus-01`側の状態だけを戻すもので、`ad-dc02`上のGPO(`TargetGroup=Pilot`へ変更済み)は戻らない。これは再試験にとっては都合がよく、修正後のGPOのまま構築をやり直せる。

### 8.3 事前条件 — メモリを先に確かめる

[切り分け結果票](../evidence/2026-09-08-wsus-sit04-sit06-root-cause.md)の残存リスクは、**「この状態で全同期を開始すると`WsusService`が停止する」**と記録している。記録された値は次のとおり。

| 項目 | 2026-09-08の記録値 |
| --- | --- |
| ホストPC搭載メモリ | 16GB |
| `ad-dc02` | 4GB固定 |
| `lab-base01` | 2GB固定 |
| `wsus-01` | 動的(上限8GB)。実割り当ては1.89GB |
| ホストの空き | 1.6GB |

`wsus-01`は本パックの最小構成として**8GB**を要求する(0節)。`ad-dc02`は`wsus-01`のドメイン参加先で`SUT-01`・`SNW-03`・`SIT-04`が依存するため停止できない。空けられるのは`lab-base01`の2GBだけであり、**上の記録値からの単純計算では`wsus-01`へ回せるのは数GB程度**にとどまる。これは概算であって実測ではないため、再試験の前に実際の値で確かめる。

```powershell
# ホストPC(Windows 11 Pro)側で実行する
Get-VM | Select-Object Name, State, MemoryAssigned, MemoryMinimum, MemoryMaximum, DynamicMemoryEnabled
Get-Counter '\Memory\Available MBytes'
Get-VHD (Get-VMHardDiskDrive -VMName 'wsus-01').Path | Select-Object Path, Size, FileSize
```

- `lab-base01`を停止した状態で`wsus-01`を起動し、**`MemoryAssigned`が8GBに届くか**を見る(`MemoryMaximum`は上限値であって割り当て実績ではない)
- 届かないなら、ホストのメモリ増設なしに全同期を完走できるかを先に見極める

**8GBが割り当たらないまま全同期を始めない。** 途中で`WsusService`が止まれば、再試験そのものが計測不能になる。

### 8.4 実施順

1. 8.3の事前条件を満たす。`ad-dc02`が稼働していることも確認する
2. 8.2で開始点を決め、巻き戻す前に現在の状態のチェックポイントを取る
3. [構築手順書](05-build-procedure.md)を0節から順に実行する。`Restore-VMCheckpoint`で`pre-wsus-role`へ戻した場合は、そのチェックポイントに3節(Firewall・RDPの締め)が含まれているかを`Get-NetFirewallProfile`と`fDenyTSConnections`で確認し、未適用なら3節から、適用済みなら4節から実行する。**どちらだったかを証跡に書く**
4. 9.2節の実行直前検証(分類・製品・グループのいずれかが0件なら`throw`)が働くことを確認する。**ここで`throw`したら、それ自体が2026-09-07の再現である**
5. [試験仕様書](06-test-specification.md)のIDを判定し、日付付きの証跡ファイルへ記録する(8.5)

### 8.5 SIT-06の再現試験との関係

切り分け結果票は、絞り込みが空になった原因の最有力候補を「8節と9節の間に走った初回全同期」とし、確定のための再現手順を**ケースA(手順書どおりの逐次実行)**と**ケースB(2026-09-07と同じ、同期実行中のルール作成)**の2つに分けている。

**再試験を手順書どおりに通すと、その過程がそのままケースAになる。** 8節でルールを作り、9節で初回全同期を完走させ、9.2節の実行直前検証で分類・製品の件数を読み戻す順序だからである。**ケースAのために別途1時間を用意する必要はない。**

| 結果 | 意味 |
| --- | --- |
| 9.2節の読み戻しが0件 → `throw` | ケースAで再現。全同期そのものが引き金 |
| 読み戻しが分類2件・製品1件・グループ1件 → `ApplyRule()`が9.2節で事前に数えた`$expected`と同じ件数で完了 | ケースAでは再現しない。引き金は「同期中のルール作成」側にある可能性が残る。参考として2026-09-08時点(同期済み557件)の`$expected`は87件だったが、再同期後の件数はこれと一致するとは限らない |

**ケースBは再試験とは目的が逆である。** 再試験は`PASS`を取りに行き、ケースBはあえて壊れる条件を作る。同じ1回の全同期で両方は測れないので、**先に再試験を通してフェーズ1の判定を確定させ、ケースBはその後に別サイクルで行う**。ケースBでルールが壊れても、9.2節の実行直前検証が`throw`して承認事故を止める。

### 8.6 既知の落とし穴

再試験中に踏み直しやすいものだけを挙げる。全量は[2026-09-07の誤り一覧](../evidence/2026-09-07-wsus-build-validation.md#実機で見つけた手順書の誤り)と[2026-09-08の追加分](../evidence/2026-09-08-wsus-sit04-sit06-root-cause.md)にある。

| 落とし穴 | 対処 |
| --- | --- |
| `Stop-Service BITS -Force`が`WsusService`を巻き添えで止める(`WsusService`は`BITS`の依存サービス)。同期がDB上`Running`のまま固まる | `WsusService`を開始してから`StopSynchronization()`で解除する |
| `Set-GPRegistryValue`等のGPO操作がWinRMセッション越しに`0x80072020`で失敗する(ダブルホップ) | コンソール/RDPの対話セッション、またはDC上で実行する |
| `Pilot`グループへの手動追加が次回のクライアント登録で消える | 手動追加しない。GPOの`TargetGroup`に`Pilot`を申告させる |
| BOM無しUTF-8で保存したスクリプトの日本語リテラル比較が成立しない | ロケール非依存のGUIDと`UpdateScope`で対象を選ぶ |
| 子グループへ明示的に「未承認」を書くと親からの継承を打ち消す | 拒否解除に`Approve(NotApproved, <子グループ>)`を使わない |

### 8.7 記録先

[試験仕様書](06-test-specification.md)の原本は`NOT RUN`のまま上書きしない。結果は`docs/evidence/YYYY-MM-DD-wsus-build-validation.md`(ネットワークは[WSUS版テンプレート](../evidence/templates/network-host-validation-wsus.md))へ新規に作り、[検証証跡台帳](../evidence/README.md)へ行を追加する。2026-09-07の証跡は当時の記録として残し、上書きしない。

**総合判定を`PASS`にできるのは、`SIT-01`〜`SIT-08`を修正後の手順で通し、実出力と期待結果の照合を証跡へ残したときだけである。** 原因が分かったことと、直したことと、直した手順が通ることは別である。
