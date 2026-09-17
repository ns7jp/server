#!/usr/bin/env bash
# D-7: メモリ逼迫（memory pressure）→ OOM・再起動観測演習
#
# 目的:
#   app コンテナに一時的なメモリ上限をかけ、そのうえでコンテナの中から
#   メモリを確保して圧迫する。OOM（Out Of Memory / メモリ不足による強制終了）が
#   起きたときにコンテナが再起動するか、healthcheck（死活監視）が復帰するか、
#   runbook (docs/runbooks/memory-pressure.md) の手順で戻せるかを確かめる。
#
# 使い方:
#   scripts/drills/d7-memory-pressure.sh --dry-run
#   scripts/drills/d7-memory-pressure.sh [--service app] [--memory-limit-mb 128]
#                                        [--alloc-mb 512] [--healthz URL]
#                                        [--timeout 120] [--project-dir DIR]
#   scripts/drills/d7-memory-pressure.sh --rollback
#
# 出力:
#   人間向けサマリーを stdout、機械可読 JSON を最終行に "RESULT_JSON=" で出力。
#
# この演習で分かること:
#   - メモリ上限に達したとき、コンテナ自体が OOMKilled になるのか、
#     それとも Gunicorn の worker だけが死んでコンテナは生き残るのか。
#   - restart: unless-stopped の設定どおりに自動で再起動するか。
#   - /healthz が 200 を返すまでに何秒かかるか（RTO = 復旧までの所要時間）。
#
# この演習で分からないこと:
#   - ホスト全体のメモリ枯渇時の挙動。ここで圧迫するのは app コンテナ 1 つに
#     対してかけた上限の範囲内だけで、ホストの空きメモリは削らない。
#   - 実運用でメモリが増える本当の原因（リークか、単なる負荷増か）の切り分け。
#   - Prometheus / Alertmanager が発報し通知先まで届くかどうか。
#     ここで見るのは Docker から観測できる範囲（コンテナの状態）だけ。
#
# 特権について:
#   特権に依存しない手段を第一候補にする。
#     第1候補: docker update --memory でメモリ上限をかける（Docker API のみ）
#     第2候補: docker exec でコンテナ内の python にメモリを確保させる
#   どちらかが使えなかった場合は黙って飛ばさず、結果コード SKIP-ENV と
#   「どの手段が、なぜ使えなかったか」を必ず記録に残す。
#
# 後始末:
#   かけたメモリ上限は trap により必ず元に戻す（壊したまま終わらない）。
#
# 状態:
#   このスクリプトは「実装済み（未実施 / NOT RUN）」。
#   実行して初めて数値が出る。実行していない数値を記録に書かないこと。

set -euo pipefail

DRILL_ID="D-7"
DRILL_TITLE="メモリ逼迫（memory pressure）→ OOM・再起動観測演習"
RUNBOOK_PATH="docs/runbooks/memory-pressure.md"

SERVICE="app"
MEMORY_LIMIT_MB=128
ALLOC_MB=512
HEALTHZ_URL="http://127.0.0.1:8080/healthz"
TIMEOUT_SECONDS=120
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRY_RUN=0
ROLLBACK_ONLY=0

CID=""
ORIG_MEMORY_BYTES=0
ORIG_MEMORY_SWAP_BYTES=0
LIMIT_APPLIED=0
CLEANUP_DONE=0
METHOD_NOTES=""

