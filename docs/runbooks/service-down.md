# Runbook: Server Monitor が停止した場合

## 発火条件

- Alert: `ServerMonitorUnavailable` / `LinuxNodeExporterUnavailable`
  - Prometheus が `server-monitor` または `linux-node` を 2 分間 scrape できない
- Alert: `SLOFastBurnRateAvailability`
  - 5 分窓と 1 時間窓の両方で 14.4 倍のバーンレートを観測。即対応が必要
- Alert: `SLOSlowBurnRateAvailability`
  - 30 分窓と 6 時間窓の両方で 6 倍のバーンレート。業務時間内に対応

SLO 違反バーンレートの場合、原因が scrape 失敗とは限らない
（アプリの一過性 5xx、Nginx 設定不整合、ホスト負荷など）。Grafana の
`Server Monitor SLO` ダッシュボードと `Server Monitor Infrastructure Lab`
ダッシュボードを両方確認する。

## 影響

- 独自ダッシュボードと独自 metrics を参照できない。
- `node-exporter` が稼働していれば Linux ホストの監視は Grafana / Prometheus で継続できる。

## 初動

```bash
date
docker compose ps
docker compose logs --tail=100 app nginx
curl http://127.0.0.1:8080/healthz
```

記録する項目:

| 項目 | 記録内容 |
| --- | --- |
| 検知時刻 | Alertmanager の開始時刻 |
| 影響 | dashboard / metrics / host metrics のどれが利用不可か |
| 直近変更 | デプロイ、設定変更、秘密値更新の有無 |
| 対応者 | 調査を開始した担当 |

## 切り分け

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| `app` が停止 | `docker compose logs app` | 設定値、依存関係、再起動回数を確認 |
| `/healthz` は成功し scrape のみ失敗 | Prometheus targets と metrics token | token ファイルの一致とマウントを確認 |
| `502 Bad Gateway` | Nginx ログ、`app` health | app 起動後に Nginx を再読み込み |
| ホスト全体も停止 | SSH 到達性、ホスト電源、ディスク | ホスト復旧手順へ移行 |

## 復旧操作

```bash
docker compose up -d app nginx prometheus
docker compose ps
curl http://127.0.0.1:8080/healthz
```

復旧後は Prometheus の `server-monitor` target が `UP` になり、Alertmanager で resolved になったことを確認する。

## 事後対応

1. 発生時刻、原因、復旧時刻、暫定対応をインシデント記録へ残す。
2. 同一原因が再発し得る場合は、設定チェック、アラート、テストのいずれかを追加する。
3. 秘密値をログへ出力した疑いがある場合は直ちにローテーションする。
