# Runbook: /healthz レイテンシ SLO の超過

## 発火条件

- Alert: `SLOLatencyHigh`
- 条件: blackbox-exporter `/healthz` probe の **1 時間 p95 が 500ms を超える状態が 10 分継続**
- 関連 SLO: 28 日窓で p95 < 500ms を 99% の時間で維持する

## 影響

- ユーザー（運用担当者）から見たダッシュボードの体感が遅くなる。
- 持続するとレイテンシ SLO のバジェットを使い切る。
- ALB ヘルスチェックの timeout 設定によっては UnHealthy 判定にも波及し得る。

## 初動

```bash
date
docker compose ps
curl -o /dev/null -s -w "code=%{http_code} time=%{time_total}\n" http://127.0.0.1:8080/healthz
curl -o /dev/null -s -w "code=%{http_code} time=%{time_total}\n" http://127.0.0.1:8080/healthz
curl -o /dev/null -s -w "code=%{http_code} time=%{time_total}\n" http://127.0.0.1:8080/healthz
```

Grafana の `Server Monitor SLO` ダッシュボードを開き、`Probe Duration (vs SLO 500ms)`
パネルで実値と p95 の差分を確認する。

| 項目 | 記録内容 |
| --- | --- |
| 検知時刻 | Alertmanager の発火時刻 |
| 影響 | p95 値、1 時間内の最大値、影響したパネル |
| 直近変更 | デプロイ、設定変更、リソース調整の有無 |
| 対応者 | 調査を開始した担当 |

## 切り分け

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| CPU 使用率も高い | `server_monitor_cpu_usage_percent` / Node Exporter | アプリ単体の負荷であれば worker 数 / 設定見直し |
| メモリが逼迫 | `node_memory_MemAvailable_bytes` | OOM、キャッシュ、リーク疑い箇所を logs で確認 |
| Disk I/O 待ち | node-exporter `iowait` | I/O ボトルネック調査（log rotation、不要書き込み） |
| Nginx だけが遅い | `docker compose logs nginx` | upstream 待ち時間、worker_connections、再読み込み |
| app の `/healthz` 自体が遅い | `docker compose exec app curl -s -w "%{time_total}\n" http://127.0.0.1:5000/healthz` | アプリ起動直後の cold start、依存サービス、GC 圧 |
| 外部 (blackbox 側) の遅延 | `up{job="blackbox"}`、blackbox ホスト負荷 | blackbox-exporter の再起動 / リソース見直し |

## 復旧操作

1. ボトルネックの根因を限定（CPU / I/O / メモリ / アプリ）
2. 一過性であれば対象コンテナを再起動: `docker compose restart app nginx`
3. 構成変更が必要なら playbook / Terraform で対応し、コミットして再デプロイ
4. 復旧後、Grafana の p95 が 500ms を下回り、Alertmanager で resolved になることを確認

## 事後対応

1. レイテンシ SLO（p95 < 500ms）のバジェット消費を [docs/slo-reviews/](../slo-reviews/) に追記する。
2. 同一原因が再発し得るなら、Prometheus alert / dashboard / テストの追加で再発を検出可能にする。
3. SLO 自体の見直しが必要か（目標値の調整、計測ポイントの変更）月次レビューで議論する。

## 参考

- SLO 定義: [docs/slo.md](../slo.md)
- バーンレート定義: `deploy/prometheus/slo-rules.yml`
