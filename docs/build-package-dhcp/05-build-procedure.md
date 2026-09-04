# 構築手順書

> 💡 **初めて読む方へ**: この文書は実際にサーバーを構築するとき、上から順に実行するコマンド手順書です。「なぜrogue DHCP確認を先にやるのか」「なぜ2回適用するのか」などは[初心者ガイド](beginner-guide.md#05-構築手順書)で先に触れています。

## 0. 作業前確認

- 対象: `dhcp-01`(Ubuntu Server 24.04 LTS、検証用VM1台)。加えて、DORA(DISCOVER/OFFER/REQUEST/ACK)を実機で確認するための**クライアント検証VM1台**が必要です。`dhcp-01`と同一の払い出し対象セグメント(`192.168.50.0/24`)に接続しておきます
- 管理端末から公開鍵SSHとsudoが、`dhcp-01`・クライアント検証VMの両方で利用可能
- 対象IP、作業時間、ロールバック条件を記録済み
- リポジトリの対象commit SHAを固定済み
- 実値の秘密情報をIssue、PR、端末ログへ貼らない
- [要件定義書](00-requirements.md)と[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go条件を確認済み
- `dhcp-01`の払い出し対象セグメント側NIC名を`ip -br link`で確認する準備ができていること(`dhcp_server_interface`変数へ反映するのは2節)
- **3節でrogue DHCP確認(NFR-08、DST-06)を初回適用の直前に実施する前提**であることを、作業者間で合意済み。この確認は`dhcp.yml`を1回でも適用してしまうと「セグメント内に他のDHCPサーバーが無いこと」の確認としての意味を失うため、必ず初回適用より前に行います
- 立ち上げ環境そのもの(VirtualBoxのHost-Only/Internalネットワーク等)の準備は本書の対象外です。[立ち上げと受け入れ試験](10-host-bringup-and-acceptance.md)を先に完了させてください

## 1. 管理端末の準備

```bash
git clone https://github.com/ns7jp/server.git
cd server
git rev-parse HEAD
python3 -m venv .venv
. .venv/bin/activate
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml
```

`dhcp_server` roleのfirewallタスクは`community.general.ufw`モジュールを使うため、`ansible/requirements.yml`の`community.general`collectionのインストールを省略しないでください。省略すると2節以降の`--check --diff`や適用が、モジュール未検出のエラーで止まります。

## 2. inventoryの準備

1. `ansible/inventory/staging.dhcp.local.yml.example`をGit管理外の`staging.dhcp.local.yml`へコピーします。この inventory は既存の監視host(`monitor`グループ、`staging.local.yml`)とは独立した、本パック(`SM-DHCP-001`)専用のファイルです
2. `dhcp-01`へSSHし、払い出し対象セグメント側のinterface名を実機確認してから、`dhcp_server_interface`へ反映します(既定値は空文字で、未設定のままだとrole内の`ansible.builtin.assert`が構築を拒否します)
3. `ansible_host`(管理面IP、記入例は`192.0.2.30`)を実環境の値へ置き換えます
4. 本パックはZabbixパックのAPIトークンやLinux版のS3資格情報のような秘密値を扱わないため、`ansible-vault`によるVault暗号化は不要です(値の正本は[パラメータシート](03-parameter-sheet.md)参照)

```bash
ssh <dhcp-01への到達性を確認済みのSSH先> 'ip -br link'
cp ansible/inventory/staging.dhcp.local.yml.example ansible/inventory/staging.dhcp.local.yml
# $EDITOR ansible/inventory/staging.dhcp.local.yml
#   dhcp_server_interface: <ip -br linkで確認した実際のinterface名>
git status --short
git check-ignore ansible/inventory/staging.dhcp.local.yml
ansible-inventory -i ansible/inventory/staging.dhcp.local.yml --graph
ansible dhcp -i ansible/inventory/staging.dhcp.local.yml -m ping
```

`ansible dhcp -m ping`が`SUCCESS`を返すまで、3節以降へ進みません。

## 3. パッケージ提供確認・rogue DHCP確認・構築

本節は3つの下位手順から成ります。**この順序を変えないでください**。特に3.2のrogue DHCP確認は、`dhcp-01`自身がまだDHCPサーバーとして稼働していない状態でこそ意味を持つ確認です。

### 3.1 isc-dhcp-serverパッケージの提供確認

[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)に記載のとおり、本パックはUbuntu 24.04(noble)のuniverseリポジトリに`isc-dhcp-server`パッケージが存在する前提で設計しています。`dhcp_server` roleの`ansible.builtin.apt`タスクに任せきりにせず、適用前に必ず対象ホストで実機確認します。

```bash
cd ansible
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a 'apt-get update'
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a 'apt-cache policy isc-dhcp-server'
```

確認点:

- `Candidate:`行にバージョン番号が表示され、`(none)`ではないこと
- `Installed:`が`(none)`であること(新規構築の前提。既に何らかのバージョンが入っている場合は[変更・ロールバック計画](08-change-rollback-plan.md)の変更手順に切り替えます)

`Candidate: (none)`だった場合は、対象ホストのuniverseリポジトリが有効化されていないか、ミラーの構成が想定と異なります。この時点で構築を止め、`sudo add-apt-repository universe`相当の是正を行うか、[基本設計書](01-basic-design.md)に記載のKea DHCPへの切替検討へ進みます。パッケージが存在しないまま4節以降へ進みません。

### 3.2 rogue DHCP確認(適用前、DST-06・NFR-08)

`dhcp-01`のisc-dhcp-serverはまだインストールされていません。つまり、この時点で払い出し対象セグメント上のDHCP要求に応答するサーバーが**1台もない**状態が、構築前の正しいベースラインです。ここで何らかのDHCPサーバーが応答した場合、それは想定外のrogue DHCPサーバーであり、`dhcp-01`を稼働させる前に特定・停止(またはセグメント分離)しなければなりません。

確認はクライアント検証VM側から行います。`nmap`の`broadcast-dhcp-discover`スクリプトを使う方法と、実際に`dhclient`でDISCOVERを送出し応答元を見る方法のどちらでも構いません。

```bash
CLIENT_VM=<クライアント検証VMへのSSH先>
CLIENT_IF=<クライアント検証VM側でip -br linkにより確認したinterface名>

ssh "$CLIENT_VM" "sudo nmap --script broadcast-dhcp-discover -e $CLIENT_IF"
```

`nmap`が利用できない環境では、`dhclient`の詳細ログで代替します。

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
# 応答が無いこと(タイムアウトすること)を確認したら、後始末として明示的に解放します
ssh "$CLIENT_VM" "sudo dhclient -r $CLIENT_IF"
```

期待結果は「応答するDHCPサーバーが1台もない」ことです。何らかのサーバーIPが応答した場合は、その値と応答内容(`DHCPOFFER`のオプション等)を記録し、[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ切り分けを残したうえで、rogue DHCPサーバーを停止するかセグメントを分離してから再確認します。安全が確認できるまで3.3以降へ進みません。

この確認結果は、[パラメータシート](03-parameter-sheet.md)実機記入欄の「rogue DHCP確認(構築直前、DST-06)」へ記録します。[ネットワーク実機検証手順](09-network-validation-procedure.md)のDNW-09は、構築完了後にあらためて同じ観点(応答するDHCPサーバーが`dhcp-01`(`192.168.50.5`)のみ)を確認する、別の正式な結果票です。

### 3.3 事前確認と初回適用

```bash
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --check --diff
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
```

fresh hostの`--check --diff`は、`ansible.builtin.assert`による入力検証やmoduleが示す差分を確認するbest-effortなpreflightです。パッケージのインストールや`dhcpd.conf`の実際の生成は行われないため、`validate: /usr/sbin/dhcpd -t -cf %s`(構文検査)を含む後続taskが、check modeでは実行されない場合があります。したがって`--check --diff`の成功そのものを、構文検査済みの証跡としては扱いません。完全な構築確認は5節で行います。

失敗時は、失敗task、対象host、終了code、直前の変更を保存して作業を中断します。原因を修正してから同じplaybookを再実行します。特に3.1で確認したパッケージ名・バージョンと、実際にinstallされたタスクの結果が食い違う場合は、apt cacheの更新タイミングを疑ってください。

## 4. 冪等性確認

```bash
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
```

`play recap`が`failed=0`かつ`changed=0`であることを記録します(NFR-02、DIT-01の2回目)。UFWルールやfirewalldとの相互作用など、環境によって毎回`changed`になるtaskがある場合は、そのtaskと理由を結果票へ残し、safe(冪等)であることを個別に説明します。

## 5. 構築後確認

まず`dhcp-01`側で、設定ファイルとサービスの状態を確認します。

```bash
ssh dhcp-01 'sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf'
ssh dhcp-01 'systemctl is-enabled isc-dhcp-server; systemctl status isc-dhcp-server --no-pager'
ssh dhcp-01 'sudo ss -lunp | grep :67'
ssh dhcp-01 'sudo ss -lntup'
ssh dhcp-01 'sudo ufw status verbose'
ssh dhcp-01 'sudo aa-status | grep dhcpd'
ssh dhcp-01 "stat -c '%U:%G %a' /etc/dhcp/dhcpd.conf"
```

確認点(DUT-01、DUT-04、DST-01〜03に対応):

- `dhcpd -t`が構文エラーなしで完了する(exit 0)
- `isc-dhcp-server`が`enabled`かつ`active (running)`
- UDP 67がbindされている(interfaceは`dhcp_server_interface`で指定した払い出し対象セグメント側のもの)
- UFWでUDP 67の許可がinterface `dhcp_server_interface`（払い出し対象セグメント側）限定で、他ネットワークへの許可がない
- AppArmorの`usr.sbin.dhcpd`が`enforce`モード
- `/etc/dhcp/dhcpd.conf`が`root:root`、`644`以下

### DORA実機確認(FR-02、DIT-02)

ここが本手順の中心です。設定ファイルの構文が正しいことと、実際にクライアントへDHCPv4リースを払い出せることは別の確認です。クライアント検証VM上で`dhclient`を実行し、同時に同じVM上でDORAの4パケット(DISCOVER/OFFER/REQUEST/ACK)を`tcpdump`で観測します。

```bash
CLIENT_VM=<クライアント検証VMへのSSH先>
CLIENT_IF=<クライアント検証VM側でip -br linkにより確認したinterface名>
```

`CLIENT_IF`は3.2のrogue DHCP確認で使ったものと同じinterfaceです。`dhcp-01`自身の`dhcp_server_interface`(例: `eth1`)とは別物である点に注意してください。

端末A(クライアント検証VMへの1つ目のSSHセッション。先にcaptureを開始します):

```bash
ssh -t "$CLIENT_VM" \
  "sudo timeout 30 tcpdump -nn -i $CLIENT_IF -c 20 'udp port 67 or port 68'"
```

端末B(同じクライアント検証VMへの2つ目のSSHセッション。captureが動いている間に実行します):

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
```

確認点:

- 端末Bの`dhclient -v`ログに、`DHCPDISCOVER` → `DHCPOFFER` → `DHCPREQUEST` → `DHCPACK`の順で出力される
- 取得したIPアドレスが動的払い出しプール`192.168.50.100`〜`.200`の範囲内である
- 端末Aの`tcpdump`出力に、対応する4パケット(送信元/宛先ポートが67・68)が観測される
- 取得したgateway・DNS・ドメイン名が設計値(`192.168.50.1`、`192.168.50.1`/`1.1.1.1`、`lab.example.test`)と一致する(FR-07、DIT-08。クライアント側で`ip route`、`resolvectl status`を確認)

```bash
ssh "$CLIENT_VM" 'ip route'
ssh "$CLIENT_VM" 'resolvectl status || cat /etc/resolv.conf'
```

固定IP予約を1件でも登録している場合は、その予約MACを持つクライアントで同じ手順を実行し、常に同一の予約IPが払い出されることを確認します(FR-03、DIT-03)。確認後、クライアント検証VM側のテストリースは`sudo dhclient -r $CLIENT_IF`で明示的に解放し、後始末します(FR-06、DIT-07の入り口にもなる操作です)。

この節の簡易確認とは別に、[試験仕様書](06-test-specification.md)のDUT-01〜05・DIT-01〜11・DST-01〜06と、[ネットワーク実機検証手順](09-network-validation-procedure.md)のDNW-01〜09は、日付付きevidenceへ個別の結果票として記録します。プール枯渇時の挙動(DIT-04)、リース更新(DIT-05)、サービス再起動後のリース永続化(DIT-06)は、6節の障害・復旧試験とあわせて確認する運用にしています。

### node_exporter導入と中央監視統合(済・手動、FR-09、DIT-10、NFR-13)

`dhcp_server` roleにはnode_exporter導入タスクを含めていません([詳細設計書](02-detailed-design.md)配備設計のとおり手動作業です)。DNW-05(待受port)とDIT-10(監視統合)を満たすには、`dhcp-01`側でのnode_exporter導入と、中央監視host(`monitor-01`)側での登録の両方が必要です。

`dhcp-01`側(node_exporterの導入とUFW許可):

```bash
ssh dhcp-01 'sudo apt-get update && sudo apt-get install -y prometheus-node-exporter'
ssh dhcp-01 'systemctl is-enabled prometheus-node-exporter; systemctl status prometheus-node-exporter --no-pager'
MONITOR_IP='192.0.2.10'   # monitor-01の実IPへ置き換える([Linux版パラメータシート](../build-package/03-parameter-sheet.md)参照)
ssh dhcp-01 "sudo ufw allow proto tcp from $MONITOR_IP to any port 9100"
ssh dhcp-01 'curl -fsS http://127.0.0.1:9100/metrics | head -n 5'
```

`monitor-01`側(中央Prometheusへの登録。`dhcp-01`側の作業とは別の権限が必要です):

```bash
# monitor-01のinventory(例: ansible/inventory/staging.local.yml)のhost varsへ追加する
#   app_node_exporter_targets:
#     - address: "192.168.50.5:9100"
#       host: dhcp-01
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

適用後、Prometheusの`up{host="dhcp-01"}`が`1`になることを確認します(DIT-10)。`dhcp-01`と`monitor-01`が異なるネットワークセグメントにある場合、そのままでは到達できないことがあります。[立ち上げと受け入れ試験](10-host-bringup-and-acceptance.md)の「5. 中央監視統合を試す場合（DIT-10）」を参照してください。

## 6. 障害・復旧試験(DIT-09、DIT-05、DIT-06)

isc-dhcp-serverサービスの停止を想定した検知・復旧演習です。単一DHCPサーバー構成のため、停止中は新規リースの払い出しが完全に止まります(冗長化は対象外、[要件定義書](00-requirements.md)5章)。

1. 事前状態を確認します。

```bash
ssh dhcp-01 'systemctl status isc-dhcp-server --no-pager'
ssh dhcp-01 'sudo cat /var/lib/dhcp/dhcpd.leases | tail -n 40'
```

2. サービスを停止します(検知開始時刻を記録)。

```bash
ssh dhcp-01 'sudo systemctl stop isc-dhcp-server'
ssh dhcp-01 'systemctl status isc-dhcp-server --no-pager'
```

3. クライアント検証VM側で新規リース要求が失敗する(応答が無くタイムアウトする)ことを確認します(FR-04、DHCPNAKまたは無応答)。

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
```

4. 停止を確認した時刻を記録し、サービスを復旧させます。

```bash
ssh dhcp-01 'sudo systemctl start isc-dhcp-server'
ssh dhcp-01 'systemctl status isc-dhcp-server --no-pager'
ssh dhcp-01 'sudo cat /var/lib/dhcp/dhcpd.leases | tail -n 40'
```

再起動後の`dhcpd.leases`に、停止前の既存リース内容が保持されていることを確認します(FR-05、DIT-06)。続けてクライアント検証VMで`dhclient -v`を再実行し、新規リースが正常に払い出されることを確認して、正常性回復とします(DIT-09)。

5. 検知時間・復旧時間(RTO)、`journalctl -u isc-dhcp-server --since today`に記録されたリース割当・解放イベント(NFR-07、DST-05)を、日付付きevidenceへ記録します。

リース更新(RENEW/REBIND、DIT-05)は`sudo dhclient -r $CLIENT_IF`による解放・再取得では代替できません(それは新たなDISCOVER/OFFERを伴う新規取得であり、RENEW/REBINDの2パケットフローを経由しないため)。確認するには、`dhcp_server_default_lease_time`のような検証用の短いリース時間を一時適用したうえで、T1到達時のunicast DHCPREQUEST（RENEW）とT2到達時のbroadcast DHCPREQUEST（REBIND）をtcpdumpで観測します。プール枯渇時の挙動(DIT-04)は、動的プール(101個)を意図的に使い切る手順が別途必要なため、[試験仕様書](06-test-specification.md)の当該手順に従って個別に実施します。

## 7. ロールバック

構成変更が原因の場合は、[変更・ロールバック計画](08-change-rollback-plan.md)に従って変更前commitの別checkoutから`playbooks/dhcp.yml`を適用します。復旧後は5節の構築後確認と、影響範囲の試験を再実行します。

`dhcpd.conf`とリースDB(`/var/lib/dhcp/dhcpd.leases`)そのものの破損が原因の場合は、直近のバックアップから復元します(NFR-09、DIT-11)。

```bash
ssh dhcp-01 'sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak-$(date +%Y%m%d%H%M)'
ssh dhcp-01 'sudo cp /var/lib/dhcp/dhcpd.leases /var/lib/dhcp/dhcpd.leases.bak-$(date +%Y%m%d%H%M)'
```

バックアップからの復元手順、RTOの記録方法は[変更・ロールバック計画](08-change-rollback-plan.md)を正本とします。復元後は必ずDORA(5節)を再実施し、新規リースが正常に払い出されることまで確認してから復旧完了とします。

## 8. 作業終了

- 結果票、実行ログ、画面(`dhclient -v`ログ、`tcpdump`出力を含む)を保存
- クライアント検証VM側の一時的なテストリース、rogue DHCP確認用の設定を削除
- 一時的なfirewall許可を削除
- 未解決事項をIssue化
- [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、計画対実績、実行時間、対象commit、差異、障害、残存リスクを記入
- 報告書の試験集計と個別結果票の件数が一致することを確認
- [引き渡しチェックリスト](07-handover-checklist.md)を確認し、`NOT RUN` / `BLOCKED`が残る場合は受領可にしない
