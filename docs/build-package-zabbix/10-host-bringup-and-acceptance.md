# 引き渡し対象ホストの立ち上げと受け入れ試験

> 💡 **初めて読む方へ**: この文書は「まだ確認していない項目」を、`zbx-01`という1台の実サーバーで一気に埋めるための手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#10-立ち上げと受け入れ試験)を参照してください。

これまでの検討はすべて[要件定義書](00-requirements.md)から[試験仕様書・結果票](06-test-specification.md)までの**設計・手順書止まり**であり、`zbx-01`に相当する実ホストは一度も構築されていません。`compose.zabbix.yaml`はCI(`python-check.yml`)で`docker compose config --quiet`による構文検証(ZUT-01)はされていますが、これはYAMLの文法確認にとどまり、実際に`docker compose up -d`でコンテナを起動した実測ではありません。次の項目はすべて`NOT RUN`のまま残っています。

- 新規構築・冪等性(ZIT-01、ZIT-02)
- host active check(ZIT-03)、Frontend認証(ZIT-04)、healthz item(ZIT-05)
- alert通知のTrigger発火確認、webhookと受信先を用意した場合のSlack配信まで(ZIT-06)
- D-Z1(`monitor-01`のZabbix Agent2停止演習)の検知・復旧・RTO記録(ZIT-07)
- DB backup/restore(ZIT-08)
- 管理端末→`zbx-01`、`monitor-01`→`zbx-01`:10051(trapper)の実ホストnetwork(ZIT-09、ZNW-01〜09)
- セキュリティ試験(ZST-01〜04)
- ホスト再起動後のコンテナ自動復帰、24時間/72時間の連続稼働

**これらは`zbx-01`を1台用意し、既存の`monitor-01`([Linux版パック](../build-package/README.md)が構築済み)と実際に通信させると大半が一度に埋まります。逆に言えば、`zbx-01`が無い限りどれも埋まりません。**

この文書は、その1台を「用意してから証跡が出るまで」を最短で通すための手順です。本パックは[Windows版パック](../build-package-windows/README.md)・[AD版パック](../build-package-ad/README.md)と違い、中央監視基盤への統合待ちの「フェーズ2」を持ちません。`zbx-01`単体の受け入れが完了すれば、この案件は完了します。

## 0. 何を用意するか

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| 国内VPS(さくら / ConoHa / Xserver等) | 月500〜1,000円 | **推奨。** 実IPが付き、`monitor-01`と同じセグメントまたはVPC内に並べやすい |
| 自宅PCのVirtualBox / Hyper-V VM | 0円 | `monitor-01`も同じ手元環境にある場合に限り、双方向の疎通を確認できる |
| クラウド無料枠 | 0〜数百円 | 期限と課金に注意。`monitor-01`と同一VPC/サブネットに置けるかを先に確認する |

最小構成の目安は1 vCPU / メモリ2GB / ディスク20GBです。Zabbix Server・Frontend(Nginx同梱)・PostgreSQLの3コンテナが動くため、メモリ1GBでは不足します。

OSは[パラメータシート](03-parameter-sheet.md)のとおり**Ubuntu Server 24.04 LTSのみ**を対象とします。[Linux版パック](../build-package/10-host-bringup-and-acceptance.md)と異なりAlmaLinux/Rocky系は対象外です(Zabbix公式リポジトリのRHEL向けパッケージへの読み替えは今後の課題)。

**`zbx-01`単体では完結しません。** `monitor-01`のZabbix Agent2がactive checkで`zbx-01`:10051へpushできる経路(同一VPC、ピアリング、または到達可能なグローバルIPとFirewall許可)を用意してください。`monitor-01`が[Linux版パック](../build-package/README.md)のまま使い捨てCI runnerやWSL2上にしか存在しない場合、`zbx-01`をどれだけ用意してもZIT-03(host active check)とD-Z1演習は埋まりません。

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておきます。あとから思い出せません。