usage() {
  cat <<EOF
Usage: $0 [--service SERVICE] [--memory-limit-mb N] [--alloc-mb N]
          [--healthz URL] [--timeout SECONDS] [--project-dir DIR]
          [--dry-run] [--rollback] [--help]

D-7: メモリ逼迫演習。app コンテナに一時的なメモリ上限をかけ、コンテナ内から
メモリを確保して圧迫し、OOM / 再起動 / healthcheck の復帰を秒単位で観測する。
上限は終了時に必ず元へ戻す（trap による後始末）。

  --service          compose サービス名 (default: app)
  --memory-limit-mb  一時的にかけるメモリ上限 MiB (default: 128)
  --alloc-mb         コンテナ内で確保を試みる量 MiB (default: 512)
  --healthz          復旧判定用の URL (default: http://127.0.0.1:8080/healthz)
  --timeout          復旧待ち上限秒 (default: 120)
  --project-dir      compose.yaml がある directory (default: リポジトリのルート)
  --dry-run          実際には上限をかけず、何をするかだけ表示する
  --rollback         後始末（メモリ上限の解除）だけを実行する
  --help             このヘルプ

結果コード:
  PASS      … 圧迫後に /healthz が 200 で復帰した
  FAIL      … 制限時間内に復帰しなかった
  SKIP-ENV  … この環境では手段が使えず演習が成立しなかった
              （docker が無い / デーモンに繋がらない / コンテナ未起動 /
                cgroup の権限が無く上限をかけられない など）

関連 runbook: $RUNBOOK_PATH
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

now_epoch() {
  date -u +%s
}

iso_of() {
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

# 使えなかった手段を、黙って飛ばさずに記録して終える共通の出口。
skip_env() {
  local method="$1"
  local reason="$2"
  log "SKIP-ENV: $reason"

  cat <<SUMMARY

================ $DRILL_ID drill summary ================
service            : $SERVICE
verdict            : SKIP-ENV
unavailable_method : $method
reason             : $reason
runbook            : $RUNBOOK_PATH
=========================================================

補足:
- SKIP-ENV は失敗ではありませんが、成功でもありません。
  「この環境では実施できなかった」という事実としてそのまま記録してください。

SUMMARY

  printf 'RESULT_JSON={"drill":"%s","mode":"run","verdict":"SKIP-ENV","service":"%s","unavailable_method":"%s","reason":"%s","runbook":"%s","at":"%s"}\n' \
    "$DRILL_ID" "$SERVICE" "$method" "$reason" "$RUNBOOK_PATH" "$(iso_of "$(now_epoch)")"
  exit 0
}

have_docker() {
  command -v docker >/dev/null 2>&1
}

docker_ready() {
  docker info >/dev/null 2>&1
}

resolve_container() {
  local id=""
  if docker compose version >/dev/null 2>&1; then
    id="$(docker compose --project-directory "$PROJECT_DIR" ps -q "$SERVICE" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$id" ]] && command -v docker-compose >/dev/null 2>&1; then
    id="$(docker-compose --project-directory "$PROJECT_DIR" ps -q "$SERVICE" 2>/dev/null | head -n 1 || true)"
  fi
  printf '%s\n' "$id"
}

inspect_field() {
  docker inspect -f "$1" "$CID" 2>/dev/null || true
}

health_status() {
  local s
  s="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CID" 2>/dev/null || true)"
  printf '%s\n' "${s:-unknown}"
}

healthz_ok() {
  curl -sS -o /dev/null --max-time 5 -w '%{http_code}' "$HEALTHZ_URL" 2>/dev/null | grep -q '^200$'
}

# ---------------------------------------------------------------------------
# 後始末。trap から必ず呼ばれる。かけたメモリ上限は何があっても元に戻す。
# ---------------------------------------------------------------------------
cleanup() {
  local rc=$?
  if [[ "$CLEANUP_DONE" -eq 1 ]]; then
    return "$rc"
  fi
  CLEANUP_DONE=1

  if [[ "$LIMIT_APPLIED" -eq 1 && -n "$CID" ]]; then
    if docker update --memory "$ORIG_MEMORY_BYTES" --memory-swap "$ORIG_MEMORY_SWAP_BYTES" "$CID" >/dev/null 2>&1; then
      log "後始末: メモリ上限を元に戻した (memory=${ORIG_MEMORY_BYTES} bytes / memory-swap=${ORIG_MEMORY_SWAP_BYTES} bytes)"
    else
      log "後始末に失敗: 手動で戻すこと → docker update --memory ${ORIG_MEMORY_BYTES} --memory-swap ${ORIG_MEMORY_SWAP_BYTES} ${CID}"
    fi
    LIMIT_APPLIED=0
  fi
  return "$rc"
}

