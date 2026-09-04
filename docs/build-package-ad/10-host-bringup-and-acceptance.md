# 引き渡し対象ホストの立ち上げと受け入れ試験

> 💡 **初めて読む方へ**: この文書は「まだ確認していない項目」を、1台の実サーバーで一気に埋めるための手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#10-立ち上げと受け入れ試験)を参照してください。

これまでの検討はすべて[要件定義書](00-requirements.md)から[ネットワーク実機検証手順](09-network-validation-procedure.md)までの**設計・手順書止まり**であり、`ad-dc01`に相当する実ホストは一度も構築されていません。[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)には使い捨てCI runnerとWSL2による代替実測がありましたが、Windows Serverにはその代替がなく、次の項目はすべて`NOT RUN`のまま残っています。

- フェーズ1(ホスト単体構築)の新規フォレスト作成・初回DC昇格・必須サービス確認・AD統合DNS・OU/GPOポリシー適用・FSMO確認・バックアップ取得・ADごみ箱復元・サービス停止復旧演習・再実行安全性・実ホストnetwork(AUT-01〜04、AIT-01〜08、AIT-10、AIT-11、AST-01〜08、ANW-01〜09)
- ホスト再起動後の永続性
- 24時間 / 72時間の連続稼働
- 実DNS / 自己署名でない実TLS証明書(WinRM HTTPS用)
- インターネット越しのWindows Defender Firewall(実管理端末からの到達性)
- フェーズ2(中央監視統合)一式(AIT-09)

**フェーズ1の範囲は、1台の検証用ホスト(`ad-dc01`)を用意すると大半が一度に埋まります。** これに対してフェーズ2は、検証用ホストの有無に関わらず[要件定義書](00-requirements.md)に記載した「未実装」3点(Windows対応Ansible role、Dockerホストと`ad-dc01`間の実接続・windows_exporterのFirewall許可の未確立、Windows向けログ集約経路)が解消しない限り埋まりません。**逆に言えば、検証用ホストが無い限りフェーズ1の項目はどれも埋まりません。**

この文書は、フェーズ1のホストを「用意してから証跡が出るまで」を最短で通すための手順です。フェーズ2の統合手順は[構築手順書](05-build-procedure.md)、統合後の判定基準は[試験仕様書・結果票](06-test-specification.md)を参照してください。

## 0. 何を用意するか

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| Azure / AWS EC2などのクラウドWindows Serverインスタンス | 従量課金(OSライセンス込みのため同スペックのLinuxより高め) | 実IP・実DNSがあり、インターネット越しのFirewall検証ができる |
| 評価版ISO(180日間有効)によるHyper-V/VMware上のVM | 0円(評価期間限定) | 費用をかけずにフォレスト作成・DC昇格の機能検証ができるが、期限管理が必要。実IP/実DNSは無い |
| 社内のボリュームライセンス/MSDN経由のWindows Server | 既存契約次第 | 実務に近いが本パックの対象外の契約管理が必要 |

最小構成の目安は**2 vCPU / メモリ4GB / ディスク60GB**です。[Windows版パック](../build-package-windows/10-host-bringup-and-acceptance.md)の`monitor-win-01`と同じ目安であり、これを下回らないようにします。Active Directory Domain Services自体はこのスペックで動作しますが、System Stateバックアップの取得やAD統合DNSの動作まで含めて確認するため、ディスクは60GBを確保します。

[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)では無償のVirtualBox VMが代替案として使えましたが、**Windows Serverはライセンス費用が発生するためこの代替が成立しません。** 評価版ISOは費用こそかかりませんが、180日の期限管理と、実IP/実DNSを使った検証(ANW-03、ANW-09相当)ができない制約が残ります。実IP/実DNSでの検証まで行う場合は、クラウドWindows Serverインスタンスを選びます。

