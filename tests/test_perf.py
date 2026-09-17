"""scripts/perf/load.py の純粋関数（集計・判定）の単体テストです。

このテストは **ネットワークを一切使いません**。
HTTP リクエストを投げる部分は呼ばず、集計と判定のロジックだけを確かめます。
pytest が tests/ 配下を自動で拾うため、登録作業は不要です。
"""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# scripts/perf はパッケージではないため、ファイルパスから直接読み込みます。
_LOAD_PY = ROOT / "scripts" / "perf" / "load.py"
_spec = importlib.util.spec_from_file_location("perf_load", _LOAD_PY)
assert _spec is not None and _spec.loader is not None
load = importlib.util.module_from_spec(_spec)
sys.modules["perf_load"] = load
_spec.loader.exec_module(load)

Sample = load.Sample
ErrorRecord = load.ErrorRecord


# ---------------------------------------------------------------------------
# percentile(): nearest-rank 法（最近接順位法）の境界
# ---------------------------------------------------------------------------


def test_percentile_returns_none_for_empty_samples():
    """サンプル 0 件でも落ちず、None を返すこと。"""
    assert load.percentile([], 50) is None
    assert load.percentile([], 95) is None
    assert load.percentile([], 99) is None


def test_percentile_with_single_sample_returns_that_sample():
    """要素 1 件なら、どの q でもその値になること。"""
    values = [42.0]
    assert load.percentile(values, 50) == 42.0
    assert load.percentile(values, 95) == 42.0
    assert load.percentile(values, 99) == 42.0
    assert load.percentile(values, 100) == 42.0


def test_percentile_with_two_samples_uses_nearest_rank():
    """要素 2 件。rank = ceil(q/100 * 2) で決まること（補間しない）。"""
    values = [10.0, 20.0]
    # ceil(0.50 * 2) = 1 -> 1 番目 = 10.0（線形補間なら 15.0 になるが、そうはならない）
    assert load.percentile(values, 50) == 10.0
    # ceil(0.95 * 2) = 2 -> 2 番目 = 20.0
    assert load.percentile(values, 95) == 20.0
    assert load.percentile(values, 99) == 20.0
    assert load.percentile(values, 100) == 20.0


def test_percentile_on_one_hundred_samples():
    """1..100 の 100 件。nearest-rank なら p50=50, p90=90, p95=95, p99=99。"""
    values = [float(i) for i in range(1, 101)]
    assert load.percentile(values, 50) == 50.0
    assert load.percentile(values, 90) == 90.0
    assert load.percentile(values, 95) == 95.0
    assert load.percentile(values, 99) == 99.0
    assert load.percentile(values, 100) == 100.0


def test_percentile_clamps_low_and_high_q():
    """q が 0 以下なら最小値、100 を超えても最大値で止まること。"""
    values = [1.0, 2.0, 3.0]
    assert load.percentile(values, 0) == 1.0
    assert load.percentile(values, -5) == 1.0
    assert load.percentile(values, 150) == 3.0


def test_percentile_result_is_an_actual_sample_value():
    """返る値は必ずサンプルに実在する値であること（補間値ではない）。"""
    values = [1.0, 2.0, 100.0]
    for q in (10, 25, 50, 75, 90, 95, 99):
        assert load.percentile(values, q) in values


# ---------------------------------------------------------------------------
# summarize(): warmup 除外
# ---------------------------------------------------------------------------


def test_summarize_excludes_warmup_samples():
    """warmup=True のサンプルは集計に一切入らないこと。"""
    samples = [
        Sample(latency_ms=9999.0, status=200, warmup=True),
        Sample(latency_ms=8888.0, status=500, warmup=True),
        Sample(latency_ms=10.0, status=200),
        Sample(latency_ms=20.0, status=200),
    ]
    summary = load.summarize(samples, [], elapsed_s=2.0)

    assert summary["total_requests"] == 2
    assert summary["success_requests"] == 2
    assert summary["latency_ms"]["count"] == 2
    assert summary["latency_ms"]["min"] == 10.0
    assert summary["latency_ms"]["max"] == 20.0
    # warmup の 9999 / 8888 が混ざっていないこと。
    assert summary["latency_ms"]["p99"] == 20.0
    assert summary["status_counts"] == {"200": 2}


