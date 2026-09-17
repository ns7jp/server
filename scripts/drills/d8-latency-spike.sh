#!/usr/bin/env bash
# D-8: レイテンシ悪化 (latency spike) → SLO 超過の検知 → 復旧演習
#
# 目的:
#   /healthz の応答をわざと遅くして docs/runbooks/latency-spike.md を実際に辿り、
#   「SLO のレイテンシ目標 (p95 < 500ms) を超えたことにその場で気づけるか」
#   「元の状態にきちんと戻せるか」「戻るまで何秒かかるか (RTO)」を確かめる。
#   ※ p95 = 100 回測って遅いほうから 5 番目、つまり「たいていはこれより速い」という値。
#
# 使い方:
#   scripts/drills/d8-latency-spike.sh [--dry-run] [--rollback]
#                                      [--method auto|limit_req|concurrency]
#                                      [--healthz URL] [--project-dir DIR]
#                                      [--nginx-conf PATH] [--delay-ms 1200]
#                                      [--samples 20] [--timeout 180]
#
# 出力:
#   人間向けサマリーを stdout に、最終行に機械可読 JSON を "RESULT_JSON=" で出す
#   (d1-process-down.sh と同じ作法)。
#
# この演習で分かること:
#   - 注入した遅延で /healthz の実測 p95 を SLO 目標 (500ms) 超えまで押し上げられるか
#   - runbook「初動」のコマンドだけで「遅い」ことをその場で確認できるか
#   - 設定を元に戻してから p95 が目標内に復帰するまでの所要時間 (RTO)
#   - どの遅延注入手段がこの環境で使えて、どれが使えないか (実行時に記録する)
#
# この演習で分からないこと:
#   - blackbox-exporter の probe_duration_seconds と recording rule
#     sli:probe_duration_seconds:p95_28d が 28 日窓で正しく出るか (窓が長すぎて 1 回の演習では見えない)
#   - Alertmanager から通知が本当に届くか (通知経路の確認は D-9 の担当)
#   - 本番で起きる遅延の再現性。ここで作る遅延はあくまで人工的なもので、真因の再現ではない
#   - tc netem による NIC (ネットワーク機器) レベルの遅延。NET_ADMIN 権限が無い環境では実施できない
#
# 前提:
#   docker / docker compose を sudo 無しで叩ける権限で実行する (sudo が要る環境では
#   `sudo -E scripts/drills/d8-latency-spike.sh ...` のように呼ぶ)。

set -euo pipefail
export LC_ALL=C

RUNBOOK="docs/runbooks/latency-spike.md"
DRILL_ID="D-8"
SLO_P95_TARGET_MS=500          # docs/slo.md: /healthz の p95 < 500ms (値は変更しない)
RTO_TARGET_SECONDS=300         # 設計書: 復旧開始から 5 分以内に戻す

HEALTHZ_URL="http://127.0.0.1:8080/healthz"
PROJECT_DIR="."
# 既定は PROJECT_DIR からの相対パスとして解決します（引数の解析後に確定させます）。
# ここで固定してしまうと、--project-dir を付けたときに別の場所のファイルを
# 書き換え・復元しようとしてしまうためです。
NGINX_CONF=""
NGINX_SERVICE="nginx"
APP_SERVICE="app"
METHOD="auto"
DELAY_MS=1200
SAMPLES=20
SAMPLE_INTERVAL="0.2"
CURL_MAX_TIME=10
TIMEOUT_SECONDS=180
LOAD_CLIENTS=24
DRY_RUN=0
ROLLBACK_ONLY=0

# cleanup / サマリーから参照する変数は set -u 対策で先に初期化しておく
WORKDIR=""
BACKUP_FILE=""
CONF_MODIFIED=0
LOAD_FLAG=""
LOAD_PIDS=()
METHOD_USED="none"
METHOD_REJECTED=""
RESTORED=0
LAST_P95_MS="-1"
LAST_MAX_MS="-1"
LAST_NON200="0"
BASELINE_P95_MS="-1"
INJECTED_P95_MS="-1"
RECOVERED_P95_MS="-1"
INJECT_TS=0
DETECT_TS=0
RECOVERY_START_TS=0
RECOVERY_DONE_TS=0