OSは[基本設計書](01-basic-design.md)のとおり**Windows Server 2022 Standard(Desktop Experience基準)**とします。Server Coreへの対応は検討課題であり、本パックの手順は基準VM(Desktop Experience)での実行を前提にしています。対象は本パックが構築する最初のドメインコントローラー`ad-dc01`1台のみであり、2台目のDC追加によるレプリケーション実測は本パックの範囲に含みません(7節参照)。

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておきます。あとから思い出せません。

| 項目 | 記入 |
| --- | --- |
| 対象ホスト(用途・OS・スペック) | |
| ドメインFQDN/NetBIOS名の最終決定(既定値`corp.example.test` / `CORP`を使うか、環境ごとに変更するか) | |
| 内部ネットワークCIDRの範囲決定(将来のドメインメンバーが所属しうる範囲) | |
| 管理元IP / CIDR(WinRM・一時RDP許可の送信元) | |
| DSRMパスワードの準備方法(秘密値台帳での生成・保管・受け渡し手順) | |
| WinRM HTTPS証明書の準備方法(自己署名 / 内部CA) | |
| 管理端末側にPowerShell 7とWinRM設定が揃っているか | |
| 再起動してよい時間帯 | |
| 接続不能になったときの復旧手段(ハイパーバイザーコンソール等) | |
| 停止許容時間 | |
| RDPを一時的に有効化する運用可否と、その場合の解除担当 | |

**WinRM(HTTPS)だけに依存しないでください。** [パラメータシート](03-parameter-sheet.md)のとおりRDPは既定Disableのため、WinRM接続に失敗すると通常の経路でログインできなくなります。ハイパーバイザーのコンソール(Hyper-VのVMConnect、クラウドのシリアルコンソール、VMwareのリモートコンソール等)に入れることを、Firewallを締める前に必ず確認してください。

さらにADでは、[要件定義書](00-requirements.md)の前提条件のとおり**初回のフォレスト作成(`Install-ADDSForest`)のみ、ハイパーバイザーのコンソールから対象VMへ直接ログオンして行います。** WinRM経由の操作にどれだけ慣れていても、この最初の一歩だけはコンソールアクセスが必須であることを、作業開始前に確認しておいてください。

## 2. 構築

[構築手順書](05-build-procedure.md)をそのまま実行します。Windows対応Ansible roleは存在しないため(要件定義書「未実装」参照)、ここは**すべて「済(手動)」のPowerShell実行**であり、`site.yml`のような自動化された経路ではありません。1節で決めたドメインFQDN/NetBIOS名、内部ネットワークCIDR、DSRMパスワードの準備方法を使って、各コマンドの引数を実際の値に置き換えます。

```powershell
# 対象ホストのビルド番号を先に記録する(証跡の必須項目)
Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsBuildNumber
```

### フォレスト作成前のスナップショットを必ず取得する

`Install-ADDSForest`によるフォレスト・ドメインの作成は、[構築手順書](05-build-procedure.md)に記す一連の手順の中で**唯一、取り消しの効かない一回限りの操作**です。実行して昇格処理(自動再起動を含む)が完了してしまうと、そのVMを未構築状態へ戻す手段はOS標準機能の範囲には無く、[変更・ロールバック計画](08-change-rollback-plan.md)が最優先手段として挙げるのはVM/ハイパーバイザーのスナップショットからの復元です。

そのため、`Install-ADDSForest`を実行する**直前**に、ハイパーバイザーのスナップショットを必ず取得してください。取得のタイミングを誤ると(実行後に取得してしまうと)、スナップショット自体が「フォレスト作成後」の状態になり、ロールバック手段として機能しません。

- [ ] `Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools`の完了後、`Install-ADDSForest`の実行前にスナップショットを取得した
- [ ] スナップショット名に日時とホスト名を含め、後から取得タイミングを識別できるようにした
- [ ] スナップショットからの復元手順を、実行者自身がこの時点で確認した(復元できるはずという想定のまま先に進まない)

