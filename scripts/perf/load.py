#!/usr/bin/env python3
"""依存ゼロの負荷生成器（closed-loop 方式）。

このスクリプトは Python 3.11 の標準ライブラリだけで動きます
（requirements-dev.txt に何も追加しません）。

用語の短い言い換え
------------------
- closed-loop（クローズドループ）: 指定した並列数ぶんの「投げ手」が、
  1 件のレスポンスを受け取ってから次の 1 件を投げる方式です。
  秒あたりの本数を固定する open-loop（オープンループ）ではありません。
- warmup（ウォームアップ）: 計測開始前の準備運転です。この期間のサンプルは
  集計から完全に除外します。
- p95: 応答時間を小さい順に並べたとき、下から 95% の位置にある値です。

パーセンタイルの定義（重要）
----------------------------
本スクリプトは **nearest-rank 法**（最近接順位法）を採用します。
昇順に並べた N 件のサンプルに対し、順位 rank を

    rank = ceil(q / 100 * N)      （1 <= rank <= N）

として、その rank 番目（1 始まり）の値をそのまま返します。
線形補間（numpy の既定など）は行いません。値はサンプルに実在する値です。
- N = 0 のときは None を返します（落ちません）。
- q <= 0 のときは rank = 1 として最小値を返します。

エラー率の定義（重要）
----------------------
    エラー率 = エラー件数 / (warmup 後に完了した全リクエスト件数)
分子は通信エラーと HTTP の非成功応答（2xx/3xx 以外）の合計です。
分母は「warmup 後に完了した全リクエスト」＝ HTTP 応答件数 + 通信エラー件数 です。
HTTP エラーは応答件数に含まれるため、分母へ二重に加算しません。
warmup 中に完了したものと、打ち切り時にまだ完了していないものは、
分子にも分母にも入れません。

レイテンシ集計の対象（重要）
----------------------------
タイムアウト・接続エラーなど、レスポンスを受け取れなかったものは
レイテンシ（応答時間）の集計に **混ぜません**。エラー種別ごとに別で数えます。
HTTP のステータスコードが 4xx/5xx でも、レスポンスが返ってきた以上は
応答時間のサンプルとして採用します（ステータス別内訳で内容が分かります）。

この計測が保証しないこと
------------------------
出力 JSON の "scope_note" に日本語で明記します。1 台のマシン上・ローカル接続・
コンテナ内という条件での参考値であり、本番環境の性能保証値ではありません。
"""

from __future__ import annotations

import argparse
import json
import math
import signal
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Any, Iterable, Sequence

SCOPE_NOTE = (
    "この計測は 1 台のマシン上でローカル接続（同一ホスト・コンテナ内）に対して "
    "行った参考値です。本番環境における性能の保証値ではありません。"
    "ネットワーク遅延・実利用者の分布・同時に動く他の負荷・データ量の違いは "
    "含まれていません。負荷生成器自身も同じマシンの CPU を使うため、"
    "高い並列数では測定側がボトルネックになることがあります。"
)

# 打ち切り要求（SIGINT）を全スレッドで共有するフラグです。
_STOP = threading.Event()


@dataclass
class Sample:
    """レスポンスを受け取れた 1 件の記録です。"""

    # 応答時間（ミリ秒）。
    latency_ms: float
    # HTTP ステータスコード。
    status: int
    # warmup 期間中に「完了」したかどうか。True なら集計から除外します。
    warmup: bool = False


@dataclass
class ErrorRecord:
    """レスポンスを受け取れなかった 1 件の記録です。"""

    # "timeout" / "connection_error" / "unknown" などの種別。
    kind: str
    # warmup 期間中に「完了」したかどうか。True なら集計から除外します。
    warmup: bool = False


@dataclass
class Collected:
    """ワーカーが集めた生データです。"""

    samples: list[Sample] = field(default_factory=list)
    errors: list[ErrorRecord] = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def add_sample(self, sample: Sample) -> None:
        with self.lock:
            self.samples.append(sample)

    def add_error(self, error: ErrorRecord) -> None:
        with self.lock:
            self.errors.append(error)


# --------------------------------------------------------------------------
# 純粋関数（ネットワークを使わない。tests/test_perf.py がここを検証します）
# --------------------------------------------------------------------------