usage() {
  cat <<EOF
Usage: $0 [options]

  --dry-run          何も変更せず、実行予定の手順と使える注入手段だけを表示する
  --rollback         注入済みの nginx 設定をバックアップから戻して終了する
  --method METHOD    遅延注入の手段 auto|limit_req|concurrency (default: auto)
  --healthz URL      計測対象 URL (default: http://127.0.0.1:8080/healthz)
  --project-dir DIR  compose.yaml がある directory (default: current directory)
  --nginx-conf PATH  差し替える nginx 設定ファイル (default: ./deploy/nginx/local.conf)
  --delay-ms MS      注入したい 1 リクエストあたりの遅延 (default: 1200)
  --samples N        p95 算出に使うサンプル数 (default: 20)
  --timeout SECONDS  検知待ち / 復旧待ちの上限秒 (default: 180)
  --help             このヘルプ

参照 runbook: ${RUNBOOK}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=1; shift ;;
    --rollback)    ROLLBACK_ONLY=1; shift ;;
    --method)      METHOD="$2"; shift 2 ;;
    --healthz)     HEALTHZ_URL="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --nginx-conf)  NGINX_CONF="$2"; shift 2 ;;
    --delay-ms)    DELAY_MS="$2"; shift 2 ;;
    --samples)     SAMPLES="$2"; shift 2 ;;
    --timeout)     TIMEOUT_SECONDS="$2"; shift 2 ;;
    --help|-h)     usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

iso_time() {
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  have_cmd "$1" || { echo "missing command: $1" >&2; exit 1; }
}

# nginx 設定ファイルの場所を確定します。
# --nginx-conf を明示していなければ PROJECT_DIR からの相対で解決します。
# 呼び出し元のカレントディレクトリ基準にすると、--project-dir を付けたときに
# 別の場所のファイルを書き換え・復元しようとしてしまうためです。
if [[ -z "$NGINX_CONF" ]]; then
  NGINX_CONF="${PROJECT_DIR%/}/deploy/nginx/local.conf"
fi

# 数値引数の妥当性確認（ここで弾かないと壊れた設定を書き込んでしまう）
positive_int() { [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]; }
positive_int "$DELAY_MS"        || { echo "invalid --delay-ms" >&2; exit 2; }
positive_int "$SAMPLES"         || { echo "invalid --samples" >&2; exit 2; }
positive_int "$TIMEOUT_SECONDS" || { echo "invalid --timeout" >&2; exit 2; }
case "$METHOD" in
  auto|limit_req|concurrency) ;;
  *) echo "invalid --method: $METHOD" >&2; exit 2 ;;
esac

float_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

# ---------------------------------------------------------------------------
# 後片付け: どの経路で終了しても、必ず元の状態へ戻す
# ---------------------------------------------------------------------------
stop_load() {
  if [[ -n "$LOAD_FLAG" ]]; then
    rm -f "$LOAD_FLAG" || true
  fi
  if [[ "${#LOAD_PIDS[@]}" -gt 0 ]]; then
    local pid
    for pid in "${LOAD_PIDS[@]}"; do
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    done
    LOAD_PIDS=()
  fi
}

nginx_reload() {
  # 設定の構文確認 → reload。reload が使えない環境では HUP シグナルで代替する。
  if "${COMPOSE[@]}" exec -T "$NGINX_SERVICE" nginx -t >/dev/null 2>&1 \
     && "${COMPOSE[@]}" exec -T "$NGINX_SERVICE" nginx -s reload >/dev/null 2>&1; then
    return 0
  fi
  "${COMPOSE[@]}" kill -s HUP "$NGINX_SERVICE" >/dev/null 2>&1
}

