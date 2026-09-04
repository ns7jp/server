# ネットワーク設計・IPアドレス表

> 💡 **初めて読む方へ**: この文書はどのIP・ポートに、誰が、どこから接続できるかを決めた文書です。本パックは監視アプリを配備しないため、他の案件パックよりも検証すべき範囲がずっと小さい点に注意してください。

## 1. 本体構成

**一言でいうと**: `foundation.yml`を適用したホストは、SSH以外のポートを一切開けません。これは実装漏れではなく、意図した設計です。

| Zone | CIDR / interface | 主な通信 | 制御 |
| --- | --- | --- | --- |
| 管理端末 | 組織で割り当て | SSH 22/tcp | 管理元CIDRを設定した場合はUFW/firewalldでその範囲のみ許可。未設定時は全送信元へのrate limitのみ |
| 対象ホスト（`ans-01` / `ans-el9-01`） | 環境で割り当て | SSH、パッケージ更新 | `default deny incoming`。`server_monitor_allowed_tcp_ports`は既定`[22]`のみ |
| Dockerネットワーク | Docker管理 | 本パックの範囲では未使用（ワークロード未配備のため） | — |

[Linux版パック](../build-package/03-parameter-sheet.md)や[Zabbix版パック](../build-package-zabbix/04-network-ip-plan.md)は、Webダッシュボードやfrontendなど複数の公開ポートを検証します。本パックが検証する公開ポートは**SSHの1つだけ**です。監視アプリやDBのようなワークロードを一切配備しない、という設計方針（[01-basic-design.md](01-basic-design.md#1-全体構成)）の直接の帰結です。

## 2. Docker導入と公開ポートの関係

`docker` roleはDocker Engine自体を導入しますが、`foundation.yml`はDocker Composeでコンテナを1つも起動しません。そのため、Dockerの導入によってホストの外部公開ポートが増えることはありません。`ss -lntup`で待受を確認したとき、Docker関連のプロセスが新たな着信ポートを開けていないことも、検証項目に含めます（[09-network-validation-procedure.md](09-network-validation-procedure.md)のAFNW-03）。

## 3. 実環境で確認する項目

実行順、期待結果、採録方法は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

- `ip -br addr`でinterfaceとCIDRを確認
- `ip route`でdefault gatewayと経路を確認
- `ss -lntup`でlisten addressを確認（`22/tcp`以外が無いこと）
- `getent hosts`で名前解決を確認
- `ssh -o BatchMode=yes`で鍵認証のみで到達できることを確認
- UFW/firewalldの許可範囲が設計値と一致することを確認

管理元CIDR限定が受入条件の環境では、`server_monitor_ssh_source_cidr`（Ubuntu）または対応するfirewalld変数（RHEL系）を案件変数として設定し、実行結果をevidenceへ記録してから引き渡します。rate limitをsource制限の証跡にはしません（[Linux版パックの同種の注意](../build-package/04-network-ip-plan.md#3-実環境で確認する項目)と同じ考え方です）。

独立した引き渡し対象host/管理端末の結果は、日付付きevidenceを作成するまで`NOT RUN`です。
