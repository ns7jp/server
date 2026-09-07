# DHCPサーバー DIT-10・DNW-03 追加実測（netnsラボ） — 2026-09-07

[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)・[同ネットワーク結果票](2026-09-04-network-host-validation-dhcp-netns-lab.md)では、DIT-10（監視統合）とDNW-03（`dhcp-01`自身の名前解決）を「このラボに`monitor-01`・DNS実装が存在しないため`SKIP-ENV`」と記録していました。2026-09-04時点のこの判定自体は事実であり、上書きしません。本ファイルは、同じ`labs/dhcp-lab/`のnetnsラボを（同一セッション内で）再構築したうえで、この2件を実際に構築・実測し直した追加記録です。

> **この証跡が示す範囲**: 2026-09-04と同じくAI支援セッションのサンドボックスコンテナ内のnetwork namespaceラボです。独立した物理／VPSホストではありません。監視サーバー（`monitor-01`相当）とDNSサーバーは、いずれも本セッションがこのラボの管理端末役netns（root netns、`mgmt-ctrl=10.99.0.1/24`）へ実際にインストールした本物のPrometheus・dnsmasqであり、モック・スタブではありません。ただし恒久的な監視基盤・組織DNSではなく、この検証のためだけに一時的に構築したものです。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 実施日時（JST） | 2026-09-07 |
| 実施者 | AI支援セッション（ユーザー: net7jp） |
| 対象環境 / host | `dhcp01`（network namespace、`seg0=192.168.50.5/24`、`mgmt0=10.99.0.30/24`） |
| 監視端末（`monitor-01`相当） | root netns（`mgmt-ctrl=10.99.0.1/24`）上に`prometheus`パッケージ（`2.45.3+ds-2ubuntu0.3`）を導入し一時起動 |
| DNSサーバー | 同じroot netns上に`dnsmasq`パッケージ（`2.91-0ubuntu0.24.04.1`）を導入し一時起動 |
| isc-dhcp-server / node_exporterバージョン | `isc-dhcpd-4.4.3-P1` / `prometheus-node-exporter 1.7.0-1ubuntu0.3` |

## DIT-10（監視統合）: SKIP-ENV → PASS

[02-detailed-design.md](../build-package-dhcp/02-detailed-design.md)・[05-build-procedure.md](../build-package-dhcp/05-build-procedure.md)が定める手順どおりに実施しました。

1. `dhcp01`へ`prometheus-node-exporter`をaptで個別導入し、`--web.listen-address=:9100`で起動。`curl http://127.0.0.1:9100/metrics`が`http_code=200`。
2. `sudo ufw allow proto tcp from $MONITOR_IP to any port 9100`（[05-build-procedure.md](../build-package-dhcp/05-build-procedure.md)記載のコマンドそのまま、`$MONITOR_IP=10.99.0.1`）でUFWにルールを追加。
3. `monitor-01`役（root netns）でPrometheusを起動し、`scrape_configs`に`job_name: dhcp-01`、`targets: ['10.99.0.30:9100']`、`labels: {host: dhcp-01}`を設定。
4. Prometheus HTTP APIへ`/api/v1/query?query=up`を実行し、`up{host="dhcp-01",instance="10.99.0.30:9100",job="dhcp-01"} = 1`を確認（`/api/v1/targets`でも`health: "up"`、`lastError: ""`）。
5. **対照実験**: `client01`（払い出しセグメント側、`monitor-01`ではないIP）から同じ`http://192.168.50.5:9100/metrics`へアクセスすると`Connection timed out`（UFWの送信元制限がmonitor-01のIPだけを許可し、他は遮断することを確認）。

実出力（要点）:

```text
$ curl -fsS http://127.0.0.1:9100/metrics | tail -3   # dhcp01上
promhttp_metric_handler_requests_total{code="200"} 6
http_code=200

$ curl "http://localhost:9090/api/v1/query?query=up"   # monitor-01役
{"status":"success","data":{"resultType":"vector","result":[{"metric":{"__name__":"up","host":"dhcp-01","instance":"10.99.0.30:9100","job":"dhcp-01"},"value":[1788747631.790,"1"]}]}}

$ curl -m 2 http://192.168.50.5:9100/metrics   # client01（monitor-01以外）から
curl: (28) Connection timed out after 2002 milliseconds
```

