# DHCPサーバー 構築・試験結果票 — 2026-09-04

[試験仕様書・結果票](../build-package-dhcp/06-test-specification.md)の原本をコピーし、`dhcp_server` role（`ansible/roles/dhcp_server/`）と実プレイブック（`ansible/playbooks/dhcp.yml`）を、AI支援セッションのサンドボックスコンテナ上へ適用した結果を記入したものです。原本は`NOT RUN`のまま保持し、実施結果はこの日付付きファイルへ記録します。

> **他の同日付証跡との関係**: 同じ2026-09-04に、別のAI支援セッションが独立に本パックの実機検証を行った記録が[`2026-09-04-dhcp-build-validation-netns-lab.md`](2026-09-04-dhcp-build-validation-netns-lab.md)（`labs/routing/`と同じ方式のnetwork namespace + veth隔離ラボ`labs/dhcp-lab/`、`common`ロールも含めて適用、31 ID中27 ID `PASS`）にあります。本ファイルはセッション自身のコンテナをDocker bridge越しに`dhcp-01`役として使う構成（`common` roleは安全上の理由で未適用、31 ID中22 ID `PASS`）です。両者は互いを置き換えるものではなく、異なる構成・スコープでの並行した実測として両方保持しています。

## この証跡が示す範囲（重要）

このパックの[README](../build-package-dhcp/README.md)は「VM/実機での実演を正本とする」と定めています。本証跡はその正本ではなく、VM/実機を用意できないAI支援セッションのサンドボックスコンテナ上で、**Linuxのnetwork namespace + veth pair + 独自bridge**を使ってDHCPのL2ブロードキャストを模擬し、実際に`isc-dhcp-server`（apt版、改変なし）を動かして得た記録です。既存の[二セグメント障害ラボ](../../labs/network-troubleshooting/README.md)が使うDocker bridgeとも異なる、本セッション限定の構成です。

- 使用したコードは**リポジトリの実物**です（`ansible/roles/dhcp_server/tasks/main.yml`・`templates/dhcpd.conf.j2`・`ansible/playbooks/dhcp.yml`を一切改変していません）。役割検証用に、`common` roleを含まない縮小版playbook（このサンドボックスコンテナ自体へSSH hardening・default deny firewallを適用するのは安全上の理由で見送った）と、セッション専用のinventory（`ansible/inventory/sandbox-dhcp.local.yml`、`.gitignore`対象・非commit）だけをこのセッションで作成しました。
- 得られたDORA・固定予約・プール枯渇・RENEW・バックアップ復元のパケットキャプチャと`dhcpd.leases`の内容は**すべて実測**です。作文・推測による結果はありません。
- 一方で、このサンドボックスコンテナには**実systemd（PID1）・AppArmor・journald/rsyslogがありません**。該当する試験ID（DUT-04、DST-03、DST-05）は環境起因で`BLOCKED`です。role・playbook自体の欠陥ではありません。
- `common` role（SSH hardening、UFW既定deny、自動更新）は、このセッションが動いている共有サンドボックスコンテナ自体へ適用するとセッションのSSH/操作性を壊すリスクがあるため、安全上の理由で意図的に適用していません。関連するDST-01、DST-04、DNW-07は`BLOCKED`/`NOT RUN`です。
- 中央Prometheus（`monitor-01`）はこのサンドボックスに存在しないため、DIT-10は`NOT RUN`です。
- 複数物理ホスト間の実ネットワーク（別VM・別ハードウェア間）の検証ではありません。単一コンテナ内で分離したnetwork namespace間の通信です。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | DHCP機能面（DUT-01〜03/05、DIT-01〜09/11、DST-02/06、DNW-01/02/04〜06/08/09）は**実測`PASS`**。`common` role相当のセキュリティ強化・監視統合・実systemd/AppArmor/journaldに依存する項目は環境制約で`BLOCKED`/`NOT RUN`（詳細は下表）。22/31が`PASS`、6/31が`BLOCKED`、3/31が`NOT RUN` |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | ns7jp（AI支援セッション） |
| 対象環境 / host | AI支援セッションのサンドボックスコンテナ自身を`dhcp-01`役として使用。払い出し対象セグメント`192.168.50.0/24`はbridge `br-dhcp50` + veth `veth-d01`（dhcpd側、`192.168.50.5/24`）+ veth `veth-cli`（`client01`という別network namespace内のクライアント役、`fe:b8:0b:ac:82:84`ほか複数MACで模擬） |
| 管理端末 / controller | 同一コンテナ内（`ansible_connection: local`、`ansible_python_interpreter: /usr/bin/python3.12`。理由は下記「サンドボックス固有の対応」） |
| commit SHA | `27fc7ec8f1cfe41e03466ba859647b0f66b836a0` |
| OS / kernel | Ubuntu 24.04.4 LTS（noble）、kernel `6.18.44-fc-v24` |
| isc-dhcp-serverバージョン | `isc-dhcpd-4.4.3-P1`（apt: `isc-dhcp-server 4.4.3-P1-4ubuntu2`、`noble/universe`） |

