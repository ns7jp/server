# DHCP実ホスト ネットワーク検証結果票 — 2026-09-04

[実行手順](../build-package-dhcp/09-network-validation-procedure.md)に沿って、AI支援セッションのサンドボックスコンテナ上に構築したDHCP環境で実施した結果です。「この証跡が示す範囲」は[構築・試験結果票](2026-09-04-dhcp-build-validation.md)を参照してください（VM/実機ではなく、network namespace + veth + bridgeで模擬した単一コンテナ内の検証です）。

> 別のAI支援セッションが`labs/dhcp-lab/`（隔離されたnetwork namespaceラボ）で独立に実施したネットワーク結果票は[`2026-09-04-network-host-validation-dhcp-netns-lab.md`](2026-09-04-network-host-validation-dhcp-netns-lab.md)を参照してください。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | DNW-01/02/04/05/06/08/09が`PASS`。DNW-03が`NOT RUN`、DNW-07が`BLOCKED`（詳細は下記） |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | ns7jp（AI支援セッション） |
| 対象環境 / host | サンドボックスコンテナ自身（`dhcp-01`役）。veth `veth-d01`（`192.168.50.5/24`）をbridge `br-dhcp50`経由でクライアント役netnsへ接続 |
| 管理端末 | 同一コンテナ内（`ansible_connection: local`） |
| クライアント検証VM | `client01`という別network namespace内のveth `veth-cli`（複数MACアドレスで複数クライアントを模擬） |
| commit SHA | `27fc7ec8f1cfe41e03466ba859647b0f66b836a0` |
| OS / kernel | Ubuntu 24.04.4 LTS、kernel `6.18.44-fc-v24` |
| isc-dhcp-server バージョン | `isc-dhcpd-4.4.3-P1`（`4.4.3-P1-4ubuntu2`） |
| 構成図・IP 表の版 | [04-network-ip-plan.md](../build-package-dhcp/04-network-ip-plan.md)（本セッション時点のHEAD） |
| raw log / screenshot | 本ファイル内に実出力を直接記載（tcpdumpのpcapはAI支援セッションの一時ディレクトリのみに存在し、リポジトリへはcommitしていない） |

公開 IP、管理元 IP、MAC address、account ID、秘密値は本パックの設計上扱っていないため、マスク対象はありません。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| DNW-01 | interface / IP / CIDR | `ip -br addr` | 設計値と一致 | PASS | 本書「DNW-01」 |
| DNW-02 | route / gateway | `ip route` | 想定 gateway / device / source | PASS | 本書「DNW-02」 |
| DNW-03 | DNS（`dhcp-01`自身の名前解決） | `dig`, `getent`, `resolvectl` | 想定 record と resolver | NOT RUN | 本書「DNW-03」 |
| DNW-04 | ICMP | `ping` | 方針どおりの疎通または遮断 | PASS | 本書「DNW-04」 |
| DNW-05 | 待受port（UDP 67、TCP 22/9100） | `ss -lunp`, `ss -lntup` | 設計どおりの待受のみ | PASS | 本書「DNW-05」 |
| DNW-06 | DORAのpacket capture | `tcpdump -nn -i <interface> udp port 67 or port 68` | DISCOVER/OFFER/REQUEST/ACKの4パケットを観測 | PASS | 本書「DNW-06」 |
| DNW-07 | host firewall | `ufw status verbose`, `nft` / `iptables` | UDP 67は払い出し対象セグメント限定、他は非公開 | BLOCKED | 本書「DNW-07」 |
| DNW-08 | クライアント側end-to-end | クライアントVMで`sudo dhclient -v <interface>` | 設計どおりのプール範囲でリースを取得 | PASS | 本書「DNW-08」 |
| DNW-09 | rogue DHCP非存在 | 応答元サーバーIPの確認 | 応答するDHCPサーバーが`dhcp-01`のみ | PASS（構築後のみ実施） | 本書「DNW-09」 |

## 実出力

### DNW-01 interface / IP / CIDR

仮説・期待値:

```text
dhcp-01(役)自身の静的IPは設計値192.168.50.5/24（04-network-ip-plan.md）と一致するはず
```

実行コマンド:

```bash
ip -br addr show veth-d01
```

実出力（要点）:

```text
veth-d01@veth-d01-br UP             192.168.50.5/24
```

判定 / 設計との差:

```text
設計値192.168.50.5/24と完全一致。差異なし。PASS
```

### DNW-02 route / gateway

```text
期待値: 払い出し対象セグメント192.168.50.0/24への経路がveth-d01経由で存在する
コマンド: ip route show dev veth-d01
実出力: 192.168.50.0/24 proto kernel scope link src 192.168.50.5
判定: 設計どおり。PASS（このホスト自体はセグメント内固定IPのためdefault gatewayは持たない設計）
```

### DNW-03 DNS

```text
期待値/コマンド: dig / getent hosts dhcp-01 / resolvectl
実出力: dig・resolvectlはこのサンドボックスに未導入。getent hosts dhcp-01は空（該当エントリなし）
判定: NOT RUN。本パックの対象はDHCPの払い出しであり、dhcp-01自身の名前解決はスコープ外の設計（03-parameter-sheet.mdのFQDN欄もNOT SET）。このサンドボックスにDNS統合が無いための制約ではなく、そもそも設計上の対象外である点に注意
```

### DNW-04 ICMP

