## 段階負荷試験サマリー

| 項目 | 値 |
| --- | --- |
| 対象 URL | `http://127.0.0.1:8080/healthz` |
| 1 段あたりの計測秒数 | 20 秒 |
| ウォームアップ | 5 秒 |
| Gunicorn worker 数 | 指定なし（既定 2） |
| 結果ファイル | `/home/runner/work/server/server/.artifacts/perf/20260917T080657Z` |

### 各段の結果

| 並列数 | スループット (req/s) | p95 (ms) | エラー率 | 前段比 伸び率 | 前段比 p95 倍率 | SLO 判定 |
| ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| 1 | 635.0 | 3.1 | 0.0000 | - | - | PASS |
| 2 | 493.7 | 5.9 | 0.0000 | -22.3% | 1.87x | PASS |
| 4 | 908.4 | 10.0 | 0.0000 | 84.0% | 1.70x | PASS |
| 8 | 1075.9 | 14.6 | 0.0000 | 18.4% | 1.45x | PASS |
| 16 | 945.7 | 24.3 | 0.0000 | -12.1% | 1.67x | PASS |

### 飽和点

判定式: 前段比のスループット伸び率 < 10% かつ p95 の伸びが 1.20x 超 を最初に満たした段の、1 つ手前の並列数を飽和点とします。

- 飽和点（まだ余裕のあった最大並列数）: **1**
- 頭打ちが現れた段: 並列 **2**
- SLO (p95 <= 500ms / error_rate <= 0.01) を満たした最大並列数: **16**
- 全体判定: **PASS**

### 記入欄（実行者が埋めてください）

- 実施日時 (UTC):
- 実施者:
- 気づいたこと:
- 改善アクション:

RESULT_JSON={"url": "http://127.0.0.1:8080/healthz", "duration_seconds": 20, "warmup_seconds": 5, "gunicorn_workers_requested": "default", "gunicorn_workers_applied": false, "run_dir": "/home/runner/work/server/server/.artifacts/perf/20260917T080657Z", "steps": [{"concurrency": 1, "throughput_rps": 635.046615331842, "latency_p50_ms": 0.9816730000125062, "latency_p95_ms": 3.147628000021996, "latency_p99_ms": 3.33674199998768, "error_rate": 0.0, "verdict": "PASS", "partial": false}, {"concurrency": 2, "throughput_rps": 493.6778095926385, "latency_p50_ms": 3.4890889999701358, "latency_p95_ms": 5.896973000005801, "latency_p99_ms": 6.655176999970536, "error_rate": 0.0, "verdict": "PASS", "partial": false}, {"concurrency": 4, "throughput_rps": 908.3683445436816, "latency_p50_ms": 3.635492000000795, "latency_p95_ms": 10.037167999996655, "latency_p99_ms": 13.926503999982742, "error_rate": 0.0, "verdict": "PASS", "partial": false}, {"concurrency": 8, "throughput_rps": 1075.8649618991753, "latency_p50_ms": 6.628332999980557, "latency_p95_ms": 14.596236999977918, "latency_p99_ms": 18.889692999948693, "error_rate": 0.0, "verdict": "PASS", "partial": false}, {"concurrency": 16, "throughput_rps": 945.6677041606739, "latency_p50_ms": 16.61462599997776, "latency_p95_ms": 24.310028999991573, "latency_p99_ms": 28.50498000003654, "error_rate": 0.0, "verdict": "PASS", "partial": false}], "saturation_concurrency": 1, "saturated_at_concurrency": 2, "saturation_gain_threshold": 0.1, "saturation_latency_factor": 1.2, "slo_max_concurrency": 16, "verdict": "PASS"}
