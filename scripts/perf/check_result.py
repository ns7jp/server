#!/usr/bin/env python3
"""Fail the CI gate on HTTP/transport failures or incomplete measurements."""

import argparse
import json
import math
from pathlib import Path


def check_result(data, threshold):
    if not isinstance(threshold, (int, float)) or not math.isfinite(threshold) or not 0 <= threshold <= 1:
        return ["error-rate threshold must be finite and between 0 and 1"]
    if not isinstance(data, dict) or data.get("schema_version") != 2:
        return ["schema_version 2 required: legacy error rates exclude HTTP failures"]
    rows = data.get("steps")
    if not isinstance(rows, list) or not rows:
        return ["no measurement steps"]
    failures = []
    for row in rows:
        if not isinstance(row, dict):
            failures.append("invalid measurement step")
            continue
        label = f"concurrency={row.get('concurrency', '?')}"
        rate = row.get("error_rate")
        total = row.get("total_requests")
        if row.get("partial") is not False:
            failures.append(f"{label}: incomplete measurement")
        if type(total) is not int or total <= 0:
            failures.append(f"{label}: no completed requests")
        if type(rate) not in (int, float) or not math.isfinite(rate) or not 0 <= rate <= 1:
            failures.append(f"{label}: missing or invalid error_rate")
        elif rate > threshold:
            failures.append(f"{label}: HTTP-inclusive error_rate={rate} > {threshold}")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path)
    parser.add_argument("--max-error-rate", required=True, type=float)
    args = parser.parse_args()
    try:
        data = json.loads(args.result.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"::error::cannot read result.json: {exc}")
        return 1
    failures = check_result(data, args.max_error_rate)
    for failure in failures:
        print(f"::error::{failure}")
    if not failures:
        print(f"all measured steps meet HTTP-inclusive error threshold ({args.max_error_rate})")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
