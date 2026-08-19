# ローカル可観測性 証跡 — 2026-08-18

## メタ情報

| 項目 | 内容 |
| --- | --- |
| 日時（JST） | 2026-08-18 13:22〜14:34 JST（04:22〜05:34 UTC） |
| 対象 commit | `aab2fcc` |
| OS | ローカル Linux（WSL2、カーネル `6.18.33.2-microsoft-standard-WSL2`） |
| Docker / Compose | Docker 29.1.3 ／ Docker Compose 2.40.3+ds1 |
| 実行者 | 島田則幸 |

## 実行コマンド

```bash
git rev-parse --short HEAD
date '+%Y-%m-%d %H:%M:%S %Z'
docker --version && docker compose version
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
```

## 起動確認

| 確認 | 結果 | 証跡 |
| --- | --- | --- |
| `docker compose ps` | 9 サービス（alertmanager / alloy / app / blackbox / grafana / loki / nginx / node-exporter / prometheus）すべて `Up`。`app` は `Up 16 minutes (healthy)` | 上記コマンドの実行結果（スクリーンショット） |
| `/healthz` | 200（`127.0.0.1:8080` 経由。`frontend` / `monitoring` ネットワークが `internal: true` のため、host からの直接到達には socat リレーの併用が必要 — 詳細は [D-1 演習記録](../drills/logs/2026-08-19-D-1.md) 参照） | 別途確認済み |
| Prometheus targets | 未確認（このラウンドでは実施していない） | — |
| Grafana dashboard | 実データ表示を確認（下記） | スクリーンショット（下記） |

## Grafana 実画面

### Server Monitor Infrastructure Lab（表示期間: Last 1 hour）

| パネル | 値 |
| --- | --- |
| Application Scrape Status（`server-monitor`） | `1`（up） |
| Application Container CPU | 4.80% |
| Linux Host CPU | 0.0508% |
| Linux Host Memory | 12.8% |

「Application Container Resource History」では 13:05 頃に一時的な CPU スパイクが記録されている（手元操作に起因するものと推測、原因の追跡はしていない）。「Linux Host Filesystem Use」は `/`・`/mnt/c`・`/var/lib/docker`・`/mnt/wsl/drivers`・`/init` の各マウントポイントを表示。

### Server Monitor SLO（表示期間: Last 6 hours）

| パネル | 値 |
| --- | --- |
| Current Availability (30d) | 100.000% |
| Error Budget Remaining (30d) | 100.0% |
| Burn Rate（1h / 6h） | 0.00 / 0.00 |
| Probe Success Ratio（5m / 1h / 6h、2026-08-18 11:45 時点） | いずれも 100% |

> **この数値の範囲を広げて解釈しない。** ラボを立ち上げてから数時間分の履歴しかない状態での表示であり、30 日間の実運用を経た SLO 実績ではない。ここで確認できたのは「可用性・エラーバジェット・バーンレートのダッシュボードとルールが実際に数値を出して動作している」ことであり、長期の SLO 遵守を証明するものではない。

### アプリ本体のダッシュボード（`docs/screenshot.png` の差し替え元）

Server Monitor アプリ自身の画面で、Linux（WSL2）上で動作していることを確認した。

| 項目 | 値 |
| --- | --- |
| OS | `Linux 6.18.33.2-microsoft-standard-WSL2` |
| ホスト名表示 | `linux-lab-01`（`MONITOR_NODE_NAME` によるマスキング済み表示。実ホスト名ではない） |
| CPU | 14.3%（Physical Cores 2 / Logical Cores 4 / 2594 MHz） |
| メモリ | 12.7%（Used 993.62 MB / Total 7.67 GB） |
| プロセスユーザー表示 | `hidden`（`MONITOR_SHOW_USERNAMES=false` によるマスキング動作を確認） |

> **気付いた点（未対応）**: DISK USAGE パネルに `/dev/sdd` が同じ値（`4.08 GB / 1006.85 GB (0.4%)`）で 5 行表示されている。マウントポイントの列挙ロジックに重複がある可能性があり、後日 `app.py` 側を確認する。

## Loki / Grafana Alloy

| 確認 | 結果 | 証跡 |
| --- | --- | --- |
| Alloy 起動 | 間接的に確認（Loki へのログ転送が機能している） | 下記の検索結果 |
| Loki ready | 確認（クエリが実データを返した） | 同上 |
| LogQL クエリ | ラベル `{compose_project="server-monitor-lab", service="nginx"}` で Explore から検索 | Grafana Explore |
| 検索結果 | nginx が `app`（`172.18.0.3:5000`）への接続に失敗し続けるエラーログを 103 行取得。期間は 2026-08-18 04:53:24〜05:32:21 UTC（約 39 分間）。原因は `frontend` / `monitoring` ネットワークが `internal: true` のため、当時 host 側からの経路が用意されていなかったこと（後日 socat リレーで回避策を確立） | [docs/evidence/logs/2026-08-18-loki-nginx-errors.txt](./logs/2026-08-18-loki-nginx-errors.txt)（Explore からの生ログ書き出し） |

## Alertmanager

| 確認 | 結果 | 証跡 |
| --- | --- | --- |
| FIRING 通知 | 別の機会に `SLOErrorBudgetExhausted` / `SLOFastBurnRateAvailability` / `ServerMonitorUnavailable` の 3 件が UI 上で FIRING になっているのを確認した記憶があるが、**ファイルとして残っていないため本ファイルでは証跡として記載しない** | 未採録。再度スクリーンショットを取得して別ファイルへ追記予定 |
| RESOLVED 通知 | 未確認 | — |
| 通知到達時間 | 未計測 | — |
| runbook_url | 未確認 | — |
| Slack 通知（優先 4） | 未確認。Alertmanager UI 上の FIRING 表示は確認したが、Slack への実配信は試していない | — |

## マスキング確認

- [x] 秘密値 — 画面内に表示なし
- [x] 公開 IP — `127.0.0.1` のみ、外部 IP の表示なし
- [x] AWS account ID — 該当なし
- [x] 個人名 — アプリ内表示は "Noriyuki Shimada"（フッターの著作権表記、公開情報）のみ
- [x] webhook URL — 画面内に表示なし

## 後続対応

- [ ] Alertmanager の FIRING 画面を再度キャプチャして採録する
- [ ] Slack への実際の通知配信を確認する（優先 4、未着手）
- [ ] DISK USAGE パネルの `/dev/sdd` 重複表示を `app.py` で確認する
- [x] `docs/screenshot.png` を本ファイルのアプリ画面に差し替える → **2026-08-19 完了**（島田さん本人がリポジトリへ直接反映）

## 関連

- [検証証跡台帳](README.md)
- [D-1 演習記録 2026-08-19](../drills/logs/2026-08-19-D-1.md)（socat リレーの背景）
