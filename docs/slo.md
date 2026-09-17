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

この 500ms が「守れる値」なのかどうかは、負荷試験でレイテンシ分布を実測して初めて
検討できます。CI 1 回分は分析済みですが、HTTP 502 の集計漏れが見つかり、容量と継続 SLO は未確認です。確かめ方と現状は
[9. SLO の妥当性をどう確かめるか](#9-slo-の妥当性をどう確かめるか)にまとめています。

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

## 9. SLO の妥当性をどう確かめるか

**現状: 2026-09-17 に旧CIのHTTP502集計漏れを分析し、修正後の再試験と接続再利用の比較へ進めました。**
原 JSON、条件、HTTP 失敗を含めた再計算は
[性能 CI 分析](evidence/2026-09-17-performance-ci-analysis.md)へ保存しています。
[集計修正後の失敗検出](evidence/2026-09-17-performance-rerun.md)と[接続再利用の比較](evidence/2026-09-17-upstream-keepalive-comparison.md)も、実行版と確認範囲を分けて記録しています。
本人環境での再測定、D-6〜D-9、継続 SLO の検証は **NOT RUN** です。

SLO の水準は利用者の要件に照らして選び、実測で達成可能性を検証します。
今回の負荷試験では短時間の p95 を観測できましたが、HTTP 失敗を含めた品質の確認に
問題がありました。p95 が目標以下だったことだけで、サービスが健全だったとは判断しません。
この節では、計測の修正から継続観測まで、残る確認を整理します。

### 9.1 いまの SLO 値の出どころ

この文書から読み取れることだけを書きます。読み取れないことは「不明」と書きます。

| 値 | この文書から読み取れること | 読み取れないこと |
| --- | --- | --- |
| 可用性 99.5% / 30 日 | [観測境界](#観測境界)節に「現在はラボ内の品質目標であり、AWS 稼働実績の主張ではない」と明記されている。つまり**実測の裏付けを主張していない目標値**である | 99.5% という水準そのものを、どの実績や要件から導いたのか |
| レイテンシ p95 < 500ms / 28 日 99% | 2.2 に定義と集計方法（recording rule）だけが書かれている | **この値の出どころは文書に書かれていない。**実測から決めた値なのか、目標として置いた値なのかは、この文書を読んだだけでは判断できない |
| アラート到達 2 分以内 | 2.3 に「月次の手動テスト」で計測すると書かれている | 実施記録の有無。証跡は [検証証跡台帳](evidence/README.md) 側で管理する |
| 保持期間 35 日 | [観測境界](#観測境界)節に「30 日窓のクエリを計算できるようにするため」と理由が書かれている | — |

負荷試験スクリプト `scripts/perf/run-perf.sh` のCI結果は、旧版・集計修正版・接続再利用版に分けて分析しています。
この短時間の試験は、目標値を決めた当初の根拠でも、28 日窓の達成証明でもありません。
したがって「p95 < 500ms は実測から導いた値だ」とは、この時点では言えません。

測定点そのものの限界（Compose 内から観測しているため、ホストや Compose 全体が
落ちたときは observer も落ちる、など）は [観測境界](#観測境界)節に書いたとおりで、
ここでは繰り返しません。

### 9.2 負荷試験でレイテンシ SLO の可否を判定する

判定に使うのは既存の負荷試験ツールです。新しい目標値は作りません。

| ファイル | 役割 |
| --- | --- |
| [`scripts/perf/run-perf.sh`](../scripts/perf/run-perf.sh) | 並列数（同時に投げるリクエスト本数）を段階的に上げていく段階負荷試験のランナー |
| [`scripts/perf/load.py`](../scripts/perf/load.py) | 依存ゼロの負荷生成器。各段の応答時間分布とエラー率を出す |

**負荷試験と SLO の関係**は次のとおりです。

1. 並列数を上げていくと、どこかでスループット（秒あたり処理本数）が伸びなくなり、
   応答時間だけが伸び始めます。この折れ曲がる点を**飽和点**と呼びます。
2. 各段の p95（応答時間を小さい順に並べて下から 95% の位置の値）を実測すると、
   「どのくらいの負荷までなら p95 が 500ms に収まるか」が数値で出ます。
3. そこで初めて、**p95 < 500ms が「守れる値」なのか「守れない値」なのか**を
   判定できます。判定は次の 3 通りに分かれます。

| 実測の出かた | 意味 | 次の行動 |
| --- | --- | --- |
| 想定する負荷の範囲では p95 が目標内に収まり、飽和点まで余裕がある | 目標として妥当。根拠のある値になる | SLO は据え置き。実測値を証跡として残す |
| 想定する負荷の付近で p95 が目標を超える | 余裕がない。構成側の改善余地がある | 改善（worker 数など）を試す。効果は再測定で確かめる |
| 想定よりかなり低い負荷で既に p95 が目標を超える | 目標が実態に合っていない可能性がある | 3.3 の月次レビューに乗せ、改善か見直しかを議論する |

この 3 行は判定の枠組みです。既存 CI では HTTP 502 が出た段も PASS と記録されており、
自動算出の飽和点も後続段の回復と整合しません。現時点で容量や SLO の妥当性は確定しません。
次は HTTP を含む失敗率で計測し、Nginx の upstream 接続失敗と資源の観測を対応付けます。
同一条件の反復、修正前後の比較、実際の利用経路での継続観測は **NOT RUN** です。

### 9.3 エラーバジェットの消費を意図的に起こして確かめる

3.1 で計算式を、3.2 で「80% 超過で変更を止める」という運用ルールを決めていますが、
**バジェットが実際に減っていく様子を一度も見ていません。**式とルールを書いただけの
状態です。そこで、劣化をこちらから意図的に起こして、次の 4 つが想定どおりに
つながるかを確かめます。

- 劣化が起きる → 2. の SLI に反映される → 3. のバジェットが減る →
  4. のアラートが鳴り、[4.2 ランブック連動](#42-ランブック連動)のとおり手順に飛べる

用意してある演習スクリプトは次の 4 本です（いずれも実在するファイルです）。

| 演習 | スクリプト | 意図的に起こすこと | SLO 側で確かめたいこと | 状態 |
| --- | --- | --- | --- | --- |
| D-6 ディスク逼迫 | [`d6-disk-full.sh`](../scripts/drills/d6-disk-full.sh) | 空き容量を減らす | しきい値の検知と [disk-full.md](runbooks/disk-full.md) での復旧。バジェットを消費する手前で止められるか | 実装済み（未実施 / NOT RUN） |
| D-7 メモリ逼迫 | [`d7-memory-pressure.sh`](../scripts/drills/d7-memory-pressure.sh) | メモリ上限をかけて圧迫し OOM を起こす | 再起動中の probe 失敗が可用性バジェットをどれだけ削るか。[memory-pressure.md](runbooks/memory-pressure.md) | 実装済み（未実施 / NOT RUN） |
| D-8 レイテンシ悪化 | [`d8-latency-spike.sh`](../scripts/drills/d8-latency-spike.sh) | `/healthz` の応答をわざと遅くする | **レイテンシ SLO の超過にその場で気づけるか。**`SLOLatencyHigh` と [latency-spike.md](runbooks/latency-spike.md) | 実装済み（未実施 / NOT RUN） |
| D-9 Alertmanager 停止 | [`d9-alertmanager-down.sh`](../scripts/drills/d9-alertmanager-down.sh) | 通知の出口を止める | 通知が飛ばないこと自体に、通知以外の手段で気づけるか。2.3 のアラート到達時間が成り立つ前提 | 実装済み（未実施 / NOT RUN） |

記録先は `docs/drills/logs/` の記録テンプレート
（`TEMPLATE-D-6-disk-full.md` / `TEMPLATE-D-7-memory-pressure.md` /
`TEMPLATE-D-8-latency-spike.md` / `TEMPLATE-D-9-alertmanager-down.md`）です。
結果欄は空のままにしてあります。実行して初めて埋まります。

**この演習で確かめられないこと**も先に書いておきます。D-8 を 1 回走らせても、
28 日窓の recording rule `sli:probe_duration_seconds:p95_28d` が正しい値を出すかは
確かめられません。窓が 28 日と長く、1 回の演習では動かないためです。D-8 で
確かめられるのは「短い窓で応答時間の悪化に気づけるか」と「元の状態に戻せるか、
戻るまで何秒かかるか」までです。

### 9.4 実測したあとの扱い

順序を固定しておきます。**実測 → 判定 → 必要なら見直し**です。逆にはしません。

1. 9.2 の負荷試験と 9.3 の演習を実行し、結果を証跡として残す
2. 結果に照らして、現在の SLO 値が妥当かどうかを判定する
3. 見直しが必要なら 3.3 の月次レビューに議題として乗せる

短時間のCI再測定は上記記録で確認します。本人環境の再現、D-6〜D-9、継続SLOの検証は残っています。
**99.5% / p95 500ms / 28 日 / 30 日 / 35 日 の各値は変更していません。**
短時間の CI 1 回から目標を緩めたり、継続達成を主張したりせず、まず計測の不備を直します。