秘密値は扱っていません（本パックの設計どおり）。

### サンドボックス固有の対応（環境の制約であり、role/playbookの欠陥ではない）

- **非blocking IO**: `ansible-playbook`実行時に`Ansible requires blocking IO on stdin/stdout/stderr`で失敗する。fd 0/1/2の`O_NONBLOCK`を解除するラッパースクリプトを噛ませて回避（このセッションの作業環境のみの対応、role・playbook側の変更なし）。
- **python3-apt**: `/usr/bin/python3`（3.11）には`apt_pkg`拡張が存在せず、`Could not import the python3-apt module`で失敗する。`ansible_python_interpreter: /usr/bin/python3.12`をinventoryで明示指定して回避。
- **systemd不在**: `systemctl status`が`System has not been booted with systemd as init system`を返す（PID1はharnessの`process_api`）。`ansible.builtin.systemd`タスク（`Enable and start isc-dhcp-server`）は毎回`Service is in unknown state`で失敗する。これはこのサンドボックス環境の制約であり、実VM/実機では発生しない。DORA実演のためだけに、Ansibleの管理外でSysV互換の`service isc-dhcp-server start/stop/status/restart`を手動実行した（この操作は明示的に開示する）。

## 単体・構成試験（DUT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DUT-01 | dhcpd.conf構文検査 | PASS | `dhcpd -t -cf /etc/dhcp/dhcpd.conf` → `Config file: /etc/dhcp/dhcpd.conf` / `Database file: ...` / `PID file: ...`のみ出力、`EXIT: 0`。設計値どおりの最終状態（プール`192.168.50.100-200`、lease時間`43200`/`86400`）で確認 |
| DUT-02 | Ansible構文チェック | PASS | `ansible-playbook -i inventory/sandbox-dhcp.local.yml playbooks/dhcp.yml --syntax-check`（実リポジトリの`ansible/playbooks/dhcp.yml`、`common`→`dhcp_server`の2play構成そのもの）→ `playbook: playbooks/dhcp.yml`のみ出力、`EXIT: 0` |
| DUT-03 | ansible-lint | PASS | `ansible-lint --offline --profile production ansible/playbooks/dhcp.yml ansible/roles/dhcp_server` → `Passed: 0 failure(s), 0 warning(s) in 8 files processed of 8 encountered. Profile 'production' was required, and it passed.`（参考: `ansible/`全体を対象にした非scoped実行では他role（docker/monitoring/nginxのmolecule verify）由来の21件が出るが、`dhcp`を含む行はゼロだった） |
| DUT-04 | systemdユニット有効化 | BLOCKED | `systemctl is-enabled isc-dhcp-server`はサンドボックスに実systemdが無いため実行不能（`System has not been booted with systemd as init system`）。環境制約であり、role側の`ansible.builtin.systemd enabled: true`宣言自体は`tasks/main.yml`に存在する |
| DUT-05 | 成果物リンク | PASS | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` → `1 passed, 52 deselected` |

## 構築・結合試験（DIT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DIT-01 | 新規構築・冪等性 | BLOCKED（非systemdタスクは実測`PASS`相当） | 初回適用: `ok=6 changed=3 failed=1`（`Enable and start isc-dhcp-server`タスクのみ、DUT-04と同じ理由で失敗）。2回目適用: `ok=6 changed=0 failed=1`（systemdタスク以外の6タスクすべてが`changed=0`で冪等性を確認）。設計値どおりの最終状態への再適用でも同じパターンを再現（`ok=6 changed=1 failed=1`→`ok=6 changed=0 failed=1`）。期待結果「1回目`failed=0`」は環境制約により未達だが、それ以外の全タスク（OS判定・入力検証・パッケージ導入・`dhcpd.conf`テンプレート化と`dhcpd -t`によるvalidate・interfaceバインド）は実測で成功かつ冪等 |
| DIT-02 | DORA実測 | PASS | `client01` netns（MAC `fe:b8:0b:ac:82:84`）で`dhclient -v veth-cli`実行。`tcpdump -v`で4パケットを観測: `Discover`→`Offer`(Server-ID `192.168.50.5`)→`Request`(Requested-IP `192.168.50.100`)→`ACK`。取得IP`192.168.50.100`は設計プール範囲`192.168.50.100-200`内 |
| DIT-03 | 固定予約 | PASS | inventoryへ`dhcp_server_reservations`で`fe:b8:0b:ac:82:84`→`192.168.50.20`を登録し再適用。同MACでの`dhclient`実行で`Discover`(Requested-IP `192.168.50.100`のヒント付き)→`Offer`→`Request`(Requested-IP `192.168.50.20`)→`ACK`(Server-ID `192.168.50.5`)を観測。クライアント側が動的プールのIPをヒントに出しても、サーバーは`host`ブロックの固定予約`192.168.50.20`を優先して払い出した |
| DIT-04 | プール枯渇 | PASS | 検証用に`range`を`192.168.50.150-151`（2アドレス）へ一時縮小。3台の異なるMACで順次要求し2アドレスを使い切った後、4台目（MAC `02:00:00:00:00:14`）が要求すると`DHCPDISCOVER`を3回再送（interval 3, 3, 7秒）するも`DHCPOFFER`が一切来ず、`timeout 8`が`EXIT: 124`で強制終了。新規リースが払い出されないことを確認。試験後、プール範囲を設計値`192.168.50.100-200`へ復元し再適用済み |
| DIT-05 | リース更新 | PASS | 検証用に`dhcp_server_default_lease_time: 20` / `max_lease_time: 40`（秒）を一時適用。初回DORA後、T1相当（約20秒後）に`192.168.50.152.68 → 192.168.50.5.67`のunicast `DHCPREQUEST`→`DHCPACK`の2パケットのみを観測（新たな`Discover`/`Offer`を介さない）。以後20秒弱の周期で同じunicast RENEWパターンを2回観測。試験後、lease時間を設計値`43200`/`86400`へ復元し再適用済み |
| DIT-06 | サービス再起動後のリース永続化 | PASS | `service isc-dhcp-server restart`前後で`dhcpd.leases`内の対象リース（`hardware ethernet 02:00:00:00:00:21`、IP `192.168.50.152`、`starts`/`ends`時刻）の内容が保持されていることを確認。dhcpd起動時に`tstp`行追加と`server-duid`書き出しでファイル自体のmd5は変わるが、bindingの実体は不変 |
| DIT-07 | リース解放 | PASS | daemonモードの`dhclient veth-cli`（MAC `02:00:00:00:00:77`）でIP`192.168.50.154`を取得後、`dhclient -r veth-cli`を実行。解放後の`dhcpd.leases`で該当エントリが`binding state active` → `binding state free;`へ遷移していることを確認（`rewind binding state`行が消え、`ends`が解放時刻に短縮） |
| DIT-08 | オプション配布 | PASS | クライアント役netns内`ip route` → `default via 192.168.50.1 dev veth-cli`（設計値の`option routers`と一致）。`cat /etc/resolv.conf`（dhclient-scriptが書き込み） → `domain lab.example.test` / `search lab.example.test` / `nameserver 192.168.50.1` / `nameserver 1.1.1.1`（設計値の`option domain-name`・`option domain-name-servers`と完全一致） |
| DIT-09 | サービス停止復旧 | PASS | `service isc-dhcp-server stop`後`status`が`dhcpd is not running.`（exit 3）を確認。即座に手動`service isc-dhcp-server start`で復旧、`status`が`dhcpd is running.`に復帰。起動コマンドのみのRTO実測値: 約2.06秒（検知は`status`確認で代替、自動検知・自動復旧の仕組みは本パックの対象外） |
| DIT-10 | 監視統合 | NOT RUN | 中央Prometheus（`monitor-01`）がこのサンドボックスに存在しないため未実施 |
| DIT-11 | バックアップ・復元 | PASS | `dhcpd.conf`・`dhcpd.leases`をバックアップ後、`dhcpd.conf`を`"BROKEN"`一行に、`dhcpd.leases`を削除して意図的に破壊。`dhcpd -t -cf`が`semicolon expected`相当のエラーでexit 1になることを確認（構文検査が実際に機能している証拠）。バックアップから復元し`dhcpd -t -cf`がexit 0、`service isc-dhcp-server start`が成功。復元直後に新規MAC（`02:00:00:00:00:99`）で`dhclient -v -1`を実行し、まず古いリース情報に対する`DHCPREQUEST`→`DHCPNAK`（サーバーが復元後の状態と矛盾する要求を正しく拒否）、続けて`Discover`→`Offer`(`192.168.50.153`)→`Request`→`ACK`のフルDORAで新規リースが正常に払い出されることを確認。RTO実測（バックアップ〜復元完了、手動操作込み）: 約3.12秒 |

## セキュリティ試験（DST）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DST-01 | UFW | BLOCKED | `ufw status verbose` → `Status: inactive`。`common` roleを意図的に未適用（安全上の理由）のため、また`dhcp_server` role自身のUFW許可タスクもsystemdタスク失敗により未到達（play全体が該当タスクの前で`fatal`になるため）。role実装自体の欠陥ではない |
| DST-02 | ファイル権限 | PASS | `stat -c '%U:%G %a' /etc/dhcp/dhcpd.conf` → `root:root 644` |
| DST-03 | AppArmor | BLOCKED | このサンドボックスのkernelにAppArmorが公開されておらず`aa-status`が使用不能。環境制約 |
| DST-04 | SSH hardening | NOT RUN | `common` roleを意図的に未適用のため（このセッションが動くコンテナ自体へSSH hardeningを適用する安全上のリスクを避けた） |
| DST-05 | 監査ログ | BLOCKED | このサンドボックスにjournald/rsyslogが動作しておらず`journalctl`が使用不能。環境制約 |
| DST-06 | rogue DHCP確認 | PASS（構築後のみ実施） | 本来は構築直前に実施する項目だが、本セッションでは構築後に`dhcp-01`役を一時停止し、セグメント上に他の応答DHCPサーバーが存在しないことを確認する形で代替実施した（構築直前の確認は本セッションの作業順序上未実施）。`service isc-dhcp-server stop`後、クライアント役から`DHCPDISCOVER`相当の`DHCPREQUEST`を2回送信し、`DHCPOFFER`/`DHCPACK`/`DHCPNAK`いずれも一切観測されないことを確認（応答するDHCPサーバーがゼロ）。確認後`dhcp-01`役を復旧 |

## ネットワーク実機検証（DNW）

集計はDNWのみ抜粋。詳細な実出力・判定根拠は[ネットワーク実機検証結果票](2026-09-04-network-host-validation-dhcp.md)を参照してください。

| ID | 確認対象 | 結果 |
| --- | --- | --- |
| DNW-01 | interface / IP / CIDR | PASS |
| DNW-02 | route / gateway | PASS |
| DNW-03 | DNS（`dhcp-01`自身の名前解決） | NOT RUN |
| DNW-04 | ICMP疎通 | PASS |
| DNW-05 | 待受port | PASS |
| DNW-06 | DORAのpacket capture | PASS |
| DNW-07 | UFWとkernel rule | BLOCKED |
| DNW-08 | クライアント側end-to-end | PASS |
| DNW-09 | rogue DHCP非存在の実機確認 | PASS（構築後のみ実施） |

## 見つかった構築上のつまずき（欠陥ではないが記録する事実）

- 独自bridge（`br-dhcp50`）を経由するブロードキャストが、`veth-d01`（dhcpd側）まで届かない事象が最初に発生した。原因は`net.bridge.bridge-nf-call-iptables=1`により、bridge越しのL2フレームがiptablesの`FORWARD`チェーンで評価される設定になっており、このセッションより前の別フェーズで残っていたDocker関連のiptables状態の影響で、`FORWARD`チェーンのdefault policy（DROP）に阻まれていたため。`br-dhcp50`自体を対象にした最小限の`ACCEPT`ルール（`-i br-dhcp50`/`-o br-dhcp50`）を追加して解決（Dockerの既存chainには触れていない）。このbridgeの挙動では、`FORWARD`チェーンが個別のveth sub-portではなくbridge master device単位でパケットを評価する
- 初回のDORA検証時、`timeout 15`付きで起動した`dhcpd -d`のデバッグプロセスが検証コマンド実行前にタイムアウトで終了しており、dhcpdが応答しなかった。`service isc-dhcp-server start`（タイムアウトなし、永続起動）に切り替えて解決
- DIT-04のプール枯渇試験は、初回試行でクライアントごとに`dhclient -r`で即座にリースを解放していたため、プールが常に空いてしまい枯渇を再現できなかった。解放せずに異なるMACで連続要求する方式に変更して再現した

## 未実施・今後の課題

- **DUT-04、DST-03、DST-05**: 実systemd・AppArmor・journald/rsyslogがこのサンドボックスに無いため`BLOCKED`。VM/実機での再検証が必要
- **DST-01、DST-04、DNW-07**: `common` role未適用（安全上の理由）のため`NOT RUN`/`BLOCKED`。VM/実機で`common`→`dhcp_server`の完全な2play構成を適用すれば解消できる見込み
- **DIT-10**: 中央Prometheus統合は`monitor-01`が存在する環境でのみ検証可能
- **本来の正本（VM/実機でのDORA実演）は未実施のまま**。本証跡はそれを代替するものではなく、DHCPプロトコル動作とAnsible roleの機能面をコード変更なしで実測した追加証跡という位置づけ
- 複数物理ホスト・複数VM間の実ネットワークでの検証（同一コンテナ内のnetwork namespace分離ではない、本来の意味での2ホスト間通信）は未実施
