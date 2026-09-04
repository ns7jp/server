# DHCP実ホスト ネットワーク検証結果票 — 2026-09-04

[実行手順](../build-package-dhcp/09-network-validation-procedure.md)に沿って、[`labs/dhcp-lab/topology.sh`](../../labs/dhcp-lab/topology.sh)と同じ構成のnetwork namespaceラボ（AI支援セッションのサンドボックスコンテナ内）で実施しました。独立した物理／VPSホスト・実VMではありません。範囲の詳細は[本体の証跡ファイル](2026-09-04-dhcp-build-validation-netns-lab.md)冒頭の「この証跡が示す範囲」を参照してください。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | DNW-01・02・04〜09が`PASS`。DNW-03（`dhcp-01`自身の名前解決）はこのラボにDNS実装が無いため`SKIP-ENV` |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | AI支援セッション（ユーザー: net7jp） |
| 対象環境 / host | `dhcp01`（network namespace、`seg0=192.168.50.5/24`、`mgmt0=10.99.0.30/24`） |
| 管理端末 | AI支援セッションの作業環境（root network namespace、`mgmt-ctrl=10.99.0.1/24`） |
| クライアント検証VM | `client01`（network namespace、`seg0`はDHCPで取得） |
| commit SHA | `ebcae209aac82811bc5fc49291c597c519f7c408` |
| OS / kernel | Ubuntu 24.04.4 LTS |
| isc-dhcp-server バージョン | `isc-dhcpd-4.4.3-P1` |
| 構成図・IP 表の版 | [04-network-ip-plan.md](../build-package-dhcp/04-network-ip-plan.md) |
| raw log / screenshot | このファイル内に実出力を転記（スクリーンショットは無し。CLI実行環境のため） |

公開 IP、管理元 IP、MAC address、account ID、秘密値は含まれていません（`192.168.50.0/24`・`10.99.0.0/24`はこのラボ専用のプライベート/検証用アドレス）。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| DNW-01 | interface / IP / CIDR | `ip -br link`, `ip -br addr` | 設計値と一致 | PASS | 下記 |
| DNW-02 | route / gateway | `ip route`, `ip route get` | 想定 gateway / device / source | PASS | 下記 |
| DNW-03 | DNS（`dhcp-01`自身の名前解決） | `dig`, `getent`, `resolvectl` | 想定 record と resolver | SKIP-ENV | 下記 |
| DNW-04 | ICMP | `ping` | 方針どおりの疎通または遮断 | PASS | 下記 |
| DNW-05 | 待受port（UDP 67、TCP 22/9100） | `ss -lunp`, `ss -lntup` | 設計どおりの待受のみ | PASS | 下記 |
| DNW-06 | DORAのpacket capture | `tcpdump -nn -i <interface> udp port 67 or port 68` | DISCOVER/OFFER/REQUEST/ACKの4パケットを観測 | PASS | 下記 |
| DNW-07 | host firewall | `ufw status verbose`, `nft` / `iptables` | UDP 67は払い出し対象セグメント限定、他は非公開 | PASS（要注記） | 下記 |
| DNW-08 | クライアント側end-to-end | クライアントVMで`sudo dhclient -v <interface>` | 設計どおりのプール範囲でリースを取得 | PASS | 下記 |
| DNW-09 | rogue DHCP非存在 | `sudo nmap --script broadcast-dhcp-discover`相当、または応答元サーバーIPの確認 | 応答するDHCPサーバーが`dhcp-01`のみ | PASS | 下記 |

## 実出力

### DNW-01 interface / IP / CIDR

仮説・期待値:

```text
seg0 が 192.168.50.5/24（払い出し対象セグメント）、mgmt0 が 10.99.0.30/24（管理リンク）
```

実行コマンド:

```bash
ip -br link
ip -br addr
```

実出力（要点）:

```text
lo        UNKNOWN  00:00:00:00:00:00  <LOOPBACK,UP,LOWER_UP>
mgmt0@if12 UP       4a:f5:89:be:4d:cd  <BROADCAST,MULTICAST,UP,LOWER_UP>
seg0@if13  UP       46:84:07:eb:85:b8  <BROADCAST,MULTICAST,UP,LOWER_UP>

lo         UNKNOWN 127.0.0.1/8
mgmt0@if12 UP      10.99.0.30/24
seg0@if13  UP      192.168.50.5/24
```

判定 / 設計との差:

```text
設計値と完全に一致。差異なし。
```

### DNW-02 route / gateway

```text
期待値: 192.168.50.0/24 は seg0 に直結、10.99.0.0/24 は mgmt0 に直結、デフォルトルートは mgmt0 経由
コマンド: ip route
実出力:
  default via 10.99.0.1 dev mgmt0
  10.99.0.0/24 dev mgmt0 proto kernel scope link src 10.99.0.30
  192.168.50.0/24 dev seg0 proto kernel scope link src 192.168.50.5
判定: PASS。設計どおり
```

