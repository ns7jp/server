"""Measurement failures must not become a green CI gate."""

import importlib.util
from pathlib import Path

import pytest

_path = Path(__file__).resolve().parents[1] / "scripts/perf/check_result.py"
_spec = importlib.util.spec_from_file_location("perf_gate", _path)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)


def result(rate=0, **overrides):
    row = {"concurrency": 4, "error_rate": rate, "total_requests": 18174, "partial": False}
    row.update(overrides)
    return {"schema_version": 2, "steps": [row]}


def test_recomputed_historical_502_rate_fails_despite_top_level_pass():
    data = result(7115 / 18174)
    data["verdict"] = "PASS"  # At least one other stage passed; this must not mask c4.
    assert gate.check_result(data, 0.05)


def test_exact_threshold_passes():
    assert gate.check_result(result(0.05), 0.05) == []


@pytest.mark.parametrize("rate", [None, float("nan"), float("inf"), -0.01, 1.1, True, "0"])
def test_invalid_rate_fails_closed(rate):
    assert gate.check_result(result(rate), 0.05)


@pytest.mark.parametrize("overrides", [{"partial": True}, {"partial": None}, {"total_requests": 0}])
def test_incomplete_measurement_cannot_pass(overrides):
    assert gate.check_result(result(**overrides), 0.05)


def test_legacy_transport_only_results_are_not_accepted():
    data = result()
    del data["schema_version"]
    assert gate.check_result(data, 0.05)


@pytest.mark.parametrize("data", [{}, {"schema_version": 2, "steps": []}, {"schema_version": 2, "steps": [None]}])
def test_missing_or_invalid_steps_fail(data):
    assert gate.check_result(data, 0.05)