スナップショット取得後、[構築手順書](05-build-procedure.md)の手順に沿ってフォレストを作成します。

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment
$SafeModePwd = Read-Host -AsSecureString "DSRM Administratorパスワードを入力"
Install-ADDSForest -DomainName "corp.example.test" -DomainNetbiosName "CORP" -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns:$true -SafeModeAdministratorPassword $SafeModePwd -Force:$true
```

`-ForestMode`/`-DomainMode`に指定する`WinThreshold`はWindows Server 2016機能レベルを指す名称であり、Windows Server 2022という値は存在しません。詳しい理由は[詳細設計書](02-detailed-design.md)を参照してください。

自動再起動後、自ホストのDNSクライアント設定を確認します。

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4
Set-DnsClientServerAddress -InterfaceAlias "イーサネット" -ServerAddresses 127.0.0.1
```

FSMO役割がすべて`ad-dc01`に存在することを確認します(AIT-05)。

```powershell
netdom query fsmo
```

### 再実行安全性の確認(AIT-11)

[Linux版](../build-package/10-host-bringup-and-acceptance.md)・[Windows版](../build-package-windows/10-host-bringup-and-acceptance.md)では、同じ構築手順を2回適用して`changed`が増えないこと(冪等性)を確認していました。AIT-11はこれとは性質が異なります。フォレスト作成は上記のとおり取り消しの効かない一回限りの操作であり、「2回目の適用で変更が0件になること」を確認する対象ではありません。AIT-11が確認するのは、**既に昇格済みのDCに対して昇格コマンドを誤って再実行してしまった場合に、安全に失敗し既存ドメインを破壊しないこと**、つまり誤操作耐性です。

既に昇格済みの`ad-dc01`に対して、次のコマンドを誤って再実行した場合の挙動を確認します。実行前に必ずスナップショットを取得してください。

```powershell
Install-ADDSForest -DomainName "corp.example.test" -DomainNetbiosName "CORP" -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns:$true -SafeModeAdministratorPassword $SafeModePwd -Force:$true
```

期待結果は、既存のフォレスト・ドメインが検出され、明確なエラーで処理が中断されることです。既存の`ntds.dit`が上書きされる、ドメインオブジェクトが破壊される、といった事態が起きた場合はAIT-11を`FAIL`とします。

### 管理元CIDR・内部ネットワークCIDRでFirewallを絞る

[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)のとおり、WinRM(5986/tcp)は管理元CIDR限定、AD DS関連の自動生成ルール群(LDAP/Kerberos/DNS/SMB等)は内部ネットワークCIDR限定、windows_exporter(9182/tcp)は中央Prometheus hostのIPのみ許可します。1節で書き出した管理元CIDR・内部ネットワークCIDRの値を使い、[構築手順書](05-build-procedure.md)のFirewallルール調整手順の送信元指定を実際の値に置き換えます。**絞る前に、ハイパーバイザーのコンソールで入れることを確認しておいてください。**

### 中央監視への統合(フェーズ2、現時点はBLOCKED)

[構築手順書](05-build-procedure.md)(`app_node_exporter_targets`への追記、中央host側の`ansible-playbook site.yml`再適用)は「済(自動)」の範囲であり、フェーズ1のホスト単体構築とは独立に、中央host側の設定だけなら今すぐ試せます。ただしscrapeが実際に成功するかどうか(AIT-09)は、Prometheusコンテナが`monitoring`(`internal: true`)に加えて非internalなbridge network`host-access`にも接続され、`host-access`経由のegress自体はnftablesルール確認済みで機能する(`internal: true`単体は妨げにならない)ことを踏まえても、Dockerホストと`ad-dc01`間の実L3接続(本ラボは全ホストRFC 5737の例示用アドレス`192.0.2.0/24`を使用しており未確立)とwindows_exporterのFirewall許可(Dockerホストの実IPに対する設定が必要)が[要件定義書](00-requirements.md)記載のとおりいずれも`NOT SET`のままであるためBLOCKEDです。フェーズ1の受け入れ試験(3節)にはこの統合作業を含めません。

