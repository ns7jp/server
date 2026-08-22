#!/usr/bin/env bash
# Deterministic live demo: running stack -> alert delivery -> process crash -> recovery.

set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
PROJECT_DIR="/opt/server-monitor"
EVIDENCE_DIR="${ROOT_DIR}/.artifacts/demo/$(date -u +%Y%m%dT%H%M%SZ)"
PACE_SECONDS=5
ALERT_ACTIVE=0
START_AT=""
DEMO_INSTANCE="demo-$(date -u +%s)-$$"

usage() {
  cat <<'EOF'
Usage: bash scripts/demo/run-demo.sh [--project-dir DIR] [--evidence-dir DIR] [--pace-seconds N]

The stack must have been provisioned with ansible/inventory/ci.yml so the local
webhook sink is available. This script never claims Slack delivery.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --pace-seconds) PACE_SECONDS="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

mkdir -p "${EVIDENCE_DIR}"
EVIDENCE_DIR=$(cd -- "${EVIDENCE_DIR}" && pwd -P)
exec > >(tee -a "${EVIDENCE_DIR}/demo-transcript.log") 2>&1

dcompose() {
  docker compose --project-directory "${PROJECT_DIR}" \
    -f "${PROJECT_DIR}/compose.yaml" \
    -f "${PROJECT_DIR}/compose.ansible.yaml" \
    -f "${PROJECT_DIR}/compose.e2e.yaml" "$@"
}

event_seen() {
  local wanted_status="$1" wanted_alert="$2" wanted_instance="$3"
  python3 -c '
import json, sys
status, alertname, instance = sys.argv[1:]
events = json.load(sys.stdin)
matched = any(
    event.get("status") == status
    and any(alert.get("labels", {}).get("alertname") == alertname
            and alert.get("labels", {}).get("instance") == instance
            for alert in event.get("alerts", []))
    for event in events
)
raise SystemExit(0 if matched else 1)
' "${wanted_status}" "${wanted_alert}" "${wanted_instance}"
}

pause() {
  if [[ "${PACE_SECONDS}" -gt 0 ]]; then sleep "${PACE_SECONDS}"; fi
}

send_resolution() {
  if [[ "${ALERT_ACTIVE}" -eq 1 ]]; then
    local end_at payload
    end_at=$(date -u -d '-1 second' '+%Y-%m-%dT%H:%M:%SZ')
    payload=$(printf '[{"labels":{"alertname":"PortfolioDemo","severity":"warning","instance":"%s"},"annotations":{"summary":"Synthetic portfolio demo alert"},"startsAt":"%s","endsAt":"%s","generatorURL":"http://127.0.0.1/demo"}]' "${DEMO_INSTANCE}" "${START_AT}" "${end_at}")
    curl -fsS -H 'Content-Type: application/json' -d "${payload}" \
      http://127.0.0.1:9093/api/v2/alerts >/dev/null || true
    ALERT_ACTIVE=0
  fi
}
trap send_resolution EXIT

echo "============================================================"
echo " Server Monitor Infrastructure Lab — live, reproducible demo"
echo "============================================================"
echo "UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Commit: $(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo installed-copy)"
echo "Scope: local webhook notification; Slack is not part of this evidence."
pause

echo
echo "[1/4] Ansible provisioned stack: core 9 services + test receiver"
dcompose ps --format 'table {{.Service}}\t{{.Status}}'
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS http://127.0.0.1:3000/api/health
pause

echo
echo "[2/4] Prometheus sees the Linux node exporter"
curl -fsS --get --data-urlencode 'query=up{job="linux-node"}' \
  http://127.0.0.1:9090/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("linux-node up =", d["data"]["result"][0]["value"][1])'
pause

echo
echo "[3/4] Send a synthetic alert through Alertmanager"
sink_ready=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:18081/healthz >/dev/null; then
    sink_ready=1
    break
  fi
  sleep 1
done
if [[ "${sink_ready}" -ne 1 ]]; then
  echo "local webhook sink did not become ready" >&2
  exit 1
fi
START_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
end_at=$(date -u -d '+5 minutes' '+%Y-%m-%dT%H:%M:%SZ')
payload=$(printf '[{"labels":{"alertname":"PortfolioDemo","severity":"warning","instance":"%s"},"annotations":{"summary":"Synthetic portfolio demo alert"},"startsAt":"%s","endsAt":"%s","generatorURL":"http://127.0.0.1/demo"}]' "${DEMO_INSTANCE}" "${START_AT}" "${end_at}")
curl -fsS -H 'Content-Type: application/json' -d "${payload}" \
  http://127.0.0.1:9093/api/v2/alerts >/dev/null
ALERT_ACTIVE=1
events='[]'
firing_seen=0
for _ in $(seq 1 30); do
  if events=$(curl -fsS --max-time 3 http://127.0.0.1:18081/events) \
    && event_seen firing PortfolioDemo "${DEMO_INSTANCE}" <<< "${events}"; then
    firing_seen=1
    break
  fi
  sleep 1
done
[[ "${firing_seen}" -eq 1 ]]
echo "Alertmanager -> local webhook: FIRING received"
send_resolution
resolved_seen=0
for _ in $(seq 1 30); do
  if events=$(curl -fsS --max-time 3 http://127.0.0.1:18081/events) \
    && event_seen resolved PortfolioDemo "${DEMO_INSTANCE}" <<< "${events}"; then
    resolved_seen=1
    break
  fi
  sleep 1
done
[[ "${resolved_seen}" -eq 1 ]]
echo "Alertmanager -> local webhook: RESOLVED received"
pause

echo
echo "[4/4] Kill app PID 1 from the host and measure automatic recovery"
bash "${ROOT_DIR}/scripts/drills/d1-process-down.sh" \
  --project-dir "${PROJECT_DIR}" --service app --timeout 300 \
  | tee "${EVIDENCE_DIR}/d1-process-down.log"

echo
echo "Demo complete. Raw transcript and D-1 result are in: ${EVIDENCE_DIR}"