def test_summarize_excludes_warmup_errors():
    """warmup 中のエラーは、エラー率の分子にも分母にも入らないこと。"""
    samples = [Sample(latency_ms=10.0, status=200)]
    errors = [
        ErrorRecord(kind="timeout", warmup=True),
        ErrorRecord(kind="connection_error", warmup=True),
    ]
    summary = load.summarize(samples, errors, elapsed_s=1.0)

    assert summary["total_requests"] == 1
    assert summary["error_requests"] == 0
    assert summary["error_rate"] == 0.0
    assert summary["error_counts"] == {}


def test_summarize_with_zero_samples_does_not_crash():
    """サンプルもエラーも 0 件でも落ちないこと。"""
    summary = load.summarize([], [], elapsed_s=0.0)

    assert summary["total_requests"] == 0
    assert summary["error_rate"] == 0.0
    assert summary["throughput_rps"] == 0.0
    assert summary["latency_ms"]["count"] == 0
    assert summary["latency_ms"]["min"] is None
    assert summary["latency_ms"]["p95"] is None
    assert summary["latency_ms"]["max"] is None


# ---------------------------------------------------------------------------
# summarize(): タイムアウト・接続エラーがレイテンシに混ざらないこと
# ---------------------------------------------------------------------------


def test_timeouts_are_not_mixed_into_latency_statistics():
    """タイムアウトはレイテンシ集計から外れ、エラーとして別に数えること。"""
    samples = [Sample(latency_ms=float(v), status=200) for v in (10, 20, 30)]
    errors = [ErrorRecord(kind="timeout") for _ in range(7)]
    summary = load.summarize(samples, errors, elapsed_s=1.0)

    # レイテンシ統計の対象はレスポンスが返った 3 件だけ。
    assert summary["latency_ms"]["count"] == 3
    assert summary["latency_ms"]["max"] == 30.0
    assert summary["latency_ms"]["p95"] == 30.0
    # タイムアウトは 10 秒（10000ms）級だが、max に現れてはいけない。
    assert summary["latency_ms"]["max"] < 100.0
    assert summary["error_counts"] == {"timeout": 7}
    assert summary["response_requests"] == 3


def test_connection_errors_are_counted_by_kind():
    """エラーは種別ごとに内訳が出ること。"""
    errors = [
        ErrorRecord(kind="timeout"),
        ErrorRecord(kind="timeout"),
        ErrorRecord(kind="connection_error"),
    ]
    summary = load.summarize([], errors, elapsed_s=1.0)

    assert summary["error_counts"] == {"connection_error": 1, "timeout": 2}
    assert summary["latency_ms"]["count"] == 0


def test_http_error_status_is_kept_in_latency_but_not_in_success():
    """4xx/5xx はレスポンスが返っているのでレイテンシには入るが、成功数には入らないこと。"""
    samples = [
        Sample(latency_ms=10.0, status=200),
        Sample(latency_ms=20.0, status=500),
        Sample(latency_ms=30.0, status=404),
    ]
    summary = load.summarize(samples, [], elapsed_s=1.0)

    assert summary["latency_ms"]["count"] == 3
    assert summary["success_requests"] == 1
    assert summary["status_counts"] == {"200": 1, "404": 1, "500": 1}
    assert summary["http_error_requests"] == 2
    assert summary["transport_error_requests"] == 0
    assert summary["error_requests"] == 2
    assert summary["error_rate"] == pytest.approx(2 / 3)
    assert summary["success_throughput_rps"] == pytest.approx(1.0)


