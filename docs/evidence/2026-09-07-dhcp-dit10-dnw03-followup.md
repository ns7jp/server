# DHCPサーバー DIT-10・DNW-03 追加実測（netnsラボ） — 2026-09-07

[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)・[同ネットワーク結果票](2026-09-04-network-host-validation-dhcp-netns-lab.md)では、DIT-10（監視統合）とDNW-03（`dhcp-01`自身の名前解決）を「このラボに`monitor-01`・DNS実装が存在しないため`SKIP-ENV`」と記録していました。2026-09-04時点のこの判定自体は事実であり、上書きしません。本ファイルは、同じ`labs/dhcp-lab/`のnetnsラボを（同一セッション内で）再構築したうえで、この2件を実際に構築・実測し直した追加記録です。

> **この証跡が示す範囲**: 2026-09-04と同じくAI支援セッションのサンドボックスコンテナ内のnetwork namespaceラボです。独立した物理／VPSホストではありません。監視サーバー（`monitor-01`相当）とDNSサーバーは、いずれも本セッションがこのラボの管理端末役netns（root netns、`mgmt-ctrl=10.99.0.1/24`）へ実際にインストールした本物のPrometheus・dnsmasqであり、モック・スタブではありません。ただし恒久的な監視基盤・組織DNSではなく、この検証のためだけに一時的に構築したものです。**本ファイルで実際に実測したのはDIT-10・DNW-03の2 IDのみです**。ラボの再構築（`dhcp.yml`の再適用含む）自体は行いましたが、[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)がPASSとした残り27 IDをこの新しいcommit（下記）で改めて実測し直してはいません。[11-work-result-report.md](../build-package-dhcp/11-work-result-report.md)が明記するとおり別commitの結果は合算しないため、本ファイルの2 IDと2026-09-04の27 IDを足した「29/31」という単一の合計値としては扱いません。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 実施日時（JST） | 2026-09-07 |
| 実施者 | AI支援セッション（ユーザー: net7jp） |
| commit SHA | `0974872ce5f8c47adfd440bd8a91ae97c35a0887`（[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)の`ebcae209`とは別commit。ラボを再構築した時点のリポジトリ状態） |
| 対象環境 / host | `dhcp01`（network namespace、`seg0=192.168.50.5/24`、`mgmt0=10.99.0.30/24`） |
| 監視端末（`monitor-01`相当） | root netns（`mgmt-ctrl=10.99.0.1/24`）上に`prometheus`パッケージ（`2.45.3+ds-2ubuntu0.3`）を導入し一時起動 |
| DNSサーバー | 同じroot netns上に`dnsmasq`パッケージ（`2.91-0ubuntu0.24.04.1`）を導入し一時起動 |
| isc-dhcp-server / node_exporterバージョン | `isc-dhcpd-4.4.3-P1` / `prometheus-node-exporter 1.7.0-1ubuntu0.3` |

## DIT-10（監視統合）: SKIP-ENV → PASS

[02-detailed-design.md](../build-package-dhcp/02-detailed-design.md)・[05-build-procedure.md](../build-package-dhcp/05-build-procedure.md)が定める手順どおりに実施しました。

