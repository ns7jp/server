# AD実ホスト ネットワーク検証結果票 — YYYY-MM-DD

このファイルを `docs/evidence/YYYY-MM-DD-network-host-validation-ad.md` へコピーし、[実行手順](../../build-package-ad/09-network-validation-procedure.md)に沿って記入します。初期値 `NOT RUN` を結果を見ずに `PASS` へ変更しません。

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
| フォレスト / ドメイン機能レベル（`Get-ADForest` / `Get-ADDomain`） | `NOT RUN` |
| PowerShell バージョン（組込5.1 / 追加導入7.4系） | `NOT RUN` |
| windows_exporter バージョン / SHA256 | `NOT RUN` |
| 構成図・IP 表の版 | `NOT RUN` |
| raw log / screenshot | `NOT RUN` |

公開 IP、管理元 IP、内部ネットワークCIDR、MAC address、Windows ログオンアカウント名、account ID、DSRM パスワードを含む秘密値は共有前にマスクします。値をマスクしても prefix length、bind address、port、判定に必要な部分は残します。

## 結果一覧

| ID | 確認対象 | 主コマンド | 期待結果 | 結果 | 証跡位置 |
| --- | --- | --- | --- | --- | --- |
| ANW-01 | interface / IP / CIDR | `Get-NetAdapter`, `Get-NetIPAddress` | 設計値と一致 | NOT RUN | — |
| ANW-02 | route / gateway | `Get-NetRoute`, `Test-NetConnection -TraceRoute` | 想定gateway/interface/経路 | NOT RUN | — |
| ANW-03 | DNS(通常レコード+SRVレコード) | `Resolve-DnsName`(Aレコード、`_ldap._tcp.dc._msdcs`等のSRVレコード) | 想定レコードと一致 | NOT RUN | — |
| ANW-04 | ICMP | `Test-Connection` | 方針どおりの疎通または遮断 | NOT RUN | — |
| ANW-05 | 待受port | `Get-NetTCPConnection -State Listen`、`Get-ChildItem Cert:\LocalMachine\My` | 53,88,135,389,445,464,3268,5986,9182が設計どおり待受、3389は既定Disableで非待受。636・3269は待受の有無が証明書ストアと整合し説明できればPASS | NOT RUN | — |
| ANW-06 | TCP/LDAP到達性 | `Test-NetConnection -Port 389/88/53/5986`等 | 内部ネットワークCIDR内は到達、windows_exporterは中央Prometheus host以外から拒否 | NOT RUN | — |
| ANW-07 | packet capture | `pktmon`(ヘッダのみ) | request/responseの経路を説明可能、本文は非採録 | NOT RUN | — |
| ANW-08 | Windows Defender Firewall | `Get-NetFirewallProfile -PolicyStore ActiveStore`, `Get-NetFirewallRule` | 実効DefaultInboundActionがBlock、AD DS自動生成ルールグループ(表示名はOS言語依存)のスコープが設計と一致 | NOT RUN | — |
| ANW-09 | end-to-end | 管理元CIDR外からのWinRM接続試行 | 管理元CIDR以外からの接続が拒否される。内部ネットワークCIDRは実際に参加するホストが無いため、範囲設計の妥当性確認にとどまる旨を明記 | NOT RUN | — |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかです。ICMP を意図的に遮断する環境では、設計と一致し TCP/LDAP が確認できれば ANW-04 を `PASS` と判定した根拠を備考へ記載します。

## 実出力

### ANW-01 interface / IP / CIDR

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

### ANW-02 route / gateway

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### ANW-03 DNS(通常レコード+SRVレコード)

```text
期待値: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
判定: NOT RUN
```

### ANW-04 ICMP

```text
期待値 / Firewall方針: NOT RUN
コマンド: NOT RUN
packet loss / RTT: NOT RUN
判定: NOT RUN
```

### ANW-05 待受port

```text
期待する待受構成: NOT RUN
コマンド: NOT RUN
実出力: NOT RUN
想定外listener: NOT RUN
判定: NOT RUN
```

### ANW-06 TCP/LDAP到達性

```text
内部ネットワークCIDR内からのLDAP(389)到達: NOT RUN
内部ネットワークCIDR内からのKerberos(88)/DNS(53)到達: NOT RUN
windows_exporter loopback応答: NOT RUN
windows_exporter 中央Prometheus host以外からの到達（拒否想定）: NOT RUN
判定: NOT RUN
```

### ANW-07 packet capture

```text
capture対象host / filter: NOT RUN
request時刻: NOT RUN
観測したSYN/SYN-ACK等: NOT RUN
本文非採録確認: NOT RUN
判定: NOT RUN
```

### ANW-08 Windows Defender Firewall

```text
プロファイル（Public/Domain）と既定Inbound: NOT RUN
AD DS自動生成ルールグループのスコープ（内部ネットワークCIDR）: NOT RUN
WinRM/windows_exporterルールのスコープ: NOT RUN
判定: NOT RUN
```

### ANW-09 end-to-end

```text
管理元CIDR内からのWinRM接続: NOT RUN
管理元CIDR外からのWinRM接続（拒否想定）: NOT RUN
内部ネットワークCIDRの範囲設計の妥当性確認（実接続ホストなし）: NOT RUN
判定: NOT RUN
```

## 差異・問題

| Issue | 観測事実 | 影響 | 暫定対応 | 恒久対応 / link |
| --- | --- | --- | --- | --- |
| — | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

問題の切り分けは [トラブルシュート一次記録テンプレート](troubleshooting-worklog.md)へ分け、推測と実出力を混在させません。

## 終了判定

- 必須: ANW-01〜09
- `FAIL / BLOCKED / NOT RUN` が一つでも残る場合は「ネットワーク実機検証完了」としません。
- 設計との差を承認して残す場合は、要件・IP アドレス表・パラメータシート・変更票を同じ PR で更新します。