def test_http_and_transport_errors_are_counted_once_and_exclude_warmup():
    samples = [
        Sample(latency_ms=1.0, status=502, warmup=True),
        Sample(latency_ms=2.0, status=200),
        Sample(latency_ms=3.0, status=302),
        Sample(latency_ms=4.0, status=502),
    ]
    errors = [ErrorRecord(kind="timeout"), ErrorRecord(kind="timeout", warmup=True)]
    summary = load.summarize(samples, errors, elapsed_s=2.0)
    assert summary["total_requests"] == 4
    assert summary["response_requests"] == 3
    assert summary["error_requests"] == 2
    assert summary["http_error_requests"] == 1
    assert summary["transport_error_requests"] == 1
    assert summary["error_rate"] == pytest.approx(0.5)
    assert summary["success_requests"] + summary["error_requests"] == 4
    assert summary["success_throughput_rps"] == pytest.approx(1.0)


def test_historical_502_failures_cannot_pass_error_rate_gate():
    # CI run 35197884893, concurrency 4: fast 502s were incorrectly counted as no error.
    samples = [Sample(latency_ms=10.0, status=200)] * 11059
    samples += [Sample(latency_ms=1.0, status=502)] * 7115
    summary = load.summarize(samples, [], elapsed_s=20.0)
    assert summary["error_rate"] == pytest.approx(7115 / 18174)
    assert load.evaluate_slo(summary, p95_ms=500, error_rate=0.05)["verdict"] == "FAIL"


def test_fast_http_errors_fail_slo_even_when_latency_is_good():
    summary = load.summarize([Sample(latency_ms=1.0, status=502)] * 10, [], 1.0)
    assert summary["latency_ms"]["p95"] == 1.0
    assert summary["error_rate"] == 1.0
    assert load.evaluate_slo(summary, p95_ms=500, error_rate=0.01)["verdict"] == "FAIL"


# ---------------------------------------------------------------------------
# summarize(): エラー率の分母とスループット
# ---------------------------------------------------------------------------


def test_error_rate_denominator_is_all_completed_requests_after_warmup():
    """エラー率の分母は「warmup 後に完了した全リクエスト」であること。

    成功 3 件 + エラー 1 件 = 4 件が分母。エラー率は 1/4 = 0.25。
    """
    samples = [Sample(latency_ms=10.0, status=200) for _ in range(3)]
    errors = [ErrorRecord(kind="timeout")]
    summary = load.summarize(samples, errors, elapsed_s=1.0)

    assert summary["total_requests"] == 4
    assert summary["error_requests"] == 1
    assert summary["error_rate"] == pytest.approx(0.25)


def test_error_rate_denominator_ignores_warmup_completions():
    """warmup 中の完了は分母から外れること（分母 = 2、エラー 1 件 -> 0.5）。"""
    samples = [
        Sample(latency_ms=10.0, status=200, warmup=True),
        Sample(latency_ms=10.0, status=200, warmup=True),
        Sample(latency_ms=10.0, status=200),
    ]
    errors = [
        ErrorRecord(kind="timeout", warmup=True),
        ErrorRecord(kind="timeout"),
    ]
    summary = load.summarize(samples, errors, elapsed_s=1.0)

    assert summary["total_requests"] == 2
    assert summary["error_rate"] == pytest.approx(0.5)


def test_error_rate_is_one_when_every_request_failed():
    """全部エラーならエラー率 1.0 になること。"""
    errors = [ErrorRecord(kind="connection_error") for _ in range(5)]
    summary = load.summarize([], errors, elapsed_s=1.0)

    assert summary["total_requests"] == 5
    assert summary["error_rate"] == pytest.approx(1.0)


def test_throughput_counts_all_completed_requests():
    """スループットは warmup 後に完了した全リクエスト ÷ 計測秒数であること。"""
    samples = [Sample(latency_ms=10.0, status=200) for _ in range(8)]
    errors = [ErrorRecord(kind="timeout") for _ in range(2)]
    summary = load.summarize(samples, errors, elapsed_s=2.0)

    assert summary["throughput_rps"] == pytest.approx(5.0)


