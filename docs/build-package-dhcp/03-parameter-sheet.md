# DHCPサーバー パラメータシート

> 💡 **初めて読む方へ**: この文書はネットワーク・DHCP払い出し・監視の具体的な設定値を一覧にした表です。「設計値」と「実績値」の違いは[初心者ガイド](beginner-guide.md#03-パラメータシート)で先に確認してください。

値の正本は `ansible/roles/dhcp_server/defaults/main.yml`、`ansible/playbooks/dhcp.yml`、`ansible/inventory/staging.dhcp.local.yml.example`（構築設定）です。この表はレビューと引き渡し用の索引であり、中央監視host（論理名`monitor-01`）側の設計値は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を正本とします。

「設計値」は本パックのAnsible role・playbook・テンプレートのコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値です。実績欄の`NOT RUN`を、設計値から推測して埋めません。役割・値の背景にある設計判断は[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)を、確認手順の詳細は[ネットワーク実機検証手順](09-network-validation-procedure.md)を参照してください。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-DHCP-001` |
| 対象環境 | 検証用VM 1台（基準）。引き渡し時に実環境名へ置換 |
| 対象ホスト | `dhcp-01`（論理名）。実FQDN / IPは`NOT SET` |
| 中央監視host（既存、変更なし） | `monitor-01`（論理名）。詳細は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を参照 |
| 設定値の正本 | `ansible/roles/dhcp_server/defaults/main.yml`、`ansible/roles/dhcp_server/templates/dhcpd.conf.j2`、`ansible/playbooks/dhcp.yml`、`ansible/inventory/staging.dhcp.local.yml.example` |
| 実装状態 | `dhcp_server` roleとplaybookは実装済み。ローカルでの`ansible-lint --offline`（production profile）とAnsible構文チェックは通過済み。2026-09-04にAI支援セッションのサンドボックスコンテナ上（VM/実機ではなくnetwork namespace + veth + bridgeによる模擬）で`dhcp_server` role単独適用・DORA実演・固定予約・プール枯渇・リース更新解放・バックアップ復元を実測（[結果票](../evidence/2026-09-04-dhcp-build-validation.md)）。**VM/実機での正本実演（本パックの完了条件）は依然`NOT RUN`** |
| 中央監視統合の正本 | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数（`dhcp-01`を1行追加するだけで完結。`dhcp-01`はLinuxホストのため、Windows/AD版のような「未実装」ブロッカーは無い）。実測はNOT RUN（`monitor-01`が検証環境に存在しない） |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用手順書バージョン / commit SHA | サンドボックス実測時点: `27fc7ec8f1cfe41e03466ba859647b0f66b836a0`（2026-09-04）。VM/実機での正本適用時のSHAは別途記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname（論理名） | `dhcp-01` | `dhcp-01`（論理名一致。サンドボックスコンテナ自身をあてたため`hostnamectl --static`による実FQDN確認は対象外） | `ansible/inventory/staging.dhcp.local.yml.example` / `hostnamectl --static` |
| FQDN | 環境ごとに決定 | `NOT RUN`（VM/実機での正本検証が対象） | inventory / `hostname --fqdn` |
| `dhcp-01`自身の静的IP / prefix | `192.168.50.5/24`（動的払い出しプールの対象外として除外） | `192.168.50.5/24`（一致。`ip -br addr`で確認） | `ip -br addr` |
| IPアドレスの割り当て方式 | 静的固定IP（DHCPサーバー自身がDHCPクライアントにはならない） | 静的固定IP（veth手動設定。一致） | `ip -br addr` |
| 払い出し対象セグメント（served LAN segment） | `192.168.50.0/24` | `192.168.50.0/24`（一致。クライアント役が`192.168.50.100`等を取得） | 本書 / `ip -br addr`、クライアント側の取得IP |
| 払い出しinterface（`dhcp_server_interface`） | 環境ごとに`ip -br link`で実機確認して決定。既定値は空文字で、未設定のままだとrole内`ansible.builtin.assert`で構築が停止する（例: `eth1`） | `veth-d01`（サンドボックス構成でのbridge越しveth。VM/実機では別名になる） | `ip -br link` / `/etc/default/isc-dhcp-server`の`INTERFACESv4` |
| ゲートウェイ（`option routers`） | `192.168.50.1`（検証環境のルーター役。VirtualBoxならHost-Onlyネットワークのホスト側、実務では既存のL3スイッチ/ルーター） | `192.168.50.1`（一致。クライアント側`ip route`の`default via`で確認） | `ip route` / クライアント側の取得gateway |
| DNSサーバー（`option domain-name-servers`） | `192.168.50.1`（既定はゲートウェイに委譲）、`1.1.1.1`（外部フォールバック。閉域網では除外可） | `192.168.50.1`、`1.1.1.1`（一致。クライアント側`/etc/resolv.conf`で確認。`resolvectl`はサンドボックス未導入のため`cat /etc/resolv.conf`で代替） | クライアント側`resolvectl status` |
| ドメイン名（`option domain-name`） | `lab.example.test` | `lab.example.test`（一致） | クライアント側`resolvectl status` |
| 管理元CIDR（SSH用、記入例） | 例示管理端末IP`192.0.2.30`を含むCIDRを環境ごとに決定（[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)の記入例と同一。実環境では置換する値） | `NOT RUN`（`common` role未適用のため） | UFWルールの送信元 |
| SSH user | staging例は`ubuntu`（common role既定を踏襲） | `NOT RUN`（`common` role未適用のため） | local inventory / `id` |
| SSH port | `22/tcp` | `NOT RUN`（`common` role未適用のため） | UFW / `ss -lntup` |
| timezone | `Asia/Tokyo` | `NOT RUN`（未確認） | `timedatectl` |

## OS

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| OS | Ubuntu Server 24.04 LTS（noble）のみ。RHEL系は未対応で、role内`ansible.builtin.assert`が`ansible_os_family != 'Debian'`を検出した時点で構築を拒否する | `ansible/roles/dhcp_server/tasks/main.yml` |
| DHCPデーモン | `isc-dhcp-server`（apt package名・systemdサービス名とも同一）。前提として`apt-cache policy isc-dhcp-server`で対象ホストのuniverseリポジトリにパッケージが存在することを構築前に確認する | `ansible/roles/dhcp_server/defaults/main.yml`（`dhcp_server_package` / `dhcp_server_service`） |
| 管理方式 | SSH公開鍵 + sudo | inventory / 対象ホスト |
| 時刻同期 | chrony（unit名`chrony`） | `ansible/roles/common/vars/*.yml` |
| firewall | UFW、default deny incoming | `ansible/roles/common/tasks/firewall-*.yml` |
| SSHブルートフォース対策 | `ufw limit 22/tcp` | 同上 |
| SSH hardening | root login禁止、password login禁止（common role既定を継承、NFR-06） | `ansible/roles/common/tasks/ssh.yml` |
| AppArmor | `isc-dhcp-server`パッケージに同梱のプロファイル`usr.sbin.dhcpd`をenforceモードで維持（roleが新規に生成するものではない、NFR-05） | `sudo aa-status \| grep dhcpd`（DST-03） |
| 自動更新 | unattended-upgrades | `ansible/roles/common/tasks/auto-updates.yml` |
| sshd unit名 | `ssh` | `ansible/roles/common/vars/*.yml` |

## DHCP固有パラメータ

`dhcpd.conf`本体に反映される値です。「実績値」列は対象ホストで`dhcpd -t -cf /etc/dhcp/dhcpd.conf`の構文検査（DUT-01）とDORA実測（DIT-02〜08）を実施するまで、すべて`NOT RUN`のままにします。

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| 払い出し対象セグメント | `192.168.50.0/24` | `192.168.50.0/24`（一致） | `dhcpd.conf`の`subnet`宣言 |
| ゲートウェイ（`option routers`） | `192.168.50.1` | `192.168.50.1`（一致、クライアント側`ip route`で確認） | クライアント側`ip route`（DIT-08） |
| インフラ用予約帯（未使用/将来のDNSやNTP等） | `192.168.50.2`〜`192.168.50.9` | `NOT RUN`（未使用帯のため払い出し試験の対象外） | 本書 / `dhcpd.leases` |
| 固定IP予約帯（host reservation、MACアドレスで予約） | `192.168.50.10`〜`192.168.50.49` | `192.168.50.20`（`fe:b8:0b:ac:82:84`を予約し、動的プールのIPをヒントに出しても予約IPが優先されることを確認） | `dhcpd.conf`の`host`ブロック / `dhcpd.leases`（DIT-03） |
| 動的払い出しプール（range） | `192.168.50.100`〜`192.168.50.200`（101個） | `192.168.50.100`（DORA実測で取得）。プール枯渇試験は一時的に`192.168.50.150`〜`151`（2個）へ縮小して実施、試験後に設計値へ復元 | `dhcpd.conf`の`range`宣言 / DIT-02、DIT-04 |
| 将来拡張用の未使用帯 | `192.168.50.201`〜`192.168.50.254` | `NOT RUN`（現時点で用途未定） | 本書（現時点で用途未定） |
| ドメイン名（`option domain-name`） | `lab.example.test` | `lab.example.test`（一致、クライアント側`/etc/resolv.conf`で確認） | クライアント側`resolvectl status`（DIT-08） |
| DNSサーバー（`option domain-name-servers`） | `192.168.50.1`、`1.1.1.1` | `192.168.50.1`、`1.1.1.1`（一致） | クライアント側`resolvectl status` / `cat /etc/resolv.conf`（DIT-08） |
| default-lease-time | `43200`秒（12時間） | `43200`秒（一致）。RENEW試験は一時的に`20`秒へ短縮して実施、試験後に復元 | `dhcpd.conf` / `dhclient -v`のログ |
| max-lease-time | `86400`秒（24時間） | `86400`秒（一致）。RENEW試験は一時的に`40`秒へ短縮して実施、試験後に復元 | `dhcpd.conf` |
| T1（renew、目安） | 目安21600秒（50%）。`dhcpd.conf`でdhcp-renewal-time（option 58）を明示指定しないため送信されず、RFC 2131の既定比率に従いクライアント側で計算される | 短縮lease時間（20秒）でT1相当（約20秒後）にunicast `DHCPREQUEST`→`DHCPACK`の2パケットRENEWを実測（新規`Discover`/`Offer`を介さない） | クライアント側`dhclient`のRENEWタイミング観測（説明用、必須試験対象外） |
| T2（rebind、目安） | 目安37800秒（87.5%）。T1と同様、dhcp-rebinding-time（option 59）を明示指定せずクライアント側で計算される | `NOT RUN`（短縮lease時間の試験ではRENEWが継続的に成功しREBINDまで到達しなかった） | 同上（説明用、必須試験対象外） |
| authoritative宣言 | 有効（`authoritative;`）。このDHCPサーバーが当該セグメントの正であると宣言し、要求外のセグメントで応答した場合はDHCPNAKを返す。他のDHCPサーバーの存在を検知する機構ではない | 有効（`dhcpd.conf`に`authoritative;`を確認）。復元後の古いリース要求に対し実際に`DHCPNAK`を返すことをDIT-11で確認 | `dhcpd.conf`。rogue DHCP非存在の確認はDST-06、DNW-09の能動的なスキャンで別途行う |
| ddns-update-style | `none`（Dynamic DNS連携なし、対象外） | `none`（一致） | `dhcpd.conf` |
| 固定IP予約（`dhcp_server_reservations`） | 既定は空リスト。追加するときは`name`/`mac`/`ip`を1件、動的プール範囲の外側（固定IP予約帯）で指定する | `client01-fixed`（`fe:b8:0b:ac:82:84` → `192.168.50.20`）を1件登録し動作確認済み | `dhcpd.conf`の`host`ブロック / [実機記入欄](#実機記入欄) |
| 動的プール枯渇時の挙動 | 新規リースを払い出さない（DHCPNAKまたは無応答）。既存リースの継続には影響しない | 無応答（`DHCPDISCOVER`を3回再送するも`DHCPOFFER`なし、`timeout 8`でEXIT 124）を実測 | DIT-04 |

## Ansible変数対応表

`ansible/roles/dhcp_server/defaults/main.yml`の全変数です。値を変えるときは`dhcpd.conf.j2`テンプレートではなく、これらの変数を`ansible/inventory/staging.dhcp.local.yml`（`.example`をコピーして作成、`.gitignore`対象）またはplaybook実行時の`-e`で上書きします。

| Ansible変数 | 既定値 | 説明 |
| --- | --- | --- |
| `dhcp_server_package` | `isc-dhcp-server` | インストールするaptパッケージ名 |
| `dhcp_server_service` | `isc-dhcp-server` | 有効化・起動するsystemdサービス名（パッケージ名と同一） |
| `dhcp_server_interface` | `""`（空文字） | 払い出し対象セグメントへbindするinterface名。既定値のままだとrole内`ansible.builtin.assert`が構築を拒否する。`ip -br link`で実機確認してからinventoryで指定する（例: `eth1`） |
| `dhcp_server_authoritative` | `true` | `dhcpd.conf`に`authoritative;`を書き込むかどうか |
| `dhcp_server_subnet` | `192.168.50.0` | `subnet`宣言の対象ネットワークアドレス |
| `dhcp_server_netmask` | `255.255.255.0` | 同上のサブネットマスク（`option subnet-mask`にも使用） |
| `dhcp_server_range_start` | `192.168.50.100` | 動的払い出しプールの開始IP |
| `dhcp_server_range_end` | `192.168.50.200` | 動的払い出しプールの終了IP |
| `dhcp_server_routers` | `[192.168.50.1]` | `option routers`（デフォルトゲートウェイ）。複数指定可能なリスト |
| `dhcp_server_dns_servers` | `[192.168.50.1, 1.1.1.1]` | `option domain-name-servers` |
| `dhcp_server_domain_name` | `lab.example.test` | `option domain-name` |
| `dhcp_server_default_lease_time` | `43200`（秒、12時間） | `default-lease-time` |
| `dhcp_server_max_lease_time` | `86400`（秒、24時間） | `max-lease-time` |
| `dhcp_server_reservations` | `[]`（空リスト） | 固定IP予約（`name`/`mac`/`ip`を持つ辞書のリスト）。1件追加すると`dhcpd.conf`に`host`ブロックが1つ生成される |
| `dhcp_server_manage_firewall` | `true` | UFWルールの管理をこのroleが行うかどうか（`common_manage_firewall`と同じ切り替え方針） |
| `dhcp_server_interface` | （既定は空文字。inventoryで指定） | UDP 67のUFW許可対象interface。DHCPDISCOVERの送信元は`0.0.0.0`のため送信元CIDRでは絞れず、`dhcp_server_interface`（払い出し対象セグメント側interface）で許可範囲を限定する |

これらの変数は、`ansible.builtin.assert`によって「変更前に検証する」方針（interface名の書式、各IPアドレスの書式、lease時間の大小関係、UFW CIDRの書式、予約のname/MAC/IPの重複有無を含む）で全入力を検査してから`/etc/dhcp/dhcpd.conf`へ反映されます。テンプレート適用時も`ansible.builtin.template`の`validate`パラメータで`dhcpd -t -cf %s`を実行し、構文エラーのある設定は反映前に拒否されます（詳細は[詳細設計書](02-detailed-design.md)）。

## 公開ポート

| Port/Proto | Service | Bind/送信元制限 | 用途 |
| --- | --- | --- | --- |
| 22/tcp | SSH | UFW `LIMIT`（全送信元）。production受入では上流FW/VPNまたはsource指定UFW ruleで管理元CIDRのみ | 構築・運用 |
| 67/udp | isc-dhcp-server（DHCPサーバー） | UFWで払い出し対象interface（`dhcp_server_interface`）限定で許可。他セグメント・インターネットへは非公開 | DHCPペイロード（DISCOVER/REQUEST受信） |
| 68/udp | DHCPクライアント側（`dhcp-01`自身は使わない） | — | クライアントの受信port（参考情報として記載） |
| 9100/tcp | node_exporter | 中央Prometheus host（`monitor-01`）からのみ許可 | 中央監視統合 |

## 実機記入欄

下表は引き渡し対象hostごとの記入欄です。以下は2026-09-04にAI支援セッションのサンドボックスコンテナ上（VM/実機ではない。範囲は[構築・試験結果票](../evidence/2026-09-04-dhcp-build-validation.md)の「この証跡が示す範囲」を参照）で実測した値です。VM/実機での正本検証はまだ実施しておらず、該当欄は`NOT RUN`のまま残しています。原本である本表を直接上書きせず日付付きevidenceへ記録する原則どおり、詳細な実出力は[結果票](../evidence/2026-09-04-dhcp-build-validation.md)を正とします。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OS / kernel（`hostnamectl` / `uname -r`） | Ubuntu 24.04.4 LTS、`6.18.44-fc-v24` | 2026-09-04 | [結果票](../evidence/2026-09-04-dhcp-build-validation.md) |
| `apt-cache policy isc-dhcp-server`の結果 | Installed/Candidate: `4.4.3-P1-4ubuntu2`（`noble/universe`） | 2026-09-04 | 同上 |
| isc-dhcp-serverバージョン（`dhcpd --version`） | `isc-dhcpd-4.4.3-P1` | 2026-09-04 | 同上 |
| 払い出しinterface名（`ip -br link`） | `veth-d01`（サンドボックス構成固有。VM/実機では別名になる） | 2026-09-04 | 同上 |
| dhcpd.conf構文検査（`sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf`） | exit 0（エラーなし） | 2026-09-04 | 同上（DUT-01） |
| `dhcp.yml`初回適用結果（`failed=`件数） | `failed=1`（systemdタスクのみ。環境にsystemdが無いための失敗で、role側の6タスクは`ok`） | 2026-09-04 | 同上（DIT-01） |
| `dhcp.yml`2回目適用結果（`changed=`件数、冪等性） | `changed=0`（systemdタスク以外の6タスクで冪等性を確認） | 2026-09-04 | 同上（DIT-01） |
| rogue DHCP確認（構築直前、DST-06） | 構築後のみ実施（応答するDHCPサーバー0件） | 2026-09-04 | 同上（DST-06） |
| DORA実測（取得IP、tcpdumpで観測した4パケット） | `192.168.50.100`。Discover→Offer→Request→ACKの4パケットを`tcpdump -v`で確認 | 2026-09-04 | 同上（DIT-02） |
| 固定予約払い出し確認（登録MACの取得IP） | `fe:b8:0b:ac:82:84` → `192.168.50.20`（動的プールのIPヒントを上書きして予約IPを払い出し） | 2026-09-04 | 同上（DIT-03） |
| プール枯渇時の挙動確認 | 2アドレスのプールで枯渇後、新規クライアントに`DHCPOFFER`なし（3回再送後timeout） | 2026-09-04 | 同上（DIT-04） |
| リース更新・解放確認（RENEW/REBIND、DHCPRELEASE） | RENEW: unicast `DHCPREQUEST`→`DHCPACK`の2パケットを実測。REBINDは未到達（RENEWが継続成功）。RELEASE: `dhclient -r`後に`binding state free;`への遷移を確認 | 2026-09-04 | 同上（DIT-05、DIT-07） |
| サービス再起動後のリース永続化確認 | `service isc-dhcp-server restart`前後でリース内容（hardware ethernet、starts/ends）が保持 | 2026-09-04 | 同上（DIT-06） |
| UFWの許可範囲（`sudo ufw status verbose`） | `Status: inactive`（`common` role未適用のため） | 2026-09-04 | 同上（DST-01、BLOCKED） |
| `/etc/dhcp/dhcpd.conf`の所有者・権限（`stat -c '%U:%G %a'`） | `root:root 644` | 2026-09-04 | 同上（DST-02） |
| AppArmorの状態（`sudo aa-status \| grep dhcpd`） | `NOT RUN`（サンドボックスにAppArmorカーネルモジュールなし） | — | 同上（DST-03、BLOCKED） |
| サービス停止からの復旧時間（RTO、DIT-09） | 約2.06秒（手動復旧、起動コマンドのみの参考値） | 2026-09-04 | 同上（DIT-09） |
| バックアップ・復元のRTO（DIT-11） | 約3.12秒（手動操作込みの参考値）。復元後に新規DORAで`192.168.50.153`を正常払い出し | 2026-09-04 | 同上（DIT-11） |
| node_exporter version / `up`メトリクス（DIT-10） | `NOT RUN`（`monitor-01`が検証環境に存在しない） | — | 同上（DIT-10） |
| 適用手順書バージョン / commit SHA | `27fc7ec8f1cfe41e03466ba859647b0f66b836a0` | 2026-09-04 | 同上 |