### DNW-03 DNS

```text
期待値: NOT SET（このラボにDNS実装（named等）を用意していないため）
コマンド: getent hosts dhcp-01
実出力: 未実施
判定: SKIP-ENV。DNS実装が存在しないための環境制約であり、不合格ではない
```

### DNW-04 ICMP

```text
期待値 / FW方針: セグメント内（seg0・mgmt0のリンク内）は疎通する方針
コマンド: ping -c 3 -W 2 <target>
packet loss / RTT:
  管理リンク（root netns → dhcp01 10.99.0.30）: 3 packets transmitted, 3 received, 0% packet loss, rtt min/avg/max/mdev = 0.084/1.296/3.721/1.714 ms
  払い出しセグメント（dhcp01 → client01 192.168.50.100）: 3 packets transmitted, 3 received, 0% packet loss, rtt min/avg/max/mdev = 0.056/0.171/0.397/0.159 ms
判定: PASS。設計どおりの疎通を確認
```

### DNW-05 待受port

```text
期待する待受構成（UDP67、TCP22/9100）: UDP 67(dhcpd)、TCP 22(sshd)。TCP 9100(node_exporter)は本検証の適用範囲(playbooks/dhcp.yml)に監視roleを含まないため対象外
コマンド: ss -lntup ; ss -lunp
実出力:
  udp UNCONN 0 0 0.0.0.0:67 0.0.0.0:* users:(("dhcpd",pid=12506,fd=7))
  tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=3237,fd=3))
想定外listener: なし
判定: PASS。TCP 9100が無いのはDIT-10（監視統合）がSKIP-ENVであることと整合し、想定どおり
```

### DNW-06 DORAのpacket capture

```text
capture対象host / filter: dhcp01の seg0、udp port 67 or port 68
DISCOVER観測時刻: 17:33:02.686872
OFFER観測時刻:    17:33:03.688768
REQUEST観測時刻:  17:33:03.688992
ACK観測時刻:      17:33:03.689811
判定: PASS。4パケットとも実キャプチャで観測（0.0.0.0:68 -> 255.255.255.255:67 のDISCOVER/REQUEST、192.168.50.5:67 -> 192.168.50.100:68 のOFFER/ACK）
```

### DNW-07 host firewall

```text
UFW status/default: Status: active / Default: deny (incoming), allow (outgoing), disabled (routed)
許可rule（UDP67の送信元CIDR）: 67/udp on seg0 ALLOW IN Anywhere（interface限定、送信元CIDRでの絞り込みではない。DHCPDISCOVERの送信元は0.0.0.0のためCIDRで絞れない設計）
上流security group/NACL（該当時）: 該当なし（ラボ内完結のため）
判定: PASS（要注記）。UFWのrule自体は設計どおりseg0限定でACCEPTになっているが、実機検証（DIT-05）でisc-dhcp-serverがraw socket(LPF)でinterfaceから直接受信しnetfilterのINPUT chainを経由しないことを確認した。実際の受信interface制限は/etc/default/isc-dhcp-serverのINTERFACESv4が担っており、UFWのこのruleはdhcpdの受信自体には効いていない（多層防御・意図の明示としては有効）。詳細は本体の証跡ファイルの「見つかった欠陥」#34を参照
```

### DNW-08 クライアント側end-to-end

```text
クライアントVMのinterface: client01 の seg0
取得したIP: 192.168.50.100（プール範囲 192.168.50.100〜.200 内）
取得したgateway/DNS/ドメイン名: gateway=192.168.50.1、DNS=192.168.50.1・1.1.1.1、domain=lab.example.test（いずれも設計値と一致）
判定: PASS
```

### DNW-09 rogue DHCP非存在

```text
確認方法: dhcp01でdhcpdが稼働している状態で、client01からscapyで素のDHCPDISCOVERを送出し、応答元IPを確認
応答したDHCPサーバーのIP一覧: 192.168.50.5（dhcp-01）のみ。1件のDHCPOFFERのみ観測
判定: PASS。このラボのセグメントには dhcp01 以外のDHCPサーバーが構造上存在しないが、実際にDISCOVERを送出して応答元を確認済み
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| DNW-07 | UFWのUDP67許可ruleはisc-dhcp-serverの受信そのものには効いていない（raw socket受信のためnetfilterを経由しない） | 実害なし（INTERFACESv4が実際のinterface制限を担っている） | `ansible/roles/dhcp_server/defaults/main.yml`のコメントを訂正（本PRに含む） | [欠陥台帳#34](defects-found.md) |

## 終了判定

- 必須: DNW-01〜09
- DNW-03のみ`SKIP-ENV`（DNS実装が存在しない環境制約）。それ以外の8 IDはすべて`PASS`。
- `FAIL` / `BLOCKED`は0件。
- 設計との差（DNW-07のUFW/netfilterに関する注記）は本体の証跡ファイルおよび欠陥台帳へ記録済み。
