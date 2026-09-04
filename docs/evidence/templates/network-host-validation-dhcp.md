# DHCP実ホスト ネットワーク検証結果票 — YYYY-MM-DD

このファイルを `docs/evidence/YYYY-MM-DD-network-host-validation-dhcp.md` へコピーし、[実行手順](../../build-package-dhcp/09-network-validation-procedure.md)に沿って記入します。初期値 `NOT RUN` を結果を見ずに `PASS` へ変更しません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | `NOT RUN` |
| 実施日時（JST） | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 対象環境 / host | `NOT RUN` |
| 管理端末 | `NOT RUN` |
| クライアント検証VM | `NOT RUN` |
| commit SHA | `NOT RUN` |
| OS / kernel | `NOT RUN` |
| isc-dhcp-server バージョン | `NOT RUN` |
| 構成図・IP 表の版 | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

公開 IP、管理元 IP、MAC address、account ID、秘密値は共有前にマスクします。値をマスクしても prefix length、bind address、port、判定に必要な部分は残します。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| DNW-01 | interface / IP / CIDR | `ip -br link`, `ip -br addr` | 設計値と一致 | NOT RUN | — |
| DNW-02 | route / gateway | `ip route`, `ip route get` | 想定 gateway / device / source | NOT RUN | — |
| DNW-03 | DNS（`dhcp-01`自身の名前解決） | `dig`, `getent`, `resolvectl` | 想定 record と resolver | NOT RUN | — |
| DNW-04 | ICMP | `ping` | 方針どおりの疎通または遮断 | NOT RUN | — |
| DNW-05 | 待受port（UDP 67、TCP 22/9100） | `ss -lunp`, `ss -lntup` | 設計どおりの待受のみ | NOT RUN | — |
| DNW-06 | DORAのpacket capture | `tcpdump -nn -i <interface> udp port 67 or port 68` | DISCOVER/OFFER/REQUEST/ACKの4パケットを観測 | NOT RUN | — |
| DNW-07 | host firewall | `ufw status verbose`, `nft` / `iptables` | UDP 67は払い出し対象セグメント限定、他は非公開 | NOT RUN | — |
| DNW-08 | クライアント側end-to-end | クライアントVMで`sudo dhclient -v <interface>` | 設計どおりのプール範囲でリースを取得 | NOT RUN | — |
| DNW-09 | rogue DHCP非存在 | `sudo nmap --script broadcast-dhcp-discover`相当、または応答元サーバーIPの確認 | 応答するDHCPサーバーが`dhcp-01`のみ | NOT RUN | — |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかです。ICMP を意図的に遮断する環境では、設計と一致し払い出し（DNW-06/08）が確認できれば DNW-04 を `PASS` と判定した根拠を備考へ記載します。

## 実出力

### DNW-01 interface / IP / CIDR

仮説・期待値:

```text
NOT RUN
```

実行コマンド:

```bash
# NOT RUN
```

実出力（要点）:

```text
NOT RUN
```

判定 / 設計との差:

```text
NOT RUN
```

### DNW-02 route / gateway

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### DNW-03 DNS

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### DNW-04 ICMP

```text
期待値 / FW方針: NOT RUN
コマンド: NOT RUN
packet loss / RTT: NOT RUN
判定: NOT RUN
```

### DNW-05 待受port

```text
期待する待受構成（UDP67、TCP22/9100）: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
想定外listener: NOT RUN
判定: NOT RUN
```

### DNW-06 DORAのpacket capture

```text
capture対象host / filter: NOT RUN
DISCOVER観測時刻: NOT RUN
OFFER観測時刻: NOT RUN
REQUEST観測時刻: NOT RUN
ACK観測時刻: NOT RUN
判定: NOT RUN
```

### DNW-07 host firewall

```text
UFW status/default: NOT RUN
許可rule（UDP67の送信元CIDR）: NOT RUN
上流security group/NACL（該当時）: NOT RUN
判定: NOT RUN
```

### DNW-08 クライアント側end-to-end

```text
クライアントVMのinterface: NOT RUN
取得したIP: NOT RUN
取得したgateway/DNS/ドメイン名: NOT RUN
判定: NOT RUN
```

### DNW-09 rogue DHCP非存在

```text
確認方法: NOT RUN
応答したDHCPサーバーのIP一覧: NOT RUN
判定: NOT RUN
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| — | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

問題の切り分けは [トラブルシュート一次記録テンプレート](troubleshooting-worklog.md)へ分け、推測と実出力を混在させません。

## 終了判定

- 必須: DNW-01〜09
- `FAIL / BLOCKED / NOT RUN` が一つでも残る場合は「ネットワーク実機検証完了」としません。
- 設計との差を承認して残す場合は、要件・IP 表・パラメータシート・変更票を同じ PR で更新します。
