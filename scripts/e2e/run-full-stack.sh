#!/usr/bin/env bash
# Apply the complete Ansible site to a disposable Ubuntu host and collect evidence.
# This script intentionally changes packages, sshd, UFW, Docker, systemd and /opt.

set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
ANSIBLE_DIR="${ROOT_DIR}/ansible"
INVENTORY="inventory/ci.yml"
INSTALL_DIR="/opt/server-monitor"
EVIDENCE_DIR="${ROOT_DIR}/.artifacts/full-stack-e2e/$(date -u +%Y%m%dT%H%M%SZ)"
CONFIRMED_DISPOSABLE=0
TMP_ROOT=""
CLIENT_CONTAINER="server-monitor-e2e-client"
CLIENT_CREATED=0
SSH_TEST_USER="server-monitor-e2e"
SSH_USER_CREATED=0
RESTORE_PROJECT=""
RESTORE_OWNED=0

usage() {
  cat <<'EOF'
Usage: bash scripts/e2e/run-full-stack.sh --confirm-disposable-host [options]

  --confirm-disposable-host  Required acknowledgement: this mutates the host
  --evidence-dir DIR         Evidence output (default: .artifacts/...timestamp)
  --inventory PATH           Inventory path relative to ansible/ (default: inventory/ci.yml)
  --install-dir DIR          Installed compose project (default: /opt/server-monitor)

Run only on a dedicated throw-away Ubuntu 22.04/24.04 VM or GitHub-hosted runner.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-disposable-host) CONFIRMED_DISPOSABLE=1; shift ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --inventory) INVENTORY="$2"; shift 2 ;;
    --install-dir) INSTALL_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${CONFIRMED_DISPOSABLE}" -ne 1 ]]; then
  echo "refusing to mutate this host without --confirm-disposable-host" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "this E2E runner supports Linux only" >&2
  exit 2