1. `dhcp01`へ`prometheus-node-exporter`をaptで個別導入し、`--web.listen-address=:9100`で起動。`curl http://127.0.0.1:9100/metrics`が`http_code=200`。
2. `sudo ufw allow proto tcp from $MONITOR_IP to any port 9100`（[05-build-procedure.md](../build-package-dhcp/05-build-procedure.md)記載のコマンドそのまま、`$MONITOR_IP=10.99.0.1`）でUFWにルールを追加。
3. `monitor-01`役（root netns）でPrometheusを起動し、`scrape_configs`に`job_name: dhcp-01`、`targets: ['10.99.0.30:9100']`、`labels: {host: dhcp-01}`を設定（一次確認）。
4. Prometheus HTTP APIへ`/api/v1/query?query=up`を実行し、`up{host="dhcp-01",instance="10.99.0.30:9100",job="dhcp-01"} = 1`を確認（`/api/v1/targets`でも`health: "up"`、`lastError: ""`）。
5. **対照実験**: `client01`（払い出しセグメント側、`monitor-01`ではないIP）から同じ`http://192.168.50.5:9100/metrics`へアクセスすると`Connection timed out`（UFWの送信元制限がmonitor-01のIPだけを許可し、他は遮断することを確認）。
6. **手順3の追加検証**: 手順3の`scrape_configs`は手書きの暫定設定だったため、[06-test-specification.md](../build-package-dhcp/06-test-specification.md)・[02-detailed-design.md](../build-package-dhcp/02-detailed-design.md)が実際に定める経路（`ansible/roles/app/defaults/main.yml`の`app_node_exporter_targets`へ`dhcp-01`を登録し、`ansible/roles/app/templates/prometheus.yml.j2`から`site.yml`相当でPrometheus設定を生成する）でも再確認しました。`app_node_exporter_targets: [{address: "10.99.0.30:9100", host: "dhcp-01", environment: "staging"}]`を与えて実物のテンプレートを`ansible.builtin.template`でレンダリングし、生成された`prometheus.yml`の`linux-node`ジョブに`node-exporter:9100`（`host: monitor-01`）と`10.99.0.30:9100`（`host: dhcp-01`）の両方が含まれることを確認。このレンダリング済み設定でPrometheusを起動し直し、`up{job="linux-node",host="dhcp-01",instance="10.99.0.30:9100"} = 1`を再実測しました。なお`site.yml`本体が要求する`docker`・`nginx`・`app`（Docker Compose本体）・`monitoring`・`backup`ロール一式のフルデプロイ（Prometheus/Grafana/Loki/Alertmanager/app/nginx/blackbox-exporterのコンテナスタック）は本追補の範囲では実施しておらず、`prometheus.yml.j2`テンプレート自体の`app_node_exporter_targets`ロジックの実測に限定しています。

実出力（要点）:

```text
$ curl -fsS http://127.0.0.1:9100/metrics | tail -3   # dhcp01上
promhttp_metric_handler_requests_total{code="200"} 6
http_code=200

$ curl "http://localhost:9090/api/v1/query?query=up"   # monitor-01役（手順3、手書き設定）
{"status":"success","data":{"resultType":"vector","result":[{"metric":{"__name__":"up","host":"dhcp-01","instance":"10.99.0.30:9100","job":"dhcp-01"},"value":[1788747631.790,"1"]}]}}

$ curl -m 2 http://192.168.50.5:9100/metrics   # client01（monitor-01以外）から
curl: (28) Connection timed out after 2002 milliseconds

# 手順6: 実物の ansible/roles/app/templates/prometheus.yml.j2 を
#   app_node_exporter_targets: [{address: "10.99.0.30:9100", host: "dhcp-01", environment: "staging"}]
# でレンダリングした結果（抜粋）
  - job_name: linux-node
    static_configs:
      - targets: ["node-exporter:9100"]
        labels:
          environment: staging
          host: monitor-01
      - targets: ["10.99.0.30:9100"]
        labels:
          environment: staging
          host: dhcp-01

$ curl "http://localhost:9090/api/v1/query?query=up"   # 上記レンダリング済み設定で起動したPrometheus
{"metric":{"__name__":"up","environment":"staging","host":"dhcp-01","instance":"10.99.0.30:9100","job":"linux-node"},"value":[1788748442.444,"1"]}
```

**判定: PASS**（手書き設定・実物の`prometheus.yml.j2`テンプレートの両方で`up{host="dhcp-01"}=1`を実測。NFR-13・FR-09・DIT-10の受け入れ条件を満たした）。node_exporter導入とUFW許可は[02-detailed-design.md](../build-package-dhcp/02-detailed-design.md)が明記するとおり`dhcp_server` role・`common` roleのタスクには含めておらず、手動導入である点は元の設計判断のまま変えていません。`site.yml`のフルデプロイ（Docker Composeスタック一式）までは実施していない点は上記のとおり明記します。

## DNW-03（`dhcp-01`自身の名前解決）: SKIP-ENV → PASS

[03-parameter-sheet.md](../build-package-dhcp/03-parameter-sheet.md)はFQDNを「環境ごとに決定」する`NOT SET`値としており、本パックはこのラボ固有のFQDNを規定していません。そのため、この結果はこのラボのためだけに用意した一時的なDNSでの実演であり、組織DNSでの検証の代替ではありません。