def test_throughput_is_zero_when_elapsed_is_not_positive():
    """計測秒数が 0 でもゼロ除算で落ちないこと。"""
    samples = [Sample(latency_ms=10.0, status=200)]
    summary = load.summarize(samples, [], elapsed_s=0.0)

    assert summary["throughput_rps"] == 0.0


# ---------------------------------------------------------------------------
# evaluate_slo(): PASS / FAIL / 閾値ちょうど
# ---------------------------------------------------------------------------


def _summary_with(p95_ms=None, error_rate=0.0, total=100):
    """判定テスト用に、最小限の集計結果の形を作ります。"""
    return {
        "total_requests": total,
        "error_rate": error_rate,
        "latency_ms": {"p95": p95_ms},
    }


def test_evaluate_slo_returns_none_verdict_without_thresholds():
    """しきい値を渡さないときは判定しないこと。"""
    result = load.evaluate_slo(_summary_with(p95_ms=100.0), None, None)

    assert result["verdict"] is None
    assert result["checks"] == []


def test_evaluate_slo_passes_when_under_thresholds():
    """p95 もエラー率もしきい値を下回れば PASS。"""
    summary = _summary_with(p95_ms=120.0, error_rate=0.001)
    result = load.evaluate_slo(summary, p95_ms=500.0, error_rate=0.01)

    assert result["verdict"] == "PASS"
    assert all(c["passed"] for c in result["checks"])


def test_evaluate_slo_fails_when_p95_exceeds_threshold():
    """p95 がしきい値を超えれば FAIL。"""
    summary = _summary_with(p95_ms=501.0, error_rate=0.0)
    result = load.evaluate_slo(summary, p95_ms=500.0, error_rate=None)

    assert result["verdict"] == "FAIL"
    assert result["checks"][0]["name"] == "p95_latency_ms"
    assert result["checks"][0]["passed"] is False
    assert result["checks"][0]["actual"] == 501.0


def test_evaluate_slo_fails_when_error_rate_exceeds_threshold():
    """エラー率がしきい値を超えれば FAIL。"""
    summary = _summary_with(p95_ms=10.0, error_rate=0.05)
    result = load.evaluate_slo(summary, p95_ms=None, error_rate=0.01)

    assert result["verdict"] == "FAIL"
    assert result["checks"][0]["name"] == "error_rate"
    assert result["checks"][0]["passed"] is False


def test_evaluate_slo_passes_at_exact_p95_threshold():
    """p95 がしきい値ちょうどのときは PASS（<= で判定）。"""
    summary = _summary_with(p95_ms=500.0, error_rate=0.0)
    result = load.evaluate_slo(summary, p95_ms=500.0, error_rate=None)

    assert result["verdict"] == "PASS"


def test_evaluate_slo_passes_at_exact_error_rate_threshold():
    """エラー率がしきい値ちょうどのときは PASS（<= で判定）。"""
    summary = _summary_with(p95_ms=10.0, error_rate=0.01)
    result = load.evaluate_slo(summary, p95_ms=None, error_rate=0.01)

    assert result["verdict"] == "PASS"


def test_evaluate_slo_fails_when_one_of_two_checks_fails():
    """複数のしきい値のうち 1 つでも超えたら全体は FAIL。"""
    summary = _summary_with(p95_ms=10.0, error_rate=0.5)
    result = load.evaluate_slo(summary, p95_ms=500.0, error_rate=0.01)

    assert result["verdict"] == "FAIL"
    assert [c["passed"] for c in result["checks"]] == [True, False]


def test_evaluate_slo_fails_when_no_latency_samples():
    """レイテンシのサンプルが 0 件なら、測れていないので FAIL 扱い。"""
    summary = _summary_with(p95_ms=None, error_rate=0.0, total=0)
    result = load.evaluate_slo(summary, p95_ms=500.0, error_rate=None)

    assert result["verdict"] == "FAIL"
    assert result["checks"][0]["actual"] is None


