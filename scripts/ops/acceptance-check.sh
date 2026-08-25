#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 引き渡し対象ホストの受け入れ試験・永続性確認
#
# docs/build-package/06-test-specification.md の試験 ID を、実ホスト上で
# 実際に実行し、記入済みの結果票を生成する。
#
# 06 の原本が全項目 NOT RUN なのは「引き渡し対象ホストが決まっていない」ため。
# 対象ホスト（VPS / VM / 物理）が決まったら、そのホスト上でこれを実行すると
# docs/evidence/<日付>-host-acceptance.md が埋まった状態で出てくる。
#
# モード:
#   acceptance  (既定) 受け入れ試験を 1 回実行して結果票を出す
#   baseline    再起動前の状態を保存する
#   after-reboot baseline と比較し、再起動をまたいで永続しているか判定する
#   soak        指定時間サンプリングし、24h / 72h 確認の証跡を出す
#
# 使い方（対象ホスト上で root として実行する）:
#   sudo ./scripts/ops/acceptance-check.sh
#   sudo ./scripts/ops/acceptance-check.sh --mode baseline
#   sudo systemctl reboot
#   sudo ./scripts/ops/acceptance-check.sh --mode after-reboot
#   sudo ./scripts/ops/acceptance-check.sh --mode soak --hours 24
#
# 秘密値は読み取るが、出力には一切書かない。
# host 名 / IP は既定でマスクする（--no-mask で解除）。
# ---------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

MODE=acceptance
PROJECT_DIR=/opt/server-monitor
SOAK_HOURS=24
SOAK_INTERVAL=900
MASK=1
STATE_DIR=/var/lib/server-monitor-acceptance
EVIDENCE_DIR="${ROOT_DIR}/docs/evidence"
RUN_DATE="$(date -u '+%Y-%m-%d')"

MONITOR_PORT="${MONITOR_PORT:-8080}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
LOKI_PORT="${LOKI_PORT:-3100}"

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)         MODE="${2:?--mode requires a value}"; shift 2 ;;
    --project-dir)  PROJECT_DIR="${2:?--project-dir requires a value}"; shift 2 ;;
    --hours)        SOAK_HOURS="${2:?--hours requires a value}"; shift 2 ;;
    --interval)     SOAK_INTERVAL="${2:?--interval requires a value}"; shift 2 ;;
    --state-dir)    STATE_DIR="${2:?--state-dir requires a value}"; shift 2 ;;
    --no-mask)      MASK=0; shift ;;
    --help|-h)      usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$MODE" in
  acceptance|baseline|after-reboot|soak) ;;
  *) echo "--mode must be acceptance, baseline, after-reboot, or soak" >&2; exit 1 ;;
esac
if ! [[ "$SOAK_HOURS" =~ ^[0-9]+$ ]] || (( SOAK_HOURS < 1 )); then
  echo "--hours must be an integer of at least 1" >&2
  exit 1
fi
if ! [[ "$SOAK_INTERVAL" =~ ^[0-9]+$ ]] || (( SOAK_INTERVAL < 60 )); then
  echo "--interval must be an integer of at least 60 seconds" >&2
  exit 1
fi
# 間隔が観測窓より長いと、1 回測っただけで「N 時間稼働した」証跡になる。
if (( SOAK_INTERVAL > SOAK_HOURS * 3600 )); then
  echo "--interval (${SOAK_INTERVAL}s) must not exceed --hours (${SOAK_HOURS}h = $((SOAK_HOURS * 3600))s)" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
NA_COUNT=0
declare -a RESULT_ROWS=()

# 判定は必ずこの関数を通す。結果票に PASS を直書きしないことで、
# 「実行はしたが比較していない」項目が混ざらないようにする。
record() {
  local id="$1" title="$2" expected="$3" observed="$4" verdict="$5"
  RESULT_ROWS+=("| ${id} | ${title} | ${expected} | ${observed} | ${verdict} |")
  # SKIP と N/A を分ける。
  #   SKIP = この環境では確認できなかった（未確認。合格ではない）
  #   N/A  = この script の設計上の対象外（別の証跡が担当する）
  # 両方を SKIP にまとめると、確認できなかった項目が対象外に紛れる。
  case "$verdict" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    N/A)  NA_COUNT=$((NA_COUNT + 1)) ;;
    *)    FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
  printf '  [%-6s] %-6s %s -> %s\n' "$verdict" "$id" "$title" "$observed"
}

