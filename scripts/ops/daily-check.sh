#!/usr/bin/env bash
# 日次点検: ディスク使用率 / systemd failed units / エラーログ件数 /
# listen ポート / compose サービス状態をまとめて確認する。
#
# 各チェックは実行環境（systemd の有無、docker の有無）に依存するため、
# 該当コマンドが無い環境では "SKIP" として扱い、スクリプト全体は失敗させない。
# 異常を検出したチェックがあれば、サマリーの最後に非ゼロで終了する。
#
# 使い方:
#   scripts/ops/daily-check.sh [--disk-threshold 80]
#
# 出力:
#   人間向けサマリーを stdout に出力。cron / systemd timer からの日次実行を想定。

set -uo pipefail

DISK_THRESHOLD=80

usage() {
  cat <<EOF
Usage: $0 [--disk-threshold PERCENT]

  --disk-threshold  ディスク使用率の警告閾値 (default: 80)
  --help            このヘルプ
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk-threshold) DISK_THRESHOLD="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

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

# 1. ディスク使用率
section "ディスク使用率（閾値 ${DISK_THRESHOLD}%）"
if command -v df >/dev/null 2>&1; then
  df -hP | tail -n +2
  OVER_THRESHOLD=$(df -P | tail -n +2 | awk -v t="$DISK_THRESHOLD" '{gsub(/%/,"",$5); if ($5+0 > t) print $6" "$5"%"}')
  if [[ -n "$OVER_THRESHOLD" ]]; then
    while IFS= read -r line; do
      log_issue "ディスク使用率が閾値超過: $line"
    done <<< "$OVER_THRESHOLD"
  else
    log_ok "全マウントポイントが閾値未満"
  fi
else
  log_skip "df が見つからない"
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
  if [[ -f compose.yaml || -f compose.yml || -f docker-compose.yml ]]; then
    COMPOSE_PS=$(docker compose ps --format 'table {{.Service}}\t{{.Status}}' 2>/dev/null || true)
    if [[ -n "$COMPOSE_PS" ]]; then
      echo "$COMPOSE_PS"
      UNHEALTHY=$(docker compose ps --format '{{.Service}} {{.Status}}' 2>/dev/null | grep -Ev 'Up|running' || true)
      if [[ -n "$UNHEALTHY" ]]; then
        log_issue "Up/running ではないサービスがある（上記参照）"
      else
        log_ok "全サービスが稼働中"
      fi
    else
      log_skip "docker compose ps が空（スタック未起動の可能性）"
    fi
  else
    log_skip "compose ファイルが見つからない（このディレクトリでは実行対象外）"
  fi
else
  log_skip "docker compose が見つからない"
fi

section "サマリー"
if [[ "$ISSUES" -eq 0 ]]; then
  echo "異常なし"
else
  echo "検出された異常: ${ISSUES} 件"
fi

[[ "$ISSUES" -eq 0 ]]