restore_conf() {
  if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
    # mv ではなく cat で上書きする。compose はこのファイルを単体で bind mount して
    # いるため、mv で inode が変わるとコンテナ側は古いファイルを見続けてしまう。
    cat "$BACKUP_FILE" > "$NGINX_CONF" || return 1
    rm -f "$BACKUP_FILE" || true
    CONF_MODIFIED=0
    nginx_reload || true
    return 0
  fi
  return 1
}

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  stop_load
  if [[ "$CONF_MODIFIED" -eq 1 ]]; then
    log "cleanup: nginx 設定をバックアップから戻します"
    if restore_conf; then
      RESTORED=1
      log "cleanup: 復元しました (${NGINX_CONF})"
    else
      echo "cleanup: 復元に失敗しました。手動で ${BACKUP_FILE} を ${NGINX_CONF} に戻してください" >&2
    fi
  fi
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR" || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# 計測
# ---------------------------------------------------------------------------
run_samples() {
  # $1: ラベル, $2: サンプル数。結果は LAST_* に入れる。
  #
  # 計測できた応答時間と、そもそも応答が返らなかった回（curl の失敗・タイムアウト）は
  # 分けて数えます。返らなかった回に「タイムアウト上限の秒数」を入れて混ぜると、
  # 測れていない値が p95 に化けます。それはこのポートフォリオの方針
  #（測っていないものを測ったように扱わない）に反するため、別ファイルに数だけ記録します。
  local label="$1" count="$2" file i raw secs code n idx
  file="${WORKDIR}/samples-${label}.txt"
  : > "$file"
  LAST_FAILED=0
  for ((i = 1; i <= count; i++)); do
    raw=$(curl -sS -o /dev/null --max-time "$CURL_MAX_TIME" \
          -w '%{time_total} %{http_code}' "$HEALTHZ_URL" 2>/dev/null) || raw=""
    if [[ -z "$raw" ]]; then
      # 応答が返らなかった。遅さの分布には入れず、失敗回数として数えるだけにします。
      LAST_FAILED=$((LAST_FAILED + 1))
      sleep "$SAMPLE_INTERVAL"
      continue
    fi
    secs="${raw%% *}"
    code="${raw##* }"
    awk -v s="$secs" -v c="$code" 'BEGIN { printf "%.1f %s\n", s * 1000, c }' >> "$file"
    sleep "$SAMPLE_INTERVAL"
  done
  n=$(wc -l < "$file" | tr -d ' ')
  if [[ "$n" -eq 0 ]]; then
    # 1 件も応答が返らなかった。遅いのではなく、落ちている可能性があります。
    LAST_P95_MS="-1"; LAST_MAX_MS="-1"; LAST_NON200="0"
    log "計測(${label}): 応答が 1 件も返りませんでした（失敗 ${LAST_FAILED} 回）。"
    log "  これは「遅い」ではなく「応答なし」です。D-1（プロセス停止）の領域かもしれません。"
    return 1
  fi
  idx=$(( (95 * n + 99) / 100 ))
  if [[ "$idx" -lt 1 ]]; then idx=1; fi
  LAST_P95_MS=$(awk '{ print $1 }' "$file" | sort -n | awk -v i="$idx" 'NR == i { print; exit }')
  LAST_MAX_MS=$(awk '{ print $1 }' "$file" | sort -n | tail -n 1)
  LAST_NON200=$(awk '$2 != "200"' "$file" | wc -l | tr -d ' ')
  log "計測(${label}): n=${n} p95=${LAST_P95_MS}ms max=${LAST_MAX_MS}ms non200=${LAST_NON200} 応答なし=${LAST_FAILED}"
  if [[ "$LAST_FAILED" -gt 0 ]]; then
    log "  注意: 応答なし ${LAST_FAILED} 回は p95 / max の計算に含めていません（測れていないため）。"
  fi
}

wait_for_condition() {
  # $1: "slow" or "fast"。SLO 目標を基準に、遅くなる / 速く戻るのを待つ。
  # 成功したら 0、タイムアウトしたら 1 を返す。
  local mode="$1" start now elapsed raw ms attempt=0
  start=$(date -u +%s)
  while :; do
    attempt=$((attempt + 1))
    raw=$(curl -sS -o /dev/null --max-time "$CURL_MAX_TIME" -w '%{time_total}' "$HEALTHZ_URL" 2>/dev/null) || raw=""
    if [[ -n "$raw" ]]; then
      ms=$(awk -v s="$raw" 'BEGIN { printf "%.1f", s * 1000 }')
      if [[ "$mode" == "slow" ]] && float_gt "$ms" "$SLO_P95_TARGET_MS"; then
        log "SLO 目標 ${SLO_P95_TARGET_MS}ms を超える応答を観測: ${ms}ms"
        return 0
      fi
      if [[ "$mode" == "fast" ]] && ! float_gt "$ms" "$SLO_P95_TARGET_MS"; then
        log "SLO 目標 ${SLO_P95_TARGET_MS}ms 以内の応答に復帰: ${ms}ms"
        return 0
      fi
    fi
    now=$(date -u +%s)
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
      log "タイムアウト: ${TIMEOUT_SECONDS} 秒以内に条件 (${mode}) を満たさなかった"
      return 1
    fi
    if (( attempt % 10 == 0 )); then
      log "待機中 (${mode})... ${elapsed}s 経過"
    fi
    sleep 1
  done
}