def test_evaluate_slo_fails_when_no_completed_requests():
    """完了したリクエストが 0 件なら、エラー率の判定も FAIL 扱い。"""
    summary = _summary_with(p95_ms=None, error_rate=0.0, total=0)
    result = load.evaluate_slo(summary, p95_ms=None, error_rate=0.01)

    assert result["verdict"] == "FAIL"


# ---------------------------------------------------------------------------
# 補助: ヘッダー解析とエラー種別の振り分け（どちらもネットワーク不要）
# ---------------------------------------------------------------------------


def test_parse_header_splits_name_and_value():
    assert load.parse_header("Authorization: Bearer abc") == ("Authorization", "Bearer abc")
    assert load.parse_header("X-Token:xyz") == ("X-Token", "xyz")


def test_parse_header_rejects_malformed_input():
    with pytest.raises(ValueError):
        load.parse_header("Authorization Bearer abc")
    with pytest.raises(ValueError):
        load.parse_header(": value")


def test_classify_error_maps_timeout_and_connection_failures():
    assert load.classify_error(TimeoutError()) == "timeout"
    assert load.classify_error(ConnectionRefusedError()) == "connection_error"
    assert load.classify_error(ValueError("?")) == "unknown"


# ---------------------------------------------------------------------------
# compose.perf.yaml と Dockerfile の整合
#
# compose.perf.yaml は、負荷試験のときだけ Gunicorn の worker 数を変えられるように、
# Dockerfile の CMD を worker 数だけ差し替えて写しています。写した以上、Dockerfile を
# 変えたときに片方だけ古くなる危険があります。そのずれを CI で見つけるためのテストです。
#
# これはロジックの単体テストであり、負荷試験を実行するものではありません。
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent


def _dockerfile_cmd():
    """Dockerfile の CMD（JSON 配列形式）をリストで返します。"""
    for line in (REPO_ROOT / "Dockerfile").read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("CMD ["):
            return json.loads(stripped[len("CMD "):])
    raise AssertionError("Dockerfile に JSON 配列形式の CMD が見つかりません")


def _compose_perf_app_command():
    """compose.perf.yaml の app.command をリストで返します。"""
    import yaml

    data = yaml.safe_load((REPO_ROOT / "compose.perf.yaml").read_text(encoding="utf-8"))
    return data["services"]["app"]["command"]


def _replace_workers(argv, value):
    """引数列の --workers の値を差し替えた新しいリストを返します。"""
    out = list(argv)
    out[out.index("--workers") + 1] = value
    return out


def test_compose_perf_command_matches_dockerfile_cmd():
    """worker 数以外は Dockerfile の CMD と一字一句同じであること。"""
    dockerfile = _dockerfile_cmd()
    overlay = _compose_perf_app_command()

    assert "--workers" in dockerfile, "Dockerfile の CMD に --workers がありません"
    assert "--workers" in overlay, "compose.perf.yaml の command に --workers がありません"

    placeholder = "<workers>"
    assert _replace_workers(dockerfile, placeholder) == _replace_workers(overlay, placeholder), (
        "Dockerfile の CMD と compose.perf.yaml の command がずれています。"
        "どちらかを変えたら両方そろえてください。"
    )


def test_compose_perf_workers_is_overridable_and_defaults_to_dockerfile_value():
    """worker 数が環境変数で差し替え可能で、未指定なら Dockerfile と同じ既定になること。"""
    dockerfile = _dockerfile_cmd()
    overlay = _compose_perf_app_command()

    default_workers = dockerfile[dockerfile.index("--workers") + 1]
    overlay_workers = overlay[overlay.index("--workers") + 1]

    # 例: "${GUNICORN_WORKERS:-2}" — 未指定なら Dockerfile と同じ 2 が使われる。
    assert overlay_workers == "${GUNICORN_WORKERS:-%s}" % default_workers, (
        "compose.perf.yaml の worker 数は ${GUNICORN_WORKERS:-<Dockerfileの既定値>} の形に"
        "してください。実際の値: %r" % overlay_workers
    )
