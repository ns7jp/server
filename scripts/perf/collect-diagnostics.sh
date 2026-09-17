#!/usr/bin/env bash
# Read-only CI diagnostics for the existing app/nginx performance experiment.
# No environment variables, credentials, headers, URLs, or config contents are dumped.
set -u
set -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2
COMPOSE=(docker compose -f compose.yaml -f compose.perf.yaml)
DEADLINE=$((SECONDS + 180))
UNAVAILABLE=0

stamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
finish() {
  printf '\n[%s] COLLECTION_STOPPED_BY_CALLER unavailable_checks=%s\n' "$(stamp)" "$UNAVAILABLE"
  exit 0
}
trap finish INT TERM

if ! command -v timeout >/dev/null 2>&1; then
  printf 'COLLECTION_UNAVAILABLE: timeout command missing; refusing unbounded probes\n'
  exit 2
fi

probe() {
  local label="$1"
  shift
  printf '\n[%s] %s\n' "$(stamp)" "$label"
  timeout --signal=TERM --kill-after=1s 3s "$@"
  local rc=$?
  if (( rc != 0 )); then
    printf 'UNAVAILABLE label=%s exit=%s\n' "$label" "$rc"
    UNAVAILABLE=$((UNAVAILABLE + 1))
  fi
  return 0
}

printf '[%s] READ_ONLY_DIAGNOSTICS max_seconds=180 poll_sleep_seconds=5\n' "$(stamp)"
printf 'Host counters and nginx network namespace are separate; no sysctl values are changed.\n'
probe 'host-kernel' uname -sr
probe 'nginx-version' "${COMPOSE[@]}" exec -T nginx nginx -v

# These are the containers from the fixed performance Compose project only.
ids="$(timeout --signal=TERM --kill-after=1s 3s "${COMPOSE[@]}" ps -q app nginx)"
ids_rc=$?
container_ids=()
if (( ids_rc == 0 )) && [[ -n "$ids" ]]; then
  mapfile -t container_ids <<< "$ids"
else
  printf 'UNAVAILABLE label=container-ids exit=%s; container stats will be omitted\n' "$ids_rc"
  UNAVAILABLE=$((UNAVAILABLE + 1))
fi

sample=0
while (( SECONDS < DEADLINE )); do
  printf '\n[%s] SAMPLE %s\n' "$(stamp)" "$sample"
  probe 'host-cpu-memory-sockets' sh -c '
    set -e
    head -n 1 /proc/stat
    awk "/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ {print}" /proc/meminfo
    cat /proc/net/sockstat
    for f in /proc/pressure/cpu /proc/pressure/memory; do
      if [ -r "$f" ]; then printf "%s\n" "$f"; cat "$f"; else printf "UNAVAILABLE %s\n" "$f"; fi
    done
  '
  probe 'nginx-network-namespace' "${COMPOSE[@]}" exec -T nginx sh -c '
    set -e
    for f in /proc/net/sockstat /proc/sys/net/ipv4/ip_local_port_range /proc/sys/net/ipv4/ip_local_reserved_ports /proc/sys/net/ipv4/tcp_tw_reuse /proc/net/snmp /proc/net/netstat; do
      printf "%s\n" "$f"
      cat "$f"
    done
    awk "FNR > 1 {states[\$4]++} END {for (s in states) print \"tcp_state_hex=\" s, \"count=\" states[s]}" /proc/net/tcp /proc/net/tcp6
    printf "tcp_state_hex: 01=ESTABLISHED 02=SYN_SENT 06=TIME_WAIT 0A=LISTEN\n"
  '
  if (( ${#container_ids[@]} > 0 )); then
    probe 'app-nginx-resource-usage' docker stats --no-stream \
      --format '{{.Name}} cpu={{.CPUPerc}} memory={{.MemUsage}} pids={{.PIDs}}' "${container_ids[@]}"
  fi
  sample=$((sample + 1))
  remaining=$((DEADLINE - SECONDS))
  (( remaining > 0 )) || break
  (( remaining < 5 )) || remaining=5
  sleep "$remaining"
done
printf '\n[%s] COLLECTION_LIMIT_REACHED samples=%s unavailable_checks=%s\n' "$(stamp)" "$sample" "$UNAVAILABLE"
# The outer workflow also enforces a hard 180-second bound. Missing probes remain visible.
(( UNAVAILABLE == 0 )) || exit 2