# ---------------------------------------------------------------------------
# 遅延注入の手段を選ぶ
#
#   1. tc netem  … NIC に遅延を足す王道。ただし NET_ADMIN capability が必要で、
#                  本ラボのコンテナは no-new-privileges / 既定 capability のままなので使えない。
#                  「使えないこと」を実行時に確認して記録する。
#   2. limit_req … nginx の同時実行制限。burst 付き・nodelay 無しだと、超過分の
#                  リクエストを「捨てずに待たせる」= 特権なしで応答時間だけ伸ばせる。第一候補。
#   3. limit_rate… 応答本文の転送速度を絞る指示。/healthz の本文は数十バイトしかなく
#                  遅延に結びつきにくいと判断し、採用しない (未検証)。
#   4. concurrency … app へ同時接続を大量に張って待ち行列を作る。設定ファイルを触れない
#                  環境向けの代替。副作用が読みにくいので第二候補。
# ---------------------------------------------------------------------------
note_rejected() {
  METHOD_REJECTED="${METHOD_REJECTED:+${METHOD_REJECTED}; }$1"
  log "使えなかった手段: $1"
}

probe_tc_netem() {
  if ! have_cmd docker; then
    note_rejected "tc netem: docker コマンドが無く確認できない"
    return 1
  fi
  if ! "${COMPOSE[@]}" exec -T "$APP_SERVICE" sh -c 'command -v tc' >/dev/null 2>&1; then
    note_rejected "tc netem: コンテナに tc (iproute2) が入っていない"
    return 1
  fi
  if ! "${COMPOSE[@]}" exec -T "$APP_SERVICE" sh -c 'tc qdisc add dev eth0 root netem delay 1ms' >/dev/null 2>&1; then
    note_rejected "tc netem: NET_ADMIN capability が無く qdisc を追加できない"
    return 1
  fi
  "${COMPOSE[@]}" exec -T "$APP_SERVICE" sh -c 'tc qdisc del dev eth0 root' >/dev/null 2>&1 || true
  note_rejected "tc netem: 実行できてしまったが、本演習では特権非依存の手段を優先するため不採用"
  return 1
}

select_method() {
  probe_tc_netem || true
  note_rejected "nginx limit_rate: /healthz の本文が小さく転送速度制限では遅延にならないと判断 (未検証)"
  if [[ "$METHOD" == "limit_req" || "$METHOD" == "auto" ]]; then
    if [[ -f "$NGINX_CONF" && -w "$NGINX_CONF" ]] \
       && grep -qE '^[[:space:]]*location = /healthz[[:space:]]*\{' "$NGINX_CONF"; then
      METHOD_USED="limit_req"
      return 0
    fi
    note_rejected "nginx limit_req: ${NGINX_CONF} が無い / 書き込めない / location = /healthz が見つからない"
    if [[ "$METHOD" == "limit_req" ]]; then
      return 1
    fi
  fi
  METHOD_USED="concurrency"
  return 0
}

