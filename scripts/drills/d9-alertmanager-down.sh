#!/usr/bin/env bash
# D-9: Alertmanager 停止 → 「通知が飛ばないこと自体に気づけるか」演習 (監視の監視)
#
# 目的:
#   Alertmanager をわざと止め、docs/runbooks/alertmanager-down.md を実際に辿って
#   「通知の出口が壊れていることに、通知以外の手段で気づけるか」を確かめる。
#   Alertmanager が落ちていると AlertmanagerDown 自身の通知も届かないため、
#   Prometheus 側の指標 (up / prometheus_notifications_* ) で気づけるかどうかが肝になる。
#   ※ Alertmanager = アラートをまとめて Slack などへ送る「通知の出口」。
#
# 使い方:
#   scripts/drills/d9-alertmanager-down.sh [--dry-run] [--rollback]
#                                          [--service alertmanager]
#                                          [--prometheus URL] [--alertmanager URL]
#                                          [--downtime 330] [--timeout 300]
#                                          [--project-dir DIR]
#
# 出力:
#   人間向けサマリーを stdout に、最終行に機械可読 JSON を "RESULT_JSON=" で出す
#   (d1-process-down.sh と同じ作法)。
#
# この演習で分かること:
#   - Prometheus 側から Alertmanager の停止を検知できるか
#       up{job="alertmanager"} が 0 になるか
#       prometheus_notifications_errors_total / _dropped_total が増えるか
#       ALERTS{alertname="AlertmanagerDown"} が pending → firing へ進むか
#   - AlertmanagerDown が firing でも「通知は届かない」という当たり前の事実を、
#     自分の目で確認できるか (= 通知に頼らない確認経路が必要だと腹落ちするか)
#   - runbook「復旧操作」に従って再起動し、up が 1 に戻るまでの所要時間 (RTO)
#
# この演習で分からないこと:
#   - Slack など外部通知の到達可否。Alertmanager を止めている間は経路そのものが無い
#   - 夜間・休日に人間が Grafana を見ているかどうか (運用体制の検証は別問題)
#   - Alertmanager を二重化した場合の挙動 (本ラボの構成では単一のため)
#   - blackbox-exporter 停止側のシナリオ (同じ runbook の対象だが、本演習では扱わない)
#
# 前提:
#   docker / docker compose を sudo 無しで叩ける権限で実行する (sudo が要る環境では
#   `sudo -E scripts/drills/d9-alertmanager-down.sh ...` のように呼ぶ)。

set -euo pipefail
export LC_ALL=C

RUNBOOK="docs/runbooks/alertmanager-down.md"
DRILL_ID="D-9"
ALERT_FOR_SECONDS=300          # runbook: up{job="alertmanager"} == 0 が 5 分継続で発火
RTO_TARGET_SECONDS=300         # 設計書: 復旧開始から 5 分以内に戻す

SERVICE="alertmanager"
PROMETHEUS_URL="http://127.0.0.1:9090"
ALERTMANAGER_URL="http://127.0.0.1:9093"
PROJECT_DIR="."
DOWNTIME_SECONDS=330           # for: 5m を越えるよう既定は 330 秒
TIMEOUT_SECONDS=300
POLL_INTERVAL=5
DRY_RUN=0
ROLLBACK_ONLY=0

# cleanup / サマリーから参照する変数は set -u 対策で先に初期化しておく
STOPPED=0
RESTARTED=0
STOP_TS=0
UP_ZERO_TS=0
FIRING_TS=0
RECOVERY_START_TS=0
RECOVERY_DONE_TS=0
NOTIF_ERRORS_BEFORE="n/a"
NOTIF_ERRORS_AFTER="n/a"
NOTIF_DROPPED_BEFORE="n/a"
NOTIF_DROPPED_AFTER="n/a"
ALERT_STATE_OBSERVED="none"

