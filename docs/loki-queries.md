# LogQL クエリ集

Grafana > Explore > データソース `Loki` で実行する。ダッシュボードの Logs パネル / 時系列パネルに貼り付けても動作する。

ラベルの設計方針は `docs/architecture.md` のとおり。動的値（IP / URL / リクエスト ID 等）はラベルにせず、本文に残してカーディナリティの爆発を避ける。

## 1. server-monitor-lab 全体のエラー / 警告ライブストリーム

ダッシュボードに常設する想定。`compose_project` ラベルは Promtail の Docker SD で自動付与される。

```logql
{compose_project="server-monitor-lab"} |~ "(?i)error|warn|fail|critical|denied|exception"
```

| 用途 | 障害発生直後、最初に開く画面。アラート発火と原因ログの突き合わせに使う。 |
| --- | --- |

## 2. Flask アプリ（server-monitor）の ERROR だけを抽出

`service` ラベルは Compose のサービス名（`app`、`nginx`、`prometheus` など）になる。

```logql
{service="app"} |= "ERROR"
```

| 用途 | アプリケーション層の異常を切り出す。Gunicorn の access ログと error ログが混在する点に注意。 |
| --- | --- |

## 3. Nginx の 5xx 応答を時系列で数える

Promtail の `pipeline_stages` で `status` を抽出済みのため、ラベル比較で絞り込める。

```logql
sum by (status) (rate({service="nginx", status=~"5.."}[5m]))
```

| 用途 | リバースプロキシ層のエラースパイク検出。`server_monitor_*` メトリクスでは見えない 5xx の発生率を可視化する。 |
| --- | --- |

## 4. ホストの認証失敗（auth.log / secure）

Promtail の `varlogs` ジョブが `/var/log/auth.log` 等を取り込んでいる。`process` ラベルは pipeline で抽出した `sshd` 等になる。

```logql
{job="varlogs"} |~ "(?i)authentication failure|failed password|invalid user"
```

| 用途 | 公開ホストでブルートフォース攻撃の痕跡を確認する。`docs/security.md` の運用ルールでは loopback / VPN 経由のため通常は出ない。 |
| --- | --- |

## 5. コンテナごとのエラー発生率（5 分窓）

```logql
sum by (container) (rate({compose_project="server-monitor-lab"} |~ "(?i)error|exception|fail|critical" [5m]))
```

| 用途 | どのコンポーネントが原因か当たりを付ける。アラートルールに昇格する場合は Loki Ruler で同式を使う。 |
| --- | --- |

## 補足：ラベルと本文の使い分け

| 種類 | 例 | 扱い |
| --- | --- | --- |
| 集計に使う固定値 | `service`、`container`、`stream`、`status`、`method` | ラベルにする |
| 高カーディナリティの値 | クライアント IP、URL パス、リクエスト ID、ユーザー ID | ラベルにしない。本文で `|=` や `|~` で絞り込む |

ラベルの組み合わせが 1 万を超えるとインデックスが肥大化するため、迷ったら本文に残す。