inject_limit_req() {
  # nginx の limit_req を /healthz にだけ足す。rate を 1 分あたりの回数で表し、
  # burst で「捨てずに待たせる」件数を確保する (nodelay は付けない = 待たせるのが目的)。
  local rate_rpm burst tmp
  rate_rpm=$(( 60000 / DELAY_MS ))
  if [[ "$rate_rpm" -lt 1 ]]; then rate_rpm=1; fi
  burst=$(( SAMPLES * 2 + 20 ))
  BACKUP_FILE="${NGINX_CONF}.d5-backup"
  if [[ -e "$BACKUP_FILE" ]]; then
    echo "既にバックアップが存在します: ${BACKUP_FILE} (前回の演習が中断した可能性)。--rollback で戻してください" >&2
    return 1
  fi
  cp "$NGINX_CONF" "$BACKUP_FILE"
  tmp="${WORKDIR}/local.conf.injected"
  awk -v zone="limit_req_zone \$binary_remote_addr zone=d5_healthz:1m rate=${rate_rpm}r/m;" \
      -v lim="    limit_req zone=d5_healthz burst=${burst};" '
    NR == 1 { print "# --- D-8 drill: 一時的な遅延注入。演習終了時に自動で元へ戻します ---"; print zone }
    { print }
    /^[[:space:]]*location = \/healthz[[:space:]]*\{/ { print lim }
  ' "$BACKUP_FILE" > "$tmp"
  if ! grep -q 'd5_healthz' "$tmp"; then
    echo "注入後の設定に目印 (d5_healthz) が入りませんでした。中止します" >&2
    rm -f "$BACKUP_FILE"
    BACKUP_FILE=""
    return 1
  fi
  # bind mount された単体ファイルなので inode を変えない形 (cat での上書き) で書き込む
  cat "$tmp" > "$NGINX_CONF"
  CONF_MODIFIED=1
  log "nginx 設定に limit_req を注入 (rate=${rate_rpm}r/m burst=${burst})"
  if ! nginx_reload; then
    echo "nginx の reload に失敗しました。設定を戻します" >&2
    return 1
  fi
  return 0
}

inject_concurrency() {
  local i
  LOAD_FLAG="${WORKDIR}/load.on"
  : > "$LOAD_FLAG"
  for ((i = 1; i <= LOAD_CLIENTS; i++)); do
    (
      while [[ -f "$LOAD_FLAG" ]]; do
        curl -sS -o /dev/null --max-time "$CURL_MAX_TIME" "$HEALTHZ_URL" >/dev/null 2>&1 || true
      done
    ) &
    LOAD_PIDS+=("$!")
  done
  log "同時接続 ${LOAD_CLIENTS} 本で負荷をかけています (PID 数=${#LOAD_PIDS[@]})"
  return 0
}

follow_runbook_initial_steps() {
  # docs/runbooks/latency-spike.md の「初動」をそのままなぞる
  log "runbook 初動: ${RUNBOOK}"
  date -u || true
  "${COMPOSE[@]}" ps || true
  local i
  for i in 1 2 3; do
    printf 'initial-check-%d ' "$i"
    curl -o /dev/null -s -w "code=%{http_code} time=%{time_total}\n" "$HEALTHZ_URL" || echo "curl failed"
  done
}

print_plan() {
  cat <<EOF

================ ${DRILL_ID} dry-run plan ================
runbook           : ${RUNBOOK}
healthz           : ${HEALTHZ_URL}
project-dir       : ${PROJECT_DIR}
nginx-conf        : ${NGINX_CONF}
method (指定)     : ${METHOD}
delay-ms          : ${DELAY_MS}
samples           : ${SAMPLES}
slo p95 target    : ${SLO_P95_TARGET_MS} ms  (docs/slo.md)
rto target        : ${RTO_TARGET_SECONDS} s

実行される手順:
  0. 事前計測  : /healthz を ${SAMPLES} 回叩いて baseline の p95 を出す
  1. 手段の選択: tc netem が使えるか実際に試し、使えなければ limit_req / concurrency を使う
  2. 遅延注入  : nginx の limit_req で /healthz を待たせる (バックアップ: ${NGINX_CONF}.d5-backup)
  3. 検知      : SLO 目標 ${SLO_P95_TARGET_MS}ms を超える応答が出るまで待ち、その時刻を記録
  4. runbook   : ${RUNBOOK} の「初動」コマンドをなぞる
  5. 復旧      : 設定をバックアップから戻して nginx を reload し、p95 が戻るまでを計測
  6. 後片付け  : trap により、異常終了しても必ず設定を元へ戻す

この環境で使えるコマンド:
  docker        : $(have_cmd docker && echo yes || echo no)
  curl          : $(have_cmd curl && echo yes || echo no)
  awk           : $(have_cmd awk && echo yes || echo no)
  sort          : $(have_cmd sort && echo yes || echo no)

注意: --dry-run では計測も設定変更も一切行いません。数値は出しません。
==========================================================
EOF
}

# ---------------------------------------------------------------------------
# compose コマンドの決定 (dry-run では未使用)
# ---------------------------------------------------------------------------
COMPOSE=(docker compose --project-directory "$PROJECT_DIR")
if [[ "$DRY_RUN" -eq 0 ]]; then
  require_cmd curl
  require_cmd awk
  require_cmd sort
  require_cmd docker
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose --project-directory "$PROJECT_DIR")
  elif have_cmd docker-compose; then
    COMPOSE=(docker-compose --project-directory "$PROJECT_DIR")
  else
    echo "docker compose plugin が見つからない" >&2
    exit 1
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_plan
  if [[ "$ROLLBACK_ONLY" -eq 1 ]]; then
    echo "--rollback (dry-run): ${NGINX_CONF}.d5-backup があれば ${NGINX_CONF} へ戻し、nginx を reload します。"
  fi
  printf 'RESULT_JSON={"drill":"%s","mode":"dry-run","executed":false,"runbook":"%s"}\n' "$DRILL_ID" "$RUNBOOK"
  exit 0