## 3. 受け入れ試験

[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)には対象ホスト上で実行すると結果票を自動生成する`acceptance-check.sh`がありますが、**本パックには同等のスクリプトは存在しません。** [Windows版パック](../build-package-windows/10-host-bringup-and-acceptance.md)と同じく、手動でのPowerShell実行結果を、日付付きのファイルへ手動で記録する運用とし、自動生成スクリプトは今後の課題とします。

[試験仕様書・結果票](06-test-specification.md)のうち、フェーズ1必須ID(合計31 ID)を対象ホスト`ad-dc01`上で実行し、期待結果と実出力を照合しながら判定します。

| 区分 | 対象ID |
| --- | --- |
| 単体・設定確認 | AUT-01, AUT-02, AUT-03, AUT-04 |
| 構築・結合試験 | AIT-01, AIT-02, AIT-03, AIT-04, AIT-05, AIT-06, AIT-07, AIT-08, AIT-10, AIT-11(AIT-09はフェーズ2対象のため対象外。[要件定義書](00-requirements.md)の未実装3点が解消するまで`BLOCKED`のまま) |
| セキュリティ試験 | AST-01, AST-02, AST-03, AST-04, AST-05, AST-06, AST-07, AST-08 |
| ネットワーク実機検証 | ANW-01, ANW-02, ANW-03, ANW-04, ANW-05, ANW-06, ANW-07, ANW-08, ANW-09([結果票テンプレート](../evidence/templates/network-host-validation-ad.md)を使用) |

判定は実施者が期待結果と実出力を照合して記入するため、**自動判定のような機械的な担保はありません。** だからこそ、期待結果と一致しない場合や前提が揃わない場合を安易に`PASS`へ書き換えないでください。[試験仕様書・結果票](06-test-specification.md)の判定値はこの4つだけです。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

Linux版のような`SKIP`判定はありません。確認していない項目は`NOT RUN`のまま残し、前提が揃わず実行自体ができない項目は理由と解除条件を添えて`BLOCKED`とします。

## 4. 再起動後の永続性

**これがフェーズ1手順書だけでは絶対に確認できない項目です。**

再起動の前後で`Get-CimInstance Win32_OperatingSystem`の`LastBootUpTime`を比較します。値が更新されていなければ、実際には再起動していないと判定し`FAIL`とします。

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

`LastBootUpTime`の更新を確認したら、AD DS関連サービスが再起動後も自動起動していることを確認します。これはAIT-02(昇格後必須サービス確認)の再起動後版であり、DC自身が再起動のたびにディレクトリサービスを提供できることを保証する、フェーズ1でもっとも基本的な永続性確認です。

```powershell
Get-Service NTDS, DNS, Netlogon, Kdc, W32Time | Select-Object Name, Status, StartType
```

すべて`Status: Running`であることを確認します。1つでも`Stopped`のまま自動起動していなければ、この項目を`FAIL`とします。

続けて次も確認します。再起動後にサービスが自動起動しない、Firewallルールが消えている、という不具合は再起動前には見えません。

```powershell
# Firewallルールが再起動前と同じ件数・内容で残っているか
Get-NetFirewallRule | Where-Object Enabled -eq $true |
  Select-Object DisplayName, Direction, Action, Profile

# WinRM(HTTPS)、AD統合DNS、LDAPへの疎通
Test-NetConnection -ComputerName localhost -Port 5986
Test-NetConnection -ComputerName localhost -Port 389
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.corp.example.test" -Type SRV

# FSMO役割保持者が再起動前と変わっていないか
netdom query fsmo

# バックアップのTask Schedulerタスクが残っているか
Get-ScheduledTask | Where-Object TaskName -like "*Backup*"
```