verdict_eq() { if [[ "$1" == "$2" ]]; then echo PASS; else echo FAIL; fi; }

mask() {
  if (( MASK )); then sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<masked-ip>/g'
  else cat; fi
}

masked_host() {
  if (( MASK )); then echo "<masked-host>"; else hostname; fi
}

# 秘密値はファイルから読むだけ。変数の中身は出力しない。
secret_of() {
  local path="${PROJECT_DIR}/deploy/secrets/$1.txt"
  [[ -r "$path" ]] || { echo ""; return; }
  tr -d '\r\n' < "$path"
}

# curl は失敗時にも "000" を出力したうえで非ゼロ終了する。
# `|| echo 000` を付けると値が二重に出て "000000" になり、後段の比較が壊れる。
# 出力を採ってから空のときだけ既定値を入れる。
http_code() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

# grep -c は一致 0 件のとき "0" を出力したうえで非ゼロ終了する。
# `|| echo 0` を付けると "0\n0" になり、算術比較が構文エラーになる。
count_lines() {
  local n
  n="$(grep -c "$@")" || true
  printf '%s' "${n:-0}"
}

have() { command -v "$1" >/dev/null 2>&1; }

# 受け入れ試験は「引き渡してよいか」を判定する。前提コマンドが無い環境で
# 個別に SKIP へ落とすと、確認できていない項目を抱えたまま合計が緑になり、
# 最初の恒久ホストの証跡が「SKIP だらけの緑」になる。
# 道具が揃っていないことは試験の結果ではなく前提の不備なので、
# ここで全体を止める（labs/three-tier/run-drill.sh の B2-02 と同じ考え方）。
REQUIRED_TOOLS=(ip ss systemctl docker awk grep sed getent)
require_tools() {
  local missing=() tool
  for tool in "${REQUIRED_TOOLS[@]}"; do
    have "$tool" || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    cat >&2 <<MSG
不足しているコマンド: ${missing[*]}

受け入れ試験はこれらを前提にしている。個別に SKIP へ落とすと、確認できて
いない項目を抱えたまま合計が PASS になるため、ここで停止する。
対象ホストへ導入してから再実行すること（Debian 系: iproute2 / procps /
systemd / docker.io、RHEL 系: iproute / systemd / docker-ce）。

どうしても実行したい場合のみ ACCEPTANCE_ALLOW_MISSING_TOOLS=1 を付ける。
その場合、結果票は「合格」として扱わないこと。
MSG
    [[ "${ACCEPTANCE_ALLOW_MISSING_TOOLS:-0}" == "1" ]] || exit 2
    printf 'ACCEPTANCE_ALLOW_MISSING_TOOLS=1 のため続行する（結果票は合格として扱わない）\n' >&2
    TOOLS_INCOMPLETE=1
  fi
}
TOOLS_INCOMPLETE=0

require_root() {
  [[ "$(id -u)" -eq 0 ]] || {
    echo "対象ホストの状態（firewall / systemd / secrets）を読むため root で実行する" >&2
    exit 1
  }
}

# --- 収集 -----------------------------------------------------------------
boot_id()      { cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; }
revision()     { cat "${PROJECT_DIR}/.server-monitor-deploy-revision" 2>/dev/null || echo unknown; }
uptime_start() { uptime -s 2>/dev/null || echo unknown; }

compose_running() {
  have docker || { echo "-1"; return; }
  docker compose -f "${PROJECT_DIR}/compose.yaml" ps --status running \
    --format '{{.Service}}' 2>/dev/null | count_lines .
}

