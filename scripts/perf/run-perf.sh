#!/usr/bin/env bash
# 段階負荷試験（ステップロードテスト）ランナー
#
# 「並列数（同時にリクエストを投げる本数）を少しずつ上げていき、どこで頭打ちに
# なるか」を測るためのスクリプトです。頭打ちになる点を「飽和点」と呼びます。
# 飽和点が分かると「この構成なら同時どれくらいまで捌けるか」という容量設計
# （キャパシティプランニング）の根拠になります。
#
# 使い方:
#   scripts/perf/run-perf.sh [--url URL] [--steps 1,2,4,8,16,32] [--duration 30]
#                            [--warmup 5] [--out-dir ./perf-results]
#                            [--workers N] [--request-timeout 10] [--no-compose]
#
# 出力:
#   docs/drills/logs/ にそのまま貼れる Markdown サマリーを stdout、
#   機械可読 JSON を最終行に "RESULT_JSON=" で出力します（d1-process-down.sh と同じ作法）。
#
# 状態: 実装済み（未実施 / NOT RUN）
#   このスクリプトはまだ実行していません。数値は実行したときに初めて生まれます。
#   このファイルにも、リポジトリのどこにも、測っていない数値は書いていません。

set -euo pipefail

# ------------------------------------------------------------------
# 既定値
# ------------------------------------------------------------------
URL="http://127.0.0.1:8080/healthz"
STEPS="1,2,4,8,16,32"
DURATION=30
WARMUP=5
OUT_DIR="./perf-results"
WORKERS=""
REQUEST_TIMEOUT=10
NO_COMPOSE=0

# /healthz が 200 を返すまで待つ上限秒（安全装置）。
readonly HEALTH_WAIT_SECONDS=120

# SLO（docs/slo.md）。値は変更しません。load.py に渡して各段の合否判定に使います。
readonly SLO_P95_MS=500
readonly SLO_ERROR_RATE=0.01

# 飽和判定のしきい値。詳しい判定式は「6. 集計と飽和点の判定」のコメントを参照。
readonly SATURATION_GAIN_THRESHOLD=0.10    # スループットの伸び率がこれ未満なら「伸びていない」
readonly SATURATION_LATENCY_FACTOR=1.20    # p95 がこの倍率を超えて伸びたら「レイテンシだけ悪化」

usage() {
  cat <<EOF
Usage: $0 [--url URL] [--steps LIST] [--duration SECONDS] [--warmup SECONDS]
          [--out-dir DIR] [--workers N] [--request-timeout SECONDS] [--no-compose]

  --url              負荷をかける URL (default: http://127.0.0.1:8080/healthz)
  --steps            並列数の段をカンマ区切りで指定 (default: 1,2,4,8,16,32)
  --duration         1 段あたりの計測秒数 (default: 30)
  --warmup           計測前のウォームアップ秒数 (default: 5)
  --out-dir          各段の JSON を保存する directory (default: ./perf-results)
  --workers          Gunicorn の worker 数 (GUNICORN_WORKERS として compose に渡す)
                     compose.perf.yaml が起動コマンドごと差し替えるため実際に効きます。
                     --no-compose のときは既に起動済みの環境を測るので効きません。
  --request-timeout  1 リクエストあたりの上限秒 (default: 10)
  --no-compose       compose を起動しない（すでに起動済みの環境に対して実行する）
  --help             このヘルプ

判定:
  各段の合否は load.py が SLO (p95 <= ${SLO_P95_MS}ms / error_rate <= ${SLO_ERROR_RATE}) で判定します。
  しきい値ちょうどは PASS です（docs/performance-test.md 7.2 参照）。
  全体の verdict は「SLO を満たした段が 1 つ以上あれば PASS」です。
  SLO を満たさなかった段があっても計測は止めず、最後まで測ってから判定します
  （どこで頭打ちになるかを知るのがこの試験の目的のためです）。
  exit code は PASS のとき 0、FAIL のとき 1、計測そのものに失敗したとき 5 です。

注意:
  このスクリプトは実際にサーバーへ負荷をかけます。本番環境では実行しないでください。
EOF
}

# ------------------------------------------------------------------
# 引数の解析（d1-process-down.sh と同じ書き方に揃えています）
# ------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)             URL="$2"; shift 2 ;;
    --steps)           STEPS="$2"; shift 2 ;;
    --duration)        DURATION="$2"; shift 2 ;;
    --warmup)          WARMUP="$2"; shift 2 ;;
    --out-dir)         OUT_DIR="$2"; shift 2 ;;
    --workers)         WORKERS="$2"; shift 2 ;;
    --request-timeout) REQUEST_TIMEOUT="$2"; shift 2 ;;
    --no-compose)      NO_COMPOSE=1; shift ;;
    --help|-h)         usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

