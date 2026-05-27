# D-1: プロセスダウン → 自動復旧演習

## 1. 目的

`restart: unless-stopped` と systemd / Docker のヘルスチェックが、人手介入なしで
プロセスを復旧できることを検証する。**最も頻繁** に発生する障害クラスのため、
月次で繰り返し体に覚えさせる位置付け。

| 項目 | 値 |
| --- | --- |
| 頻度 | 月次（推奨: 毎月第 1 月曜 10:00 JST） |
| 想定時間 | 15 分（操作 5 分 + 振り返り 10 分） |
| 環境 | ローカル Docker Compose または dev |
| RTO 目標 | **5 分以内** |
| RPO 目標 | **0**（メトリクス欠損は scrape 間隔以内に収まる） |
| 想定対象 | `app` コンテナ。応用で `nginx` / `prometheus` / `loki` も同じ手順 |
| 関連ランブック | [docs/runbooks/service-down.md](../runbooks/service-down.md) |
| 関連 SLO | 可用性 99.5%（[docs/slo.md](../slo.md)）|

## 2. 事前準備

1. `docker compose ps` でスタックが healthy であることを確認
2. Slack 演習チャンネルでキックオフを宣言（[docs/incident-comms.md](../incident-comms.md)）
3. 観測役は Grafana の `Server Monitor SLO` ダッシュボードを別タブで開く
4. 復旧手順とランブック URL を手元に開く

## 3. 演習スクリプト

```bash
# 自動化されたランナー（推奨）
./scripts/drills/d1-process-down.sh

# サービスを変えたい場合
./scripts/drills/d1-process-down.sh --service nginx
```

スクリプトは次を自動で行う。

1. 対象コンテナの稼働確認
2. `docker compose kill -s KILL <service>` で強制終了（演習用に SIGKILL）
3. 復旧開始時刻を記録
4. ヘルスチェック (`curl /healthz`) が 200 を返すまで poll
5. 各イベントの所要秒数を表示

## 4. 手動でやる場合

スクリプトを使わずに体感したい場合の手順。

```bash
# 1. 障害発生
START=$(date -u +%s)
docker compose kill -s KILL app
date -u +%H:%M:%SZ

# 2. 自動復旧を待つ
while ! curl -fsS http://127.0.0.1:8080/healthz >/dev/null; do
  sleep 1
done
END=$(date -u +%s)

# 3. 計測
echo "復旧までの時間: $((END - START)) 秒"

# 4. 状態確認
docker compose ps app
docker inspect server-monitor-lab-app-1 --format \
  'restartCount={{.RestartCount}} startedAt={{.State.StartedAt}}'
```

## 5. 期待される結果

| 項目 | 期待 |
| --- | --- |
| `RestartCount` 増加 | +1 |
| `/healthz` 復活 | 30 秒以内（compose healthcheck の interval=30s） |
| Prometheus `up{job="server-monitor"}` | 一時的に 0 → 復活後 1 |
| `ServerMonitorUnavailable` アラート | `for: 2m` のため発火しない見込み |
| SLO バーンレート | 一時的な短窓スパイク（fast burn しきい値未満） |

RTO 5 分以内なら合格。これを超える場合はランブック / 設定の見直しを開始する。

## 6. 計測項目（演習ログに転記）

| 項目 | 目標 | 実測 | 評価 |
| --- | --- | --- | --- |
| 障害発生 → コンテナ再起動開始 | 5 秒 | _要記録_ | ✓ / ✗ |
| コンテナ再起動 → `/healthz` 200 | 30 秒 | _要記録_ | ✓ / ✗ |
| `/healthz` 200 → Prometheus `up=1` | 15 秒 | _要記録_ | ✓ / ✗ |
| Grafana ダッシュボード更新 | 30 秒 | _要記録_ | ✓ / ✗ |
| **合計 RTO** | **5 分** | _要記録_ | ✓ / ✗ |

## 7. 想定発見事項のヒント

演習で確認する候補。実際に見つかった事項だけをテンプレートに沿って追記する。

- compose healthcheck の `interval` を短くすると Prometheus への影響が早く出る
- `nginx` を kill した場合、`app` の depends_on で待つため復旧が遅れることがある
- macOS の Docker Desktop と Linux ホストで再起動時間に差がある
- Loki / Grafana Alloy が並走しているとログから再起動の前後が遡れる

## 8. 振り返り

[docs/drill-template.md](../drill-template.md) をコピーして
`docs/drills/logs/YYYY-MM-DD-D-1.md` に保存。Slack スレッドのリンクを貼り、
発見事項 / 改善アクションを記入して PR にする。