usage() {
  cat <<EOF
Usage: $0 [options]

  --dry-run           何も変更せず、実行予定の手順だけを表示する
  --rollback          停止したままの ${SERVICE} を起動し直して終了する
  --service NAME      停止対象の compose サービス名 (default: alertmanager)
  --prometheus URL    Prometheus のベース URL (default: http://127.0.0.1:9090)
  --alertmanager URL  Alertmanager のベース URL (default: http://127.0.0.1:9093)
  --downtime SECONDS  停止させておく秒数 (default: 330 / 発火条件の 5 分を越える長さ)
  --timeout SECONDS   検知待ち・復旧待ちの上限秒 (default: 300)
  --project-dir DIR   compose.yaml がある directory (default: current directory)
  --help              このヘルプ

参照 runbook: ${RUNBOOK}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=1; shift ;;
    --rollback)     ROLLBACK_ONLY=1; shift ;;
    --service)      SERVICE="$2"; shift 2 ;;
    --prometheus)   PROMETHEUS_URL="$2"; shift 2 ;;
    --alertmanager) ALERTMANAGER_URL="$2"; shift 2 ;;
    --downtime)     DOWNTIME_SECONDS="$2"; shift 2 ;;
    --timeout)      TIMEOUT_SECONDS="$2"; shift 2 ;;
    --project-dir)  PROJECT_DIR="$2"; shift 2 ;;
    --help|-h)      usage; exit 0 ;;
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

positive_int() { [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]]; }
positive_int "$DOWNTIME_SECONDS" || { echo "invalid --downtime" >&2; exit 2; }
positive_int "$TIMEOUT_SECONDS"  || { echo "invalid --timeout" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Prometheus への問い合わせ
#   jq があれば使い、無ければ sed で value を取り出す。
#   値が無い (= 該当する時系列が存在しない) 場合は空文字を返す。
# ---------------------------------------------------------------------------
prom_scalar() {
  local query="$1" body
  body=$(curl -fsS --max-time 10 --get --data-urlencode "query=${query}" \
         "${PROMETHEUS_URL}/api/v1/query" 2>/dev/null) || return 1
  if have_cmd jq; then
    printf '%s' "$body" | jq -r '.data.result[0].value[1] // empty'
  else
    printf '%s' "$body" | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)"\].*/\1/p' | head -n 1
  fi
}

prom_scalar_or_na() {
  local v
  v=$(prom_scalar "$1" 2>/dev/null) || v=""
  if [[ -z "$v" ]]; then
    printf 'n/a'
  else
    printf '%s' "$v"
  fi
}

alertmanager_healthy() {
  curl -fsS -o /dev/null --max-time 5 "${ALERTMANAGER_URL}/-/healthy"
}

compose_running() {
  local cid
  cid=$("${COMPOSE[@]}" ps -q "$SERVICE" 2>/dev/null) || return 1
  [[ -n "$cid" ]] || return 1
  [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" == "true" ]]
}

start_service() {
  "${COMPOSE[@]}" start "$SERVICE" >/dev/null 2>&1 || "${COMPOSE[@]}" up -d "$SERVICE" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 後片付け: どの経路で終了しても Alertmanager を必ず起動し直す
# ---------------------------------------------------------------------------
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ "$STOPPED" -eq 1 && "$RESTARTED" -eq 0 ]]; then
    log "cleanup: ${SERVICE} を起動し直します"
    if start_service; then
      RESTARTED=1
      log "cleanup: ${SERVICE} を起動しました"
    else
      echo "cleanup: ${SERVICE} の起動に失敗しました。手動で 'docker compose start ${SERVICE}' を実行してください" >&2
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

wait_until() {
  # $1: 判定コマンド名, $2: 説明。成功で 0、タイムアウトで 1。
  local fn="$1" desc="$2" start now elapsed attempt=0
  start=$(date -u +%s)
  while :; do
    attempt=$((attempt + 1))
    if "$fn"; then
      log "確認できました: ${desc}"
      return 0
    fi
    now=$(date -u +%s)
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
      log "タイムアウト: ${TIMEOUT_SECONDS} 秒以内に確認できませんでした (${desc})"
      return 1
    fi
    if (( attempt % 6 == 0 )); then
      log "待機中 (${desc})... ${elapsed}s 経過"
    fi
    sleep "$POLL_INTERVAL"
  done
}

cond_up_zero() {
  local v
  v=$(prom_scalar "up{job=\"alertmanager\"}" 2>/dev/null) || return 1
  [[ "$v" == "0" ]]
}

cond_up_one() {
  local v
  v=$(prom_scalar "up{job=\"alertmanager\"}" 2>/dev/null) || return 1
  [[ "$v" == "1" ]]
}

cond_healthy() {
  alertmanager_healthy >/dev/null 2>&1
}

alert_state() {
  # AlertmanagerDown の現在の状態 (pending / firing / none) を返す
  local v
  v=$(prom_scalar 'ALERTS{alertname="AlertmanagerDown",alertstate="firing"}' 2>/dev/null) || v=""
  if [[ -n "$v" ]]; then printf 'firing'; return 0; fi
  v=$(prom_scalar 'ALERTS{alertname="AlertmanagerDown",alertstate="pending"}' 2>/dev/null) || v=""
  if [[ -n "$v" ]]; then printf 'pending'; return 0; fi
  printf 'none'
}

