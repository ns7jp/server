# 引き渡し対象ホストの立ち上げと受け入れ試験

これまでの検討はすべて[要件定義書](00-requirements.md)から[試験仕様書](06-test-specification.md)までの**設計・手順書止まり**であり、`monitor-win-01` に相当する実ホストは一度も構築されていません。[Linux版](../build-package/10-host-bringup-and-acceptance.md)には使い捨てCI runnerとWSL2による代替実測がありましたが、Windows Serverにはその代替がなく、次の項目はすべて `NOT RUN` のまま残っています。

- フェーズ1(ホスト単体構築)の新規構築・冪等性・IIS疎通・サービス停止復旧演習・バックアップ復元・実ホストnetwork(WIT-01, WIT-02, WIT-04, WIT-08, WIT-09, WIT-10、WNW-01〜09、WST-01〜06)
- ホスト再起動後の永続性
- 24時間 / 72時間の連続稼働
- 実DNS / 自己署名でない実TLS証明書
- インターネット越しのWindows Defender Firewall(実管理端末からの到達性)
- フェーズ2(中央監視統合)一式(WIT-03, WIT-05, WIT-06, WIT-07, WIT-11)

**フェーズ1の範囲は、1台の検証用ホストを用意すると大半が一度に埋まります。** これに対してフェーズ2は、検証用ホストの有無に関わらず[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible role、`compose.yaml` の `monitoring` networkの `internal: true` 制約、Grafana Alloy for Windows未導入)が解消しない限り埋まりません。**逆に言えば、検証用ホストが無い限りフェーズ1の項目はどれも埋まりません。**

この文書は、フェーズ1のホストを「用意してから証跡が出るまで」を最短で通すための手順です。フェーズ2の統合手順は[構築手順書](05-build-procedure.md)5節、統合後の判定基準は[試験仕様書](06-test-specification.md)を参照してください。

## 0. 何を用意するか

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| Azure / AWS EC2などのクラウドWindows Serverインスタンス | 従量課金(OSライセンス込みのため同スペックのLinuxより高め) | 実IP・実DNSがあり、インターネット越しのFirewall検証ができる |
| 評価版ISO(180日間有効)によるHyper-V/VMware上のVM | 0円(評価期間限定) | 費用をかけずに機能検証ができるが、期限管理が必要。実IP/実DNSは無い |
| 社内のボリュームライセンス/MSDN経由のWindows Server | 既存契約次第 | 実務に近いが本パックの対象外の契約管理が必要 |

最小構成の目安は **2 vCPU / メモリ 4GB / ディスク 60GB** です。監視スタック本体(Prometheus / Grafana / Loki / Alertmanager)はWindows上では動かしませんが、Windows Server 2022(Desktop Experience基準)自体の前提要件がUbuntuより高いため、この目安を下回らないようにします。

Linux版では無償のVirtualBox VMが代替案として使えましたが、**Windows Serverはライセンス費用が発生するためこの代替が成立しません。** 評価版ISOは費用こそかかりませんが、180日の期限管理と、実IP/実DNSを使った検証(WNW-03、WNW-09相当)ができない制約が残ります。実IP/実DNSでの検証まで行う場合は、クラウドWindows Serverインスタンスを選びます。

OSは[基本設計書](01-basic-design.md)のとおり **Windows Server 2022 Standard(Desktop Experience基準)**とします。Server Coreへの対応は検討課題であり、本パックの手順は基準VM(Desktop Experience)での実行を前提にしています。OS系統は系統A(ワークグループ)を既定とし、系統B(ADドメイン参加)は検証用ADドメインが別途必要なため、本パックの手順だけでは検証できません(7節参照)。

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておきます。あとから思い出せません。

| 項目 | 記入 |
| --- | --- |
| 対象ホスト(用途・OS・スペック) | |
| OS系統(系統A: ワークグループ / 系統B: ADドメイン参加) | |
| 管理元IP / CIDR(WinRM・一時RDP許可の送信元) | |
| WinRM HTTPS証明書の準備方法(系統A: 自己署名 / 系統B: 内部CA) | |
| 管理端末側にPowerShell 7とWinRM設定が揃っているか | |
| 再起動してよい時間帯 | |
| 接続不能になったときの復旧手段(ハイパーバイザーコンソール等) | |
| 停止許容時間 | |
| RDPを一時的に有効化する運用可否と、その場合の解除担当 | |

