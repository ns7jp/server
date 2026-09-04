# DHCPサーバー構築 構築・試験結果票 — 2026-09-04

[試験仕様書・結果票](../build-package-dhcp/06-test-specification.md)の原本をコピーし、`ansible/roles/dhcp_server/` + `ansible/playbooks/dhcp.yml`を実際のホストへ適用した結果を記入したものです。原本は`NOT RUN`のまま保持し、実施結果はこの日付付きファイルへ記録します。

> **この証跡が示す範囲**: 独立した物理／VPSホストや`dhcp-01`に相当する実VMではなく、**AI支援セッションのサンドボックスコンテナ内にnetwork namespaceで組んだラボ**（[`labs/dhcp-lab/topology.sh`](../../labs/dhcp-lab/topology.sh)と同じ構成、`dhcp01`＝DHCPサーバー役、`client01`＝クライアント役、`mgmt-ctrl`＝管理端末役）に対する実施記録です。SSH・Ansible適用・DORA・固定予約・プール枯渇・RENEW・再起動・停止復旧・バックアップ復元・rogue DHCP確認はすべて実コマンドと実出力で確認していますが、次の点でLinux/AD/Zabbixパックの実機検証と条件が異なります。
>
> - このサンドボックス自体に`systemd`がPID 1として動いていないため、`isc-dhcp-server`の起動・停止・再起動はすべて手動（`dhcpd`を直接起動・`pkill`で停止）で行いました。Ansible側は`dhcp_server_manage_service: false`（inventory側の一時上書き）で`systemd` unitのenable/startタスクをスキップしています。実運用（`dhcp_server_manage_service`の既定値`true`）ではAnsibleが`systemctl enable --now`相当を実行します。
> - AppArmor LSMがロードされていないため、DST-03は`SKIP-ENV`です。
> - `journald`/`rsyslog`のいずれも動いておらず`/dev/log`も存在しないため、`journalctl`によるDST-05（監査ログ）は`SKIP-ENV`です。dhcpdの`log-facility local7`設定自体は構文検査済みです。
> - `monitor-01`に相当する監視サーバーがこのラボに存在しないため、DIT-10（監視統合）は`SKIP-ENV`です。
> - DNS実装（named等）を用意していないため、DNW-03（`dhcp-01`自身の名前解決）は`SKIP-ENV`です。
>
> これらは[Zabbix実機検証](2026-09-04-zabbix-build-validation.md)・[Ansible自動化基盤 実機検証](2026-09-04-ansible-foundation-build.md)と同じ「サンドボックス制約の範囲」であることを明記した上で記録します。DORA・固定予約・プール枯渇・RENEW（unicast）・冪等性・再起動後のリース永続化・リース解放・バックアップ復元・rogue DHCP確認は、いずれも**本物のDHCPプロトコルのやり取り**（`dhclient`、`scapy`で生成した実パケット、`tcpdump`キャプチャ）で確認しており、モック・スタブではありません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | **DUT-01〜05、DIT-01〜09・11、DST-01・02・04・06が全件`PASS`**。DIT-10・DST-03・DST-05・DNW-03は環境制約により`SKIP-ENV`（理由は上記「この証跡が示す範囲」参照）。ネットワーク実機検証（DNW-01〜09）は[別紙](2026-09-04-network-host-validation-dhcp.md)に記録 |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | AI支援セッション（ユーザー: net7jp） |
| 対象環境 / host | `dhcp01`（network namespace、`ansible_host=10.99.0.30`、払い出しセグメント側`seg0=192.168.50.5/24`） |
| 管理端末 / controller | AI支援セッションの作業環境（rootのnetwork namespace、`mgmt-ctrl=10.99.0.1/24`） |
| クライアント検証VM | `client01`（network namespace、`seg0`はDHCPで取得。実MAC`06:d4:96:24:e7:91`） |
| commit SHA | `ebcae209aac82811bc5fc49291c597c519f7c408` |
| OS / kernel | Ubuntu 24.04.4 LTS（ホストと同一。network namespaceはファイルシステムを共有するため） |
| isc-dhcp-server バージョン | `isc-dhcpd-4.4.3-P1` |
| Ansibleバージョン | `ansible-core 2.19.12` |
| `dhcp_server_interface`（実機値） | `seg0` |

