# SLI / SLO / エラーバジェット設計

## 1. 対象とスコープ

`server-monitor` は社内向けの監視ダッシュボード。SLO は **利用者（運用担当者）が
ダッシュボードを参照しメトリクス / ログを確認できる状態** を品質として定義する。

| 観点 | 内容 |
| --- | --- |
| 利用時間帯 | 平日 9:00 〜 22:00 中心、夜間障害対応で随時 |
| クリティカリティ | 「監視の監視」のため、停止すると一次障害に気づけない |
| 計画停止 | 早朝 / 週末で 1 時間 / 月まで許容（事前周知） |

### 観測境界

現在実装している blackbox-exporter は Compose 内で Nginx を probe するラボ用の
観測点である。アプリ停止の演習は観測できるが、ホスト全体または Compose 全体が
停止した場合は observer も停止し、外部利用者から見た停止時間を完全には測定できない。

AWS の可用性 SLO として採用する場合は、ALB の CloudWatch metric に加え、
CloudWatch Synthetics 等の対象 EC2 外の probe を追加し、そのデータを正本として
記録する。従って、以下の 99.5% は現在はラボ内の品質目標であり、AWS 稼働実績の
主張ではない。

30 日窓のクエリを計算できるようにするため、Prometheus の保持期間（`compose.yaml` の
`--storage.tsdb.retention.time`）は 30 日より長い **35 日**にしている。

## 2. SLI / SLO 定義

### 2.1 可用性

| 項目 | 内容 |
| --- | --- |
| SLI | `(成功した /healthz probe 数) / (全 probe 数)` を 30 秒ごとに計測 |
| 計測 | blackbox-exporter が `http://nginx:8080/healthz` を 30 秒間隔で GET |
| 集計 | Prometheus recording rule `sli:probe_success:ratio_rate30d` |
| **SLO** | **30 日窓で 99.5%**（許容ダウンタイム：216 分 / 月） |
| 例外 | 事前周知された計画停止は集計から除外（実装は手動で incidents.md に記録） |

### 2.2 レイテンシ

| 項目 | 内容 |
| --- | --- |
| SLI | `/healthz` の応答時間（blackbox-exporter `probe_duration_seconds`） |
| 集計 | `sli:probe_duration_seconds:p95_28d`（28 日 p95） |
| **SLO** | **p95 < 500ms を 28 日のうち 99% の時間で維持** |

### 2.3 アラート到達時間

| 項目 | 内容 |
| --- | --- |
| SLI | 模擬障害発生から Alertmanager 通知到達までの実測時間 |
| 計測 | 月次の手動テスト（CPU 高負荷の演習を含む） |
| **SLO** | **2 分以内に通知が到達** |

## 3. エラーバジェット

### 3.1 計算

| SLO | 期間 | バジェット |
| --- | --- | --- |
| 可用性 99.5% | 30 日 = 43,200 分 | 0.5% × 43,200 = **216 分** |
| レイテンシ 99% | 28 日のリクエスト数 N | 0.01 × N リクエスト |

Prometheus rule で連続的に算出する。

| Rule | 意味 |
| --- | --- |
| `slo:availability_target:server_monitor` | SLO 目標値 (0.995) |
| `slo:availability_error_rate:rate30d` | 30 日エラー率 |
| `slo:error_budget_consumed_ratio:rate30d` | 0 〜 1+。1 を超えると SLO 違反 |
| `slo:error_budget_remaining_ratio:rate30d` | バジェット残量比率 |
| `slo:burn_rate:rate{5m,30m,1h,6h}` | バーンレート（短窓 / 長窓） |

### 3.2 運用ルール

バジェットの消費量に応じて、変更への慎重さを変える。

| 消費量 | 行動 |
| --- | --- |
| 〜 80% | 通常運用 |
| 80% 超過 | 変更は一旦止め、原因調査を優先する |

### 3.3 月次レビュー