**WinRM(HTTPS)だけに依存しないでください。** [ポート表](03-parameter-sheet.md)のとおりRDPは既定Disableのため、WinRM接続に失敗すると通常の経路でログインできなくなります。ハイパーバイザーのコンソール(Hyper-VのVMConnect、クラウドのシリアルコンソール、VMwareのリモートコンソール等)に入れることを、Firewallを締める前に必ず確認してください。

## 2. 構築

[構築手順書](05-build-procedure.md)をそのまま実行します。Windows対応Ansible roleは存在しないため(要件定義書「未実装」参照)、ここは**すべて「済(手動)」のPowerShell実行**であり、`site.yml` のような自動化された経路ではありません。1節で決めた系統(A/B)に応じて、証明書・Firewallプロファイル・時刻同期先の各手順を読み替えます。

```powershell
# 対象ホストのビルド番号を先に記録する(証跡の必須項目)
Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsBuildNumber

# 05-build-procedure.md の 0〜4節を順に実行
# 0. 作業前確認 / 1. 管理端末の準備 / 2. 初期設定とWinRM有効化
# 3. Windows Defender FirewallとRDPの締め / 4. IIS・windows_exporter・Backup導入
```

### 冪等性の確認(WIT-02)

`acceptance-check.sh` のような自動判定スクリプトが無いため、同一手順を2回目実行した際の「変更が発生しないこと」は手作業で確認します。1回目実行後と2回目実行後で、少なくとも次を比較します。

```powershell
# 1回目実行後に記録しておく
Get-NetFirewallRule | Where-Object Enabled -eq $true | Measure-Object | Select-Object Count
Get-Service windows_exporter, W3SVC, WinRM | Select-Object Name, Status, StartType

# 2回目実行後、上記と件数・状態が一致することを確認する
# ルール件数が増えている、サービスが再作成されている場合はWIT-02をFAILとする
```

### 管理元CIDRでWinRM/IISを絞る

[ポート表](03-parameter-sheet.md)のとおり、WinRM(5986/tcp)は管理元CIDR限定、windows_exporter(9182/tcp)は中央Prometheus hostのIPのみ許可します。1節で書き出した管理元CIDRを使い、[構築手順書](05-build-procedure.md)3節のFirewallルール作成コマンドの `RemoteAddress` を実際の値に置き換えます。**絞る前に、ハイパーバイザーのコンソールで入れることを確認しておいてください。**

### 中央監視への統合(フェーズ2、現時点はBLOCKED)

[構築手順書](05-build-procedure.md)5節(`app_node_exporter_targets` への追記、中央host側の `ansible-playbook site.yml` 再適用)は「済(自動)」の範囲であり、フェーズ1のホスト単体構築とは独立に、中央host側の設定だけなら今すぐ試せます(WUT-02)。ただしscrapeが実際に成功するかどうか(WIT-03)は、[要件定義書](00-requirements.md)の「未実装」3点のうち `compose.yaml` の `monitoring` networkの `internal: true` 制約が解消するまでBLOCKEDです。フェーズ1の受け入れ試験(3節)にはこの統合作業を含めません。

## 3. 受け入れ試験

Linux版には対象ホスト上で実行すると結果票を自動生成する `acceptance-check.sh` がありますが、**本パックには同等のスクリプトは存在しません。** 本パックでは手動でのPowerShell実行結果を、日付付きのファイルへ手動で記録する運用とし、Linux版のような自動生成スクリプトは今後の課題とします。

[試験仕様書](06-test-specification.md)のうち、フェーズ1必須IDに対応する試験を対象ホスト上で実行し、期待結果と実出力を照合しながら判定します。

| 区分 | 対象ID |
| --- | --- |
| 単体・設定確認 | WUT-01, WUT-02, WUT-05(WUT-03, WUT-04も導入時に実施済みのはず) |
| 構築・結合試験 | WIT-01, WIT-02, WIT-04, WIT-08, WIT-09, WIT-10 |
| セキュリティ試験 | WST-01〜WST-06 |
| ネットワーク実機検証 | WNW-01〜09([Windows版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-windows.md)を使用) |

判定は実施者が期待結果と実出力を照合して記入するため、**自動判定のような機械的な担保はありません。** だからこそ、期待結果と一致しない場合や前提が揃わない場合を安易に `PASS` へ書き換えないでください。[試験仕様書](06-test-specification.md)の判定値はこの4つだけです。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

Linux版のような `SKIP` 判定はありません。確認していない項目は `NOT RUN` のまま残し、前提が揃わず実行自体ができない項目は理由と解除条件を添えて `BLOCKED` とします。