# --- 引数処理 ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)            [[ $# -ge 2 ]] || die "--service に値がない";           SERVICE="$2"; shift 2 ;;
    --service=*)          SERVICE="${1#*=}"; shift ;;
    --memory-limit-mb)    [[ $# -ge 2 ]] || die "--memory-limit-mb に値がない";   MEMORY_LIMIT_MB="$2"; shift 2 ;;
    --memory-limit-mb=*)  MEMORY_LIMIT_MB="${1#*=}"; shift ;;
    --alloc-mb)           [[ $# -ge 2 ]] || die "--alloc-mb に値がない";          ALLOC_MB="$2"; shift 2 ;;
    --alloc-mb=*)         ALLOC_MB="${1#*=}"; shift ;;
    --healthz)            [[ $# -ge 2 ]] || die "--healthz に値がない";           HEALTHZ_URL="$2"; shift 2 ;;
    --healthz=*)          HEALTHZ_URL="${1#*=}"; shift ;;
    --timeout)            [[ $# -ge 2 ]] || die "--timeout に値がない";           TIMEOUT_SECONDS="$2"; shift 2 ;;
    --timeout=*)          TIMEOUT_SECONDS="${1#*=}"; shift ;;
    --project-dir)        [[ $# -ge 2 ]] || die "--project-dir に値がない";       PROJECT_DIR="$2"; shift 2 ;;
    --project-dir=*)      PROJECT_DIR="${1#*=}"; shift ;;
    --dry-run)            DRY_RUN=1; shift ;;
    --rollback)           ROLLBACK_ONLY=1; shift ;;
    --help|-h)            usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for v in MEMORY_LIMIT_MB ALLOC_MB TIMEOUT_SECONDS; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || die "$v は 0 以上の整数で指定すること（現在: ${!v}）"
done
(( MEMORY_LIMIT_MB >= 6 )) || die "--memory-limit-mb は 6 以上で指定すること（Docker 側の下限がある）"
[[ -d "$PROJECT_DIR" ]] || die "--project-dir が存在しない: $PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# EXIT では後始末だけを行う。INT / TERM では後始末をしたうえで必ず終了する。
# cleanup は値を返すだけなので、INT / TERM にそのまま仕掛けると Ctrl+C を押しても
# 本体が走り続け、「中断したのに完走したかのようなサマリー」が出てしまう。
# 演習記録で最もやってはいけないことなので、ここでは明示的に exit する。
# （メモリ上限の解除は cleanup 側で行うため、どちらの経路でも必ず元に戻る。）
trap cleanup EXIT
trap 'cleanup || true; exit 130' INT
trap 'cleanup || true; exit 143' TERM

# --- --dry-run: 説明だけ -----------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  DOCKER_CLI_STATE="なし（実施すると SKIP-ENV になる）"
  DOCKER_DAEMON_STATE="未確認"
  if have_docker; then
    DOCKER_CLI_STATE="あり"
    if docker_ready; then
      DOCKER_DAEMON_STATE="応答あり"
    else
      DOCKER_DAEMON_STATE="応答なし（実施すると SKIP-ENV になる）"
    fi
  fi
  CURL_STATE="なし（実施すると SKIP-ENV になる）"
  command -v curl >/dev/null 2>&1 && CURL_STATE="あり"

  cat <<SUMMARY

================ $DRILL_ID dry-run ================
実際にはメモリ上限を 1 つも変更しない。

実行したときの動作:
  1. compose サービス "$SERVICE" のコンテナ ID を調べる
  2. 現在のメモリ上限を docker inspect で控える（後で必ず戻すため）
  3. 第1候補（特権不要）:
     docker update --memory ${MEMORY_LIMIT_MB}m --memory-swap ${MEMORY_LIMIT_MB}m <container>
  4. 第2候補（特権不要）:
     docker exec <container> python で ${ALLOC_MB} MiB の確保を試み、圧迫する
  5. OOMKilled / コンテナの状態 / 再起動回数 / healthcheck を docker inspect で観測する
  6. $RUNBOOK_PATH の「復旧操作」に従い上限を戻し、
     $HEALTHZ_URL が 200 を返すまでの時間 (RTO) を計測する（上限 ${TIMEOUT_SECONDS} 秒）
  7. trap により、メモリ上限は何があっても元に戻す

使えない手段があった場合:
  黙って飛ばさず、verdict=SKIP-ENV と「どの手段が、なぜ使えなかったか」を残す。