秘密値・公開IPは含まれていません（`192.168.50.0/24`・`10.99.0.0/24`はいずれもこのラボ専用のプライベート/検証用アドレス）。

## 単体・構成試験（DUT）

| ID | 試験 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DUT-01 | dhcpd.conf構文検査 | PASS | `dhcpd -t -cf /etc/dhcp/dhcpd.conf` → exit 0（Ansible適用の`validate:`でも毎回通過） |
| DUT-02 | Ansible構文チェック | PASS | `ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --syntax-check` → `playbook: playbooks/dhcp.yml`のみで正常終了 |
| DUT-03 | ansible-lint | PASS | `ansible-lint --offline`（`ansible/`直下、`.ansible-lint`のprofile: productionが既定） → `Passed: 0 failure(s), 0 warning(s) in 78 files processed of 86 encountered. Profile 'production' was required, and it passed.` |
| DUT-04 | systemdユニット有効化 | PASS（要注記） | `systemctl is-enabled isc-dhcp-server` → `enabled`。ただしこの結果は**Ansibleの「Enable and start」タスクではなく、`isc-dhcp-server` debパッケージのpostinst（`deb-systemd-helper`）が導入時に既定でenableした結果**（今回`dhcp_server_manage_service: false`でAnsible側のenable/startタスク自体はスキップしている）。`dhcp_server_manage_service: true`（既定値）の環境では、Ansibleの`ansible.builtin.systemd: enabled: true`タスク自体もこの状態を明示的に保証する |
| DUT-05 | 成果物リンク | PASS | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` → `1 passed, 52 deselected` |

## 構築・結合試験（DIT）

| ID | 試験 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DIT-01 | 新規構築・冪等性 | PASS | `dhcp.yml`初回適用: `ok=46 changed=16 failed=0 skipped=16`（`isc-dhcp-server`は事前に未導入の状態から実施し、真の新規導入を確認）。直後の2回目適用: `ok=46 changed=0 failed=0 skipped=14` |
| DIT-02 | DORA実測 | PASS | `client01`で`dhclient -v seg0`実行。`tcpdump -i seg0 udp port 67 or 68`で4パケット（DISCOVER→OFFER→REQUEST→ACK）を実キャプチャ。取得IP`192.168.50.100`（プール範囲内）、`dhclient`ログに`DHCPOFFER of 192.168.50.100 from 192.168.50.5`〜`bound to 192.168.50.100`を記録 |
| DIT-03 | 固定予約 | PASS | `client01`の実MAC（`06:d4:96:24:e7:91`）を`dhcp_server_reservations`へ登録し再適用（`changed=1`、dhcpd.conf中の`host client01-fixed { hardware ethernet ...; fixed-address 192.168.50.50; }`を確認）。再起動後に`dhclient`実行 → 常に`192.168.50.50`（プール範囲外の固定IP）を取得 |
| DIT-04 | プール枯渇 | PASS | `scapy`でMACアドレスを変えた103台分のDISCOVER→REQUEST→ACKを送出するスクリプトを実行。プール（`192.168.50.100`〜`.200`、101個）ちょうど101台目まで正常にACKを取得し、102台目（`i=101`）はDHCPOFFERが一切返らない（無応答）ことを確認。dhcpdのログにも`Wrote 1 leases to leases file`等、枯渇後の内部状態変化が記録された |
| DIT-05 | リース更新 | PASS（REBIND分岐は未観測、理由は備考） | `dhcp_server_default_lease_time`を一時的に310秒へ変更（**実機確認: isc-dhcp-server 4.4.3-P1は300秒以下を指定しても実際の払い出しを300秒へ暗黙にクランプするため、301秒以上を使う必要があった**。詳細は下記「見つかった欠陥」参照）。`client01`で`dhclient -v seg0`（foreground）を起動し続け、T1到達ごとに**unicast**のDHCPREQUEST→DHCPACK（`192.168.50.50.68 > 192.168.50.5.67`、broadcastではなく相手を指定したunicast）で自動更新されることを、`tcpdump`のキャプチャと`dhclient.leases`のrenew/rebind/expire予測値の両方で複数回（別々の観測セッションを合わせて計5回のunicast RENEW成功）にわたり確認した。REBIND（T2、broadcast）を強制するため`iptables -I INPUT -i seg0 -p udp --dport 67 -j DROP`でRENEWを意図的に遮断しようと試みたが、**dhcpdはinterfaceに直結したraw socket(LPF)で受信するためnetfilterのINPUT chainを経由せず、このDROPルールはdhcpdの受信に一切影響しなかった**（対照実験として同じ形のDROPルールが通常のUDPソケット（`nc`）宛の通信は確実に遮断することも確認済み）。そのためRENEWが常に成功し、REBINDへ遷移する状況を本ラボでは再現できなかった。これは試験の失敗ではなく、dhcpdの受信経路そのものに関する重要な実機発見であり、「見つかった欠陥」に記録した |
| DIT-06 | 再起動後のリース永続化 | PASS | 動的リース1件（`192.168.50.100`、`hardware ethernet 02:00:00:aa:bb:cc`）を作成後、`dhcpd`を`kill -TERM`→手動再起動。再起動後も同一の`starts`/`ends`/`hardware ethernet`を持つリースエントリが保持されていることを`dhcpd.leases`で確認（`tstp`行が追加されるのみ） |
| DIT-07 | リース解放 | PASS | 上記リースに対し`scapy`でDHCPRELEASEを送出。`dhcpd.leases`の最新エントリが`binding state active` → `binding state free`へ遷移したことを確認。journalへの記録確認は`SKIP-ENV`（このサンドボックスに`journald`/`rsyslog`が無いため。DST-05と同一理由） |
| DIT-08 | オプション配布 | PASS | DIT-02のDORA後、`client01`の`ip route`→`default via 192.168.50.1 dev seg0`、`/etc/resolv.conf`→`domain lab.example.test` / `search lab.example.test` / `nameserver 192.168.50.1` / `nameserver 1.1.1.1`。いずれも設計値（[パラメータシート](../build-package-dhcp/03-parameter-sheet.md)）と一致 |
| DIT-09 | サービス停止復旧 | PASS | `dhcpd`を`pkill -9`で停止（`ss -lunp`でUDP 67の待受消失を確認）→手動で再起動→`client01`から**完全なDORA**（DISCOVER→OFFER→REQUEST→ACK、`scapy`で全4段階を実施）を送出しACKを取得したことを、`dhcpd.leases`に新規`lease 192.168.50.101 { ... binding state active; hardware ethernet 02:00:00:aa:bb:01; }`が追加されたことで確認。停止時刻`09:27:46`UTC、復旧（新規リース確定）確認時刻`09:27:57`UTC、**RTO ≈ 11秒**（手動検知・手動復旧。自動監視によるRTOではない。DIT-10がSKIP-ENVのため自動アラートは前提にできない）。※初回実施時はDISCOVER→OFFERのみのスクリプトを誤って使い「ACK取得」と記録していたが、アドバーサリアル検証でリースファイルに新規エントリが無いことから指摘を受け、完全なDORAスクリプトで再実施し直した |
| DIT-10 | 監視統合 | SKIP-ENV | このラボに`monitor-01`（Prometheus/Grafana監視サーバー）が存在しないため未実施。`ansible/playbooks/dhcp.yml`自体はnode_exporterを含まない設計（[05-build-procedure.md](../build-package-dhcp/05-build-procedure.md)参照、監視統合は別途`site.yml`側の責務） |
| DIT-11 | バックアップ・復元 | PASS | `dhcpd.conf`・`dhcpd.leases`をバックアップ（`09:28:06`UTC）→`dhcpd.leases`を破損データで上書き→`08-change-rollback-plan.md`の手順どおり`systemctl stop`相当→バックアップから復元→`dhcpd -t`で構文確認（exit 0）→復元後の`dhcpd.leases`のmd5sumがバックアップ取得時と完全一致することを確認→再起動→`client01`から**完全なDORA**を送出しACKを取得したことを、`dhcpd.leases`に新規`lease 192.168.50.102 { ... binding state active; hardware ethernet 02:00:00:aa:bb:02; }`が追加されたことで確認（`09:28:22`UTC）。**RTO（バックアップ完了〜復元後DORA正常化）≈ 16秒**。※DIT-09と同じ理由で、DISCOVER→OFFERのみの簡易確認から完全なDORA確認へ差し替えて再実施した |

## セキュリティ試験（DST）

| ID | 試験 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| DST-01 | UFW | PASS | `ufw status verbose` → `Default: deny (incoming), allow (outgoing)`、`67/udp on seg0 ALLOW IN Anywhere`（`seg0`限定）、`22/tcp LIMIT IN Anywhere`。他ネットワークへの許可なし。※実際の受信制御は`INTERFACESv4`が担っている点はDIT-05の備考および「見つかった欠陥」参照 |
| DST-02 | ファイル権限 | PASS | `stat -c '%U:%G %a' /etc/dhcp/dhcpd.conf` → `root:root 644` |
| DST-03 | AppArmor | SKIP-ENV | このサンドボックスにAppArmor LSMがロードされていない（`aa-status`実行不可）。既知の環境制約（Linux/AD/Zabbixパックの実機検証と同様） |
| DST-04 | SSH hardening | PASS | `sshd -T \| grep -E 'permitrootlogin\|passwordauthentication'` → `permitrootlogin no`、`passwordauthentication no` |
| DST-05 | 監査ログ | SKIP-ENV | `journald`/`rsyslog`のいずれも動作しておらず`/dev/log`も存在しないため`journalctl`が使えない。dhcpd自体は`log-facility local7`で構成済み（構文検査PASS）だが、受け皿となるsyslogデーモンがこのサンドボックスに無いため送出先での記録確認はできない |
| DST-06 | rogue DHCP確認（構築直前相当） | PASS | `dhcpd`を一旦停止した状態で（1）`nmap --script broadcast-dhcp-discover -e seg0 -Pn -n 192.168.50.5`実行 → DHCP応答なし（スクリプト結果セクションが出力されない）、（2）`scapy`で素のDISCOVERを送出 → `NO OFFER`。2方式で「応答するDHCPサーバーが1台もない」ことを確認。※本来は初回`dhcp.yml`適用前に実施するタイミングの試験だが、本ラボでは`dhcpd`停止状態を作って事後的に再現した（[試験仕様書](../build-package-dhcp/06-test-specification.md)のDST-06節が要求するタイミングとは異なることを明記する） |

ネットワーク実機検証（DNW-01〜09）は[別紙](2026-09-04-network-host-validation-dhcp.md)に記録した。

## 見つかった欠陥

実行して初めて見つかった実装上の欠陥・仕様理解のギャップが3件あります。詳細は[欠陥台帳](defects-found.md)（#31〜#33）を参照してください。

1. **`common`ロールの欠陥（#31）**: Ubuntu 24.04では`hwclock`が`util-linux`パッケージから`util-linux-extra`パッケージへ分離されており、`common_os_packages`（Debian系）に`util-linux`しか無かったため、`community.general.timezone`タスクが`Failed to find required executable "hwclock"`で失敗した。全パック共通の`common`ロールに影響する欠陥で、`ansible/roles/common/vars/Debian.yml`へ`util-linux-extra`を追加して修正済み（本PRに含む）。
2. **isc-dhcp-serverの仕様（#32）**: `default-lease-time`に300秒以下を指定しても、実際に払い出す`lease-time`（DHCPACKのoption 51）を300秒へ暗黙にクランプする。`dhcpd -t`の構文検査は通過するため設定ミスとして気づきにくい。値を60→100→299→300→301→500→3600と変えながら実測し、300秒がしきい値であることを確認した。`ansible/roles/dhcp_server/defaults/main.yml`の`dhcp_server_default_lease_time`にコメントで注記済み（本PRに含む）。
3. **UFWがdhcpdの受信を実際には制御していない（#33）**: isc-dhcp-serverはLinux上でinterfaceに直結したraw socket（LPF）経由でDHCPパケットを受信するため、netfilter（iptables/UFW）のINPUT chainを経由しない。`iptables -I INPUT`でUDP 67宛を明示的にDROPしても、dhcpdは変わらず受信・応答した（対照実験として、通常のUDPソケット宛の通信は同じ形のDROPルールで確実に遮断されることを確認済み）。実際にinterfaceを絞っているのは`/etc/default/isc-dhcp-server`の`INTERFACESv4`であり、UFWのallow ruleはdhcpdの受信自体には効いていない。セキュリティ上の実害は無い（`INTERFACESv4`が正しく機能している限りinterface制限は保たれる）が、「UFWがinterfaceを絞っている」という説明はdhcpdについては不正確なため、`ansible/roles/dhcp_server/defaults/main.yml`のコメントを訂正した（本PRに含む）。

## 見つかった構築上のつまずき（欠陥ではないが記録する事実）

- **サンドボックス自身の`eth0`が`192.0.2.0/24`（RFC 5737 TEST-NET-1）を使用しており**、ラボの管理リンクに同じ帯域を使うと衝突して疎通しなくなった。パラメータシート等の記入例が使う`192.0.2.0/24`はあくまで文書上のプレースホルダであり、本ラボの管理リンクは`10.99.0.0/24`という別帯域を使うことで回避した（[topology.sh](../../labs/dhcp-lab/topology.sh)のコメント参照）。
- **手動起動した`dhcpd`をkillした直後にpidfileを消さずに再起動しようとすると失敗する**。このサンドボックスのPID 1（Firecracker系のinit）がreparentされたzombieプロセスを即座にreapしないことがあり、`dhcpd`が「既に起動中」と誤認して起動を拒否する。`/run/dhcpd.pid`を明示的に削除してから再起動することで回避した。`dhcp_server_manage_service: true`（既定）でsystemd管理下にある実運用環境では発生しない、このサンドボックス固有の制約。
- `dhcp01`のnetwork namespaceは既定でインターネット疎通が無く（プライベートなveth linkしか持たないため）、`common`ロールのパッケージインストールが`Temporary failure resolving 'archive.ubuntu.com'`で失敗した。`sysctl net.ipv4.ip_forward=1` + `iptables -t nat -A POSTROUTING -s 10.99.0.0/24 -o eth0 -j MASQUERADE` + `dhcp01`側のdefault route追加でNAT越しの疎通を確立し、実際のパッケージインストールを本物のapt経由で完走させた（ICMP（ping）はサンドボックスの外側ネットワークポリシーで遮断されているが、TCP/DNS/HTTPは正常に機能する）。

## 未実施・今後の課題

- DIT-10（監視統合）: `monitor-01`が無いため`SKIP-ENV`。将来、Linux/ADパックと同様に監視サーバーを用意できた時点で実施する。
- DST-03（AppArmor）・DST-05（監査ログ）: このサンドボックスの環境制約による`SKIP-ENV`。実VM/実ホスト（systemd + AppArmor + journald/rsyslogが揃う環境）で再実施すればPASSする見込み。
- DIT-05のREBIND（T2、broadcast）分岐: 上記のとおりdhcpdのraw socket受信によりRENEW遮断を再現できず未観測。異なる手段（dhcpd自体のプロセスを一時停止する等、ただし停止するとRENEW/REBINDどちらも試行不能になるため要検討）での再現は今後の課題。
- 独立した物理／VPSホストでの再実施（本証跡はAI支援セッションのサンドボックス内netnsラボでの実施であり、Linux/ADパックのような独立ホストでの検証ではない）。