def percentile(sorted_values: Sequence[float], q: float) -> float | None:
    """昇順に並んだ数値列から、nearest-rank 法でパーセンタイルを返します。

    rank = ceil(q / 100 * N) を 1 以上 N 以下に丸め、その rank 番目
    （1 始まり）の値をそのまま返します。線形補間は行いません。

    引数 sorted_values は **昇順に並んでいる前提** です（この関数は並べ替えません）。
    サンプルが 0 件のときは None を返します。
    """
    n = len(sorted_values)
    if n == 0:
        return None
    if q <= 0:
        return sorted_values[0]
    rank = math.ceil(q / 100.0 * n)
    if rank < 1:
        rank = 1
    if rank > n:
        rank = n
    return sorted_values[rank - 1]


def summarize(
    samples: Iterable[Sample],
    errors: Iterable[ErrorRecord],
    elapsed_s: float,
) -> dict[str, Any]:
    """warmup を除いたサンプルとエラーから、集計結果の辞書を作ります。

    - warmup=True の記録は、サンプル・エラーの両方とも完全に除外します。
    - レイテンシ統計の対象は「レスポンスを受け取れたもの」だけです。
      タイムアウト・接続エラーは latency に混ざりません。
    - エラー率の分母は「warmup 後に完了した全リクエスト」
      ＝ HTTP 応答件数 + 通信エラー件数 です。HTTP 非成功応答も分子へ含めます。
    - elapsed_s が 0 以下のときは throughput を 0.0 とします（ゼロ除算回避）。
    """
    counted_samples = [s for s in samples if not s.warmup]
    counted_errors = [e for e in errors if not e.warmup]

    latencies = sorted(s.latency_ms for s in counted_samples)
    status_counts = Counter(s.status for s in counted_samples)
    error_counts = Counter(e.kind for e in counted_errors)

    # 分母: warmup 後に完了した全リクエスト。
    total_completed = len(counted_samples) + len(counted_errors)
    # 2xx/3xx を「成功」とみなします（4xx/5xx はレスポンスは返っているので
    # レイテンシには含めますが、成功数からは外します）。
    success_count = sum(c for st, c in status_counts.items() if 200 <= st < 400)
    transport_error_count = len(counted_errors)
    http_error_count = len(counted_samples) - success_count
    error_count = transport_error_count + http_error_count
    error_rate = (error_count / total_completed) if total_completed else 0.0

    throughput = (total_completed / elapsed_s) if elapsed_s > 0 else 0.0

    return {
        "total_requests": total_completed,
        "success_requests": success_count,
        "response_requests": len(counted_samples),
        "error_requests": error_count,
        "transport_error_requests": transport_error_count,
        "http_error_requests": http_error_count,
        "error_rate": error_rate,
        "error_rate_definition": "通信エラー + HTTP 非成功応答（2xx/3xx 以外） / 全完了件数",
        "error_rate_denominator": "warmup 後に完了した全リクエスト（HTTP 応答 + 通信エラー）",
        "status_counts": {str(k): v for k, v in sorted(status_counts.items())},
        "error_counts": dict(sorted(error_counts.items())),
        "elapsed_seconds": elapsed_s,
        "throughput_rps": throughput,
        "success_throughput_rps": (success_count / elapsed_s) if elapsed_s > 0 else 0.0,
        "latency_ms": {
            "count": len(latencies),
            "min": latencies[0] if latencies else None,
            "p50": percentile(latencies, 50),
            "p90": percentile(latencies, 90),
            "p95": percentile(latencies, 95),
            "p99": percentile(latencies, 99),
            "max": latencies[-1] if latencies else None,
        },
        "percentile_method": "nearest-rank（最近接順位法・線形補間なし）",
    }