現在の環境:
  docker コマンド : $DOCKER_CLI_STATE
  docker デーモン : $DOCKER_DAEMON_STATE
  curl            : $CURL_STATE
  runbook         : $RUNBOOK_PATH
===================================================
SUMMARY

  printf 'RESULT_JSON={"drill":"%s","mode":"dry-run","verdict":"DRY-RUN","service":"%s","memory_limit_mb":%s,"alloc_mb":%s,"healthz":"%s","timeout_seconds":%s,"runbook":"%s","at":"%s"}\n' \
    "$DRILL_ID" "$SERVICE" "$MEMORY_LIMIT_MB" "$ALLOC_MB" "$HEALTHZ_URL" "$TIMEOUT_SECONDS" \
    "$RUNBOOK_PATH" "$(iso_of "$(now_epoch)")"
  exit 0
fi

# --- --rollback: 後始末だけ --------------------------------------------------
if [[ "$ROLLBACK_ONLY" -eq 1 ]]; then
  log "後始末のみを実行する (--rollback)"
  RESTORED=false
  ROLLBACK_VERDICT="SKIP-ENV"

  if have_docker && docker_ready; then
    CID="$(resolve_container)"
    if [[ -n "$CID" ]]; then
      # memory=0 は「制限なし」。compose 側に上限指定が無い既定構成へ戻す。
      if docker update --memory 0 --memory-swap 0 "$CID" >/dev/null 2>&1; then
        RESTORED=true
        ROLLBACK_VERDICT="OK"
        log "メモリ上限を解除した (memory=0 = 制限なし): $CID"
      else
        log "メモリ上限を解除できなかった: $CID"
      fi
    else
      log "対象コンテナが見つからない (service=$SERVICE)"
    fi
  else
    log "docker が使えないため、戻すべき状態はない"
  fi
  CLEANUP_DONE=1

  cat <<SUMMARY

================ $DRILL_ID rollback summary ================
service           : $SERVICE
container         : ${CID:-n/a}
restored          : $RESTORED
verdict           : $ROLLBACK_VERDICT
runbook           : $RUNBOOK_PATH
============================================================
SUMMARY

  printf 'RESULT_JSON={"drill":"%s","mode":"rollback","verdict":"%s","service":"%s","container":"%s","restored":%s,"runbook":"%s","at":"%s"}\n' \
    "$DRILL_ID" "$ROLLBACK_VERDICT" "$SERVICE" "${CID:-}" "$RESTORED" "$RUNBOOK_PATH" "$(iso_of "$(now_epoch)")"
  exit 0
fi

# --- 前提確認 ---------------------------------------------------------------
log "$DRILL_ID 開始: $DRILL_TITLE"
log "runbook: $RUNBOOK_PATH"

have_docker  || skip_env "docker CLI" "docker コマンドがこの環境にない。"
docker_ready || skip_env "docker daemon" "docker デーモンに接続できない (docker info が失敗)。"
command -v curl >/dev/null 2>&1 || skip_env "curl" "curl が無く、${HEALTHZ_URL} の復帰を確認できない。"

CID="$(resolve_container)"
[[ -n "$CID" ]] || skip_env "docker compose ps" "service '$SERVICE' のコンテナが起動していない。先に docker compose up -d を実行すること。"
log "対象コンテナ: $CID"

if ! healthz_ok; then
  skip_env "事前確認 healthz" "${HEALTHZ_URL} が事前確認で 200 を返さない。演習前から壊れている状態では計測できない。"
fi
log "事前確認 OK: ${HEALTHZ_URL} が 200"

# --- 元の状態を控える（必ず戻すため） ----------------------------------------
ORIG_MEMORY_BYTES="$(inspect_field '{{.HostConfig.Memory}}')"
ORIG_MEMORY_SWAP_BYTES="$(inspect_field '{{.HostConfig.MemorySwap}}')"
[[ "$ORIG_MEMORY_BYTES" =~ ^-?[0-9]+$ ]] || ORIG_MEMORY_BYTES=0
[[ "$ORIG_MEMORY_SWAP_BYTES" =~ ^-?[0-9]+$ ]] || ORIG_MEMORY_SWAP_BYTES=0
BEFORE_RESTART="$(inspect_field '{{.RestartCount}}')"
[[ "$BEFORE_RESTART" =~ ^[0-9]+$ ]] || BEFORE_RESTART=0
HEALTH_BEFORE="$(health_status)"
log "元のメモリ上限: ${ORIG_MEMORY_BYTES} bytes（0 は「制限なし」の意味）"
log "事前 restart_count(${SERVICE})=${BEFORE_RESTART} / healthcheck=${HEALTH_BEFORE}"

