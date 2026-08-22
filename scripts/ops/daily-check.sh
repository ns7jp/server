#!/usr/bin/env bash
# 日次点検: ディスク使用率 / systemd failed units / エラーログ件数 /
# listen ポート / compose サービス状態をまとめて確認する。
#
# 各チェックは実行環境（systemd の有無、docker の有無）に依存するため、
# 該当コマンドが無い環境では "SKIP" として扱い、スクリプト全体は失敗させない。
# 異常を検出したチェックがあれば、サマリーの最後に非ゼロで終了する。
#
# 使い方:
#   scripts/ops/daily-check.sh [--disk-threshold 80] [--project-dir /opt/server-monitor]
#
# 出力:
#   人間向けサマリーを stdout に出力。cron / systemd timer からの日次実行を想定。

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"
DISK_THRESHOLD=80
PROJECT_DIR="${ROOT_DIR}"

usage() {
  cat <<EOF
Usage: $0 [--disk-threshold PERCENT] [--project-dir DIR]

  --disk-threshold  ディスク使用率の警告閾値 (default: 80)
  --project-dir     compose.yaml がある配備先 (default: scriptから解決したrepository root)
  --help            このヘルプ
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk-threshold)
      [[ $# -ge 2 ]] || { echo "--disk-threshold requires a value" >&2; exit 1; }
      DISK_THRESHOLD="$2"
      shift 2
      ;;
    --project-dir)
      [[ $# -ge 2 ]] || { echo "--project-dir requires a value" >&2; exit 1; }
      PROJECT_DIR="$2"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if ! [[ "${DISK_THRESHOLD}" =~ ^[0-9]+$ ]] \
  || (( 10#${DISK_THRESHOLD} < 1 || 10#${DISK_THRESHOLD} > 100 )); then
  echo "--disk-threshold must be an integer from 1 to 100" >&2
  exit 1
fi

if [[ ! -d "${PROJECT_DIR}" ]]; then
  echo "--project-dir is not a directory: ${PROJECT_DIR}" >&2
  exit 1
fi
PROJECT_DIR="$(cd -- "${PROJECT_DIR}" && pwd -P)"

ISSUES=0

section() {
  printf '\n=== %s ===\n' "$1"
}

log_issue() {
  printf '[NG] %s\n' "$1"
  ISSUES=$((ISSUES + 1))
}

log_ok() {
  printf '[OK] %s\n' "$1"
}

log_skip() {
  printf '[SKIP] %s\n' "$1"
}

printf '日次点検: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf '対象project: %s\n' "${PROJECT_DIR}"

section "配備revision"
REVISION_FILE="${PROJECT_DIR}/.server-monitor-deploy-revision"
if [[ -f "${REVISION_FILE}" ]]; then
  DEPLOYED_REVISION="$(tr -d '\r\n' < "${REVISION_FILE}")"
  if [[ "${DEPLOYED_REVISION}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    log_ok "配備commit: ${DEPLOYED_REVISION}"
  else
    log_issue "revision markerが40桁commit SHAではない: ${REVISION_FILE}"
  fi
else
  log_skip "revision markerなし（Ansible配備外、または配備未完了）"
fi

# 1. ディスク使用率
section "ディスク使用率（閾値 ${DISK_THRESHOLD}%）"
DF_PARSER="${SCRIPT_DIR}/df-over-threshold.awk"
if command -v df >/dev/null 2>&1 && command -v awk >/dev/null 2>&1; then
  df -hP | tail -n +2
  if [[ ! -r "${DF_PARSER}" ]]; then
    log_issue "ディスク判定parserを読めない: ${DF_PARSER}"
  elif DF_OUTPUT=$(df --output=pcent,target 2>/dev/null); then
    OVER_THRESHOLD=$(printf '%s\n' "${DF_OUTPUT}" \
      | awk -v threshold="${DISK_THRESHOLD}" -f "${DF_PARSER}")
    if [[ -n "$OVER_THRESHOLD" ]]; then
      while IFS= read -r line; do
        log_issue "ディスク使用率が閾値超過: $line"
      done <<< "$OVER_THRESHOLD"
    else
      log_ok "全マウントポイントが閾値未満"
    fi
  else
    log_issue "dfから使用率とmount先を取得できない"
  fi
else
  log_skip "df または awk が見つからない"
fi

# 2. systemd failed units
section "systemd failed units"
if command -v systemctl >/dev/null 2>&1; then
  FAILED=$(systemctl --failed --no-legend 2>/dev/null || true)
  if [[ -n "$FAILED" ]]; then
    echo "$FAILED"
    log_issue "failed unit あり（上記参照）"
  else
    log_ok "failed unit なし"
  fi
else
  log_skip "systemctl が見つからない（systemd 未使用の環境）"
fi

# 3. 直近24時間のエラーログ件数
section "journalctl エラーログ件数（過去24時間、priority=err以上）"
if command -v journalctl >/dev/null 2>&1; then
  ERR_COUNT=$(journalctl -p err --since "-24 hours" --no-pager 2>/dev/null | grep -c . || true)
  printf 'エラーログ件数: %s\n' "$ERR_COUNT"
  if [[ "$ERR_COUNT" -gt 0 ]]; then
    log_issue "エラーログが ${ERR_COUNT} 件検出された。詳細は journalctl -p err --since '-24 hours' を確認"
  else
    log_ok "エラーログなし"
  fi
else
  log_skip "journalctl が見つからない（systemd 未使用の環境）"
fi

# 4. listen ポート一覧（異常検出ではなく、想定外の公開が無いかの目視確認用）
section "listen ポート一覧"
if command -v ss >/dev/null 2>&1; then
  ss -lntup 2>/dev/null || ss -lntu
else
  log_skip "ss が見つからない"
fi

# 5. docker compose サービス状態
section "docker compose サービス状態"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if ! docker info >/dev/null 2>&1; then
    log_issue "Docker daemonへ接続できない（daemon停止またはsudo権限を確認）"
  elif [[ -f "${PROJECT_DIR}/compose.yaml" ]]; then
    COMPOSE_ARGS=(
      docker compose
      --project-directory "${PROJECT_DIR}"
      -f "${PROJECT_DIR}/compose.yaml"
    )
    if [[ -f "${PROJECT_DIR}/deploy/secrets/slack_webhook_url.txt" ]]; then
      COMPOSE_ARGS+=(-f "${PROJECT_DIR}/compose.slack.yaml.example")
    fi
    if [[ -f "${PROJECT_DIR}/deploy/alertmanager/alertmanager.ansible.yml" ]]; then
      COMPOSE_ARGS+=(-f "${PROJECT_DIR}/compose.ansible.yaml")
    fi

    EXPECTED_SERVICES=$("${COMPOSE_ARGS[@]}" config --services 2>/dev/null || true)
    COMPOSE_PS=$("${COMPOSE_ARGS[@]}" ps --all --format 'table {{.Service}}\t{{.Status}}' 2>/dev/null || true)
    if [[ -z "${EXPECTED_SERVICES}" ]]; then
      log_issue "Compose設定を解決できない（secret / overlay / YAMLを確認）"
    elif [[ -n "${COMPOSE_PS}" ]]; then
      echo "${COMPOSE_PS}"
      RUNNING_SERVICES=$("${COMPOSE_ARGS[@]}" ps --services --status running 2>/dev/null || true)
      NOT_RUNNING=$(comm -23 \
        <(printf '%s\n' "${EXPECTED_SERVICES}" | sed '/^$/d' | sort -u) \
        <(printf '%s\n' "${RUNNING_SERVICES}" | sed '/^$/d' | sort -u))
      BAD_STATUS=$("${COMPOSE_ARGS[@]}" ps --all --format '{{.Service}} {{.Status}}' 2>/dev/null \
        | grep -Ei 'unhealthy|restarting|exited|dead|created|paused' || true)
      if [[ -n "${NOT_RUNNING}" || -n "${BAD_STATUS}" ]]; then
        [[ -n "${NOT_RUNNING}" ]] && printf 'runningでないservice:\n%s\n' "${NOT_RUNNING}"
        [[ -n "${BAD_STATUS}" ]] && printf '異常status:\n%s\n' "${BAD_STATUS}"
        log_issue "期待serviceの停止または異常statusを検出"
      else
        log_ok "Compose設定上の全serviceが稼働中"
      fi
    else
      log_issue "docker compose ps が空（スタック未起動）"
    fi
  else
    log_issue "compose.yamlが見つからない: ${PROJECT_DIR}"
  fi
else
  if [[ -f "${PROJECT_DIR}/compose.yaml" ]]; then
    log_issue "配備対象にcompose.yamlがあるがDocker Compose commandを利用できない"
  else
    log_skip "docker compose が見つからず、対象projectにもcompose.yamlがない"
  fi
fi

section "サマリー"
if [[ "$ISSUES" -eq 0 ]]; then
  echo "異常なし"
else
  echo "検出された異常: ${ISSUES} 件"
fi

[[ "$ISSUES" -eq 0 ]]
