# Runbook: Server Monitor が停止した場合

## 発火条件

- Alert: `ServerMonitorUnavailable`
- 条件: Prometheus が `server-monitor` を2分間 scrape できない

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