**判定: PASS**（`up{host="dhcp-01"}=1`を実測。NFR-13・FR-09・DIT-10の受け入れ条件を満たした）。node_exporter導入とUFW許可は[02-detailed-design.md](../build-package-dhcp/02-detailed-design.md)が明記するとおり`dhcp_server` role・`common` roleのタスクには含めておらず、手動導入である点は元の設計判断のまま変えていません。

## DNW-03（`dhcp-01`自身の名前解決）: SKIP-ENV → PASS

[03-parameter-sheet.md](../build-package-dhcp/03-parameter-sheet.md)はFQDNを「環境ごとに決定」する`NOT SET`値としており、本パックはこのラボ固有のFQDNを規定していません。そのため、この結果はこのラボのためだけに用意した一時的なDNSでの実演であり、組織DNSでの検証の代替ではありません。

1. root netns（管理端末役）に`dnsmasq`を導入し、`mgmt-ctrl`（`10.99.0.1`）で待受。`address=/dhcp-01/10.99.0.30`・`address=/dhcp-01.lab.example.test/10.99.0.30`を設定。
2. `dhcp01`の`/etc/resolv.conf`を`nameserver 10.99.0.1`に設定。
3. `dhcp01`から`getent hosts dhcp-01`・`dig +short dhcp-01.lab.example.test @10.99.0.1`を実行。

実出力:

```text
$ getent hosts dhcp-01
10.99.0.30      dhcp-01

$ dig +short dhcp-01.lab.example.test @10.99.0.1
10.99.0.30
```

**判定: PASS**（このラボ内で構築した一時DNSに対して、想定どおりのレコードが解決できることを確認した。組織DNSでの実測ではない点は明記する）。

## 全体状態への反映

[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)の31 ID中、本追補によりPASSは27→**29**、SKIP-ENVは4→**2**（`DST-03`のAppArmor、`DST-05`の監査ログのみ残存。理由は元の結果票のとおり、このサンドボックスにAppArmor LSM・journald/rsyslogが無い恒久的な環境制約で、今回も再確認し変わっていない）。

## 見つかった構築上のつまずき（欠陥ではないが記録する事実）

- 3日前（2026-09-04）に構築したnetwork namespace・dhcpd・sshdは、コンテナ再起動でネットワーク名前空間ごと消えていた（`ip netns list`が`Peer netns reference is invalid`を返す状態）。一方`/home/user/server`や`/tmp/.../scratchpad`配下のファイル（Ansible inventory、SSH鍵、labadminユーザーの`/etc/passwd`エントリ等）はディスク上に残っていた。このサンドボックスは**ネットワーク名前空間などのカーネル実行時状態はコンテナ再起動で失われるが、ファイルシステムは永続化される**という性質を持つ。`labs/dhcp-lab/topology.sh build`を再実行し、`ip netns exec dhcp01 /usr/sbin/sshd -D`を手動起動して復旧した。
- 再適用時、`apt-get update`がベースイメージに残っていた壊れたPPA（`deadsnakes`・`ondrej/php`、いずれも上流が403を返し「no longer signed」）で失敗し、`common`ロールのパッケージインストールタスク全体をブロックした。`dhcp_server`ロール・本案件のコードとは無関係な、このサンドボックスの base image 側の問題。該当2つの`.sources`ファイルを退避して回避した。

## 未実施・今後の課題

- DST-03（AppArmor）・DST-05（監査ログ）は引き続き`SKIP-ENV`。実VM/実ホスト（AppArmor・journald/rsyslogが揃う環境）で再実施すればPASSする見込み（[元の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)と同じ結論）。
- 独立した物理／VPSホストでの受け入れは引き続き`NOT RUN`。