毎月 1 日に前月のエラーバジェット消費を集計し、`docs/roadmap/slo-reviews/YYYY-MM.md` に
議事録を残す。テンプレートは `docs/roadmap/slo-reviews/TEMPLATE.md`。

- バジェット内で完了 → 通常運用継続
- バジェット超過 → 原因分析 → 改善計画策定 → 翌月の SLO 見直し（緩めるか、改善するか）

## 4. アラート設計

「CPU 80%」のような単純な閾値ではなく、**バジェットの消費ペース**でアラートする。
短い時間窓と長い時間窓の両方が同時にしきい値を超えたときだけ発火させ、瞬間的な
スパイクだけで誤って通知が飛ばないようにしている（この考え方は参考文献のパターンを
踏襲したもので、独自に編み出したものではない）。

| アラート | 短窓 / 長窓 | 消費ペース | 意味 |
| --- | --- | --- | --- |
| `SLOFastBurnRateAvailability` | 5 分 / 1 時間 | 速い | 1 時間でバジェットの 2% を消費（即対応） |
| `SLOSlowBurnRateAvailability` | 30 分 / 6 時間 | ゆるやか | 6 時間でバジェットの 5% を消費（業務時間中対応） |
| `SLOErrorBudgetExhausted` | — | — | バジェットを使い切った（変更を止めて調査） |
| `SLOLatencyHigh` | 1 時間 p95 | — | p95 が 500ms を超えた状態が 10 分継続 |

### 4.2 ランブック連動

| アラート | ランブック |
| --- | --- |
| `SLOFastBurnRateAvailability` | [service-down.md](runbooks/service-down.md) |
| `SLOSlowBurnRateAvailability` | [service-down.md](runbooks/service-down.md) |
| `SLOLatencyHigh` | [latency-spike.md](runbooks/latency-spike.md) |
| `AlertmanagerDown` / `BlackboxExporterDown` | [alertmanager-down.md](runbooks/alertmanager-down.md) |
| `SLOErrorBudgetExhausted` | この `slo.md`（運用ルールに従い変更を止めて調査） |

すべてのアラートには `annotations.runbook_url` を付与し、通知先からワンクリックで
ランブックに到達できるようにしている。

## 5. ダッシュボード

Grafana の **Server Monitor SLO** ダッシュボード（uid: `slo-overview`）で次を可視化。

- 30 日可用性
- エラーバジェット残量比率
- 1h / 6h バーンレート
- 5m / 1h / 6h の成功率推移
- /healthz の応答時間（現在値 + 1h p95）
- 4 窓のバーンレート時系列
- 監視の監視（alertmanager / blackbox / server-monitor の up）

## 6. 計画停止と除外

計画停止を SLI 計算から除外したい場合は、blackbox-exporter のスクレイプを一時的に
停止する（`docker compose stop blackbox`）か、ダッシュボード上で対象期間を annotation
として除外する。実装はまだ自動化していないため、停止計画と実績を
[docs/roadmap/slo-reviews/](roadmap/slo-reviews/) で記録する運用とする。

## 7. 段階的導入の振り返り

| 週 | 内容 | 達成 |
| --- | --- | --- |
| 1 | blackbox-exporter を compose に追加、`/healthz` を 30 秒間隔でプローブ | ✅ |
| 2 | SLO ダッシュボードを Grafana プロビジョニング JSON で追加 | ✅ |
| 3 | Burn rate alert + 各アラートに runbook_url annotation | ✅ |
| 4 | 初回月次レビューの議事録テンプレートを設置 | ✅ |

実測証跡の有無は [検証証跡台帳](evidence/README.md) で管理する。D-1 / D-2 の
実行結果が記録されるまでは、ランブックと自動化コードの整備完了としてのみ扱う。

## 8. 参考文献

- [Google SRE Book — Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Prometheus: Multi-Window Multi-Burn-Rate Alerts](https://promlabs.com/blog/2024/04/08/multi-window-multi-burn-rate-alerts/)
