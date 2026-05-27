#!/usr/bin/env bash
# D-1: プロセスダウン → 自動復旧演習
#
# 指定したサービスのコンテナを SIGKILL し、`/healthz` 200 が復活するまでの
# 所要時間を計測する。月次演習の自動ランナー。
#
# 使い方:
#   scripts/drills/d1-process-down.sh [--service app] [--healthz URL] [--timeout 300]
#
# 出力:
#   人間向けサマリーを stdout、機械可読 JSON を最終行に "RESULT_JSON=" で出力。
#   Slack 演習チャンネルへのコピペとログ作成の双方に使える。

set -euo pipefail

SERVICE="app"
HEALTHZ_URL="http://127.0.0.1:8080/healthz"
TIMEOUT_SECONDS=300

usage() {
  cat <<EOF
Usage: $0 [--service SERVICE] [--healthz URL] [--timeout SECONDS]

  --service   compose サービス名 (default: app)
  --healthz   復旧判定用の URL (default: http://127.0.0.1:8080/healthz)
  --timeout   復旧待ち上限秒 (default: 300)
  --help      このヘルプ
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)  SERVICE="$2"; shift 2 ;;
    --healthz)  HEALTHZ_URL="$2"; shift 2 ;;
    --timeout)  TIMEOUT_SECONDS="$2"; shift 2 ;;
    --help|-h)  usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}

require_cmd docker
require_cmd curl

# docker compose v2 plugin を想定（v1 docker-compose も後方互換）
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "docker compose plugin が見つからない" >&2
  exit 1
fi

log "サービス: $SERVICE  healthz: $HEALTHZ_URL  timeout: ${TIMEOUT_SECONDS}s"

# 0. 事前確認: サービスが稼働しており healthz が 200 を返すこと
log "事前確認: ${HEALTHZ_URL}"
if ! curl -fsS --max-time 5 "$HEALTHZ_URL" >/dev/null; then
  log "事前確認 NG: ${HEALTHZ_URL} が 200 を返さない。compose を起動してから再実行する。"
  exit 2
fi

# 復元前の restart count
BEFORE_RESTART=$($COMPOSE ps --format json "$SERVICE" 2>/dev/null \
  | (command -v jq >/dev/null && jq -r '.RestartCount // 0' || echo "?"))
log "事前 restart_count(${SERVICE})=${BEFORE_RESTART}"

# 1. 障害発生: SIGKILL
KILL_TS_EPOCH=$(date -u +%s)
log "障害発生: ${COMPOSE} kill -s KILL ${SERVICE}"
$COMPOSE kill -s KILL "$SERVICE" >/dev/null

# 2. 復旧待ち
ATTEMPT=0
SUCCESS=0
RECOVER_TS_EPOCH=0
while :; do
  ATTEMPT=$((ATTEMPT + 1))
  if curl -fsS --max-time 3 "$HEALTHZ_URL" >/dev/null 2>&1; then
    SUCCESS=1
    RECOVER_TS_EPOCH=$(date -u +%s)
    break
  fi
  NOW_EPOCH=$(date -u +%s)
  ELAPSED=$((NOW_EPOCH - KILL_TS_EPOCH))
  if [[ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]]; then
    log "タイムアウト: ${TIMEOUT_SECONDS} 秒以内に復旧しなかった"
    break
  fi
  if (( ATTEMPT % 5 == 0 )); then
    log "復旧待ち... ${ELAPSED}s 経過 (attempts=${ATTEMPT})"
  fi
  sleep 1
done

# 3. 計測結果
if [[ "$SUCCESS" -eq 1 ]]; then
  RECOVER_SECONDS=$((RECOVER_TS_EPOCH - KILL_TS_EPOCH))
  log "復旧完了: ${RECOVER_SECONDS} 秒"
else
  RECOVER_SECONDS=-1
fi

# 4. ポストチェック: restart count とコンテナ状態
AFTER_RESTART=$($COMPOSE ps --format json "$SERVICE" 2>/dev/null \
  | (command -v jq >/dev/null && jq -r '.RestartCount // 0' || echo "?"))
log "事後 restart_count(${SERVICE})=${AFTER_RESTART}"

# 5. 評価
RTO_TARGET=300   # 設計書: RTO 5 分以内
if [[ "$SUCCESS" -eq 1 && "$RECOVER_SECONDS" -le "$RTO_TARGET" ]]; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

# 6. サマリー
KILL_TS_ISO=$(date -u -d "@$KILL_TS_EPOCH" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -r "$KILL_TS_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')
RECOVER_TS_ISO="n/a"
if [[ "$RECOVER_TS_EPOCH" -gt 0 ]]; then
  RECOVER_TS_ISO=$(date -u -d "@$RECOVER_TS_EPOCH" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$RECOVER_TS_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')
fi

cat <<SUMMARY

================ D-1 drill summary ================
service           : $SERVICE
healthz           : $HEALTHZ_URL
kill_at           : $KILL_TS_ISO
recover_at        : $RECOVER_TS_ISO
recover_seconds   : $RECOVER_SECONDS
rto_target_seconds: $RTO_TARGET
restart_count     : $BEFORE_RESTART -> $AFTER_RESTART
verdict           : $VERDICT
===================================================

次の手順:
1. このサマリーを Slack 演習チャンネルに貼る (docs/incident-comms.md)
2. docs/drill-template.md をコピーして docs/drills/logs/$(date -u +%Y-%m-%d)-D-1.md を作る
3. 発見事項と改善アクションを記入して PR

SUMMARY

printf 'RESULT_JSON={"service":"%s","verdict":"%s","recover_seconds":%s,"rto_target_seconds":%s,"restart_count_before":"%s","restart_count_after":"%s","kill_at":"%s","recover_at":"%s"}\n' \
  "$SERVICE" "$VERDICT" "$RECOVER_SECONDS" "$RTO_TARGET" "$BEFORE_RESTART" "$AFTER_RESTART" "$KILL_TS_ISO" "$RECOVER_TS_ISO"

[[ "$VERDICT" == "PASS" ]]