## 5. 24時間 / 72時間の連続稼働

Windows Serverには`systemd-run`に相当する常駐実行の仕組みがないため、Task Scheduler(`Register-ScheduledTask`)で定期サンプリングを登録し、切断してもサンプリングが継続する形にします。

```powershell
# LDAP(389)への疎通結果を5分間隔でCSVに記録するタスクを登録する例
# (サンプリング処理自体は本パックに同梱スクリプトが無いため、実施者が用意する)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -Command "& { $ok = (Test-NetConnection -ComputerName localhost -Port 389 -WarningAction SilentlyContinue).TcpTestSucceeded; Add-Content C:\soak-log.csv ((Get-Date -Format o) + \",\" + $ok) }"'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Hours 24)
Register-ScheduledTask -TaskName "ad-dc01-soak" -Action $action -Trigger $trigger -RunLevel Highest
```

サンプリング中は次を記録します。72時間の場合は`RepetitionDuration`を`(New-TimeSpan -Hours 72)`に変更します。

- LDAP(389)への疎通が失敗した回数
- `Get-Service NTDS, DNS, Netlogon, Kdc, W32Time`がすべて`Running`のままであったか(窓の途中で`Stopped`になった時刻があれば記録する)
- `Get-CimInstance Win32_OperatingSystem`の`LastBootUpTime`が窓の途中で変化していないか(変化していれば意図しない再起動)
- `Get-WinEvent -LogName "Directory Service"`、`Get-WinEvent -LogName System`に予期しないエラーが記録されていないか

窓が終わったら`C:\soak-log.csv`とEvent Logの確認結果を、日付付きの証跡ファイルへ手動でまとめます。この集計・整形を自動化するスクリプトは、3節で述べたとおり本パックには存在せず、今後の課題です。

## 6. 証跡の採録

生成・記入したファイルを**自分で読んでから**コミットします。

- [ ] `FAIL`の項目について、原因を理解している(理解できないまま採録しない)
- [ ] `BLOCKED`の項目について、前提条件と解除条件を本文に残している
- [ ] host名 / IP / 秘密値(DSRMパスワード、証明書秘密鍵)が出ていない。自動マスクの仕組みが無いため、公開する証跡は実施者が手動で置き換える
- [ ] [検証証跡台帳](../evidence/README.md)の該当行を`NOT RUN`から更新した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] [試験仕様書・結果票](06-test-specification.md)の**原本は`NOT RUN`のまま**(上書きしない)

## 7. この手順で埋まらないもの

| 項目 | 追加で必要なもの |
| --- | --- |
| フェーズ2(中央監視統合)一式(AIT-09) | [要件定義書](00-requirements.md)の「未実装」3点(Windows対応Ansible role、Dockerホスト↔対象Windowsホスト間の実接続・windows_exporterのFirewall許可、Windows向けログ集約経路)の解消 |
| 2台目のDC追加によるレプリケーション実測 | 2台目のWindows Serverホストと、[基本設計書](01-basic-design.md)2.4節に記す`Install-ADDSDomainController`・`repadmin`による検証 |
| `monitor-win-01`のドメイン参加検証 | [Windows版パック](../build-package-windows/README.md)の監視対象ホスト(`monitor-win-01`)と、両パックを同時に運用できる検証環境 |
| 組織DNS / 上流firewall | 実際の組織ネットワーク |
| 自己署名でない実TLS証明書(WinRM HTTPS用) | 内部CA、または独自ドメインとLet's Encrypt相当の仕組み |
| クラウドの実費・従量課金の実績 | クラウドアカウントと予算アラートの設定 |
| 物理層(L1) | スイッチ、ケーブル、VLAN対応機器 |

**フェーズ1のホスト1台では埋まらないものを、埋まったことにしないでください。** フェーズ2は、恒久ホストをいくら用意しても「未実装」3点の解消なしには埋まりません。