# --- 1. 第1候補（特権不要）: docker update でメモリ上限をかける ---------------
LIMIT_METHOD="docker update --memory"
if docker update --memory "${MEMORY_LIMIT_MB}m" --memory-swap "${MEMORY_LIMIT_MB}m" "$CID" >/dev/null 2>&1; then
  LIMIT_APPLIED=1
  log "メモリ上限をかけた: ${MEMORY_LIMIT_MB} MiB (手段: $LIMIT_METHOD)"
else
  skip_env "$LIMIT_METHOD" "docker update --memory が失敗した。cgroup v1/v2 の設定や権限が原因のことがある。"
fi

# --- 2. 第2候補（特権不要）: コンテナ内の python でメモリを確保して圧迫 -------
PRESSURE_METHOD="docker exec + python"
INJECT_EPOCH="$(now_epoch)"
log "圧迫開始: コンテナ内の python で ${ALLOC_MB} MiB の確保を試みる (手段: $PRESSURE_METHOD)"

PRESSURE_RC=0
docker exec "$CID" python -c "
import sys
target = ${ALLOC_MB}
chunks = []
for i in range(target):
    chunks.append(bytearray(1024 * 1024))
    if (i + 1) % 32 == 0:
        sys.stderr.write('allocated %d MiB\n' % (i + 1))
        sys.stderr.flush()
sys.stderr.write('allocated %d MiB (done)\n' % target)
" >/dev/null 2>&1 || PRESSURE_RC=$?

if (( PRESSURE_RC == 0 )); then
  log "確保が最後まで通った（OOM は起きなかった）。上限 ${MEMORY_LIMIT_MB} MiB に対し ${ALLOC_MB} MiB では足りなかった可能性がある。"
  METHOD_NOTES="alloc completed without OOM"
else
  log "確保の途中でプロセスが終了した (exit=${PRESSURE_RC})。OOM の可能性がある。"
  METHOD_NOTES="alloc terminated (exit=${PRESSURE_RC})"
fi

# --- 3. 観測 -----------------------------------------------------------------
DETECT_EPOCH="$(now_epoch)"
OOM_KILLED="$(inspect_field '{{.State.OOMKilled}}')"
[[ -n "$OOM_KILLED" ]] || OOM_KILLED="unknown"
CONTAINER_STATE="$(inspect_field '{{.State.Status}}')"
[[ -n "$CONTAINER_STATE" ]] || CONTAINER_STATE="unknown"
AFTER_RESTART="$(inspect_field '{{.RestartCount}}')"
[[ "$AFTER_RESTART" =~ ^[0-9]+$ ]] || AFTER_RESTART="$BEFORE_RESTART"
log "観測: state=${CONTAINER_STATE} OOMKilled=${OOM_KILLED} restart_count=${BEFORE_RESTART}->${AFTER_RESTART}"

# --- 4. 復旧: runbook「復旧操作」= 上限を戻し、復帰を確認する -----------------
RECOVERY_START_EPOCH="$(now_epoch)"
log "復旧開始: ${RUNBOOK_PATH} の『復旧操作』に従い、メモリ上限を元に戻して復帰を待つ"
cleanup || true
CLEANUP_DONE=0   # 終了時の trap でもう一度確認できるようにしておく（上限は解除済み）

RECOVERED=0
RECOVERY_END_EPOCH=0
ATTEMPT=0
DEADLINE=$(( RECOVERY_START_EPOCH + TIMEOUT_SECONDS ))
while :; do
  ATTEMPT=$(( ATTEMPT + 1 ))
  if healthz_ok; then
    RECOVERED=1
    RECOVERY_END_EPOCH="$(now_epoch)"
    break
  fi
  if (( $(now_epoch) >= DEADLINE )); then
    RECOVERY_END_EPOCH="$(now_epoch)"
    log "タイムアウト: ${TIMEOUT_SECONDS} 秒以内に復旧しなかった"
    break
  fi
  if (( ATTEMPT % 5 == 0 )); then
    log "復旧待ち... $(( $(now_epoch) - RECOVERY_START_EPOCH ))s 経過 (attempts=${ATTEMPT})"
  fi
  sleep 1
