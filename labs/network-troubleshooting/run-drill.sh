#!/usr/bin/env bash
set -euo pipefail

LAB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
COMPOSE=(docker compose -f "$LAB_DIR/compose.yaml")
BACKEND_NETWORK=server-monitor-lab-backend

proxy_id=""
restore_network() {
  if [[ -n "$proxy_id" ]] && ! docker inspect "$proxy_id" --format '{{json .NetworkSettings.Networks}}' | grep -q "$BACKEND_NETWORK"; then
    docker network connect --ip 172.28.20.10 "$BACKEND_NETWORK" "$proxy_id" >/dev/null
  fi
}
trap restore_network EXIT

echo '[1/6] Start the two-segment lab'
"${COMPOSE[@]}" up -d
proxy_id=$("${COMPOSE[@]}" ps -q proxy)

echo '[2/6] Baseline: client -> proxy -> app'
"${COMPOSE[@]}" exec -T client curl --retry 10 --retry-delay 1 --retry-connrefused -fsS http://proxy/

echo '[3/6] Inject fault: detach proxy from backend'
docker network disconnect "$BACKEND_NETWORK" "$proxy_id"

echo '[4/6] Confirm user-visible failure'
if "${COMPOSE[@]}" exec -T client curl -fsS --max-time 5 http://proxy/; then
  echo 'FAIL: request unexpectedly succeeded after fault injection' >&2
  exit 1
else
  echo 'PASS: request failed as expected'
fi

echo '[5/6] Diagnose network membership, route, and name resolution'
docker network inspect "$BACKEND_NETWORK" --format '{{json .Containers}}'
"${COMPOSE[@]}" exec -T proxy ip route
"${COMPOSE[@]}" exec -T proxy getent hosts app || true

echo '[6/6] Restore backend membership and verify service recovery'
docker network connect --ip 172.28.20.10 "$BACKEND_NETWORK" "$proxy_id"
"${COMPOSE[@]}" exec -T client curl --retry 10 --retry-delay 1 --retry-connrefused -fsS http://proxy/
echo 'PASS: network fault was reproduced, isolated, and recovered'

