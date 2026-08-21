# Linux 実ホスト ネットワーク検証結果票 — YYYY-MM-DD

このファイルを `docs/evidence/YYYY-MM-DD-network-host-validation.md` へコピーし、[実行手順](../../build-package/09-network-validation-procedure.md)に沿って記入します。初期値 `NOT RUN` を結果を見ずに `PASS` へ変更しません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | `NOT RUN` |
| 実施日時（JST） | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 対象環境 / host | `NOT RUN` |
| 管理端末 | `NOT RUN` |
| commit SHA | `NOT RUN` |
| OS / kernel | `NOT RUN` |
| Docker / Compose | `NOT RUN` |
| 構成図・IP 表の版 | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

公開 IP、管理元 IP、MAC address、account ID、秘密値は共有前にマスクします。値をマスクしても prefix length、bind address、port、判定に必要な部分は残します。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| NW-01 | interface / IP / CIDR | `ip -br link`, `ip -br addr` | 設計値と一致 | NOT RUN | — |
| NW-02 | route / gateway | `ip route`, `ip route get` | 想定 gateway / device / source | NOT RUN | — |
| NW-03 | DNS | `dig`, `getent`, `resolvectl` | 想定 record と resolver | NOT RUN | — |
| NW-04 | ICMP | `ping` | 方針どおりの疎通または遮断 | NOT RUN | — |
| NW-05 | listen socket | `ss -lntup` | 管理 UI は loopback のみ | NOT RUN | — |
| NW-06 | TCP / HTTP | `curl` | 内部 200、外部から管理 port は遮断 | NOT RUN | — |
| NW-07 | packet path | `tcpdump` | request / response の経路を説明可能 | NOT RUN | — |
| NW-08 | host firewall | `ufw`, `nft` / `iptables` | active、default deny、SSH のみ許可 | NOT RUN | — |
| NW-09 | end-to-end | SSH tunnel + browser / `curl` | tunnel 経由で利用可能 | NOT RUN | — |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかです。ICMP を意図的に遮断する環境では、設計と一致し TCP / HTTP が確認できれば NW-04 を `PASS (blocked by policy as designed)` とせず、`PASS` と判定した根拠を備考へ記載します。

## 実出力

### NW-01 interface / IP / CIDR

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

### NW-02 route / gateway

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### NW-03 DNS

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### NW-04 ICMP

```text
期待値 / FW方針: NOT RUN
コマンド: NOT RUN
packet loss / RTT: NOT RUN
判定: NOT RUN
```

### NW-05 listen socket

```text
期待するbind address: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
想定外listener: NOT RUN
判定: NOT RUN
```

### NW-06 TCP / HTTP

```text
内部health: NOT RUN
外部直接接続: NOT RUN
readiness: NOT RUN
判定: NOT RUN
```

### NW-07 packet path

```text
capture interface / filter: NOT RUN
request時刻: NOT RUN
観測したSYN/SYN-ACK等: NOT RUN
payload非採録確認: NOT RUN
判定: NOT RUN
```

### NW-08 firewall

```text
UFW status/default: NOT RUN
許可rule: NOT RUN
上流security group/NACL（該当時）: NOT RUN
判定: NOT RUN
```

### NW-09 end-to-end

```text
SSH tunnel: NOT RUN
接続元と到達先: NOT RUN
HTTP status: NOT RUN
判定: NOT RUN
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| — | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

問題の切り分けは [トラブルシュート一次記録テンプレート](troubleshooting-worklog.md)へ分け、推測と実出力を混在させません。

## 終了判定

- 必須: NW-01〜09
- `FAIL / BLOCKED / NOT RUN` が一つでも残る場合は「ネットワーク実機検証完了」としません。
- 設計との差を承認して残す場合は、要件・IP 表・パラメータシート・変更票を同じ PR で更新します。