done
RTO_SECONDS=$(( RECOVERY_END_EPOCH - RECOVERY_START_EPOCH ))
HEALTH_AFTER="$(health_status)"

# --- 5. 評価 -----------------------------------------------------------------
if (( RECOVERED == 1 )); then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi
log "復旧完了: verdict=${VERDICT} / RTO ${RTO_SECONDS} 秒 / healthcheck=${HEALTH_AFTER}"

# --- 6. サマリー -------------------------------------------------------------
cat <<SUMMARY

================ $DRILL_ID drill summary ================
service            : $SERVICE
container          : $CID
healthz            : $HEALTHZ_URL
memory_limit_mb    : $MEMORY_LIMIT_MB (元: ${ORIG_MEMORY_BYTES} bytes, 0 は制限なし)
alloc_mb           : $ALLOC_MB
limit_method       : $LIMIT_METHOD
pressure_method    : $PRESSURE_METHOD (exit=${PRESSURE_RC})
oom_killed         : $OOM_KILLED
container_state    : $CONTAINER_STATE
restart_count      : $BEFORE_RESTART -> $AFTER_RESTART
healthcheck        : $HEALTH_BEFORE -> $HEALTH_AFTER
inject_at          : $(iso_of "$INJECT_EPOCH")
detect_at          : $(iso_of "$DETECT_EPOCH")
recovery_start_at  : $(iso_of "$RECOVERY_START_EPOCH")
recovery_end_at    : $(iso_of "$RECOVERY_END_EPOCH")
rto_seconds        : $RTO_SECONDS
notes              : ${METHOD_NOTES:-none}
verdict            : $VERDICT
runbook            : $RUNBOOK_PATH
=========================================================

補足:
- inject_at から detect_at までの $(( DETECT_EPOCH - INJECT_EPOCH )) 秒は、
  確保が終わる（または OOM で落ちる）までにかかった時間です。
- oom_killed が false のまま verdict が PASS の場合、OOM そのものは再現できて
  いません。--memory-limit-mb を下げるか --alloc-mb を上げて再実施してください。

次の手順:
1. このサマリーを Slack 演習チャンネルに貼る (docs/incident-comms.md)
2. docs/drill-template.md をコピーして docs/drills/logs/$(date -u +%Y-%m-%d)-D-4.md を作る
3. 発見事項と改善アクションを記入して PR

SUMMARY

printf 'RESULT_JSON={"drill":"%s","mode":"run","verdict":"%s","service":"%s","container":"%s","memory_limit_mb":%s,"alloc_mb":%s,"original_memory_bytes":%s,"limit_method":"%s","pressure_method":"%s","pressure_exit_code":%s,"oom_killed":"%s","container_state":"%s","restart_count_before":"%s","restart_count_after":"%s","health_before":"%s","health_after":"%s","inject_at":"%s","detect_at":"%s","recovery_start_at":"%s","recovery_end_at":"%s","rto_seconds":%s,"notes":"%s","runbook":"%s"}\n' \
  "$DRILL_ID" "$VERDICT" "$SERVICE" "$CID" "$MEMORY_LIMIT_MB" "$ALLOC_MB" "$ORIG_MEMORY_BYTES" \
  "$LIMIT_METHOD" "$PRESSURE_METHOD" "$PRESSURE_RC" "$OOM_KILLED" "$CONTAINER_STATE" \
  "$BEFORE_RESTART" "$AFTER_RESTART" "$HEALTH_BEFORE" "$HEALTH_AFTER" \
  "$(iso_of "$INJECT_EPOCH")" "$(iso_of "$DETECT_EPOCH")" "$(iso_of "$RECOVERY_START_EPOCH")" \
  "$(iso_of "$RECOVERY_END_EPOCH")" "$RTO_SECONDS" "${METHOD_NOTES:-none}" "$RUNBOOK_PATH"

[[ "$VERDICT" == "PASS" ]]