## 4. 再起動後の永続性

**これがフェーズ1手順書だけでは絶対に確認できない項目です。**

再起動の前後で `Get-CimInstance Win32_OperatingSystem` の `LastBootUpTime` を比較します。値が更新されていなければ、実際には再起動していないと判定し `FAIL` とします。

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

`LastBootUpTime` の更新を確認したら、次を続けて確認します。再起動後にサービスが自動起動しない、Firewallルールが消えている、という不具合は再起動前には見えません。

```powershell
# サービスがAutomaticで起動しているか
Get-Service windows_exporter, W3SVC, WinRM | Select-Object Name, Status, StartType

# Firewallルールが再起動前と同じ件数・内容で残っているか
Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action, Profile

# WinRM(HTTPS)、IIS、windows_exporterへの疎通
Test-NetConnection -ComputerName localhost -Port 5986
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost/healthz.html
curl.exe -s http://localhost:9182/metrics | Select-String "windows_cs_hostname"

# バックアップのTask Schedulerタスクが残っているか
Get-ScheduledTask | Where-Object TaskName -like "*Backup*"
```

## 5. 24時間 / 72時間の連続稼働

Windows Serverには `systemd-run` に相当する常駐実行の仕組みがないため、Task Scheduler(`Register-ScheduledTask`)で定期サンプリングを登録し、切断してもサンプリングが継続する形にします。

```powershell
# サンプリングを5分間隔でCSVに記録するタスクを登録する例
# (サンプリング処理自体は本パックに同梱スクリプトが無いため、実施者が用意する)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -Command "& { Add-Content C:\soak-log.csv ((Get-Date -Format o) + \",\" + (curl.exe -s -o NUL -w \"%{http_code}\" http://localhost/healthz.html)) }"'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 24)
Register-ScheduledTask -TaskName "server-monitor-soak" -Action $action -Trigger $trigger -RunLevel Highest
```

サンプリング中は次を記録します。72時間の場合は `RepetitionDuration` を `(New-TimeSpan -Hours 72)` に変更します。

- health用エンドポイントが200でなかった回数
- `Get-CimInstance Win32_OperatingSystem` の `LastBootUpTime` が窓の途中で変化していないか(変化していれば意図しない再起動)
- `Get-WinEvent -LogName System` に予期しないエラーが記録されていないか

窓が終わったら `C:\soak-log.csv` とEvent Logの確認結果を、日付付きの証跡ファイルへ手動でまとめます。この集計・整形を自動化するスクリプトは、3節で述べたとおり本パックには存在せず、今後の課題です。

## 6. 証跡の採録

生成・記入したファイルを**自分で読んでから**コミットします。

- [ ] `FAIL` の項目について、原因を理解している(理解できないまま採録しない)
- [ ] `BLOCKED` の項目について、前提条件と解除条件を本文に残している
- [ ] host名 / IP / 秘密値(証明書秘密鍵、パスワード)が出ていない。自動マスクの仕組みが無いため、公開する証跡は実施者が手動で置き換える
- [ ] [検証証跡台帳](../evidence/README.md)の該当行を `NOT RUN` から更新した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] [試験仕様書](06-test-specification.md)の**原本は `NOT RUN` のまま**(上書きしない)

## 7. この手順で埋まらないもの

| 項目 | 追加で必要なもの |
| --- | --- |
| フェーズ2(中央監視統合)全体(WIT-03, WIT-05, WIT-06, WIT-07, WIT-11) | [要件定義書](00-requirements.md)の「未実装」3点(Windows対応Ansible role、`compose.yaml` の `monitoring` network拡張、Grafana Alloy for Windows導入)の解消 |
| 系統B(ADドメイン参加)の実機検証 | 検証用ADドメイン環境(構築は本パックの対象外) |
| 自己署名でない実TLS証明書 | 内部CA、または独自ドメインとLet's Encrypt相当の仕組み |
| 組織DNS / 上流firewall | 実際の組織ネットワーク |
| バックアップの別ホストへの復元(WIT-09の完全な形) | 2台目のWindowsホスト |
| クラウドの実費・従量課金の実績 | クラウドアカウントと予算アラートの設定 |
| 物理層(L1) | スイッチ、ケーブル、VLAN対応機器 |

**フェーズ1のホスト1台では埋まらないものを、埋まったことにしないでください。** フェーズ2は、恒久ホストをいくら用意しても「未実装」3点の解消なしには埋まりません。
