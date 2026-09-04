# WSUS実ホスト ネットワーク検証結果票 — YYYY-MM-DD

このファイルを `docs/evidence/YYYY-MM-DD-network-host-validation-wsus.md` へコピーし、[実行手順](../../build-package-wsus/09-network-validation-procedure.md)に沿って記入します。初期値 `NOT RUN` を結果を見ずに `PASS` へ変更しません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | `NOT RUN` |
| 実施日時（JST） | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 対象環境 / host | `NOT RUN` |
| 管理端末 | `NOT RUN` |
| commit SHA | `NOT RUN` |
| ホストのビルド番号（`winver` / `Get-ComputerInfo` の `OsBuildNumber`） | `NOT RUN` |
| ドメイン参加状態（`Get-ComputerInfo` の `CsPartOfDomain` / `CsDomain`） | `NOT RUN` |
| PowerShell バージョン（組込5.1 / 追加導入7.4系） | `NOT RUN` |
| WSUSロールのバージョン / コンテンツストアの空き容量 | `NOT RUN` |
| windows_exporter バージョン / SHA256 | `NOT RUN` |
| 構成図・IP 表の版 | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

公開 IP、管理元 IP、内部ネットワークCIDR、MAC address、Windows ログオンアカウント名、account ID を含む秘密値は共有前にマスクします。値をマスクしても prefix length、bind address、port、判定に必要な部分は残します。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| SNW-01 | interface / IP / CIDR | `Get-NetAdapter`, `Get-NetIPAddress` | 設計値と一致 | NOT RUN | — |
| SNW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 想定 gateway / interface / 経路 | NOT RUN | — |
| SNW-03 | DNS（corp.example.testゾーン） | `Resolve-DnsName` | wsus-01.corp.example.testのAレコード等が想定どおり解決される | NOT RUN | — |
| SNW-04 | ICMP | `Test-Connection` | 方針どおりの疎通または遮断 | NOT RUN | — |
| SNW-05 | 待受port | `Get-NetTCPConnection -State Listen` | 5986, 8530, 9182が設計どおり待受、3389は既定Disableで非待受 | NOT RUN | — |
| SNW-06 | TCP / HTTP | `Invoke-WebRequest` / `curl.exe` | WSUS管理サイト（8530）は内部ネットワークCIDR内から到達、windows_exporterは中央Prometheus host以外から拒否 | NOT RUN | — |
| SNW-07 | packet capture | `pktmon` | request / response の経路を説明可能、本文は非採録 | NOT RUN | — |
| SNW-08 | Windows Defender Firewall | `Get-NetFirewallProfile`, `Get-NetFirewallRule` | プロファイル（Domain）・許可ルールが設計と一致 | NOT RUN | — |
| SNW-09 | end-to-end | 許可CIDR内外からの接続試行 | 管理元CIDR以外からのWinRM接続、内部ネットワークCIDR以外からのWSUSコンテンツ接続が拒否される | NOT RUN | — |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかです。ICMP を意図的に遮断する環境では、設計と一致し TCP / HTTP が確認できれば SNW-04 を `PASS` と判定した根拠を備考へ記載します。

## 実出力

### SNW-01 interface / IP / CIDR

仮説・期待値:

```text
NOT RUN
```

実行コマンド:

```powershell
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

### SNW-02 route / gateway

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### SNW-03 DNS（corp.example.testゾーン）

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### SNW-04 ICMP

```text
期待値 / Firewall方針: NOT RUN
コマンド: NOT RUN
packet loss / RTT: NOT RUN
判定: NOT RUN
```

### SNW-05 待受port

```text
期待する待受構成: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
想定外listener: NOT RUN
判定: NOT RUN
```

### SNW-06 TCP / HTTP

```text
WSUS管理サイト loopback応答: NOT RUN
WSUS管理サイト 内部ネットワークCIDR内からの到達: NOT RUN
windows_exporter loopback応答: NOT RUN
windows_exporter 中央Prometheus host以外からの到達（拒否想定）: NOT RUN
判定: NOT RUN
```

### SNW-07 packet capture

```text
capture対象host / filter: NOT RUN
request時刻: NOT RUN
観測したSYN/SYN-ACK等: NOT RUN
本文非採録確認: NOT RUN
判定: NOT RUN
```

### SNW-08 Windows Defender Firewall

```text
プロファイル（Domain）と既定Inbound: NOT RUN
許可rule（port / 送信元）: NOT RUN
RDPルールの状態: NOT RUN
判定: NOT RUN
```

### SNW-09 end-to-end

```text
管理元CIDR内からのWinRM接続: NOT RUN
管理元CIDR外からのWinRM接続（拒否想定）: NOT RUN
内部ネットワークCIDR外からのWSUSコンテンツ接続（拒否想定）: NOT RUN
判定: NOT RUN
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| — | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

問題の切り分けは [トラブルシュート一次記録テンプレート](troubleshooting-worklog.md)へ分け、推測と実出力を混在させません。

## 終了判定

- 必須: SNW-01〜09
- `FAIL / BLOCKED / NOT RUN` が一つでも残る場合は「ネットワーク実機検証完了」としません。
- 設計との差を承認して残す場合は、要件・IP アドレス表・パラメータシート・変更票を同じ PR で更新します。
