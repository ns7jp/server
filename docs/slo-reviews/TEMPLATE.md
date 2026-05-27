# SLO 月次レビュー: YYYY-MM

毎月 1 日に前月のエラーバジェット消費とインシデントを集計し、本テンプレートを
コピーして記入する。記入後にコミット → PR で履歴に残す。

## 1. 集計サマリー

| 項目 | 値 | 出典 |
| --- | --- | --- |
| 30 日可用性 | YY.YY% | Grafana `slo-overview` の "Current Availability (30d)" |
| エラーバジェット消費率 | YY.Y% | `slo:error_budget_consumed_ratio:rate30d` |
| エラーバジェット残量 | YY 分 / 216 分 | `slo:error_budget_remaining_ratio:rate30d * 216` |
| /healthz 28 日 p95 | YY ms | `sli:probe_duration_seconds:p95_28d` |
| Fast burn 発火回数 | N 回 | Alertmanager 履歴 |
| Slow burn 発火回数 | N 回 | Alertmanager 履歴 |

## 2. インシデント

| 日時 (JST) | 影響時間 | 発火アラート | 一次原因 | 暫定対応 | 恒久対応 |
| --- | --- | --- | --- | --- | --- |
| MM/DD HH:MM | XX 分 | SLOFastBurnRateAvailability | ... | ... | ... |

## 3. 計画停止

| 日時 (JST) | 時間 | 内容 | バジェット控除 |
| --- | --- | --- | --- |
| MM/DD HH:MM | XX 分 | 例: TLS 証明書更新 | する / しない |

## 4. 判断

| 項目 | 状態 |
| --- | --- |
| SLO 達成 | はい / いいえ |
| バジェット消費区分 | 〜50% / 50–80% / 80–100% / 100% 超過 |
| 新機能リリース | 可 / 要レビュー / 控える / 凍結 |

## 5. 改善計画（バジェット超過 / 80% 超過時のみ）

- 原因分析: …
- 改善アクション: …
- 担当 / 期限: …
- SLO 見直し是非: …

## 6. アクションアイテム

- [ ] …

---

参考: [docs/slo.md](../slo.md)