```text
期待値 / FW方針: セグメント内クライアント⇔dhcp-01間はICMP疎通可能な設計（明示的な遮断方針なし）
コマンド: ip netns exec client01 ping -c 3 -W 1 192.168.50.5 / ping -c 3 -W 1 192.168.50.153
packet loss / RTT: どちらの方向も3/3 received、0% packet loss。client→dhcp-01: rtt min/avg/max 0.106/0.438/1.099ms。dhcp-01→client: rtt min/avg/max 0.070/0.167/0.360ms
判定: PASS
```

### DNW-05 待受port

```text
期待する待受構成（UDP67、TCP22/9100）: dhcpdがUDP 67のみ全interfaceでLISTEN。TCP 22（SSH）・9100（node_exporter）はcommon/monitoring role未適用のため待受なしが期待どおり
コマンド: ss -lunp | grep -E ":67|dhcpd" ; ss -lntup | grep -E ":22|:9100"
実出力: UNCONN 0 0 0.0.0.0:67 0.0.0.0:* users:(("dhcpd",pid=8234,fd=7))。TCP 22/9100のgrep結果は0件（listenなし）
想定外listener: なし（ss -lntup全体では、このサンドボックスのharness自体が使う127.0.0.1:42357等のローカル専用portのみ。dhcp_server roleの対象外）
判定: PASS（common/monitoring role未適用の現状の構成として妥当。DST-01/DNW-07のBLOCKEDと合わせて解釈すること）
```

### DNW-06 DORAのpacket capture

```text
capture対象host / filter: tcpdump -i br-dhcp50 -w dora.pcap udp port 67 or udp port 68
DISCOVER観測時刻: 2026-09-04 08:51:48.417362 (MAC fe:b8:0b:ac:82:84 → 255.255.255.255)
OFFER観測時刻: 2026-09-04 08:51:49.419559 (192.168.50.5 → 192.168.50.100、Server-ID 192.168.50.5)
REQUEST観測時刻: 2026-09-04 08:51:49.420101 (Requested-IP 192.168.50.100)
ACK観測時刻: 2026-09-04 08:51:49.421141 (Server-ID 192.168.50.5)
判定: PASS。4パケットとも`tcpdump -v`のDHCP-Message(53)フィールドで種別を確認済み。復元後の新規リース確認（DIT-11相当）でも同型の4パケットDORAを別途観測（09:03:41〜09:03:44、Discover→Offer(192.168.50.153)→Request→ACK）
```

### DNW-07 host firewall

```text
UFW status/default: ufw status verbose → Status: inactive
許可rule（UDP67の送信元CIDR）: 未設定（UFW自体が有効化されていない）
上流security group/NACL（該当時）: 該当なし（単一コンテナ内のためsecurity groupの概念なし）
判定: BLOCKED。common role未適用（安全上の理由）に加え、dhcp_server role自身のUFW許可タスクもsystemdタスク失敗によりplayが先に停止するため未到達。iptables INPUT chainはdefault ACCEPT(0 packets)で、br-dhcp50向けにこのセッションで追加した最小限のFORWARD ACCEPTルールのみが存在する（Dockerの既存chainには変更なし）
```

### DNW-08 クライアント側end-to-end

```text
クライアントVMのinterface: client01 netns内のveth-cli
取得したIP: 192.168.50.100（DIT-02のDORA）、192.168.50.20（DIT-03の固定予約）など、複数MACで設計どおりのプール範囲/予約帯から取得
取得したgateway/DNS/ドメイン名: ip route → default via 192.168.50.1 dev veth-cli（設計値のoption routersと一致）。/etc/resolv.conf → domain lab.example.test / search lab.example.test / nameserver 192.168.50.1 / nameserver 1.1.1.1（設計値のoption domain-name・option domain-name-serversと完全一致）
判定: PASS
```

### DNW-09 rogue DHCP非存在

```text
確認方法: dhcp-01役のisc-dhcp-serverを一時停止(service isc-dhcp-server stop)した状態で、クライアント役から2回DHCPREQUESTを送出し、応答(OFFER/ACK/NAK)の有無を確認
応答したDHCPサーバーのIP一覧: なし(0件)。tcpdumpでも0.0.0.0.68 → 255.255.255.255.67のRequestのみが2回記録され、192.168.50.5からの応答も他IPからの応答も一切観測されなかった
判定: PASS（構築後のみ実施）。本来は構築直前の確認も必要だが、本セッションでは構築後に一時停止して代替確認した。確認後dhcp-01役を復旧
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| bridge越しのDORAブロードキャストが届かない | `net.bridge.bridge-nf-call-iptables=1`により、`br-dhcp50`経由のL2フレームが`FORWARD`チェーンのdefault DROP policyに阻まれていた（別フェーズのDocker関連iptables状態が残存） | 初回のDORA検証がタイムアウトした | `br-dhcp50`を対象にした最小限のACCEPTルールを追加（Dockerの既存chainには非干渉） | サンドボックス固有の事象。role/playbook側の対応は不要 |
| UFW/AppArmor/journald/SSH hardeningが未検証 | `common` role未適用・実systemd/AppArmor/journald不在 | DST-01/03/04/05、DNW-07が未検証のまま残る | 本証跡では対象外として明示 | VM/実機での正本検証（[README](../build-package-dhcp/README.md)記載）で解消予定 |

## 終了判定

- 必須: DNW-01〜09
- DNW-03（NOT RUN）とDNW-07（BLOCKED）が残るため、「ネットワーク実機検証完了」とはしない
- DHCPプロトコル動作の実測（DNW-01/02/04/05/06/08/09）は完了。host firewallとDNS名前解決は、`common` role適用済みのVM/実機での正本検証が必要