def evaluate_slo(
    summary: dict[str, Any],
    p95_ms: float | None = None,
    error_rate: float | None = None,
) -> dict[str, Any]:
    """集計結果を SLO のしきい値と突き合わせ、PASS / FAIL を判定します。

    - しきい値が両方とも None のときは判定しません（verdict は None）。
    - 「しきい値ちょうど」は PASS です（p95 <= しきい値 / error_rate <= しきい値）。
    - 判定に必要なサンプルが 0 件のときは FAIL とします
      （測れていないものを PASS とは呼ばないためです）。
    """
    checks: list[dict[str, Any]] = []

    if p95_ms is not None:
        actual_p95 = summary.get("latency_ms", {}).get("p95")
        if actual_p95 is None:
            checks.append(
                {
                    "name": "p95_latency_ms",
                    "threshold": p95_ms,
                    "actual": None,
                    "passed": False,
                    "reason": "レイテンシのサンプルが 0 件のため判定できません（FAIL 扱い）。",
                }
            )
        else:
            passed = actual_p95 <= p95_ms
            checks.append(
                {
                    "name": "p95_latency_ms",
                    "threshold": p95_ms,
                    "actual": actual_p95,
                    "passed": passed,
                    "reason": (
                        f"p95 = {actual_p95:.3f} ms がしきい値 {p95_ms} ms 以下です。"
                        if passed
                        else f"p95 = {actual_p95:.3f} ms がしきい値 {p95_ms} ms を超えました。"
                    ),
                }
            )

    if error_rate is not None:
        actual_rate = summary.get("error_rate")
        total = summary.get("total_requests", 0)
        if not total:
            checks.append(
                {
                    "name": "error_rate",
                    "threshold": error_rate,
                    "actual": None,
                    "passed": False,
                    "reason": "完了したリクエストが 0 件のため判定できません（FAIL 扱い）。",
                }
            )
        else:
            passed = actual_rate <= error_rate
            checks.append(
                {
                    "name": "error_rate",
                    "threshold": error_rate,
                    "actual": actual_rate,
                    "passed": passed,
                    "reason": (
                        f"エラー率 {actual_rate:.6f} がしきい値 {error_rate} 以下です。"
                        if passed
                        else f"エラー率 {actual_rate:.6f} がしきい値 {error_rate} を超えました。"
                    ),
                }
            )

    if not checks:
        return {"verdict": None, "checks": [], "note": "SLO のしきい値が指定されていません。"}

    verdict = "PASS" if all(c["passed"] for c in checks) else "FAIL"
    return {
        "verdict": verdict,
        "checks": checks,
        "note": "しきい値ちょうどの場合は PASS とします（<= で判定）。",
    }


def parse_header(raw: str) -> tuple[str, str]:
    """`Name: value` 形式の文字列を (名前, 値) に分解します。"""
    if ":" not in raw:
        raise ValueError(f"ヘッダーは 'Name: value' 形式で指定してください: {raw!r}")
    name, _, value = raw.partition(":")
    name = name.strip()
    value = value.strip()
    if not name:
        raise ValueError(f"ヘッダー名が空です: {raw!r}")
    return name, value


def classify_error(exc: BaseException) -> str:
    """例外を、集計に使うエラー種別の文字列に振り分けます。"""
    if isinstance(exc, TimeoutError):
        return "timeout"
    if isinstance(exc, urllib.error.HTTPError):
        # HTTPError はレスポンスが返っているため通常ここには来ませんが、保険です。
        return "http_error"
    if isinstance(exc, urllib.error.URLError):
        reason = getattr(exc, "reason", None)
        if isinstance(reason, TimeoutError):
            return "timeout"
        if isinstance(reason, OSError):
            return "connection_error"
        return "url_error"
    if isinstance(exc, OSError):
        return "connection_error"
    return "unknown"


# --------------------------------------------------------------------------
# 実行部（ここはネットワークを使います）
# --------------------------------------------------------------------------


def _request_once(
    url: str, headers: dict[str, str], timeout: float
) -> tuple[float, int | None, str | None]:
    """1 件だけリクエストを投げ、(応答時間ms, ステータス, エラー種別) を返します。"""
    req = urllib.request.Request(url, method="GET")
    for name, value in headers.items():
        req.add_header(name, value)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            resp.read()
            status = resp.status
        elapsed_ms = (time.monotonic() - started) * 1000.0
        return elapsed_ms, status, None
    except urllib.error.HTTPError as exc:
        # 4xx/5xx はレスポンスが返っているので、レイテンシのサンプルにします。
        try:
            exc.read()
        except Exception:  # noqa: BLE001  読み捨てに失敗しても計測は続けます。
            pass
        finally:
            exc.close()
        elapsed_ms = (time.monotonic() - started) * 1000.0
        return elapsed_ms, exc.code, None
    except BaseException as exc:  # noqa: BLE001  種別に振り分けて数えます。
        elapsed_ms = (time.monotonic() - started) * 1000.0
        return elapsed_ms, None, classify_error(exc)


