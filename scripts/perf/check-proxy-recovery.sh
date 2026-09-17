#!/usr/bin/env bash
# Isolated CI regression: cold DNS, authentication, and upstream IP replacement.
# It never stops or recreates the performance Compose stack.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == "true" && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ ]] || {
  echo "NOT RUN: this destructive lifecycle test is restricted to disposable GitHub Actions runners" >&2
  exit 2
}
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f compose.yaml -f compose.perf.yaml)
app_image="$("${COMPOSE[@]}" images -q app)"
nginx_image="$("${COMPOSE[@]}" images -q nginx)"
[[ -n "$app_image" && -n "$nginx_image" && "$app_image" != *$'\n'* && "$nginx_image" != *$'\n'* ]] || {
  echo "NOT RUN: expected one existing app image and nginx image" >&2
  exit 2
}
prefix="perf-proxy-${GITHUB_RUN_ID}-$$"
network_id=""
created=()
cleanup() {
  local rc=$?
  local cleanup_failed=0
  trap - EXIT
  for id in "${created[@]}"; do
    if timeout 3s docker container inspect "$id" >/dev/null 2>&1; then
      timeout 10s docker rm -f "$id" >/dev/null 2>&1 || cleanup_failed=1
    fi
  done
  if [[ -n "$network_id" ]]; then
    timeout 10s docker network rm "$network_id" >/dev/null 2>&1 || cleanup_failed=1
  fi
  if (( cleanup_failed != 0 )); then
    echo "FAIL isolated resource cleanup; inspect disposable runner" >&2
    (( rc != 0 )) || rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
network_id="$(docker network create "$prefix")"
nginx_id="$(docker run -d --name "${prefix}-nginx" --network "$network_id" \
  -p 127.0.0.1::8080 \
  -v "$ROOT/deploy/nginx/local.conf:/etc/nginx/conf.d/default.conf:ro" "$nginx_image")"
created+=("$nginx_id")
binding="$(docker port "$nginx_id" 8080/tcp)"
[[ "$binding" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo "Unexpected bind: $binding" >&2; exit 1; }
url="http://$binding"
expect() {
  local path="$1" wanted="$2" auth="${3:-}" code=""
  if [[ -n "$auth" ]]; then
    code="$(curl --silent --show-error --max-time 3 -o /dev/null -w '%{http_code}' --user "$auth" "$url$path")"
  else
    code="$(curl --silent --show-error --max-time 3 -o /dev/null -w '%{http_code}' "$url$path")"
  fi
  [[ "$code" == "$wanted" ]] || { echo "FAIL path=$path expected=$wanted actual=$code" >&2; return 1; }
  echo "PASS path=$path status=$code"
}
wait_health() {
  local code=""
  for _ in $(seq 1 45); do
    code="$(curl --silent --max-time 1 -o /dev/null -w '%{http_code}' "$url/healthz")" || true
    if [[ "$code" == "200" ]]; then return 0; fi
    sleep 1
  done
  echo "FAIL health did not recover after DNS/app change" >&2
  return 1
}
# Nginx must start even when Docker DNS has no app record.
for _ in $(seq 1 10); do
  if [[ "$(docker inspect --format '{{.State.Running}}' "$nginx_id")" == true ]] && \
    curl --silent --max-time 1 -o /dev/null "$url/healthz"; then break; fi
  sleep 1
done
docker exec "$nginx_id" nginx -t
expect /healthz 502
echo "PASS nginx started while app was absent"

start_app() {
  # Synthetic credentials belong only to this isolated test.
  app_id="$(docker run -d --network "$network_id" --network-alias app \
    -e MONITOR_USERNAME=monitor -e MONITOR_PASSWORD=proxy-test-only \
    -e MONITOR_METRICS_TOKEN=proxy-test-only "$app_image")"
  created+=("$app_id")
}
start_app
wait_health
expect /healthz 200
expect / 401
expect / 200 'monitor:proxy-test-only'
old_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app_id")"
[[ -n "$old_ip" ]] || exit 1
docker rm -f "$app_id" >/dev/null
# Reserve the released address so recreation must produce a genuinely new IP.
reservation="$(docker run -d --network "$network_id" --ip "$old_ip" \
  --entrypoint /bin/sh "$nginx_image" -c 'sleep 120')"
created+=("$reservation")
start_app
new_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app_id")"
[[ -n "$new_ip" && "$new_ip" != "$old_ip" ]] || { echo "FAIL app IP did not change" >&2; exit 1; }
wait_health
expect /healthz 200
expect / 401
expect / 200 'monitor:proxy-test-only'
[[ "$(docker inspect --format '{{.State.Running}}' "$nginx_id")" == true ]]
echo "PASS dynamic upstream recovered after app IP changed; original nginx container retained"