fi

if [[ "$ROLLBACK_ONLY" -eq 1 ]]; then
  BACKUP_FILE="${NGINX_CONF}.d5-backup"
  if restore_conf; then
    RESTORED=1
    log "rollback: ${NGINX_CONF} を復元し、nginx を reload しました"
  else
    log "rollback: 戻すべきバックアップ (${BACKUP_FILE}) はありません"
  fi
  printf 'RESULT_JSON={"drill":"%s","mode":"rollback","restored":%s,"runbook":"%s"}\n' \
    "$DRILL_ID" "$RESTORED" "$RUNBOOK"
  exit 0
fi

WORKDIR=$(mktemp -d)

log "${DRILL_ID} 開始  healthz=${HEALTHZ_URL}  runbook=${RUNBOOK}"

# 0. 事前確認
log "事前確認: ${HEALTHZ_URL} が 200 を返すこと"
PRE_CODE=$(curl -sS -o /dev/null --max-time 5 -w '%{http_code}' "$HEALTHZ_URL" 2>/dev/null) || PRE_CODE="000"
if [[ "$PRE_CODE" != "200" ]]; then
  log "事前確認 NG: HTTP ${PRE_CODE}。compose を起動してから再実行してください"
  exit 2
fi
run_samples baseline "$SAMPLES"
BASELINE_P95_MS="$LAST_P95_MS"
if float_gt "$BASELINE_P95_MS" "$SLO_P95_TARGET_MS"; then
  log "事前確認 NG: 注入前から p95 が SLO 目標を超えています。まず現状の調査が先です"
  exit 2
fi

# 1. 遅延注入の手段を決める
if ! select_method; then
  echo "利用できる遅延注入手段がありません" >&2
  exit 2
fi
log "採用した手段: ${METHOD_USED}"

# 2. 注入
INJECT_TS=$(date -u +%s)
case "$METHOD_USED" in
  limit_req)   inject_limit_req ;;
  concurrency) inject_concurrency ;;
  *) echo "unexpected method: ${METHOD_USED}" >&2; exit 2 ;;
esac

# 3. 検知: SLO 目標を超えたことに気づけるか
DETECTED=0
if wait_for_condition slow; then
  DETECTED=1
  DETECT_TS=$(date -u +%s)
fi
run_samples injected "$SAMPLES"
INJECTED_P95_MS="$LAST_P95_MS"
INJECTED_NON200="$LAST_NON200"

# 4. runbook の初動をなぞる
follow_runbook_initial_steps

# 5. 復旧
RECOVERY_START_TS=$(date -u +%s)
log "復旧開始: ${RUNBOOK} の「復旧操作」に従い、注入した設定 / 負荷を取り除きます"
stop_load
if [[ "$CONF_MODIFIED" -eq 1 ]]; then
  if restore_conf; then
    RESTORED=1
  fi
else
  RESTORED=1
fi
RECOVERED=0
if wait_for_condition fast; then
  RECOVERED=1
  RECOVERY_DONE_TS=$(date -u +%s)