print_plan() {
  cat <<EOF

================ ${DRILL_ID} dry-run plan ================
runbook            : ${RUNBOOK}
service            : ${SERVICE}
prometheus         : ${PROMETHEUS_URL}
alertmanager       : ${ALERTMANAGER_URL}
project-dir        : ${PROJECT_DIR}
downtime           : ${DOWNTIME_SECONDS} s (発火条件 for: ${ALERT_FOR_SECONDS}s を越える長さ)
timeout            : ${TIMEOUT_SECONDS} s
rto target         : ${RTO_TARGET_SECONDS} s

実行される手順:
  0. 事前確認 : ${ALERTMANAGER_URL}/-/healthy が 200、up{job="alertmanager"} == 1 であること
                prometheus_notifications_errors_total / _dropped_total の現在値を控える
  1. 停止     : docker compose stop ${SERVICE}
                ※ D-1 と違い、ここでは「止めたままにしたい」ので Engine の stop API を
                  あえて使う。restart_policy による自動復帰が抑止されるのが狙い。
  2. 検知     : 通知に頼らずに気づけるかを、次の 3 つで確認する
                (a) up{job="alertmanager"} が 0 になるか
                (b) ALERTS{alertname="AlertmanagerDown"} が pending → firing へ進むか
                (c) prometheus_notifications_errors_total / _dropped_total が増えるか
  3. 観察     : ${DOWNTIME_SECONDS} 秒そのままにして、firing でも通知は届かないことを確認
  4. 復旧     : ${RUNBOOK} の「復旧操作」に従って ${SERVICE} を起動し、
                /-/healthy と up{job="alertmanager"} == 1 に戻るまでを計測
  5. 後片付け : trap により、異常終了しても必ず ${SERVICE} を起動し直す

この環境で使えるコマンド:
  docker        : $(have_cmd docker && echo yes || echo no)
  curl          : $(have_cmd curl && echo yes || echo no)
  jq            : $(have_cmd jq && echo "yes" || echo "no (sed で代替します)")

注意: --dry-run では停止も計測も一切行いません。数値は出しません。
==========================================================
EOF
}

# ---------------------------------------------------------------------------
COMPOSE=(docker compose --project-directory "$PROJECT_DIR")
if [[ "$DRY_RUN" -eq 0 ]]; then
  require_cmd curl
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
    echo "--rollback (dry-run): ${SERVICE} が止まっていれば起動し、/-/healthy を確認します。"
  fi
  printf 'RESULT_JSON={"drill":"%s","mode":"dry-run","executed":false,"runbook":"%s"}\n' "$DRILL_ID" "$RUNBOOK"
  exit 0
fi

if [[ "$ROLLBACK_ONLY" -eq 1 ]]; then
  log "rollback: ${SERVICE} を起動します"
  if start_service; then
    RESTARTED=1
  fi
  HEALTHY_AFTER=0
  if wait_until cond_healthy "${ALERTMANAGER_URL}/-/healthy が応答する"; then
    HEALTHY_AFTER=1
  fi
  printf 'RESULT_JSON={"drill":"%s","mode":"rollback","restarted":%s,"healthy":%s,"runbook":"%s"}\n' \
    "$DRILL_ID" "$RESTARTED" "$HEALTHY_AFTER" "$RUNBOOK"
  exit 0
fi

log "${DRILL_ID} 開始  service=${SERVICE}  runbook=${RUNBOOK}"

# 0. 事前確認
log "事前確認: ${ALERTMANAGER_URL}/-/healthy"
if ! alertmanager_healthy >/dev/null 2>&1; then
  log "事前確認 NG: Alertmanager が既に不健全です。まず現状の調査が先です"
  exit 2
fi
if ! compose_running; then
  log "事前確認 NG: compose サービス ${SERVICE} が起動していません"
  exit 2
fi
UP_BEFORE=$(prom_scalar_or_na "up{job=\"alertmanager\"}")
if [[ "$UP_BEFORE" != "1" ]]; then
  log "事前確認 NG: up{job=\"alertmanager\"} が 1 ではありません (観測値: ${UP_BEFORE})"
  exit 2
fi
NOTIF_ERRORS_BEFORE=$(prom_scalar_or_na 'sum(prometheus_notifications_errors_total)')
NOTIF_DROPPED_BEFORE=$(prom_scalar_or_na 'sum(prometheus_notifications_dropped_total)')
log "事前値: notifications_errors_total=${NOTIF_ERRORS_BEFORE} notifications_dropped_total=${NOTIF_DROPPED_BEFORE}"