| 項目 | 記入 |
| --- | --- |
| 対象ホスト(`zbx-01`の用途・スペック) | |
| `monitor-01`の所在(Linux版パックのどの実ホストか)と、`zbx-01`との接続経路 | |
| 管理元IP / CIDR | |
| SSH公開鍵 | |
| DBパスワード・Slack webhook URLの受け渡し方法(秘密値台帳など) | |
| Zabbix Frontend Admin新パスワードの受け渡し方法 | |
| 再起動してよい時間帯 | |
| 接続不能になったときの復旧手段(コンソール) | |
| 停止許容時間 | |

**SSHだけに依存しないでください。** VPSのコンソール(シリアル / VNC)に入れることを、`DOCKER-USER` chainでtrapperの送信元を絞る前に必ず確認します。

## 2. 構築

[構築手順書](05-build-procedure.md)の0〜10節をそのまま実行します。本パックは専用Ansible roleを持たないため([要件定義書](00-requirements.md)の実装区分参照)、`docker compose up -d`(済(自動))以外はすべて手順書のコマンド・UIクリックを1つずつ実行する「済(手動)」です。

```bash
ssh <ssh-user>@192.0.2.11
cd /opt/zabbix-lab   # 05-build-procedure.mdの手順で取得済みのcheckout
docker compose -f compose.zabbix.yaml config --quiet
docker compose -f compose.zabbix.yaml up -d
docker compose -f compose.zabbix.yaml up -d
# 2回目。Recreating / Recreatedが出ないことを確認する(ZIT-02)
```

### trapperの送信元を実際のIPに絞る(DOCKER-USER chain。UFWではない)

[構築手順書](05-build-procedure.md)2.3節の既定は例示IP(`192.0.2.10`)です。実ホストでは`monitor-01`の実際のIPへ置き換えます。**この送信元制限はUFWではなく`DOCKER-USER` iptables chainで行います**(DockerがPublishしたportはUFWの`INPUT`chainを経由しないため。[04-network-ip-plan.md](04-network-ip-plan.md)参照)。Docker Engine導入(構築手順書2.2節)が完了してから実施してください(`DOCKER-USER`chainはDockerデーモン起動後に作成されます)。

```bash
sudo iptables -I DOCKER-USER -p tcp --dport 10051 -j DROP
sudo iptables -I DOCKER-USER -p tcp --dport 10051 -s <monitor-01の実IP> -j ACCEPT
sudo iptables -L DOCKER-USER -n --line-numbers
sudo netfilter-persistent save
```

`-I`はchainの先頭へ挿入するため、DROPを先に、ACCEPTを後に実行します(順序は[構築手順書](05-build-procedure.md)2.3節を参照)。`netfilter-persistent save`を忘れると再起動後にルールが消えます。

**絞る前にコンソールで入れることを確認しておきます。** Frontend(`${ZABBIX_WEB_PORT:-8081}/tcp`)はloopback bindが唯一の防御線のため追加のfirewallルールは不要ですが、trapperは`DOCKER-USER` chainの送信元制限が唯一の防御線です。この違いを混同しないでください([04-network-ip-plan.md](04-network-ip-plan.md)参照)。

## 3. 受け入れ試験

本パックには、[Linux版パック](../build-package/README.md)の`acceptance-check.sh`のような結果票を自動生成するスクリプトはありません。[試験仕様書・結果票](06-test-specification.md)のIDを対象ホストで実行し、期待結果と実出力を実施者が照合して判定します。

| 区分 | 対象ID |
| --- | --- |
| 単体・構成試験 | ZUT-01〜03(evidence列「—」= CIで継続的に検証されるため、本節での個別記入は不要) |
| 構築・結合試験 | ZIT-01〜09 |
| セキュリティ試験 | ZST-01〜04 |
| ネットワーク実機検証 | ZNW-01〜09([ネットワーク実機検証手順](09-network-validation-procedure.md)、[結果票テンプレート](../evidence/templates/network-host-validation.md)を使用) |