# ------------------------------------------------------------------
# 1. 入力の検証（安全装置）
#    おかしな値のまま負荷をかけ始めないよう、先にすべて弾きます。
# ------------------------------------------------------------------
[[ "$DURATION"        =~ ^[1-9][0-9]{0,4}$ ]] || { echo "invalid --duration: $DURATION" >&2; exit 2; }
[[ "$WARMUP"          =~ ^[0-9]{1,4}$      ]] || { echo "invalid --warmup: $WARMUP" >&2; exit 2; }
[[ "$REQUEST_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "invalid --request-timeout: $REQUEST_TIMEOUT" >&2; exit 2; }
[[ "$URL" =~ ^https?:// ]] || { echo "invalid --url: $URL" >&2; exit 2; }
if [[ -n "$WORKERS" ]]; then
  [[ "$WORKERS" =~ ^[1-9][0-9]{0,2}$ ]] || { echo "invalid --workers: $WORKERS" >&2; exit 2; }
fi

# --steps をカンマで分解して配列にします。
STEP_LIST=()
IFS=',' read -r -a STEP_LIST <<< "$STEPS"
[[ "${#STEP_LIST[@]}" -ge 1 ]] || { echo "invalid --steps: $STEPS" >&2; exit 2; }
PREV_STEP=0
for step in "${STEP_LIST[@]}"; do
  [[ "$step" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "invalid step in --steps: $step" >&2; exit 2; }
  # 段は昇順であることを要求します。飽和点の判定が「前の段との比較」だからです。
  if (( 10#$step <= PREV_STEP )); then
    echo "--steps は昇順で指定してください: $STEPS" >&2
    exit 2
  fi
  PREV_STEP=$((10#$step))
done

require_cmd curl
require_cmd python3

# ------------------------------------------------------------------
# 2. パスの決定
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
LOAD_PY="${SCRIPT_DIR}/load.py"

if [[ ! -f "$LOAD_PY" ]]; then
  echo "負荷生成スクリプトが見つかりません: $LOAD_PY" >&2
  echo "scripts/perf/load.py が必要です。数値を捏造しないため、ここで停止します。" >&2
  exit 3
fi

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_DIR="${OUT_DIR%/}/${RUN_ID}"

# ------------------------------------------------------------------
# 3. compose の準備と後始末（trap）
#    --no-compose のときは何も起動せず、何も落としません。
# ------------------------------------------------------------------
COMPOSE=()
COMPOSE_STARTED=0

cleanup() {
  local rc=$?
  if [[ "$COMPOSE_STARTED" -eq 1 && "${#COMPOSE[@]}" -gt 0 ]]; then
    log "後始末: app と nginx を停止します（コンテナや volume は削除しません）"
    "${COMPOSE[@]}" stop app nginx >/dev/null 2>&1 || true
  fi
  return "$rc"
}
trap cleanup EXIT

if [[ "$NO_COMPOSE" -eq 0 ]]; then
  require_cmd docker
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose
             -f "${PROJECT_DIR}/compose.yaml"
             -f "${PROJECT_DIR}/compose.perf.yaml"
             --project-directory "$PROJECT_DIR")
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose
             -f "${PROJECT_DIR}/compose.yaml"
             -f "${PROJECT_DIR}/compose.perf.yaml"
             --project-directory "$PROJECT_DIR")
  else
    echo "docker compose plugin が見つかりません" >&2
    exit 1
  fi

  if [[ -n "$WORKERS" ]]; then
    export GUNICORN_WORKERS="$WORKERS"
    log "Gunicorn worker 数: ${WORKERS}（compose.perf.yaml が起動コマンドごと差し替えます）"
  else
    log "Gunicorn worker 数: 指定なし（compose.perf.yaml の既定 2 のまま）"
  fi

  log "compose 起動: app, nginx （監視系は profiles で除外しています）"
  COMPOSE_STARTED=1
  "${COMPOSE[@]}" up -d app nginx
else
  log "--no-compose: 起動済みの環境に対して実行します（後始末もしません）"
fi

# ------------------------------------------------------------------
# 4. /healthz が 200 を返すまで待機（安全装置）
#    起動しきる前に負荷をかけると、起動遅延を「遅さ」として誤って測ってしまいます。
# ------------------------------------------------------------------
health_ok() {
  local status
  status="$(curl -sS -o /dev/null --max-time 5 -w '%{http_code}' "$URL")" || return 1
  [[ "$status" == "200" ]]
}

log "疎通待ち: ${URL} が 200 を返すまで最大 ${HEALTH_WAIT_SECONDS} 秒待ちます"
WAIT_DEADLINE=$(( $(date -u +%s) + HEALTH_WAIT_SECONDS ))
HEALTH_READY=0
while :; do
  if health_ok 2>/dev/null; then
    HEALTH_READY=1
    break
  fi
  if [[ "$(date -u +%s)" -ge "$WAIT_DEADLINE" ]]; then
    break
  fi
  sleep 2
done

if [[ "$HEALTH_READY" -ne 1 ]]; then
  echo "疎通 NG: ${HEALTH_WAIT_SECONDS} 秒待っても ${URL} が 200 を返しませんでした。" >&2
  echo "負荷をかけずに終了します（測れていないものを結果として残さないためです）。" >&2
  exit 4
fi
log "疎通 OK"

# 疎通が取れてから結果 directory を作ります。1 度も測らずに終わった実行が
# 空の結果 directory を残さないようにするためです。
mkdir -p "$RUN_DIR"
log "結果の保存先: ${RUN_DIR}"

# ------------------------------------------------------------------
# 5. ウォームアップ → 各段の計測
#    ウォームアップ（暖機運転）は、初回アクセス時だけ発生する遅さ（Python の
#    import、コネクション確立など）を計測結果から除くための空回しです。
#    ここで 1 回まとめて空回ししておき、各段では --warmup 0 で計測に専念します。
# ------------------------------------------------------------------
STEP_FILES=()

if [[ "$WARMUP" -gt 0 ]]; then
  log "ウォームアップ: 並列 ${STEP_LIST[0]} で ${WARMUP} 秒（結果は集計に使いません）"
  python3 "$LOAD_PY" \
    --url "$URL" \
    --concurrency "${STEP_LIST[0]}" \
    --duration "$WARMUP" \
    --warmup 0 \
    --timeout "$REQUEST_TIMEOUT" \
    --label "warmup" \
    --out "${RUN_DIR}/warmup.json" >/dev/null
fi

for step in "${STEP_LIST[@]}"; do
  out_file="${RUN_DIR}/step-c${step}.json"
  log "計測: 並列 ${step} / ${DURATION} 秒 -> ${out_file}"
  # load.py は SLO を満たさなかった段で終了コード 1 を返します。
  # ここで set -e に止められてしまうと、最初に SLO を割った段で試験全体が
  # 打ち切られ、「どこで頭打ちになるか」を探すというこの試験の目的そのものが
  # 果たせなくなります（飽和点は前後の段を比べて初めて分かるためです）。
  # そこで終了コードは記録だけして次の段へ進み、合否は「6. 集計」で
  # すべての段が出そろってから判定します。
  step_rc=0
  python3 "$LOAD_PY" \
    --url "$URL" \
    --concurrency "$step" \
    --duration "$DURATION" \
    --warmup 0 \
    --timeout "$REQUEST_TIMEOUT" \
    --label "c${step}" \
    --slo-p95-ms "$SLO_P95_MS" \
    --slo-error-rate "$SLO_ERROR_RATE" \
    --out "$out_file" >/dev/null || step_rc=$?
  # 結果 JSON が空、または書き出されていない場合は、SLO 未達ではなく
  # 計測そのものが失敗しています。測れていないものを集計に混ぜないよう、
  # ここで停止します。
  if [[ ! -s "$out_file" ]]; then
    echo "計測に失敗しました（並列 ${step} / load.py の終了コード ${step_rc}）。" >&2
    echo "結果 JSON が書き出されていないため、ここで停止します。" >&2
    echo "測っていない値を結果として残さないための停止です。" >&2
    exit 5
  fi
  if (( step_rc != 0 )); then
    log "並列 ${step}: load.py の終了コードは ${step_rc}（SLO を満たさなかった段）。計測は続けます。"
  fi
  STEP_FILES+=("$out_file")
  # 段と段のあいだを少し空け、サーバー側のキューやコネクションを落ち着かせます。
  sleep 3
done

# ------------------------------------------------------------------
# 6. 集計と飽和点の判定
#
#    【飽和点の判定式】
#      段 i（i >= 2、並列数の昇順）について、1 つ手前の段 i-1 と比べます。
#
#        gain_i      = (rps_i - rps_{i-1}) / rps_{i-1}     … スループットの伸び率
#        lat_ratio_i = p95_i / p95_{i-1}                    … レイテンシ p95 の伸び率
#
#      次の 2 条件を同時に満たした最初の段 i を「飽和した段」と呼びます。
#
#        (A) gain_i      <  ${SATURATION_GAIN_THRESHOLD}   … 並列を増やしても処理量が伸びない
#        (B) lat_ratio_i >  ${SATURATION_LATENCY_FACTOR}   … その一方でレイテンシだけ悪化する
#
#      このとき報告する「飽和点 (saturation_concurrency)」は、飽和した段 i ではなく
#      その 1 つ手前の段 i-1 の並列数です。すなわち「まだ余裕のあった最大の並列数」を
#      容量設計の基準値として扱います。
#
#      最後の段まで (A) と (B) を同時に満たさなかった場合、飽和点は null（未検出）です。
#      これは「飽和しなかった」ではなく「試験した範囲内では飽和点が見つからなかった」
#      という意味です。より大きい並列数で再測定する必要があります。
#
#      rps_{i-1} が 0、または p95_{i-1} が 0 の段は比較できないため判定をスキップします。
#
#    集計は python3 に任せます（bash は小数計算が苦手なためです）。
#    数値はすべて各段の JSON から読み出したものだけで、計算以外の加工はしません。
# ------------------------------------------------------------------
python3 - \
  "$SATURATION_GAIN_THRESHOLD" \
  "$SATURATION_LATENCY_FACTOR" \
  "$URL" "$DURATION" "$WARMUP" "${WORKERS:-default}" "$RUN_DIR" "$NO_COMPOSE" \
  "${STEP_FILES[@]}" <<'PY' | tee "${RUN_DIR}/summary.md"
import json
import sys

gain_threshold = float(sys.argv[1])
latency_factor = float(sys.argv[2])
url, duration, warmup, workers, run_dir, no_compose_raw = sys.argv[3:9]
step_files = sys.argv[9:]

# --no-compose のときは既に起動済みの環境をそのまま測るため、worker 数の指定は
# 反映されません。渡した値と実際に適用されたかどうかを取り違えないよう分けて持ちます。
no_compose = no_compose_raw == "1"
workers_applied = (workers != "default") and not no_compose

def pick(data, *candidates):
    """JSON の入れ子の形が変わっても読めるよう、候補の場所を順に試します。

    load.py は値を top-level に置く場合と summary / config の下に置く場合が
    あるため、両方に対応します。見つからなければ None を返し、その段は
    「値なし」として扱います（推測で埋めることは絶対にしません）。
    """
    for keys in candidates:
        cur = data
        found = True
        for key in keys:
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            else:
                found = False
                break
        if found and cur is not None:
            return cur
    return None


rows = []
for path in step_files:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    rows.append({
        "path": path,
        "label": pick(data, ("label",)) or "",
        "concurrency": pick(data, ("concurrency",), ("config", "concurrency")),
        "rps": pick(data, ("throughput_rps",), ("summary", "throughput_rps")),
        "p50": pick(data, ("latency_ms", "p50"), ("summary", "latency_ms", "p50")),
        "p95": pick(data, ("latency_ms", "p95"), ("summary", "latency_ms", "p95")),
        "p99": pick(data, ("latency_ms", "p99"), ("summary", "latency_ms", "p99")),
        "error_rate": pick(data, ("error_rate",), ("summary", "error_rate")),
        "verdict": pick(data, ("verdict",), ("slo", "verdict")),
        "partial": bool(pick(data, ("partial",)) or False),
    })


def num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def fmt(value, digits):
    return format(value, "." + str(digits) + "f") if num(value) else "n/a"


# ---- 飽和点の判定（判定式は run-perf.sh のコメントと同一）----
saturated_index = None
for i in range(1, len(rows)):
    prev, cur = rows[i - 1], rows[i]
    if not (num(prev["rps"]) and num(cur["rps"]) and num(prev["p95"]) and num(cur["p95"])):
        continue
    if prev["rps"] <= 0 or prev["p95"] <= 0:
        continue
    gain = (cur["rps"] - prev["rps"]) / prev["rps"]
    lat_ratio = cur["p95"] / prev["p95"]
    cur["gain"] = gain
    cur["lat_ratio"] = lat_ratio
    if saturated_index is None and gain < gain_threshold and lat_ratio > latency_factor:
        saturated_index = i

if saturated_index is None:
    saturation_concurrency = None
    saturated_at = None
else:
    saturation_concurrency = rows[saturated_index - 1]["concurrency"]
    saturated_at = rows[saturated_index]["concurrency"]

# ---- SLO を満たした最大の並列数 ----
slo_ok = [r["concurrency"] for r in rows
          if r["verdict"] == "PASS" and num(r["concurrency"])]
slo_max_concurrency = max(slo_ok) if slo_ok else None
verdict = "PASS" if slo_max_concurrency is not None else "FAIL"

# ---- Markdown サマリー（docs/drills/logs/ にそのまま貼れる形）----
out = []
out.append("## 段階負荷試験サマリー")
out.append("")
out.append("| 項目 | 値 |")
out.append("| --- | --- |")
out.append("| 対象 URL | `%s` |" % url)
out.append("| 1 段あたりの計測秒数 | %s 秒 |" % duration)
out.append("| ウォームアップ | %s 秒 |" % warmup)
out.append("| Gunicorn worker 数 | %s |" % (
    workers if workers_applied
    else ("%s（渡したが未適用）" % workers if workers != "default" else "指定なし（既定 2）")))
out.append("| 結果ファイル | `%s` |" % run_dir)
out.append("")
if workers != "default" and not workers_applied:
    # 渡した値と、実際に適用された値を取り違えないための注記です。
    out.append("> 注意: `--no-compose` で起動済みの環境を測ったため、`--workers` の指定は")
    out.append("> 反映されていません。worker 数を変えて比べるときは `--no-compose` を外します。")
    out.append("")
out.append("### 各段の結果")
out.append("")
out.append("| 並列数 | スループット (req/s) | p95 (ms) | エラー率 | 前段比 伸び率 | 前段比 p95 倍率 | SLO 判定 |")
out.append("| ---: | ---: | ---: | ---: | ---: | ---: | :--- |")
for r in rows:
    out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
        r["concurrency"] if r["concurrency"] is not None else "n/a",
        fmt(r["rps"], 1),
        fmt(r["p95"], 1),
        fmt(r["error_rate"], 4),
        (fmt(r["gain"] * 100, 1) + "%") if num(r.get("gain")) else "-",
        (fmt(r["lat_ratio"], 2) + "x") if num(r.get("lat_ratio")) else "-",
        r["verdict"] or "n/a",
    ))
out.append("")
out.append("### 飽和点")
out.append("")
out.append("判定式: 前段比のスループット伸び率 < %s%% かつ p95 の伸びが %sx 超 を"
           "最初に満たした段の、1 つ手前の並列数を飽和点とします。"
           % (fmt(gain_threshold * 100, 0), fmt(latency_factor, 2)))
out.append("")
if saturation_concurrency is None:
    out.append("- 飽和点: **未検出**（試験した並列数の範囲内では頭打ちになりませんでした）")
    out.append("- 次の一手: `--steps` にもっと大きい並列数を足して再測定します。")
else:
    out.append("- 飽和点（まだ余裕のあった最大並列数）: **%s**" % saturation_concurrency)
    out.append("- 頭打ちが現れた段: 並列 **%s**" % saturated_at)
out.append("- SLO (p95 <= 500ms / error_rate <= 0.01) を満たした最大並列数: **%s**"
           % (slo_max_concurrency if slo_max_concurrency is not None else "なし"))
out.append("- 全体判定: **%s**" % verdict)
out.append("")
partial_steps = [r["concurrency"] for r in rows if r["partial"]]
if partial_steps:
    out.append("> 注意: 次の段は計測が途中で打ち切られています（値は参考扱いにしてください）: %s"
               % ", ".join(str(c) for c in partial_steps))
    out.append("")
missing = [r["concurrency"] for r in rows if not (num(r["rps"]) and num(r["p95"]))]
if missing:
    out.append("> 注意: 次の段はスループットまたは p95 が取得できませんでした（飽和判定から除外）: %s"
               % ", ".join(str(c) for c in missing))
    out.append("")
out.append("### 記入欄（実行者が埋めてください）")
out.append("")
out.append("- 実施日時 (UTC):")
out.append("- 実施者:")
out.append("- 気づいたこと:")
out.append("- 改善アクション:")
out.append("")

sys.stdout.write("\n".join(out) + "\n")

result = {
    "url": url,
    "duration_seconds": int(duration),
    "warmup_seconds": int(warmup),
    # 「渡した値」と「実際に適用されたか」を分けて持ちます。--no-compose のときは
    # 起動済みの環境を測るだけなので、指定しても適用されません。
    "gunicorn_workers_requested": workers,
    "gunicorn_workers_applied": workers_applied,
    "run_dir": run_dir,
    "steps": [{
        "concurrency": r["concurrency"],
        "throughput_rps": r["rps"],
        "latency_p50_ms": r["p50"],
        "latency_p95_ms": r["p95"],
        "latency_p99_ms": r["p99"],
        "error_rate": r["error_rate"],
        "verdict": r["verdict"],
        "partial": r["partial"],
    } for r in rows],
    "saturation_concurrency": saturation_concurrency,
    "saturated_at_concurrency": saturated_at,
    "saturation_gain_threshold": gain_threshold,
    "saturation_latency_factor": latency_factor,
    "slo_max_concurrency": slo_max_concurrency,
    "verdict": verdict,
}
sys.stdout.write("RESULT_JSON=" + json.dumps(result, ensure_ascii=False) + "\n")

sys.exit(0 if verdict == "PASS" else 1)
PY