# 1. 停止
#    D-1 では「予期せぬ死」を再現したかったので Engine の kill API を避けたが、
#    この演習の狙いは「通知の出口が無い時間帯」を意図して作ることなので、
#    自動復帰しない compose stop をあえて使う。
STOP_TS=$(date -u +%s)
log "障害発生: docker compose stop ${SERVICE}"
"${COMPOSE[@]}" stop "$SERVICE"
STOPPED=1

# 2. 検知: 通知に頼らずに気づけるか
DETECTED_UP_ZERO=0
if wait_until cond_up_zero 'up{job="alertmanager"} == 0'; then
  DETECTED_UP_ZERO=1
  UP_ZERO_TS=$(date -u +%s)
fi

log "Prometheus /alerts 相当の確認 (ALERTS{alertname=\"AlertmanagerDown\"})"
ALERT_STATE_OBSERVED=$(alert_state)
log "現在のアラート状態: ${ALERT_STATE_OBSERVED}"

# 3. 観察: for: 5m を越えるまで待ち、firing になっても通知が届かないことを見る
OBSERVE_UNTIL=$((STOP_TS + DOWNTIME_SECONDS))
log "観察: ${DOWNTIME_SECONDS} 秒経過するまで停止したままにします (発火条件 for: ${ALERT_FOR_SECONDS}s)"
while :; do
  NOW_TS=$(date -u +%s)
  if [[ "$NOW_TS" -ge "$OBSERVE_UNTIL" ]]; then
    break
  fi
  STATE_NOW=$(alert_state)
  if [[ "$STATE_NOW" == "firing" && "$FIRING_TS" -eq 0 ]]; then
    FIRING_TS="$NOW_TS"
    ALERT_STATE_OBSERVED="firing"
    log "AlertmanagerDown が firing になりました。ただしこの通知は届きません (出口が停止中のため)"
  elif [[ "$STATE_NOW" == "pending" && "$ALERT_STATE_OBSERVED" == "none" ]]; then
    ALERT_STATE_OBSERVED="pending"
    log "AlertmanagerDown が pending になりました"
  fi
  sleep "$POLL_INTERVAL"
done

NOTIF_ERRORS_AFTER=$(prom_scalar_or_na 'sum(prometheus_notifications_errors_total)')
NOTIF_DROPPED_AFTER=$(prom_scalar_or_na 'sum(prometheus_notifications_dropped_total)')
log "停止中の値: notifications_errors_total=${NOTIF_ERRORS_AFTER} notifications_dropped_total=${NOTIF_DROPPED_AFTER}"

NOTIF_SIGNAL=0
if [[ "$NOTIF_ERRORS_BEFORE" != "n/a" && "$NOTIF_ERRORS_AFTER" != "n/a" ]] \
   && awk -v a="$NOTIF_ERRORS_AFTER" -v b="$NOTIF_ERRORS_BEFORE" 'BEGIN { exit !(a > b) }'; then
  NOTIF_SIGNAL=1
fi
if [[ "$NOTIF_DROPPED_BEFORE" != "n/a" && "$NOTIF_DROPPED_AFTER" != "n/a" ]] \
   && awk -v a="$NOTIF_DROPPED_AFTER" -v b="$NOTIF_DROPPED_BEFORE" 'BEGIN { exit !(a > b) }'; then
  NOTIF_SIGNAL=1
fi

# 4. 復旧: runbook の「復旧操作」に従う
RECOVERY_START_TS=$(date -u +%s)
log "復旧開始: ${RUNBOOK} の「復旧操作」に従い ${SERVICE} を起動します"
if start_service; then
  RESTARTED=1
fi
RECOVERED=0
if wait_until cond_healthy "${ALERTMANAGER_URL}/-/healthy が応答する" \
   && wait_until cond_up_one 'up{job="alertmanager"} == 1'; then
  RECOVERED=1
  RECOVERY_DONE_TS=$(date -u +%s)
fi

if [[ "$RECOVERY_DONE_TS" -gt 0 ]]; then
  RTO_SECONDS=$((RECOVERY_DONE_TS - RECOVERY_START_TS))
else
  RTO_SECONDS=-1
fi
if [[ "$UP_ZERO_TS" -gt 0 ]]; then
  DETECT_SECONDS=$((UP_ZERO_TS - STOP_TS))
else
  DETECT_SECONDS=-1
