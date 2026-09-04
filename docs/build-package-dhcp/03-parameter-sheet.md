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
| 実装状態 | `dhcp_server` roleとplaybookは実装済み。ローカルでの`ansible-lint --offline`（production profile）とAnsible構文チェックは通過を確認しているが、対象ホストへの実適用・DORA実演は`NOT RUN`（roleは実装済みで静的チェックはPASS、実ホスト適用はNOT RUNという中間状態。詳細は[要件定義書](00-requirements.md)） |
| 中央監視統合の正本 | `ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`変数（`dhcp-01`を1行追加するだけで完結。`dhcp-01`はLinuxホストのため、Windows/AD版のような「未実装」ブロッカーは無い） |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用手順書バージョン / commit SHA | `NOT SET` — branch名ではなく本リポジトリの40桁commit SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname（論理名） | `dhcp-01` | `NOT RUN` | `ansible/inventory/staging.dhcp.local.yml.example` / `hostnamectl --static` |
| FQDN | 環境ごとに決定 | `NOT RUN` | inventory / `hostname --fqdn` |
| `dhcp-01`自身の静的IP / prefix | `192.168.50.5/24`（動的払い出しプールの対象外として除外） | `NOT RUN` | `ip -br addr` |
| IPアドレスの割り当て方式 | 静的固定IP（DHCPサーバー自身がDHCPクライアントにはならない） | `NOT RUN` | `ip -br addr` |
| 払い出し対象セグメント（served LAN segment） | `192.168.50.0/24` | `NOT RUN` | 本書 / `ip -br addr`、クライアント側の取得IP |
| 払い出しinterface（`dhcp_server_interface`） | 環境ごとに`ip -br link`で実機確認して決定。既定値は空文字で、未設定のままだとrole内`ansible.builtin.assert`で構築が停止する（例: `eth1`） | `NOT RUN` | `ip -br link` / `/etc/default/isc-dhcp-server`の`INTERFACESv4` |
| ゲートウェイ（`option routers`） | `192.168.50.1`（検証環境のルーター役。VirtualBoxならHost-Onlyネットワークのホスト側、実務では既存のL3スイッチ/ルーター） | `NOT RUN` | `ip route` / クライアント側の取得gateway |
| DNSサーバー（`option domain-name-servers`） | `192.168.50.1`（既定はゲートウェイに委譲）、`1.1.1.1`（外部フォールバック。閉域網では除外可） | `NOT RUN` | クライアント側`resolvectl status` |
| ドメイン名（`option domain-name`） | `lab.example.test` | `NOT RUN` | クライアント側`resolvectl status` |
| 管理元CIDR（SSH用、記入例） | 例示管理端末IP`192.0.2.30`を含むCIDRを環境ごとに決定（[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)の記入例と同一。実環境では置換する値） | `NOT RUN` | UFWルールの送信元 |
| SSH user | staging例は`ubuntu`（common role既定を踏襲） | `NOT RUN` | local inventory / `id` |
| SSH port | `22/tcp` | `NOT RUN` | UFW / `ss -lntup` |
| timezone | `Asia/Tokyo` | `NOT RUN` | `timedatectl` |

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
| 払い出し対象セグメント | `192.168.50.0/24` | `NOT RUN` | `dhcpd.conf`の`subnet`宣言 |
| ゲートウェイ（`option routers`） | `192.168.50.1` | `NOT RUN` | クライアント側`ip route`（DIT-08） |
| インフラ用予約帯（未使用/将来のDNSやNTP等） | `192.168.50.2`〜`192.168.50.9` | `NOT RUN` | 本書 / `dhcpd.leases` |
| 固定IP予約帯（host reservation、MACアドレスで予約） | `192.168.50.10`〜`192.168.50.49` | `NOT RUN` | `dhcpd.conf`の`host`ブロック / `dhcpd.leases`（DIT-03） |
| 動的払い出しプール（range） | `192.168.50.100`〜`192.168.50.200`（101個） | `NOT RUN` | `dhcpd.conf`の`range`宣言 / DIT-02、DIT-04 |
| 将来拡張用の未使用帯 | `192.168.50.201`〜`192.168.50.254` | `NOT RUN` | 本書（現時点で用途未定） |
| ドメイン名（`option domain-name`） | `lab.example.test` | `NOT RUN` | クライアント側`resolvectl status`（DIT-08） |
| DNSサーバー（`option domain-name-servers`） | `192.168.50.1`、`1.1.1.1` | `NOT RUN` | クライアント側`resolvectl status` / `cat /etc/resolv.conf`（DIT-08） |
| default-lease-time | `43200`秒（12時間） | `NOT RUN` | `dhcpd.conf` / `dhclient -v`のログ |
| max-lease-time | `86400`秒（24時間） | `NOT RUN` | `dhcpd.conf` |
| T1（renew、目安） | 目安21600秒（50%）。`dhcpd.conf`でdhcp-renewal-time（option 58）を明示指定しないため送信されず、RFC 2131の既定比率に従いクライアント側で計算される | `NOT RUN` | クライアント側`dhclient`のRENEWタイミング観測（説明用、必須試験対象外） |
| T2（rebind、目安） | 目安37800秒（87.5%）。T1と同様、dhcp-rebinding-time（option 59）を明示指定せずクライアント側で計算される | `NOT RUN` | 同上（説明用、必須試験対象外） |
| authoritative宣言 | 有効（`authoritative;`）。このDHCPサーバーが当該セグメントの正であると宣言し、要求外のセグメントで応答した場合はDHCPNAKを返す。他のDHCPサーバーの存在を検知する機構ではない | `NOT RUN` | `dhcpd.conf`。rogue DHCP非存在の確認はDST-06、DNW-09の能動的なスキャンで別途行う |
| ddns-update-style | `none`（Dynamic DNS連携なし、対象外） | `NOT RUN` | `dhcpd.conf` |
| 固定IP予約（`dhcp_server_reservations`） | 既定は空リスト。追加するときは`name`/`mac`/`ip`を1件、動的プール範囲の外側（固定IP予約帯）で指定する | `NOT RUN` | `dhcpd.conf`の`host`ブロック / [実機記入欄](#実機記入欄) |
| 動的プール枯渇時の挙動 | 新規リースを払い出さない（DHCPNAKまたは無応答）。既存リースの継続には影響しない | `NOT RUN` | DIT-04 |

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

下表は引き渡し対象hostごとの記入欄なので、未指定の現時点では`NOT RUN`を維持します。記録時は[検証証跡台帳](../evidence/README.md)の様式に従い、日付付きのevidenceファイル（例: `docs/evidence/YYYY-MM-DD-dhcp-build-validation.md`）へ分けて記録します。原本である本表は直接上書きしません。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OS / kernel（`hostnamectl` / `uname -r`） | `NOT RUN` | — | — |
| `apt-cache policy isc-dhcp-server`の結果 | `NOT RUN` | — | — |
| isc-dhcp-serverバージョン（`dhcpd --version`） | `NOT RUN` | — | — |
| 払い出しinterface名（`ip -br link`） | `NOT RUN` | — | — |
| dhcpd.conf構文検査（`sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf`） | `NOT RUN` | — | — |
| `dhcp.yml`初回適用結果（`failed=`件数） | `NOT RUN` | — | — |
| `dhcp.yml`2回目適用結果（`changed=`件数、冪等性） | `NOT RUN` | — | — |
| rogue DHCP確認（構築直前、DST-06） | `NOT RUN` | — | — |
| DORA実測（取得IP、tcpdumpで観測した4パケット） | `NOT RUN` | — | — |
| 固定予約払い出し確認（登録MACの取得IP） | `NOT RUN` | — | — |
| プール枯渇時の挙動確認 | `NOT RUN` | — | — |
| リース更新・解放確認（RENEW/REBIND、DHCPRELEASE） | `NOT RUN` | — | — |
| サービス再起動後のリース永続化確認 | `NOT RUN` | — | — |
| UFWの許可範囲（`sudo ufw status verbose`） | `NOT RUN` | — | — |
| `/etc/dhcp/dhcpd.conf`の所有者・権限（`stat -c '%U:%G %a'`） | `NOT RUN` | — | — |
| AppArmorの状態（`sudo aa-status \| grep dhcpd`） | `NOT RUN` | — | — |
| サービス停止からの復旧時間（RTO、DIT-09） | `NOT RUN` | — | — |
| バックアップ・復元のRTO（DIT-11） | `NOT RUN` | — | — |
| node_exporter version / `up`メトリクス（DIT-10） | `NOT RUN` | — | — |
| 適用手順書バージョン / commit SHA | `NOT RUN` | — | — |