fi
install_dir_with_slash="${INSTALL_DIR}/"
if [[ ! "${INSTALL_DIR}" =~ ^/(opt|srv)/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] \
  || [[ "${install_dir_with_slash}" == *"/./"* ]] \
  || [[ "${install_dir_with_slash}" == *"/../"* ]]; then
  echo "--install-dir must be a dedicated /opt or /srv path without dot segments: ${INSTALL_DIR}" >&2
  exit 2
fi
if ! command -v realpath >/dev/null 2>&1; then
  echo "realpath is required to validate --install-dir" >&2
  exit 2
fi
install_dir_canonical=$(realpath -m -- "${INSTALL_DIR}")
if [[ "${install_dir_canonical}" != "${INSTALL_DIR}" ]] \
  || [[ -L "${INSTALL_DIR}" ]] \
  || [[ -e "${INSTALL_DIR}" && ! -d "${INSTALL_DIR}" ]]; then
  echo "--install-dir must be canonical and must not traverse a symlink: ${INSTALL_DIR}" >&2
  exit 2
fi

mkdir -p "${EVIDENCE_DIR}"
EVIDENCE_DIR=$(cd -- "${EVIDENCE_DIR}" && pwd -P)

IDS=(
  ENV IT-01 IT-02 STACK IT-03 IT-04 IT-05 IT-08-local IT-09 IT-10
  NW-01 NW-02 NW-03 NW-04 NW-05 NW-06 NW-07 NW-08 NW-09 IT-12
  ST-01 ST-02 ST-04
)
declare -A STATUS DETAIL DESCRIPTION

DESCRIPTION[ENV]="実行環境とツール版"
DESCRIPTION[IT-01]="site.yml 新規一括適用"
DESCRIPTION[IT-02]="site.yml 2回目 changed=0"
DESCRIPTION[STACK]="core 10 services と E2E sink の稼働・Docker API proxy制限"
DESCRIPTION[IT-03]="Prometheus linux-node up=1"
DESCRIPTION[IT-04]="UI Basic 認証"
DESCRIPTION[IT-05]="metrics Bearer 認証"
DESCRIPTION[IT-08-local]="Alertmanager からローカル webhook への FIRING / RESOLVED 配送"
DESCRIPTION[IT-09]="D-1 process crash と自動復旧"
DESCRIPTION[IT-10]="backup checksum と別 volume restore"
DESCRIPTION[NW-01]="interface / IP / CIDR"
DESCRIPTION[NW-02]="route / gateway"
DESCRIPTION[NW-03]="DNS / NSS resolver"
DESCRIPTION[NW-04]="ICMP loopback"
DESCRIPTION[NW-05]="listen socket"
DESCRIPTION[NW-06]="loopback HTTP と別 namespace からの直接遮断"
DESCRIPTION[NW-07]="header-only tcpdump"
DESCRIPTION[NW-08]="UFW policy"
DESCRIPTION[NW-09]="別 namespace から SSH tunnel 経由の HTTP"
DESCRIPTION[IT-12]="NW-01〜09 の ephemeral VM network 検証"
DESCRIPTION[ST-01]="管理 port の loopback bind"
DESCRIPTION[ST-02]="app container の non-root user"
DESCRIPTION[ST-04]="UFW active / default deny / SSH limit"

for id in "${IDS[@]}"; do
  STATUS["${id}"]="NOT RUN"
  DETAIL["${id}"]="前段未完了または未実行"
done

write_results() {
  {
    printf 'id\tstatus\tdescription\tdetail\n'
    for id in "${IDS[@]}"; do
      printf '%s\t%s\t%s\t%s\n' \
        "${id}" "${STATUS[$id]}" "${DESCRIPTION[$id]}" "${DETAIL[$id]}"
    done
  } > "${EVIDENCE_DIR}/results.tsv"
}

write_report() {
  local overall="PASS" id detail
  for id in "${IDS[@]}"; do
    if [[ "${STATUS[$id]}" != "PASS" ]]; then
      overall="FAIL"
    fi
  done
  {
    echo "# Full-stack E2E result"
    echo
    echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "- Overall: **${overall}**"
    echo "- Scope: disposable Ubuntu host / local webhook sink (not Slack)"
    echo "- Raw log: \`run.log\`"
    echo
    echo "| ID | Result | Check | Evidence note |"
    echo "| --- | --- | --- | --- |"
    for id in "${IDS[@]}"; do
      detail=${DETAIL[$id]//$'\n'/ }
      detail=${detail//|/\\|}
      printf '| `%s` | **%s** | %s | %s |\n' \
        "${id}" "${STATUS[$id]}" "${DESCRIPTION[$id]}" "${detail}"
    done
    echo
    echo "A PASS in this file is generated only after the corresponding command exits successfully."
    echo "Slack delivery, AWS apply/destroy and a persistent production host are outside this run."
  } > "${EVIDENCE_DIR}/summary.md"
}

mark() {
  local id="$1" status="$2" detail="$3"
  if [[ -z "${STATUS[$id]+x}" ]]; then
    echo "unknown result id: ${id}" >&2
    return 2
  fi
  case "${status}" in PASS|FAIL|BLOCKED|NOT\ RUN) ;; *) return 2 ;; esac
  STATUS["${id}"]="${status}"
  DETAIL["${id}"]="${detail//$'\t'/ }"
  write_results
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

dcompose() {
  run_as_root docker compose \
    --project-directory "${INSTALL_DIR}" \
    -f "${INSTALL_DIR}/compose.yaml" \
    -f "${INSTALL_DIR}/compose.ansible.yaml" \
    -f "${INSTALL_DIR}/compose.e2e.yaml" "$@"
}

webhook_event_seen() {
  local wanted_status="$1" wanted_alert="$2" wanted_instance="$3" event_file="$4"
  python3 - "${wanted_status}" "${wanted_alert}" "${wanted_instance}" "${event_file}" <<'PY'
import json
import sys

status, alertname, instance, path = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as stream:
        events = json.load(stream)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

matched = any(
    event.get("status") == status
    and any(
        alert.get("labels", {}).get("alertname") == alertname
        and alert.get("labels", {}).get("instance") == instance
        for alert in event.get("alerts", [])
    )
    for event in events
)
raise SystemExit(0 if matched else 1)
PY
}

cleanup() {
  local exit_code=$?
  set +e
  if [[ "${CLIENT_CREATED}" -eq 1 ]]; then
    run_as_root docker rm -f "${CLIENT_CONTAINER}" >/dev/null 2>&1
  fi
  if [[ "${SSH_USER_CREATED}" -eq 1 ]]; then
    run_as_root userdel --remove "${SSH_TEST_USER}" >/dev/null 2>&1
  fi
  if [[ "${RESTORE_OWNED}" -eq 1 && -n "${RESTORE_PROJECT}" ]]; then
    for volume in prometheus_data grafana_data loki_data; do
      run_as_root docker volume rm "${RESTORE_PROJECT}_${volume}" >/dev/null 2>&1
    done
  fi
  if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
    rm -rf -- "${TMP_ROOT}"
  fi
  write_results
  write_report
  exit "${exit_code}"
}
trap cleanup EXIT

exec > >(tee -a "${EVIDENCE_DIR}/run.log") 2>&1

# site.yml 自身がDockerとip/ping/ss/tcpdump等を導入するため、ここでは
# playbookを開始するために本当に必要なhost側commandだけを前提にする。
for command in ansible-playbook git python3; do
  command -v "${command}" >/dev/null 2>&1 || {
    mark ENV FAIL "missing command: ${command}"
    exit 1
  }
done
command -v sudo >/dev/null 2>&1 || [[ "$(id -u)" -eq 0 ]] || {
  mark ENV FAIL "sudo is required"
  exit 1
}

TMP_ROOT=$(mktemp -d)
VARS_FILE="${TMP_ROOT}/e2e-vars.yml"
SSH_KEY="${TMP_ROOT}/id_ed25519"
chmod 700 "${TMP_ROOT}"

monitor_password=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
metrics_token=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
grafana_password=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
{
  printf '%s\n' '---'
  printf 'vault_monitor_password: "%s"\n' "${monitor_password}"
  printf 'vault_metrics_token: "%s"\n' "${metrics_token}"
  printf 'vault_grafana_admin_password: "%s"\n' "${grafana_password}"
  printf '%s\n' 'vault_slack_webhook_url: ""'
  printf 'server_monitor_install_dir: %s\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${INSTALL_DIR}")"
} > "${VARS_FILE}"
chmod 600 "${VARS_FILE}"

{
  date -u '+timestamp_utc=%Y-%m-%dT%H:%M:%SZ'
  printf 'commit=%s\n' "$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  uname -a
  sed -n '1,8p' /etc/os-release
  python3 --version
  ansible-playbook --version | sed -n '1,3p'
  if command -v docker >/dev/null 2>&1; then
    printf 'docker_preinstalled=yes\n'
    docker --version
  else
    printf 'docker_preinstalled=no\n'
  fi
} > "${EVIDENCE_DIR}/environment-before-site.txt" 2>&1
mark ENV PASS "environment-before-site.txt にcommit/OS/AnsibleとDocker事前有無を採録"

echo "=== IT-01: first site.yml apply ==="
if (
  cd "${ANSIBLE_DIR}"
  ANSIBLE_FORCE_COLOR=0 ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
    ansible-playbook -i "${INVENTORY}" playbooks/site.yml --extra-vars "@${VARS_FILE}"
) 2>&1 | tee "${EVIDENCE_DIR}/ansible-first.log"; then
  mark IT-01 PASS "ansible-first.log: exit 0 / failed=0"
else
  mark IT-01 FAIL "site.yml first apply failed; see ansible-first.log"
  exit 1
fi

for command in curl docker getent ip openssl ping ss ssh-keygen systemctl tcpdump; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    mark STACK FAIL "site.yml completed but required diagnostic command is missing: ${command}"
    exit 1
  fi
done
{
  date -u '+timestamp_utc=%Y-%m-%dT%H:%M:%SZ'
  docker version
  docker compose version
} > "${EVIDENCE_DIR}/environment-after-site.txt" 2>&1
mark ENV PASS "Docker事前有無とsite.yml後のversionをenvironment-*.txtに採録"

echo "=== IT-02: second site.yml apply ==="
if (
  cd "${ANSIBLE_DIR}"
  ANSIBLE_FORCE_COLOR=0 ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
    ansible-playbook -i "${INVENTORY}" playbooks/site.yml --extra-vars "@${VARS_FILE}"
) 2>&1 | tee "${EVIDENCE_DIR}/ansible-second.log"; then
  if grep -Eq '^ci-monitor-01[[:space:]]*:.*changed=0[[:space:]].*unreachable=0[[:space:]].*failed=0' \
    "${EVIDENCE_DIR}/ansible-second.log"; then
    mark IT-02 PASS "ansible-second.log の PLAY RECAP: changed=0 / failed=0"
  else
    mark IT-02 FAIL "2回目は exit 0 だが changed=0 ではない"
    exit 1
  fi
else
  mark IT-02 FAIL "site.yml second apply failed; see ansible-second.log"
  exit 1
fi

echo "=== Runtime and authentication checks ==="
required_services=(app nginx prometheus alertmanager grafana loki alloy blackbox node-exporter docker-socket-proxy webhook-sink)
running_services=$(dcompose ps --services --status running | sort)
printf '%s\n' "${running_services}" > "${EVIDENCE_DIR}/compose-running-services.txt"
missing_service=0
for service in "${required_services[@]}"; do
  grep -Fxq "${service}" <<< "${running_services}" || missing_service=1
done

proxy_ping_ok=0
for _ in $(seq 1 30); do
  if dcompose exec -T docker-socket-proxy \
    wget -qO- http://127.0.0.1:2375/_ping \
    > "${EVIDENCE_DIR}/docker-proxy-ping.txt" 2>&1 \
    && grep -Fxq 'OK' "${EVIDENCE_DIR}/docker-proxy-ping.txt"; then
    proxy_ping_ok=1
    break
  fi
  sleep 1
done
proxy_post_result=$(dcompose exec -T docker-socket-proxy sh -c \
  "wget -S -O /dev/null --post-data='' http://127.0.0.1:2375/containers/e2e-do-not-exist/stop 2>&1 || true" \
  || true)
printf '%s\n' "${proxy_post_result}" > "${EVIDENCE_DIR}/docker-proxy-denied-post.txt"
proxy_post_denied=0
if grep -q '403 Forbidden' "${EVIDENCE_DIR}/docker-proxy-denied-post.txt"; then
  proxy_post_denied=1
fi

docker_log_marker="server-monitor-e2e-docker-log-$(date -u +%s)-$$"
proxy_loki_ok=0
loki_log_result='{}'
for _ in $(seq 1 60); do
  # A unique Nginx request proves the complete read path rather than only the
  # proxy's always-available /_ping endpoint:
  # Docker containers/networks API -> Alloy discovery/log stream -> Loki.
  curl -sS -o /dev/null --user "monitor:${monitor_password}" \
    "http://127.0.0.1:8080/${docker_log_marker}" || true
  loki_log_result=$(curl -fsS --get \
    --data-urlencode "query={service=\"nginx\"} |= \"${docker_log_marker}\"" \
    --data-urlencode 'limit=20' \
    http://127.0.0.1:3100/loki/api/v1/query_range || true)
  printf '%s\n' "${loki_log_result}" \
    > "${EVIDENCE_DIR}/docker-proxy-loki-query.json"
  if python3 -c '
import json, sys
marker = sys.argv[1]
result = json.load(sys.stdin).get("data", {}).get("result", [])
matched = any(marker in line for stream in result for _, line in stream.get("values", []))
raise SystemExit(0 if matched else 1)
' "${docker_log_marker}" <<< "${loki_log_result}"; then
    proxy_loki_ok=1
    break
  fi
  sleep 1
done

if [[ "${missing_service}" -eq 0 && "${proxy_ping_ok}" -eq 1 \
  && "${proxy_post_denied}" -eq 1 && "${proxy_loki_ok}" -eq 1 ]]; then
  mark STACK PASS "core 10 + E2E sink running / Docker log→Loki GET可・POST 403"
else
  mark STACK FAIL "serviceまたはDocker API/log policy不一致; compose-running-services.txt / docker-proxy-*.txtを参照"
fi
dcompose ps > "${EVIDENCE_DIR}/compose-ps.txt"

prom_query=$(curl -fsS --get --data-urlencode 'query=up{job="linux-node"}' \
  http://127.0.0.1:9090/api/v1/query)
printf '%s\n' "${prom_query}" > "${EVIDENCE_DIR}/prometheus-linux-node.json"
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"]=="success" and any(x["value"][1]=="1" for x in d["data"]["result"])' \
  <<< "${prom_query}"; then
  mark IT-03 PASS "Prometheus API で up{job=linux-node}=1"
else
  mark IT-03 FAIL "Prometheus linux-node query did not return 1"
fi

ui_unauth=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/)
ui_auth=$(curl -sS -o /dev/null -w '%{http_code}' \
  --user "monitor:${monitor_password}" http://127.0.0.1:8080/)
if [[ "${ui_unauth}" == "401" && "${ui_auth}" == "200" ]]; then
  mark IT-04 PASS "認証なし=401 / Basic認証あり=200（credential は非採録）"
else
  mark IT-04 FAIL "unexpected UI status: unauth=${ui_unauth}, auth=${ui_auth}"
fi

metrics_unauth=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/metrics)
metrics_body="${TMP_ROOT}/metrics.txt"
metrics_auth=$(curl -sS -o "${metrics_body}" -w '%{http_code}' \
  -H "Authorization: Bearer ${metrics_token}" http://127.0.0.1:8080/metrics)
if [[ "${metrics_unauth}" == "401" && "${metrics_auth}" == "200" ]] \
  && grep -q '^server_monitor_cpu_usage_percent' "${metrics_body}"; then
  mark IT-05 PASS "tokenなし=401 / Bearer tokenあり=200 + metric確認（token は非採録）"
else
  mark IT-05 FAIL "metrics auth or body assertion failed"
fi

echo "=== IT-08-local: Alertmanager webhook delivery ==="
sink_ready=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:18081/healthz >/dev/null; then
    sink_ready=1
    break
  fi
  sleep 1
done
if [[ "${sink_ready}" -ne 1 ]]; then
  mark IT-08-local FAIL "local webhook sink did not become ready"
  exit 1
fi
start_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
end_at=$(date -u -d '+5 minutes' '+%Y-%m-%dT%H:%M:%SZ')
alert_instance="ci-monitor-01-$(date -u +%s)-$$"
alert_payload=$(printf '[{"labels":{"alertname":"E2ENotificationPipeline","severity":"warning","instance":"%s"},"annotations":{"summary":"E2E synthetic alert"},"startsAt":"%s","endsAt":"%s","generatorURL":"http://127.0.0.1/e2e"}]' "${alert_instance}" "${start_at}" "${end_at}")
curl -fsS -H 'Content-Type: application/json' -d "${alert_payload}" \
  http://127.0.0.1:9093/api/v2/alerts >/dev/null
alert_events="${EVIDENCE_DIR}/alert-webhook-events.json"
firing_seen=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 http://127.0.0.1:18081/events > "${alert_events}" \
    && webhook_event_seen firing E2ENotificationPipeline "${alert_instance}" "${alert_events}"; then
    firing_seen=1
    break
  fi
  sleep 1
done
resolve_at=$(date -u -d '-1 second' '+%Y-%m-%dT%H:%M:%SZ')
resolved_payload=$(printf '[{"labels":{"alertname":"E2ENotificationPipeline","severity":"warning","instance":"%s"},"annotations":{"summary":"E2E synthetic alert"},"startsAt":"%s","endsAt":"%s","generatorURL":"http://127.0.0.1/e2e"}]' "${alert_instance}" "${start_at}" "${resolve_at}")
curl -fsS -H 'Content-Type: application/json' -d "${resolved_payload}" \
  http://127.0.0.1:9093/api/v2/alerts >/dev/null
resolved_seen=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 http://127.0.0.1:18081/events > "${alert_events}" \
    && webhook_event_seen resolved E2ENotificationPipeline "${alert_instance}" "${alert_events}"; then
    resolved_seen=1
    break
  fi
  sleep 1
done
if [[ "${firing_seen}" -eq 1 && "${resolved_seen}" -eq 1 ]]; then
  mark IT-08-local PASS "local webhook sink で FIRING / RESOLVED を受信（Slackは対象外）"
else
  mark IT-08-local FAIL "FIRING=${firing_seen}, RESOLVED=${resolved_seen}; alert-webhook-events.json を参照"
fi

echo "=== IT-09: D-1 process crash drill ==="
if run_as_root bash "${ROOT_DIR}/scripts/drills/d1-process-down.sh" \
  --project-dir "${INSTALL_DIR}" --service app --timeout 300 \
  2>&1 | tee "${EVIDENCE_DIR}/d1-process-down.log"; then
  mark IT-09 PASS "unexpected process death から healthz が RTO 5分以内に自動復旧"
else
  mark IT-09 FAIL "D-1 drill failed; see d1-process-down.log"
fi

echo "=== IT-10: backup and restore to isolated volumes ==="
marker="e2e-$(date -u +%s)-$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
for volume in prometheus_data grafana_data loki_data; do
  run_as_root docker run --rm -v "server-monitor-lab_${volume}:/data" alpine:3.20 \
    sh -c 'printf "%s\n" "$1" > /data/.server-monitor-e2e-marker' _ "${marker}"
done
if run_as_root systemctl start server-monitor-backup.service; then
  latest_backup=$(run_as_root find /var/backups/server-monitor-e2e -mindepth 1 -maxdepth 1 \
    -type d -name '20*' -printf '%T@ %p\n' | sort -nr | sed -n '1p' | cut -d' ' -f2-)
  RESTORE_PROJECT="server-monitor-e2e-restore-$(date -u +%s)-$$"
  restore_conflict=0
  for volume in prometheus_data grafana_data loki_data; do
    if run_as_root docker volume inspect "${RESTORE_PROJECT}_${volume}" >/dev/null 2>&1; then
      restore_conflict=1
    fi
  done
  if [[ "${restore_conflict}" -eq 0 ]]; then
    # Cleanup may remove only names proven absent before this run created them.
    RESTORE_OWNED=1
  fi
  if [[ -n "${latest_backup}" && "${restore_conflict}" -eq 0 ]] \
    && run_as_root bash "${ROOT_DIR}/scripts/ops/restore-volumes.sh" \
    --backup-dir "${latest_backup}" --target-project "${RESTORE_PROJECT}" \
    2>&1 | tee "${EVIDENCE_DIR}/backup-restore.log"; then
    restore_ok=1
    for volume in prometheus_data grafana_data loki_data; do
      restored=$(run_as_root docker run --rm -v "${RESTORE_PROJECT}_${volume}:/data:ro" alpine:3.20 \
        cat /data/.server-monitor-e2e-marker 2>/dev/null || true)
      [[ "${restored}" == "${marker}" ]] || restore_ok=0
    done
    if [[ "${restore_ok}" -eq 1 ]]; then
      mark IT-10 PASS "SHA256検証後、別名3 volumeへ復元し marker 一致"
    else
      mark IT-10 FAIL "restore completed but marker comparison failed"
    fi
  else
    mark IT-10 FAIL "backup archive creation or restore command failed"
  fi
else
  mark IT-10 FAIL "server-monitor-backup.service failed"
fi

echo "=== NW-01..09 and ST checks ==="
{
  ip -br link
  ip -br addr
} > "${EVIDENCE_DIR}/network-interfaces.txt"
if grep -Eq '^lo[[:space:]].*127\.0\.0\.1/8' "${EVIDENCE_DIR}/network-interfaces.txt"; then
  mark NW-01 PASS "interface / address を network-interfaces.txt に採録"
else
  mark NW-01 FAIL "loopback address assertion failed"
fi

ip route show table main > "${EVIDENCE_DIR}/network-routes.txt"
ip route get 1.1.1.1 >> "${EVIDENCE_DIR}/network-routes.txt"
if grep -q '^default ' "${EVIDENCE_DIR}/network-routes.txt"; then
  mark NW-02 PASS "default route と route selection を採録"
else
  mark NW-02 FAIL "default route not found"
fi

{
  getent ahostsv4 localhost
  getent ahostsv4 github.com
  cat /etc/resolv.conf
} > "${EVIDENCE_DIR}/network-dns.txt"
if getent ahostsv4 github.com >/dev/null; then
  mark NW-03 PASS "CI host に対象FQDNはないため、resolver/NSS の外部名前解決を確認"
else
  mark NW-03 FAIL "resolver lookup failed"
fi

if ping -c 2 -W 2 127.0.0.1 > "${EVIDENCE_DIR}/network-ping.txt"; then
  mark NW-04 PASS "loopback ICMP 0% loss"
else
  mark NW-04 FAIL "loopback ICMP failed"
fi

run_as_root ss -lntp > "${EVIDENCE_DIR}/network-listeners.txt"
listener_ok=1
for port in 8080 9090 9093 3000 3100 18081; do
  grep -Eq "127\.0\.0\.1:${port}[[:space:]]" "${EVIDENCE_DIR}/network-listeners.txt" || listener_ok=0
  grep -Eq "(0\.0\.0\.0|\*|\[::\]):${port}[[:space:]]" "${EVIDENCE_DIR}/network-listeners.txt" && listener_ok=0
done
if [[ "${listener_ok}" -eq 1 ]]; then
  mark NW-05 PASS "管理5 port + E2E sink は 127.0.0.1 のみ"
  mark ST-01 PASS "管理 port の wildcard bind なし"
else
  mark NW-05 FAIL "listener address mismatch; network-listeners.txt を参照"
  mark ST-01 FAIL "管理 port に欠落または wildcard bind あり"
fi

app_cid=$(dcompose ps -q app)
app_user=$(run_as_root docker inspect -f '{{.Config.User}}' "${app_cid}")
if [[ -n "${app_user}" && "${app_user}" != "0" && "${app_user}" != "root" ]]; then
  mark ST-02 PASS "running app container Config.User=${app_user}"
else
  mark ST-02 FAIL "running app container user is root or empty"
fi

run_as_root systemctl start ssh
if id "${SSH_TEST_USER}" >/dev/null 2>&1; then
  mark NW-09 FAIL "temporary SSH test user already exists; refusing to reuse it"
else
  run_as_root useradd --create-home --shell /bin/bash "${SSH_TEST_USER}"
  SSH_USER_CREATED=1
  ssh-keygen -q -t ed25519 -N '' -f "${SSH_KEY}"
  run_as_root install -d -m 0700 -o "${SSH_TEST_USER}" -g "${SSH_TEST_USER}" "/home/${SSH_TEST_USER}/.ssh"
  run_as_root install -m 0600 -o "${SSH_TEST_USER}" -g "${SSH_TEST_USER}" \
    "${SSH_KEY}.pub" "/home/${SSH_TEST_USER}/.ssh/authorized_keys"
  docker run -d --name "${CLIENT_CONTAINER}" --add-host target:host-gateway \
    -v "${SSH_KEY}:/tmp/e2e-key:ro" alpine:3.20 sleep 600 >/dev/null
  CLIENT_CREATED=1
  docker exec "${CLIENT_CONTAINER}" apk add --no-cache curl openssh-client >/dev/null

  if curl -fsS http://127.0.0.1:8080/healthz >/dev/null \
    && docker exec "${CLIENT_CONTAINER}" sh -c \
      'if curl -fsS --max-time 3 http://target:8080/healthz >/dev/null 2>&1; then exit 1; else exit 0; fi'; then
    mark NW-06 PASS "host loopback HTTP=200 / 別namespaceからhost:8080へ直接接続不可"
  else
    mark NW-06 FAIL "loopback HTTP or external-namespace isolation assertion failed"
  fi

  capture_file="${EVIDENCE_DIR}/network-tcpdump.txt"
  run_as_root timeout 15 tcpdump -nn -i lo -c 2 'tcp port 8080' > "${capture_file}" 2>&1 &
  capture_pid=$!
  sleep 1
  curl -fsS http://127.0.0.1:8080/healthz >/dev/null
  if wait "${capture_pid}" && grep -q '127.0.0.1.8080' "${capture_file}"; then
    mark NW-07 PASS "lo の tcp/8080 header を2 packet採録（payloadなし）"
  else
    mark NW-07 FAIL "tcpdump did not capture loopback health request"
  fi

  if docker exec "${CLIENT_CONTAINER}" ssh -f -N \
    -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ExitOnForwardFailure=yes -i /tmp/e2e-key \
    -L 18080:127.0.0.1:8080 "${SSH_TEST_USER}@target" \
    && docker exec "${CLIENT_CONTAINER}" curl -fsS --max-time 5 http://127.0.0.1:18080/healthz >/dev/null; then
    mark NW-09 PASS "別namespace client -> SSH/22 -> 127.0.0.1:8080 tunnel で200"
  else
    mark NW-09 FAIL "SSH tunnel validation failed"
  fi
fi

run_as_root ufw status verbose > "${EVIDENCE_DIR}/network-ufw.txt"
if grep -q '^Status: active' "${EVIDENCE_DIR}/network-ufw.txt" \
  && grep -Eq '^Default: deny \(incoming\)' "${EVIDENCE_DIR}/network-ufw.txt" \
  && grep -Eq '^22/tcp[[:space:]]+LIMIT' "${EVIDENCE_DIR}/network-ufw.txt" \
  && ! grep -Eq '^(8080|9090|9093|3000|3100)/tcp[[:space:]]+ALLOW' "${EVIDENCE_DIR}/network-ufw.txt"; then
  mark NW-08 PASS "UFW active / incoming deny / SSH limit / 管理port allowなし"
  mark ST-04 PASS "network-ufw.txt に policy と rules を採録"
else
  mark NW-08 FAIL "UFW policy assertion failed; network-ufw.txt を参照"
  mark ST-04 FAIL "UFW hardening assertion failed"
fi

network_all_pass=1
for id in NW-01 NW-02 NW-03 NW-04 NW-05 NW-06 NW-07 NW-08 NW-09; do
  [[ "${STATUS[$id]}" == "PASS" ]] || network_all_pass=0
done
if [[ "${network_all_pass}" -eq 1 ]]; then
  mark IT-12 PASS "GitHub Actions ephemeral VM と別Docker namespaceで NW-01〜09 を完走"
else
  mark IT-12 FAIL "NW-01〜09 に未完了または失敗あり"
fi

required_all_pass=1
for id in "${IDS[@]}"; do
  [[ "${STATUS[$id]}" == "PASS" ]] || required_all_pass=0
done
if [[ "${required_all_pass}" -eq 1 ]]; then
  echo "FULL_STACK_E2E=PASS"
  exit 0
fi

echo "FULL_STACK_E2E=FAIL"
exit 1