# --- 受け入れ試験本体 ------------------------------------------------------
run_acceptance_checks() {
  local dashboard_password metrics_token username
  username="$(secret_of monitor_username)"
  [[ -n "$username" ]] || username=monitor
  dashboard_password="$(secret_of dashboard_password)"
  metrics_token="$(secret_of metrics_token)"

  # --- IT-03 host metrics -------------------------------------------------
  local up_value
  up_value="$(curl -s --max-time 10 \
    "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query?query=up%7Bjob%3D%22linux-node%22%7D" 2>/dev/null \
    | grep -o '"value":\[[^]]*\]' | grep -oE '"[01]"' | tr -d '"' | head -1)"
  if [[ -z "$up_value" ]]; then
    record IT-03 "host metrics" 'up{job="linux-node"}=1' "Prometheus へ到達できない" FAIL
  else
    record IT-03 "host metrics" 'up{job="linux-node"}=1' "up=${up_value}" "$(verdict_eq "$up_value" 1)"
  fi

  # --- IT-04 UI auth ------------------------------------------------------
  local ui_anon ui_auth
  ui_anon="$(http_code "http://127.0.0.1:${MONITOR_PORT}/")"
  if [[ -n "$dashboard_password" ]]; then
    ui_auth="$(http_code -u "${username}:${dashboard_password}" "http://127.0.0.1:${MONITOR_PORT}/")"
  else
    ui_auth="secret-unreadable"
  fi
  if [[ "$ui_anon" =~ ^(401|503)$ && "$ui_auth" == "200" ]]; then
    record IT-04 "UI auth" "未認証 401/503、認証あり 200" "未認証=${ui_anon}, 認証=${ui_auth}" PASS
  else
    record IT-04 "UI auth" "未認証 401/503、認証あり 200" "未認証=${ui_anon}, 認証=${ui_auth}" FAIL
  fi

  # --- IT-05 metrics auth -------------------------------------------------
  local m_anon m_auth
  m_anon="$(http_code "http://127.0.0.1:${MONITOR_PORT}/metrics")"
  if [[ -n "$metrics_token" ]]; then
    m_auth="$(http_code -H "Authorization: Bearer ${metrics_token}" "http://127.0.0.1:${MONITOR_PORT}/metrics")"
  else
    m_auth="secret-unreadable"
  fi
  if [[ "$m_anon" =~ ^(401|503)$ && "$m_auth" == "200" ]]; then
    record IT-05 "metrics auth" "token なし 401/503、あり 200" "なし=${m_anon}, あり=${m_auth}" PASS
  else
    record IT-05 "metrics auth" "token なし 401/503、あり 200" "なし=${m_anon}, あり=${m_auth}" FAIL
  fi

  # --- IT-06 Grafana ------------------------------------------------------
  local grafana
  grafana="$(http_code "http://127.0.0.1:${GRAFANA_PORT}/api/health")"
  record IT-06 "Grafana health" "200" "status=${grafana}" "$(verdict_eq "$grafana" 200)"

  # --- IT-07 logs (LogQL) -------------------------------------------------
  local loki_hits
  loki_hits="$(curl -s --max-time 15 -G "http://127.0.0.1:${LOKI_PORT}/loki/api/v1/query_range" \
    --data-urlencode 'query={container=~".+"}' --data-urlencode 'limit=1' 2>/dev/null \
    | count_lines '"values"')"
  if [[ "${loki_hits:-0}" -gt 0 ]]; then
    record IT-07 "logs (LogQL)" "log を取得できる" "Loki から結果あり" PASS
  else
    record IT-07 "logs (LogQL)" "log を取得できる" "Loki から結果なし" FAIL
  fi

  # --- Alertmanager readiness --------------------------------------------
  local am
  am="$(http_code "http://127.0.0.1:${ALERTMANAGER_PORT}/-/ready")"
  record IT-08a "Alertmanager readiness" "200" "status=${am}" "$(verdict_eq "$am" 200)"
  # 実 Slack 配信は webhook 秘密値と外部到達が要るため、この script では扱わない。
  record IT-08 "alert 実配信" "Slack へ到達" "この script の設計上の対象外（別途 Slack 実配信の証跡で確認する）" "N/A"

  # --- ST-01 bind address -------------------------------------------------
  if have ss; then
    local exposed
    exposed="$(ss -lntupH 2>/dev/null \
      | awk '{print $5}' \
      | grep -E ":(${MONITOR_PORT}|${PROMETHEUS_PORT}|${GRAFANA_PORT}|${ALERTMANAGER_PORT}|${LOKI_PORT})$" \
      | count_lines -vE '^(127\.0\.0\.1|\[::1\])')"
    if [[ "$exposed" -eq 0 ]]; then
      record ST-01 "bind address" "管理 UI は loopback のみ" "非 loopback listener なし" PASS
    else
      record ST-01 "bind address" "管理 UI は loopback のみ" "非 loopback listener ${exposed} 件" FAIL
    fi
  else
    record ST-01 "bind address" "管理 UI は loopback のみ" "ss が無い" SKIP
  fi

  # --- ST-02 container user ----------------------------------------------
  if have docker; then
    local app_user
    app_user="$(docker inspect --format '{{.Config.User}}' \
      "$(docker compose -f "${PROJECT_DIR}/compose.yaml" ps -q app 2>/dev/null)" 2>/dev/null || echo "")"
    if [[ -z "$app_user" ]]; then
      record ST-02 "container user" "app は root でない" "app container を特定できない" FAIL
    elif [[ "$app_user" == "root" || "$app_user" == "0" ]]; then
      record ST-02 "container user" "app は root でない" "user=${app_user}" FAIL
    else
      record ST-02 "container user" "app は root でない" "user=${app_user}" PASS
    fi
  else
    record ST-02 "container user" "app は root でない" "docker が無い" SKIP
  fi

  # --- ST-04 / NW-08 firewall --------------------------------------------
  if have ufw; then
    local ufw_out
    ufw_out="$(ufw status verbose 2>/dev/null)"
    if grep -q '^Status: active' <<<"$ufw_out" \
      && grep -Eq '^Default: deny \(incoming\)' <<<"$ufw_out" \
      && ! grep -Eq "^(${MONITOR_PORT}|${PROMETHEUS_PORT}|${GRAFANA_PORT}|${ALERTMANAGER_PORT}|${LOKI_PORT})/tcp[[:space:]]+ALLOW" <<<"$ufw_out"; then
      record ST-04 "firewall (ufw)" "active / deny incoming / 管理 port 非公開" "条件を満たす" PASS
    else
      record ST-04 "firewall (ufw)" "active / deny incoming / 管理 port 非公開" "条件を満たさない" FAIL
    fi
  elif have firewall-cmd; then
    local zone_out
    zone_out="$(firewall-cmd --list-all 2>/dev/null)"
    if grep -qE '^\s*ports:\s*$' <<<"$zone_out" \
      || ! grep -qE "(${MONITOR_PORT}|${PROMETHEUS_PORT}|${GRAFANA_PORT})/tcp" <<<"$zone_out"; then
      record ST-04 "firewall (firewalld)" "管理 port を公開しない" "管理 port の公開なし" PASS
    else
      record ST-04 "firewall (firewalld)" "管理 port を公開しない" "管理 port が公開されている" FAIL
    fi
  else
    record ST-04 "firewall" "許可通信だけ開放" "ufw / firewall-cmd が無い" SKIP
  fi

  # --- NW-01 / NW-02 / NW-03 ---------------------------------------------
  if have ip; then
    local addr_count route_default
    addr_count="$(ip -br -4 addr show scope global 2>/dev/null | count_lines .)"
    route_default="$(ip route show default 2>/dev/null | count_lines .)"
    record NW-01 "interface / IP / CIDR" "global アドレスが 1 つ以上" "${addr_count} 件" \
      "$([[ ${addr_count} -ge 1 ]] && echo PASS || echo FAIL)"
    record NW-02 "route / default gateway" "default route がある" "${route_default} 件" \
      "$([[ ${route_default} -ge 1 ]] && echo PASS || echo FAIL)"
  else
    record NW-01 "interface / IP / CIDR" "global アドレスが 1 つ以上" "ip が無い" SKIP
    record NW-02 "route / default gateway" "default route がある" "ip が無い" SKIP
  fi
  if getent hosts github.com >/dev/null 2>&1; then
    record NW-03 "DNS 名前解決" "外部名を解決できる" "解決できた" PASS
  else
    record NW-03 "DNS 名前解決" "外部名を解決できる" "解決できない" FAIL
  fi

  # --- 永続性の前提: systemd / backup timer -------------------------------
  if have systemctl; then
    local failed_units
    failed_units="$(systemctl --failed --no-legend --no-pager 2>/dev/null | count_lines .)"
    record PS-01 "systemd failed units" "0 件" "${failed_units} 件" \
      "$(verdict_eq "$failed_units" 0)"

    local timer_state
    timer_state="$(systemctl is-active server-monitor-backup.timer 2>/dev/null || echo inactive)"
    record PS-02 "backup timer" "active" "${timer_state}" "$(verdict_eq "$timer_state" active)"
  else
    record PS-01 "systemd failed units" "0 件" "systemctl が無い" SKIP
    record PS-02 "backup timer" "active" "systemctl が無い" SKIP
  fi

  local running
  running="$(compose_running)"
  if [[ "$running" == "-1" ]]; then
    record PS-03 "compose services" "必須 service が running" "docker が無い" SKIP
  elif [[ "${running:-0}" -ge 10 ]]; then
    record PS-03 "compose services" "10 以上が running" "${running} 件" PASS
  else
    record PS-03 "compose services" "10 以上が running" "${running} 件" FAIL
  fi
}