判定は実施者が期待結果と実出力を照合して記入するため、**自動判定のような機械的な担保はありません。** だからこそ、期待結果と一致しない場合や前提が揃わない場合を安易に`PASS`へ書き換えないでください。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

`ZIT-06`(alert通知)は、webhookと受信先チャンネルを用意した場合だけSlack配信まで確認します。用意できない環境では、Trigger発火(PROBLEM遷移)までの確認は必須のまま行い、実配信部分だけを`BLOCKED`(理由: webhook未用意)として記録します。

## 4. D-Z1障害演習

D-Z1(`monitor-01`のZabbix Agent2停止演習)は、この案件パックの中で唯一「`zbx-01`と`monitor-01`が実際に通信できていること」を検知・復旧という形で証明する試験です。既存の[D-1](../drills/logs/TEMPLATE-D-1-process-down.md)は単一host内のプロセス停止演習のためCI runner1台でも実測できますが、D-Z1は監視サーバー(`zbx-01`)と監視対象(`monitor-01`)という**別々のhost間のtrapper通信**が前提のため、`zbx-01`を用意しない限り実測できません。

[構築手順書](05-build-procedure.md)7節の手順をそのまま使います。

```bash
# 事前状態(PROBLEMが無いこと)を確認してから停止
ssh <ssh-user>@192.0.2.10 'sudo systemctl stop zabbix-agent2'
date -u +%Y-%m-%dT%H:%M:%SZ   # 検知開始の基準時刻

# FrontendのMonitoring > ProblemsでPROBLEM遷移した時刻を検知時刻として記録

ssh <ssh-user>@192.0.2.10 'sudo systemctl start zabbix-agent2'
date -u +%Y-%m-%dT%H:%M:%SZ   # 復旧操作の時刻

# FrontendのMonitoring > ProblemsでRESOLVED(OK)に変わった時刻を復旧時刻として記録
```

検知時刻から復旧時刻までをRTOとして算出し、実行コマンド・実出力とあわせて[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)の様式で日付付きevidenceへ保存します。webhookと受信先を用意している場合は、Slackへの通知到達もあわせて記録します(ZIT-07、NFR-08)。

## 5. 証跡の採録

生成・記入したファイルを**自分で読んでから**コミットします。

- [ ] `FAIL`の項目について、原因を理解している(理解できないまま採録しない)
- [ ] `BLOCKED`の項目について、前提条件と解除条件を本文に残している
- [ ] host名 / IP / 秘密値(DBパスワード、Slack webhook URL、Zabbix Adminパスワード)が出ていない
- [ ] [検証証跡台帳](../evidence/README.md)の該当行を`NOT RUN`から更新した
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] [試験仕様書・結果票](06-test-specification.md)の**原本は`NOT RUN`のまま**(上書きしない)

## 6. この手順で埋まらないもの

| 項目 | 追加で必要なもの |
| --- | --- |
| Slack実配信(ZIT-06のうち配信部分) | Slack Incoming Webhook URLと受信先チャンネル |
| passive check(任意拡張) | 複数の監視対象hostが増えた場合の設計判断。現状は設計のみで実装対象外 |
| 専用Ansible role(`ansible/roles/zabbix_agent`相当) | 手動手順の自動化方針の決定と実装([要件定義書](00-requirements.md)「未実装」参照) |
| RHEL系(AlmaLinux / Rocky)でのZabbix構築 | 対象外。行う場合はZabbix公式リポジトリのRHEL向けパッケージへの読み替えが必要 |
| ホスト再起動後の永続性、24時間 / 72時間の連続稼働 | 本書の必須試験には含みませんが、確認する場合は[Linux版パックの立ち上げ・受け入れ手順](../build-package/10-host-bringup-and-acceptance.md)4節・5節の考え方を`zbx-01`へ適用します |
| 組織DNS / 上流firewall | 実際の組織ネットワーク |
| 物理層(L1) | スイッチ、ケーブル、VLAN対応機器 |

**`zbx-01`1台では埋まらないものを、埋まったことにしないでください。**
