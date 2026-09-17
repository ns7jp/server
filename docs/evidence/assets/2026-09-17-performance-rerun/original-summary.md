## 負荷試験サマリー

- 対象 URL: `http://127.0.0.1:8080/healthz`
- 段階: `1,2,4,8,16`
- 各段階の測定時間: 20 秒（助走 5 秒）
- 実行環境: GitHub hosted runner（`Linux`）

| 同時接続数 | req/s | p50 (ms) | p95 (ms) | p99 (ms) | エラー率 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 620.8643623159128 | 1.151977999995779 | 3.5098419999997077 | 4.243876000003866 | 0.0 |
| 2 | 491.2296195429281 | 3.6817899999874726 | 5.913765999991938 | 7.104662999992684 | 0.0 |
| 4 | 789.6388719105666 | 4.163983000012195 | 10.718074000010347 | 16.261222999986558 | 0.2104463437796771 |
| 8 | 976.1597301188119 | 6.841443000013214 | 16.724506000002748 | 21.841870999992352 | 0.0 |
| 16 | 803.7892031290983 | 19.332027999979573 | 29.05693299999257 | 35.60907700000371 | 0.0 |

<details><summary>RESULT_JSON</summary>

```json
{
  "schema_version": 2,
  "url": "http://127.0.0.1:8080/healthz",
  "duration_seconds": 20,
  "warmup_seconds": 5,
  "gunicorn_workers_requested": "default",
  "gunicorn_workers_applied": false,
  "run_dir": "/home/runner/work/server/server/.artifacts/perf/20260917T085042Z",
  "steps": [
    {
      "concurrency": 1,
      "throughput_rps": 620.8643623159128,
      "latency_p50_ms": 1.151977999995779,
      "latency_p95_ms": 3.5098419999997077,
      "latency_p99_ms": 4.243876000003866,
      "error_rate": 0.0,
      "total_requests": 12419,
      "success_throughput_rps": 620.8643623159128,
      "http_error_requests": 0,
      "transport_error_requests": 0,
      "verdict": "PASS",
      "partial": false
    },
    {
      "concurrency": 2,
      "throughput_rps": 491.2296195429281,
      "latency_p50_ms": 3.6817899999874726,
      "latency_p95_ms": 5.913765999991938,
      "latency_p99_ms": 7.104662999992684,
      "error_rate": 0.0,
      "total_requests": 9826,
      "success_throughput_rps": 491.2296195429281,
      "http_error_requests": 0,
      "transport_error_requests": 0,
      "verdict": "PASS",
      "partial": false
    },
    {
      "concurrency": 4,
      "throughput_rps": 789.6388719105666,
      "latency_p50_ms": 4.163983000012195,
      "latency_p95_ms": 10.718074000010347,
      "latency_p99_ms": 16.261222999986558,
      "error_rate": 0.2104463437796771,
      "total_requests": 15795,
      "success_throughput_rps": 623.4622584106792,
      "http_error_requests": 3324,
      "transport_error_requests": 0,
      "verdict": "FAIL",
      "partial": false
    },
    {
      "concurrency": 8,
      "throughput_rps": 976.1597301188119,
      "latency_p50_ms": 6.841443000013214,
      "latency_p95_ms": 16.724506000002748,
      "latency_p99_ms": 21.841870999992352,
      "error_rate": 0.0,
      "total_requests": 19529,
      "success_throughput_rps": 976.1597301188119,
      "http_error_requests": 0,
      "transport_error_requests": 0,
      "verdict": "PASS",
      "partial": false
    },
    {
      "concurrency": 16,
      "throughput_rps": 803.7892031290983,
      "latency_p50_ms": 19.332027999979573,
      "latency_p95_ms": 29.05693299999257,
      "latency_p99_ms": 35.60907700000371,
      "error_rate": 0.0,
      "total_requests": 16082,
      "success_throughput_rps": 803.7892031290983,
      "http_error_requests": 0,
      "transport_error_requests": 0,
      "verdict": "PASS",
      "partial": false
    }
  ],
  "saturation_concurrency": 1,
  "saturated_at_concurrency": 2,
  "saturation_gain_threshold": 0.1,
  "saturation_latency_factor": 1.2,
  "slo_max_concurrency": 16,
  "verdict": "PASS",
  "verdict_definition": "at_least_one_step_passed_slo",
  "all_steps_verdict": "FAIL",
  "saturation_status": "candidate_only"
}
```
</details>

> 上の表は、このジョブで実際に測った値（実測済み）です。GitHub hosted runner は
> 実行ごとに性能がばらつくため、絶対値の比較ではなく飽和点と p95 の傾向を
> 読む目的で使います。
> 本番相当の判定は `docs/slo.md` の SLO に基づき別途行います。
