# Runbook: メモリ使用率の逼迫

> [共通の実行前提](README.md)を確認し、既定配備先`/opt/server-monitor`で実行します。

## 発火条件

- Alert: `LinuxNodeMemoryPressure`
- 条件: 利用可能メモリ比率から算出した使用率が **90% を超える状態が 10 分継続**
- 定義: `deploy/prometheus/rules.yml`

## 影響

- OOM Killer によってコンテナやプロセスが強制終了される可能性がある。
- スワップが有効な場合、レイテンシが悪化する（[レイテンシ Runbook](./latency-spike.md)と併発しやすい）。
- Prometheus / Loki / Grafana 自身が落ちると監視が欠損する。

## 初動

```bash
cd /opt/server-monitor
date
free -h
sudo docker stats --no-stream
```

記録する項目:

| 項目 | 記録内容 |
| --- | --- |
| 検知時刻 | Alertmanager の発火時刻 |
| 影響 | 空きメモリ量、スワップ使用量、影響しているコンテナ |
| 直近変更 | デプロイ、設定変更、負荷増加の有無 |
| 対応者 | 調査を開始した担当 |

## 切り分け

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| 特定コンテナが大量消費 | `sudo docker stats --no-stream` | 対象コンテナを特定し、`sudo docker compose logs <service>` でリーク・無限ループの兆候を確認 |
| OOM Killer が発火済み | `sudo dmesg -T \| grep -i "killed process"` | 落ちたprocess / containerを特定し`sudo docker compose ps`で再起動状態を確認 |
| Prometheus / Loki のメモリ使用量が高い | `sudo docker compose stats --no-stream prometheus loki` | service名をComposeに解決させ、query負荷、retention設定、cardinalityを確認 |
| 徐々に増加している（リーク疑い） | `sudo docker stats` を数分間隔で複数回取得し推移を比較 | 対象コンテナの再起動で一時回避し、原因調査は事後対応へ |
| ホスト全体の空きメモリが少ない | `free -h`、`ps aux --sort=-%mem \| head` | 監視スタック以外のプロセスの影響も確認 |

## 復旧操作

1. 上記切り分けで特定した対象コンテナ・プロセスを再起動する。

```bash
sudo docker compose restart <service>
sudo docker stats --no-stream
free -h
```

2. `free -h` で使用率が下がったことを確認する。
3. Alertmanager で `LinuxNodeMemoryPressure` が resolved になったことを確認する。

## 事後対応

1. 発生時刻、原因、対応内容をインシデント記録へ残す。
2. リークが疑われる場合は、対象コンテナのメモリ使用量推移を Grafana で継続観察する。
3. 恒常的に逼迫する傾向であれば、ホストのメモリ増設または `docker compose` のリソース制限見直しを検討する。

## 参考

- [SLO 定義](../slo.md)
- [レイテンシ Runbook](./latency-spike.md)