1. root netns（管理端末役）に`dnsmasq`を導入し、`mgmt-ctrl`（`10.99.0.1`）で待受。`address=/dhcp-01/10.99.0.30`・`address=/dhcp-01.lab.example.test/10.99.0.30`を設定。
2. `dhcp01`の`/etc/resolv.conf`を`nameserver 10.99.0.1`に設定。
3. `dhcp01`から`getent hosts dhcp-01`・`dig +short dhcp-01.lab.example.test @10.99.0.1`を実行。
4. [09-network-validation-procedure.md](../build-package-dhcp/09-network-validation-procedure.md)は管理端末側・`dhcp-01`側の両方での確認を求めているため、管理端末役のroot netns（`mgmt-ctrl=10.99.0.1`、`/etc/resolv.conf`が`nameserver 10.99.0.1`）からも`getent hosts dhcp-01`・`dig @10.99.0.1 dhcp-01.lab.example.test`を実行。

実出力:

```text
$ getent hosts dhcp-01   # dhcp01側
10.99.0.30      dhcp-01

$ dig +short dhcp-01.lab.example.test @10.99.0.1   # dhcp01側
10.99.0.30

$ getent hosts dhcp-01   # 管理端末側（root netns、mgmt-ctrl=10.99.0.1）
10.99.0.30      dhcp-01

$ dig @10.99.0.1 dhcp-01.lab.example.test +short   # 管理端末側
10.99.0.30
```

**判定: PASS**（このラボ内で構築した一時DNSに対して、`dhcp-01`側・管理端末側の双方から想定どおりのレコードが解決できることを確認した。組織DNSでの実測ではない点は明記する）。

## 全体状態への反映

[2026-09-04の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)（commit `ebcae209`）は31 ID中27 ID `PASS` / 4 ID `SKIP-ENV`のままです。本ファイル（commit `0974872`、別commit）は、そのうちDIT-10・DNW-03の2 IDについて、再構築した同じ種類のnetnsラボで`SKIP-ENV`から`PASS`へ切り替わることを実測した記録です。この2 IDは元の結果票の27 IDとは異なるcommitでの実測のため合算せず、「29/31」という単一の合計値では表現しません。残る`SKIP-ENV`は`DST-03`（AppArmor）・`DST-05`（監査ログ）の2 IDで、理由は元の結果票のとおりこのサンドボックスにAppArmor LSM・journald/rsyslogが無い恒久的な環境制約であり、今回も再確認し変わっていません。

## 見つかった構築上のつまずき（欠陥ではないが記録する事実）

- 3日前（2026-09-04）に構築したnetwork namespace・dhcpd・sshdは、コンテナ再起動でネットワーク名前空間ごと消えていた（`ip netns list`が`Peer netns reference is invalid`を返す状態）。一方`/home/user/server`や`/tmp/.../scratchpad`配下のファイル（Ansible inventory、SSH鍵、labadminユーザーの`/etc/passwd`エントリ等）はディスク上に残っていた。このサンドボックスは**ネットワーク名前空間などのカーネル実行時状態はコンテナ再起動で失われるが、ファイルシステムは永続化される**という性質を持つ。`labs/dhcp-lab/topology.sh build`を再実行し、`ip netns exec dhcp01 /usr/sbin/sshd -D`を手動起動して復旧した。
- 再適用時、`apt-get update`がベースイメージに残っていた壊れたPPA（`deadsnakes`・`ondrej/php`、いずれも上流が403を返し「no longer signed」）で失敗し、`common`ロールのパッケージインストールタスク全体をブロックした。`dhcp_server`ロール・本案件のコードとは無関係な、このサンドボックスの base image 側の問題。該当2つの`.sources`ファイルを退避して回避した。

## 未実施・今後の課題

- DST-03（AppArmor）・DST-05（監査ログ）は引き続き`SKIP-ENV`。実VM/実ホスト（AppArmor・journald/rsyslogが揃う環境）で再実施すればPASSする見込み（[元の結果票](2026-09-04-dhcp-build-validation-netns-lab.md)と同じ結論）。
- 独立した物理／VPSホストでの受け入れは引き続き`NOT RUN`。