# --- 出力 -----------------------------------------------------------------
emit_evidence() {
  local title="$1" outfile="$2" extra="${3:-}"
  local OS_PRETTY_NAME MASK_NOTE
  if (( MASK )); then MASK_NOTE="マスクしている"; else MASK_NOTE="マスクしていない"; fi
  # shellcheck source=/dev/null
  OS_PRETTY_NAME="$( [ -r /etc/os-release ] && . /etc/os-release && echo "${PRETTY_NAME}" )"
  mkdir -p "$(dirname "$outfile")"
  {
    cat <<HEAD
# ${title} — ${RUN_DATE}

> このファイルは \`scripts/ops/acceptance-check.sh\` が実ホスト上の実行結果から
> 生成した。判定は script が期待値と実測値を比較した結果で、手で書き換えていない。
> host 名と IP は${MASK_NOTE}。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| モード | ${MODE} |
| 対象ホスト | $(masked_host) |
| OS | ${OS_PRETTY_NAME} |
| kernel | $(uname -r) |
| boot 時刻 | $(uptime_start) |
| boot ID | $(boot_id) |
| 配備 revision | $(revision) |
| 配備先 | ${PROJECT_DIR} |
| 実行ホスト | $(id -un 2>/dev/null || echo unknown) @ $(hostname 2>/dev/null || echo unknown) |
| 実行者 | ${DRILL_OPERATOR:-未設定（DRILL_OPERATOR 環境変数で指定する）} |
| 前提コマンド | $( ((TOOLS_INCOMPLETE)) && echo '**不足あり（この結果票は合格として扱わない）**' || echo '揃っている' ) |

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
HEAD
    printf '%s\n' "${RESULT_ROWS[@]}"
    cat <<TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL / ${SKIP_COUNT} SKIP / ${NA_COUNT} N/A

> **SKIP は「この環境で確認できなかった」であり、合格ではありません。**
> SKIP が 1 件でもある結果票は、引き渡しの合格証跡として使えません。
> N/A はこの script の設計上の対象外で、別の証跡が担当します。
> $( ((SKIP_COUNT)) && echo "**この実行には SKIP が ${SKIP_COUNT} 件あります。合格として扱わないでください。**" || echo "この実行に SKIP はありません。" )

${extra}

## この結果が示さないこと

- この結果票は **この 1 台・この時点** の状態を示す。別ホスト、別時点の
  保証ではない。
- \`SKIP\` は「確認していない」であって「問題なし」ではない。
- Alertmanager から Slack への実配信、AWS 適用、D-2 復旧演習、
  組織 DNS / 上流 firewall の確認は、この script の対象外。
- 管理端末側からの疎通（NW-09 の SSH tunnel 経由 end-to-end）は、
  管理端末で別途実施する。

## 元になった原本

[試験仕様書・結果票](../build-package/06-test-specification.md) の試験 ID に対応する。
原本は引き渡し対象ホスト未定の \`NOT RUN\` 初期値のまま保持し、上書きしない。
TAIL
  } > "$outfile"
  printf '\n証跡: %s\n' "$outfile"
  printf '合計: %d PASS / %d FAIL / %d SKIP / %d N/A\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$NA_COUNT"
}

save_state() {
  mkdir -p "$STATE_DIR"
  {
    echo "boot_id=$(boot_id)"
    echo "revision=$(revision)"
    echo "uptime_start=$(uptime_start)"
    echo "compose_running=$(compose_running)"
    echo "captured_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "${STATE_DIR}/baseline.env"
  printf 'baseline を保存した: %s/baseline.env\n' "$STATE_DIR"
}

# --- モード別実行 ----------------------------------------------------------
require_root
require_tools

case "$MODE" in
  baseline)
    save_state
    ;;

  acceptance)
    printf '受け入れ試験を実行する (対象: %s)\n\n' "${PROJECT_DIR}"
    run_acceptance_checks
    emit_evidence "引き渡し対象ホスト 受け入れ試験結果票" \
      "${EVIDENCE_DIR}/${RUN_DATE}-host-acceptance.md"
    ;;

  after-reboot)
    [[ -r "${STATE_DIR}/baseline.env" ]] || {
      echo "baseline が無い。先に --mode baseline を実行して再起動する" >&2
      exit 1
    }
    # shellcheck source=/dev/null
    prev_boot_id="$(grep '^boot_id=' "${STATE_DIR}/baseline.env" | cut -d= -f2-)"
    prev_revision="$(grep '^revision=' "${STATE_DIR}/baseline.env" | cut -d= -f2-)"
    now_boot_id="$(boot_id)"
    now_revision="$(revision)"

    printf '再起動をまたいだ永続性を確認する\n\n'
    # boot ID が変わっていなければ、そもそも再起動していない。
    if [[ "$prev_boot_id" != "$now_boot_id" ]]; then
      record RB-01 "実際に再起動した" "boot ID が変わる" "変化を確認" PASS
    else
      record RB-01 "実際に再起動した" "boot ID が変わる" "boot ID が同じ（未再起動）" FAIL
    fi
    if [[ "$prev_revision" == "$now_revision" ]]; then
      record RB-02 "配備 revision の維持" "再起動前と同一" "同一" PASS
    else
      record RB-02 "配備 revision の維持" "再起動前と同一" "変化した" FAIL
    fi
    run_acceptance_checks
    emit_evidence "永続ホスト 再起動後確認 結果票" \
      "${EVIDENCE_DIR}/${RUN_DATE}-host-reboot.md" \
      "> 再起動前 boot ID と比較して、同一ホストが自動起動で復帰したことを確認している。"
    ;;

  soak)
    total_seconds=$(( SOAK_HOURS * 3600 ))
    # サンプル間だけ sleep するので、n 回の観測がまたぐ時間は (n-1) 間隔。
    # total / interval のままだと観測窓が 1 間隔ぶん短くなり、
    # 「N 時間連続稼働」と題した証跡が実際には N 時間を観測していないことになる。
    samples=$(( total_seconds / SOAK_INTERVAL + 1 ))
    printf '%d 時間の連続稼働を %d 秒間隔で %d 回サンプリングする（観測窓 %d 秒）\n' \
      "$SOAK_HOURS" "$SOAK_INTERVAL" "$samples" "$(( (samples - 1) * SOAK_INTERVAL ))"
    printf 'nohup / systemd-run などで切断に耐える形で起動することを推奨する\n\n'

    soak_started_at=$(date -u +%s)
    start_boot_id="$(boot_id)"
    degraded=0
    reboots=0
    for (( i = 1; i <= samples; i++ )); do
      running="$(compose_running)"
      current_boot="$(boot_id)"
      [[ "$current_boot" != "$start_boot_id" ]] && reboots=$((reboots + 1))
      healthz="$(http_code "http://127.0.0.1:${MONITOR_PORT}/healthz")"
      [[ "$healthz" != "200" || "${running:-0}" -lt 10 ]] && degraded=$((degraded + 1))
      printf '  [%3d/%3d] %s healthz=%s running=%s\n' \
        "$i" "$samples" "$(date -u '+%H:%M:%S')" "$healthz" "$running"
      (( i < samples )) && sleep "$SOAK_INTERVAL"
    done

    soak_ended_at=$(date -u +%s)
    soak_observed=$(( soak_ended_at - soak_started_at ))
    # 実際に観測できた時間が要求より短ければ、その証跡は要求を満たしていない。
    # 途中で中断された場合もここで落ちる。
    if (( soak_observed >= total_seconds )); then
      record SK-00 "観測窓が要求時間を満たす" "${total_seconds} 秒以上" \
        "${soak_observed} 秒" PASS
    else
      record SK-00 "観測窓が要求時間を満たす" "${total_seconds} 秒以上" \
        "${soak_observed} 秒（不足）" FAIL
    fi
    record SK-01 "連続稼働中の可用性" "全サンプルで healthz=200" \
      "${samples} 回中 ${degraded} 回が異常" "$(verdict_eq "$degraded" 0)"
    record SK-02 "意図しない再起動" "0 回" "${reboots} 回" "$(verdict_eq "$reboots" 0)"
    run_acceptance_checks
    emit_evidence "永続ホスト ${SOAK_HOURS} 時間連続稼働 結果票" \
      "${EVIDENCE_DIR}/${RUN_DATE}-host-soak-${SOAK_HOURS}h.md" \
      "> サンプリング間隔 ${SOAK_INTERVAL} 秒、サンプル数 ${samples}、実測した観測窓 ${soak_observed} 秒（要求 ${total_seconds} 秒）。"
    ;;
esac

# 合否判定。FAIL が無いことに加えて、
#  - SKIP が無いこと（SKIP は未確認であって合格ではない）
#  - 判定件数が下限を超えていること（何も実行できていない緑を防ぐ）
# の 3 つを満たしたときだけ 0 で終わる。
# baseline モードは状態を保存するだけで判定を行わないため対象外。
ACCEPTANCE_MIN_CHECKS="${ACCEPTANCE_MIN_CHECKS:-10}"

if [[ "$MODE" == "baseline" ]]; then
  exit 0
fi

exit_code=0
if [[ $FAIL_COUNT -ne 0 ]]; then
  printf 'FAIL が %d 件ある。\n' "$FAIL_COUNT" >&2
  exit_code=1
fi
if [[ $SKIP_COUNT -ne 0 ]]; then
  printf 'SKIP が %d 件ある。SKIP は未確認であり合格ではないため、合格としない。\n' "$SKIP_COUNT" >&2
  exit_code=1
fi
if [[ $((PASS_COUNT + FAIL_COUNT)) -lt ${ACCEPTANCE_MIN_CHECKS} ]]; then
  printf '判定できた項目が %d 件で下限 %s 件に満たない。実行できていない試験がある。\n' \
    "$((PASS_COUNT + FAIL_COUNT))" "${ACCEPTANCE_MIN_CHECKS}" >&2
  exit_code=1
fi
if ((TOOLS_INCOMPLETE)); then
  printf '前提コマンドが不足したまま実行した。この結果票は合格として扱わない。\n' >&2
  exit_code=1
fi
exit "$exit_code"

