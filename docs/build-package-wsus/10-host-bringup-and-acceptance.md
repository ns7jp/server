# 引き渡し対象ホストの立ち上げと受け入れ試験

これまでの検討はすべて[要件定義書](00-requirements.md)から[ネットワーク実機検証手順](09-network-validation-procedure.md)までの**設計・手順書止まり**であり、`wsus-01`に相当する実ホストは一度も構築されていない。[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)には使い捨てCI runnerとWSL2による代替実測があったが、Windows Serverにはその代替がなく、次の項目はすべて`NOT RUN`のまま残っている。

- フェーズ1(ホスト単体構築)のドメイン参加・WSUSロール導入・初回同期・GPO適用と自己登録・承認と適用・自動承認ルール・クリーンアップウィザード・バックアップ/リストア・冪等性・実ホストnetwork(`SUT-01`〜`05`、`SIT-01`〜`08`、`SST-01`〜`06`、`SNW-01`〜`09`)
- ホスト再起動後の永続性
- 24時間 / 72時間の連続稼働
- 実DNS / 自己署名でない実TLS証明書(WinRM HTTPS用)
- インターネット越しのWindows Defender Firewall(実管理端末からの到達性)
- フェーズ2(中央監視統合)一式(`SIT-09`)

**フェーズ1の範囲は、1台の検証用ホスト(`wsus-01`)を用意すると大半が一度に埋まる。** これに対してフェーズ2は、検証用ホストの有無に関わらず[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible role、`compose.yaml`の`monitoring`ネットワークの`internal: true`制約、Windows向けログ集約経路)が解消しない限り埋まらない。**逆に言えば、検証用ホストが無い限りフェーズ1の項目はどれも埋まらない。**

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

[構築手順書](05-build-procedure.md)10節(`app_node_exporter_targets`への追記、中央host側の`site.yml`再適用)は「済(自動)」の範囲であり、フェーズ1のホスト単体構築とは独立に今すぐ試せる。ただしscrapeが実際に成功するかどうか(`SIT-09`)は、[要件定義書](00-requirements.md)の「未実装」3点のうち`compose.yaml`の`monitoring`ネットワークの`internal: true`制約が解消するまでBLOCKEDである。フェーズ1の受け入れ試験(3節)にはこの統合作業を含めない。

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