def _worker(
    url: str,
    headers: dict[str, str],
    timeout: float,
    warmup_deadline: float,
    end_deadline: float,
    collected: Collected,
) -> None:
    """closed-loop の投げ手 1 本ぶんのループです。"""
    while not _STOP.is_set() and time.monotonic() < end_deadline:
        latency_ms, status, error_kind = _request_once(url, headers, timeout)
        # 「完了した時刻」が warmup 期間内なら、そのサンプルは集計から除外します。
        is_warmup = time.monotonic() < warmup_deadline
        if error_kind is None and status is not None:
            collected.add_sample(Sample(latency_ms=latency_ms, status=status, warmup=is_warmup))
        else:
            collected.add_error(ErrorRecord(kind=error_kind or "unknown", warmup=is_warmup))


def run_load(
    url: str,
    concurrency: int,
    duration_s: float,
    warmup_s: float,
    timeout_s: float,
    headers: dict[str, str],
) -> tuple[Collected, float, bool]:
    """負荷をかけ、(生データ, 計測秒数, 打ち切られたか) を返します。

    計測秒数は warmup を除いた実測時間です（time.monotonic() で測ります）。
    """
    collected = Collected()
    start = time.monotonic()
    warmup_deadline = start + warmup_s
    end_deadline = warmup_deadline + duration_s

    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [
            pool.submit(
                _worker, url, headers, timeout_s, warmup_deadline, end_deadline, collected
            )
            for _ in range(concurrency)
        ]
        for fut in futures:
            fut.result()

    finished = time.monotonic()
    # warmup 後の実測時間。warmup 中に打ち切られた場合は 0 未満になりうるので下限を置きます。
    measured_s = max(0.0, finished - warmup_deadline)
    return collected, measured_s, _STOP.is_set()


def build_report(
    args: argparse.Namespace,
    summary: dict[str, Any],
    slo: dict[str, Any],
    interrupted: bool,
) -> dict[str, Any]:
    """出力 JSON を組み立てます。"""
    report: dict[str, Any] = {
        "schema_version": 2,
        "tool": "scripts/perf/load.py",
        "label": args.label,
        "target_url": args.url,
        "config": {
            "concurrency": args.concurrency,
            "duration_seconds": args.duration,
            "warmup_seconds": args.warmup,
            "timeout_seconds": args.timeout,
            "mode": "closed-loop",
        },
        "partial": interrupted,
        "partial_note": (
            "SIGINT（Ctrl+C）で途中打ち切りされたため、予定した計測時間に達していません。"
            "この結果は部分的なものです。"
            if interrupted
            else ""
        ),
        "summary": summary,
        "slo": slo,
        "verdict": slo.get("verdict"),
        "scope_note": SCOPE_NOTE,
    }
    return report


def _install_sigint_handler() -> None:
    def _handler(signum: int, frame: Any) -> None:  # noqa: ARG001
        _STOP.set()
        print("\n[load.py] SIGINT を受け取りました。安全に打ち切ります…", file=sys.stderr)

    signal.signal(signal.SIGINT, _handler)