fi
run_samples recovered "$SAMPLES"
RECOVERED_P95_MS="$LAST_P95_MS"

if [[ "$RECOVERY_DONE_TS" -gt 0 ]]; then
  RTO_SECONDS=$((RECOVERY_DONE_TS - RECOVERY_START_TS))
else
  RTO_SECONDS=-1
fi
if [[ "$DETECT_TS" -gt 0 ]]; then
  DETECT_SECONDS=$((DETECT_TS - INJECT_TS))
else
  DETECT_SECONDS=-1
fi

# 6. 評価
VERDICT="FAIL"
if [[ "$DETECTED" -eq 1 && "$RESTORED" -eq 1 && "$RECOVERED" -eq 1 \
      && "$RTO_SECONDS" -ge 0 && "$RTO_SECONDS" -le "$RTO_TARGET_SECONDS" ]] \
   && float_gt "$INJECTED_P95_MS" "$SLO_P95_TARGET_MS" \
   && ! float_gt "$RECOVERED_P95_MS" "$SLO_P95_TARGET_MS"; then
  VERDICT="PASS"
fi

INJECT_TS_ISO=$(iso_time "$INJECT_TS")
DETECT_TS_ISO="n/a"
if [[ "$DETECT_TS" -gt 0 ]]; then DETECT_TS_ISO=$(iso_time "$DETECT_TS"); fi
RECOVERY_START_ISO=$(iso_time "$RECOVERY_START_TS")
RECOVERY_DONE_ISO="n/a"
if [[ "$RECOVERY_DONE_TS" -gt 0 ]]; then RECOVERY_DONE_ISO=$(iso_time "$RECOVERY_DONE_TS"); fi

cat <<SUMMARY

================ ${DRILL_ID} drill summary ================
runbook             : ${RUNBOOK}
healthz             : ${HEALTHZ_URL}
method_used         : ${METHOD_USED}
method_rejected     : ${METHOD_REJECTED:-none}
inject_at           : ${INJECT_TS_ISO}
detect_at           : ${DETECT_TS_ISO}
recovery_start_at   : ${RECOVERY_START_ISO}
recovery_done_at    : ${RECOVERY_DONE_ISO}
detect_seconds      : ${DETECT_SECONDS}
rto_seconds         : ${RTO_SECONDS}
rto_target_seconds  : ${RTO_TARGET_SECONDS}
p95_baseline_ms     : ${BASELINE_P95_MS}
p95_injected_ms     : ${INJECTED_P95_MS}
p95_recovered_ms    : ${RECOVERED_P95_MS}
slo_p95_target_ms   : ${SLO_P95_TARGET_MS}
non200_while_injected: ${INJECTED_NON200}
config_restored     : ${RESTORED}
verdict             : ${VERDICT}
===========================================================

次の手順:
1. このサマリーを Slack 演習チャンネルに貼る (docs/incident-comms.md)
2. docs/drill-template.md をコピーして docs/drills/logs/$(date -u +%Y-%m-%d)-D-5.md を作る
3. 「SLO 超過に気づけたか」「runbook の記述で迷った箇所」を記入して PR

SUMMARY

printf 'RESULT_JSON={"drill":"%s","verdict":"%s","method_used":"%s","method_rejected":"%s","detect_seconds":%s,"rto_seconds":%s,"rto_target_seconds":%s,"p95_baseline_ms":%s,"p95_injected_ms":%s,"p95_recovered_ms":%s,"slo_p95_target_ms":%s,"config_restored":%s,"inject_at":"%s","detect_at":"%s","recovery_done_at":"%s","runbook":"%s"}\n' \
  "$DRILL_ID" "$VERDICT" "$METHOD_USED" "${METHOD_REJECTED:-none}" "$DETECT_SECONDS" "$RTO_SECONDS" \
  "$RTO_TARGET_SECONDS" "$BASELINE_P95_MS" "$INJECTED_P95_MS" "$RECOVERED_P95_MS" \
  "$SLO_P95_TARGET_MS" "$RESTORED" "$INJECT_TS_ISO" "$DETECT_TS_ISO" "$RECOVERY_DONE_ISO" "$RUNBOOK"

[[ "$VERDICT" == "PASS" ]]