fi

# 5. 評価
#    「気づけたか」は up メトリクスでの検知を必須条件とする。
#    通知系カウンタの増加とアラート firing は、あくまで補助的な観測として記録する。
VERDICT="FAIL"
if [[ "$DETECTED_UP_ZERO" -eq 1 && "$RESTARTED" -eq 1 && "$RECOVERED" -eq 1 \
      && "$RTO_SECONDS" -ge 0 && "$RTO_SECONDS" -le "$RTO_TARGET_SECONDS" ]]; then
  VERDICT="PASS"
fi

STOP_TS_ISO=$(iso_time "$STOP_TS")
UP_ZERO_ISO="n/a"
if [[ "$UP_ZERO_TS" -gt 0 ]]; then UP_ZERO_ISO=$(iso_time "$UP_ZERO_TS"); fi
FIRING_ISO="n/a"
if [[ "$FIRING_TS" -gt 0 ]]; then FIRING_ISO=$(iso_time "$FIRING_TS"); fi
RECOVERY_START_ISO=$(iso_time "$RECOVERY_START_TS")
RECOVERY_DONE_ISO="n/a"
if [[ "$RECOVERY_DONE_TS" -gt 0 ]]; then RECOVERY_DONE_ISO=$(iso_time "$RECOVERY_DONE_TS"); fi

cat <<SUMMARY

================ ${DRILL_ID} drill summary ================
runbook              : ${RUNBOOK}
service              : ${SERVICE}
prometheus           : ${PROMETHEUS_URL}
alertmanager         : ${ALERTMANAGER_URL}
stop_at              : ${STOP_TS_ISO}
up_zero_at           : ${UP_ZERO_ISO}
alert_firing_at      : ${FIRING_ISO}
recovery_start_at    : ${RECOVERY_START_ISO}
recovery_done_at     : ${RECOVERY_DONE_ISO}
detect_seconds       : ${DETECT_SECONDS}
rto_seconds          : ${RTO_SECONDS}
rto_target_seconds   : ${RTO_TARGET_SECONDS}
downtime_seconds     : ${DOWNTIME_SECONDS}
alert_state_observed : ${ALERT_STATE_OBSERVED}
notif_errors         : ${NOTIF_ERRORS_BEFORE} -> ${NOTIF_ERRORS_AFTER}
notif_dropped        : ${NOTIF_DROPPED_BEFORE} -> ${NOTIF_DROPPED_AFTER}
notif_signal_seen    : ${NOTIF_SIGNAL} (通知系カウンタが増えたか)
service_restarted    : ${RESTARTED}
verdict              : ${VERDICT}
===========================================================

注意: この演習の最中、Alertmanager 経由の通知は一切届きません。
      「届かなかったこと」は失敗ではなく、この演習が確かめたい仕様そのものです。
      気づけた経路 (up メトリクス / Prometheus /alerts 画面 / Grafana パネル) を記録してください。

次の手順:
1. このサマリーを Slack 演習チャンネルに貼る (docs/incident-comms.md)
2. docs/drill-template.md をコピーして docs/drills/logs/$(date -u +%Y-%m-%d)-D-6.md を作る
3. 「通知が来ないことにどれくらいで気づけたか」「気づけた経路」を記入して PR

SUMMARY

printf 'RESULT_JSON={"drill":"%s","verdict":"%s","service":"%s","detect_seconds":%s,"rto_seconds":%s,"rto_target_seconds":%s,"downtime_seconds":%s,"alert_state_observed":"%s","notif_errors_before":"%s","notif_errors_after":"%s","notif_dropped_before":"%s","notif_dropped_after":"%s","notif_signal_seen":%s,"service_restarted":%s,"stop_at":"%s","up_zero_at":"%s","recovery_done_at":"%s","runbook":"%s"}\n' \
  "$DRILL_ID" "$VERDICT" "$SERVICE" "$DETECT_SECONDS" "$RTO_SECONDS" "$RTO_TARGET_SECONDS" \
  "$DOWNTIME_SECONDS" "$ALERT_STATE_OBSERVED" "$NOTIF_ERRORS_BEFORE" "$NOTIF_ERRORS_AFTER" \
  "$NOTIF_DROPPED_BEFORE" "$NOTIF_DROPPED_AFTER" "$NOTIF_SIGNAL" "$RESTARTED" \
  "$STOP_TS_ISO" "$UP_ZERO_ISO" "$RECOVERY_DONE_ISO" "$RUNBOOK"

[[ "$VERDICT" == "PASS" ]]