def format_human(report: dict[str, Any]) -> str:
    """人間向けのサマリーを組み立てます。"""
    s = report["summary"]
    lat = s["latency_ms"]

    def ms(value: float | None) -> str:
        return "-" if value is None else f"{value:.1f} ms"

    lines = [
        "==== 負荷試験サマリー ====",
        f"対象 URL          : {report['target_url']}",
        f"ラベル            : {report['label'] or '(なし)'}",
        f"並列数 / 計測時間 : {report['config']['concurrency']} / "
        f"{s['elapsed_seconds']:.2f} 秒（warmup {report['config']['warmup_seconds']} 秒は除外）",
        f"総リクエスト      : {s['total_requests']} 件"
        f"（うち成功 {s['success_requests']} 件 / エラー {s['error_requests']} 件）",
        f"エラー率          : {s['error_rate'] * 100:.3f} %",
        f"スループット      : {s['throughput_rps']:.2f} req/s",
        f"ステータス内訳    : {s['status_counts'] or '(なし)'}",
        f"通信エラー内訳    : {s['error_counts'] or '(なし)'}",
        f"HTTP 非成功応答   : {s['http_error_requests']} 件（2xx/3xx 以外）",
        f"レイテンシ        : min {ms(lat['min'])} / p50 {ms(lat['p50'])} / "
        f"p90 {ms(lat['p90'])} / p95 {ms(lat['p95'])} / p99 {ms(lat['p99'])} / max {ms(lat['max'])}",
        f"パーセンタイル法  : {s['percentile_method']}",
    ]
    if report["partial"]:
        lines.append(f"注意              : {report['partial_note']}")
    if report["slo"]["verdict"] is not None:
        lines.append(f"SLO 判定          : {report['slo']['verdict']}")
        for check in report["slo"]["checks"]:
            lines.append(f"  - {check['name']}: {check['reason']}")
    lines.append(f"この計測の範囲    : {report['scope_note']}")
    return "\n".join(lines)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="load.py",
        description=(
            "依存ゼロ（標準ライブラリのみ）の closed-loop 負荷生成器です。"
            "指定した並列数で URL にリクエストを投げ続け、応答時間とエラーを集計します。"
        ),
        epilog=(
            "注意: この計測は 1 台のマシン上のローカル接続に対する参考値であり、"
            "本番環境の性能保証値ではありません。"
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--url", required=True, help="負荷をかける対象の URL")
    parser.add_argument("--concurrency", type=int, default=4, help="同時に投げる本数（並列数）")
    parser.add_argument("--duration", type=float, default=30.0, help="計測時間（秒）")
    parser.add_argument(
        "--warmup", type=float, default=5.0, help="準備運転の時間（秒）。この間のサンプルは集計しません"
    )
    parser.add_argument("--timeout", type=float, default=10.0, help="1 リクエストのタイムアウト（秒）")
    parser.add_argument("--out", default=None, help="結果 JSON の出力先ファイルパス")
    parser.add_argument(
        "--header",
        action="append",
        default=[],
        metavar="'Name: value'",
        help="追加する HTTP ヘッダー（複数回指定できます）",
    )
    parser.add_argument(
        "--slo-p95-ms", type=float, default=None, help="p95 応答時間のしきい値（ミリ秒）"
    )
    parser.add_argument(
        "--slo-error-rate", type=float, default=None, help="エラー率のしきい値（0.01 = 1%%）"
    )
    parser.add_argument("--label", default="", help="この実行につける名前（結果 JSON に入ります）")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    if args.concurrency < 1:
        print("[load.py] --concurrency は 1 以上にしてください。", file=sys.stderr)
        return 2
    if args.duration <= 0:
        print("[load.py] --duration は 0 より大きくしてください。", file=sys.stderr)
        return 2
    if args.warmup < 0:
        print("[load.py] --warmup は 0 以上にしてください。", file=sys.stderr)
        return 2

    try:
        headers = dict(parse_header(h) for h in args.header)
    except ValueError as exc:
        print(f"[load.py] {exc}", file=sys.stderr)
        return 2

    _install_sigint_handler()

    collected, measured_s, interrupted = run_load(
        url=args.url,
        concurrency=args.concurrency,
        duration_s=args.duration,
        warmup_s=args.warmup,
        timeout_s=args.timeout,
        headers=headers,
    )

    summary = summarize(collected.samples, collected.errors, measured_s)
    slo = evaluate_slo(summary, args.slo_p95_ms, args.slo_error_rate)
    report = build_report(args, summary, slo, interrupted)

    print(format_human(report))

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(report, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        print(f"[load.py] 結果 JSON を書き出しました: {args.out}")

    # 最終行に機械可読の JSON を出します（既存 drill スクリプトと同じ流儀です）。
    print("RESULT_JSON=" + json.dumps(report, ensure_ascii=False, separators=(",", ":")))

    if slo["verdict"] == "FAIL":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
