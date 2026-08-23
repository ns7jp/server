#!/usr/bin/env bash
# Rehearse an immutable git-mode deployment and rollback on a disposable Linux host.
# The host must already have been provisioned by run-full-stack.sh.

set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
INSTALL_DIR="/opt/server-monitor"
EVIDENCE_DIR="${ROOT_DIR}/.artifacts/change-rollback/$(date -u +%Y%m%dT%H%M%SZ)"
INVENTORY="inventory/ci.yml"
GIT_REPO_URL="https://github.com/ns7jp/server-monitor.git"
CANDIDATE_SHA=""
ROLLBACK_SHA=""
REQUESTED_ROLLBACK_SHA=""
CONFIRMED_DISPOSABLE=0
TMP_ROOT=""
CANDIDATE_WORKTREE=""
ROLLBACK_WORKTREE=""
CANDIDATE_WORKTREE_ADDED=0
ROLLBACK_WORKTREE_ADDED=0
EVIDENCE_READY=0
OVERALL="FAIL"
CURRENT_STAGE="input validation"

usage() {
  cat <<'EOF'
Usage: bash scripts/e2e/run-git-rollback-rehearsal.sh \
  --confirm-disposable-host --candidate-sha SHA --rollback-sha SHA [options]

  --confirm-disposable-host  Required acknowledgement: this mutates the host
  --candidate-sha SHA        Immutable 40-character candidate revision
  --rollback-sha SHA         Immutable 40-character last-known-good revision
  --requested-rollback-sha SHA  Original base/before SHA when it differs from
                                the selected common-ancestor rollback revision
  --evidence-dir DIR         Evidence output directory
  --inventory PATH           Inventory relative to ansible/ (default: inventory/ci.yml)
  --install-dir DIR          Installed project path (default: /opt/server-monitor)
  --git-repo-url URL         Public repository fetched by git mode

Run only after run-full-stack.sh on a dedicated throw-away Ubuntu runner.
This does not prove a production-host rollback, AWS recovery, or Slack delivery.
EOF
}

require_option_value() {
  local option="$1" value="${2-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    echo "${option} requires a value" >&2
    usage >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-disposable-host) CONFIRMED_DISPOSABLE=1; shift ;;
    --candidate-sha) require_option_value "$1" "${2-}"; CANDIDATE_SHA="$2"; shift 2 ;;
    --rollback-sha) require_option_value "$1" "${2-}"; ROLLBACK_SHA="$2"; shift 2 ;;
    --requested-rollback-sha) require_option_value "$1" "${2-}"; REQUESTED_ROLLBACK_SHA="$2"; shift 2 ;;
    --evidence-dir) require_option_value "$1" "${2-}"; EVIDENCE_DIR="$2"; shift 2 ;;
    --inventory) require_option_value "$1" "${2-}"; INVENTORY="$2"; shift 2 ;;
    --install-dir) require_option_value "$1" "${2-}"; INSTALL_DIR="$2"; shift 2 ;;
    --git-repo-url) require_option_value "$1" "${2-}"; GIT_REPO_URL="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

write_summary() {
  local generated_at
  generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  mkdir -p "${EVIDENCE_DIR}"
  {
    echo "# Git-mode change and rollback rehearsal"
    echo
    echo "- Generated: ${generated_at}"
    echo "- Overall: **${OVERALL}**"
    echo "- Last stage: ${CURRENT_STAGE}"
    echo "- Candidate SHA: \`${CANDIDATE_SHA:-NOT SET}\`"
    echo "- Rollback SHA: \`${ROLLBACK_SHA:-NOT SET}\`"
    echo "- Requested base/before SHA: \`${REQUESTED_ROLLBACK_SHA:-NOT SET}\`"
    echo "- Target: disposable Ubuntu runner at \`${INSTALL_DIR}\`"
    echo "- Source mode: immutable \`git\` SHA"
    echo "- Scope boundary: not a persistent/production host, AWS recovery, D-2, or Slack delivery"
    echo
    echo "A PASS is written only after candidate deploy/verify, rollback check/deploy/verify,"
    echo "revision-marker equality, running-container manifest equality, forced container replacement,"
    echo "stale-file removal, loopback binding, and Loki log ingestion pass."
  } > "${EVIDENCE_DIR}/change-rollback-summary.md"
}

cleanup() {
  local exit_code=$? summary_exit=0
  set +e
  if [[ "${ROLLBACK_WORKTREE_ADDED}" -eq 1 && -n "${ROLLBACK_WORKTREE}" ]]; then
    git -C "${ROOT_DIR}" worktree remove --force "${ROLLBACK_WORKTREE}" >/dev/null 2>&1
  fi
  if [[ "${CANDIDATE_WORKTREE_ADDED}" -eq 1 && -n "${CANDIDATE_WORKTREE}" ]]; then
    git -C "${ROOT_DIR}" worktree remove --force "${CANDIDATE_WORKTREE}" >/dev/null 2>&1
  fi
  if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
    find "${TMP_ROOT}" -mindepth 1 -maxdepth 1 -type f -delete >/dev/null 2>&1
    rmdir -- "${TMP_ROOT}" >/dev/null 2>&1
  fi
  if [[ "${EVIDENCE_READY}" -eq 1 ]]; then
    write_summary
    summary_exit=$?
    if [[ "${summary_exit}" -ne 0 ]]; then
      echo "failed to write rollback evidence summary" >&2
      [[ "${exit_code}" -ne 0 ]] || exit_code="${summary_exit}"
    fi
  fi
  exit "${exit_code}"
}
trap cleanup EXIT

if [[ "${CONFIRMED_DISPOSABLE}" -ne 1 ]]; then
  echo "refusing to mutate this host without --confirm-disposable-host" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "this rehearsal supports Linux only" >&2
  exit 2
fi
for sha_name in CANDIDATE_SHA ROLLBACK_SHA; do
  sha_value=${!sha_name}
  if [[ ! "${sha_value}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "${sha_name} must be a full 40-character commit SHA" >&2
    exit 2
  fi
done
if [[ -n "${REQUESTED_ROLLBACK_SHA}" ]] \
  && [[ ! "${REQUESTED_ROLLBACK_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "REQUESTED_ROLLBACK_SHA must be empty or a full 40-character commit SHA" >&2
  exit 2
fi
CANDIDATE_SHA=${CANDIDATE_SHA,,}
ROLLBACK_SHA=${ROLLBACK_SHA,,}
REQUESTED_ROLLBACK_SHA=${REQUESTED_ROLLBACK_SHA,,}
if [[ "${CANDIDATE_SHA}" == "${ROLLBACK_SHA}" ]]; then
  echo "candidate and rollback SHA must differ" >&2
  exit 2
fi
if [[ "${GIT_REPO_URL}" =~ ^https?://[^/]*@ ]]; then
  echo "--git-repo-url must not contain embedded credentials" >&2
  exit 2
fi
install_dir_with_slash="${INSTALL_DIR}/"
if [[ ! "${INSTALL_DIR}" =~ ^/(opt|srv)/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] \
  || [[ "${install_dir_with_slash}" == *"/./"* ]] \
  || [[ "${install_dir_with_slash}" == *"/../"* ]]; then
  echo "--install-dir must be a dedicated canonical /opt or /srv path" >&2
  exit 2
fi
if [[ "$(realpath -m -- "${INSTALL_DIR}")" != "${INSTALL_DIR}" ]] \
  || [[ -L "${INSTALL_DIR}" ]] \
  || [[ ! -d "${INSTALL_DIR}" ]]; then
  echo "the provisioned install directory is missing, redirected, or unsafe" >&2
  exit 2
fi
for command in ansible-playbook curl diff docker git python3 realpath ss; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "missing command: ${command}" >&2
    exit 2
  }
done
command -v sudo >/dev/null 2>&1 || [[ "$(id -u)" -eq 0 ]] || {
  echo "sudo is required" >&2
  exit 2
}
git -C "${ROOT_DIR}" cat-file -e "${CANDIDATE_SHA}^{commit}"
git -C "${ROOT_DIR}" cat-file -e "${ROLLBACK_SHA}^{commit}"
git -C "${ROOT_DIR}" merge-base --is-ancestor "${ROLLBACK_SHA}" "${CANDIDATE_SHA}"

mkdir -p "${EVIDENCE_DIR}"
EVIDENCE_DIR=$(cd -- "${EVIDENCE_DIR}" && pwd -P)
EVIDENCE_READY=1
exec > >(tee -a "${EVIDENCE_DIR}/change-rollback-run.log") 2>&1

TMP_ROOT=$(mktemp -d)
chmod 700 "${TMP_ROOT}"
CANDIDATE_WORKTREE="${TMP_ROOT}/candidate-worktree"
ROLLBACK_WORKTREE="${TMP_ROOT}/rollback-worktree"
VARS_FILE="${TMP_ROOT}/rehearsal-vars.yml"

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
  printf 'server_monitor_git_repo: %s\n' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${GIT_REPO_URL}")"
  printf '%s\n' 'app_compose_build_policy: always'
} > "${VARS_FILE}"
chmod 600 "${VARS_FILE}"

run_playbook() {
  local checkout="$1" revision="$2" playbook="$3" log_file="$4"
  shift 4
  (
    cd "${checkout}/ansible"
    ANSIBLE_FORCE_COLOR=0 ANSIBLE_NOCOLOR=1 ANSIBLE_STDOUT_CALLBACK=default \
      ansible-playbook -i "${INVENTORY}" \
      --extra-vars "@${VARS_FILE}" \
      -e server_monitor_source_mode=git \
      -e "server_monitor_git_version=${revision}" \
      "playbooks/${playbook}" "$@"
  ) 2>&1 | tee "${EVIDENCE_DIR}/${log_file}"
}

read_revision() {
  if [[ "$(id -u)" -eq 0 ]]; then
    cat "${INSTALL_DIR}/.server-monitor-deploy-revision"
  else
    sudo cat "${INSTALL_DIR}/.server-monitor-deploy-revision"
  fi
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

compose() {
  run_as_root docker compose \
    --project-directory "${INSTALL_DIR}" \
    -f "${INSTALL_DIR}/compose.yaml" \
    -f "${INSTALL_DIR}/compose.ansible.yaml" \
    -f "${INSTALL_DIR}/compose.e2e.yaml" "$@"
}

force_recreate_app() {
  local container_id health
  compose up -d --no-deps --force-recreate app
  container_id=$(compose ps -q app | tr -d '[:space:]')
  if [[ -z "${container_id}" ]]; then
    echo "app container was not created" >&2
    return 1
  fi
  for _ in $(seq 1 90); do
    health=$(run_as_root docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "${container_id}")
    [[ "${health}" == "healthy" ]] && return 0
    [[ "${health}" == "unhealthy" || "${health}" == "exited" || "${health}" == "dead" ]] && break
    sleep 1
  done
  echo "app container did not become healthy after forced replacement (state=${health:-unknown})" >&2
  return 1
}

write_checkout_runtime_manifest() {
  local checkout="$1" output="$2"
  python3 - "${checkout}" > "${output}" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

root = Path(sys.argv[1])
paths = [root / "app.py", root / "requirements.txt"]
for directory in (root / "templates", root / "static"):
    paths.extend(path for path in directory.rglob("*") if path.is_file())
for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix()):
    relative = path.relative_to(root).as_posix()
    print(f"{sha256(path.read_bytes()).hexdigest()}  {relative}")
PY
}

write_container_runtime_manifest() {
  local container_id="$1" output="$2"
  run_as_root docker exec -i "${container_id}" python - > "${output}" <<'PY'
from hashlib import sha256
from pathlib import Path

root = Path("/app")
paths = [root / "app.py", root / "requirements.txt"]
for directory in (root / "templates", root / "static"):
    paths.extend(path for path in directory.rglob("*") if path.is_file())
for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix()):
    relative = path.relative_to(root).as_posix()
    print(f"{sha256(path.read_bytes()).hexdigest()}  {relative}")
PY
}

assert_running_app_matches() {
  local checkout="$1" prefix="$2" container_id image_id
  container_id=$(compose ps -q app | tr -d '[:space:]')
  [[ -n "${container_id}" ]] || {
    echo "app container is missing while checking ${prefix} runtime provenance" >&2
    return 1
  }
  image_id=$(run_as_root docker inspect --format '{{.Image}}' "${container_id}")
  printf '%s\n' "${container_id}" > "${EVIDENCE_DIR}/${prefix}-app-container-id.txt"
  printf '%s\n' "${image_id}" > "${EVIDENCE_DIR}/${prefix}-app-image-id.txt"
  write_checkout_runtime_manifest "${checkout}" \
    "${EVIDENCE_DIR}/${prefix}-expected-runtime-manifest.sha256"
  write_container_runtime_manifest "${container_id}" \
    "${EVIDENCE_DIR}/${prefix}-actual-runtime-manifest.sha256"
  if ! diff -u \
    "${EVIDENCE_DIR}/${prefix}-expected-runtime-manifest.sha256" \
    "${EVIDENCE_DIR}/${prefix}-actual-runtime-manifest.sha256" \
    > "${EVIDENCE_DIR}/${prefix}-runtime-manifest.diff"; then
    echo "running app content does not match ${prefix} checkout" >&2
    return 1
  fi
}

CURRENT_STAGE="record change context"
{
  date -u '+started_at_utc=%Y-%m-%dT%H:%M:%SZ'
  printf 'candidate_sha=%s\n' "${CANDIDATE_SHA}"
  printf 'rollback_sha=%s\n' "${ROLLBACK_SHA}"
  printf 'install_dir=%s\n' "${INSTALL_DIR}"
  printf 'source_mode=git\n'
  git -C "${ROOT_DIR}" diff --stat "${ROLLBACK_SHA}..${CANDIDATE_SHA}"
} > "${EVIDENCE_DIR}/change-context.txt"

CURRENT_STAGE="prepare isolated candidate checkout"
git -C "${ROOT_DIR}" worktree add --detach "${CANDIDATE_WORKTREE}" "${CANDIDATE_SHA}"
CANDIDATE_WORKTREE_ADDED=1

CURRENT_STAGE="candidate dry run"
run_playbook "${CANDIDATE_WORKTREE}" "${CANDIDATE_SHA}" deploy.yml candidate-check.log --check --diff

CURRENT_STAGE="candidate deployment"
run_playbook "${CANDIDATE_WORKTREE}" "${CANDIDATE_SHA}" deploy.yml candidate-deploy.log
force_recreate_app
run_playbook "${CANDIDATE_WORKTREE}" "${CANDIDATE_SHA}" verify.yml candidate-verify.log
assert_running_app_matches "${CANDIDATE_WORKTREE}" candidate
candidate_revision=$(read_revision | tr -d '[:space:]')
printf '%s\n' "${candidate_revision}" > "${EVIDENCE_DIR}/candidate-revision.txt"
if [[ "${candidate_revision}" != "${CANDIDATE_SHA}" ]]; then
  echo "candidate revision marker mismatch" >&2
  exit 1
fi

CURRENT_STAGE="prepare isolated rollback checkout"
git -C "${ROOT_DIR}" worktree add --detach "${ROLLBACK_WORKTREE}" "${ROLLBACK_SHA}"
ROLLBACK_WORKTREE_ADDED=1
stale_marker="${INSTALL_DIR}/.rollback-rehearsal-stale"
run_as_root install -m 0640 /dev/null "${stale_marker}"

CURRENT_STAGE="rollback dry run"
run_playbook "${ROLLBACK_WORKTREE}" "${ROLLBACK_SHA}" deploy.yml rollback-check.log --check --diff

CURRENT_STAGE="rollback deployment"
run_playbook "${ROLLBACK_WORKTREE}" "${ROLLBACK_SHA}" deploy.yml rollback-deploy.log
force_recreate_app
run_playbook "${ROLLBACK_WORKTREE}" "${ROLLBACK_SHA}" verify.yml rollback-verify.log
assert_running_app_matches "${ROLLBACK_WORKTREE}" rollback
rollback_revision=$(read_revision | tr -d '[:space:]')
printf '%s\n' "${rollback_revision}" > "${EVIDENCE_DIR}/rollback-revision.txt"
if [[ "${rollback_revision}" != "${ROLLBACK_SHA}" ]]; then
  echo "rollback revision marker mismatch" >&2
  exit 1
fi
candidate_container_id=$(tr -d '[:space:]' < "${EVIDENCE_DIR}/candidate-app-container-id.txt")
rollback_container_id=$(tr -d '[:space:]' < "${EVIDENCE_DIR}/rollback-app-container-id.txt")
if [[ "${candidate_container_id}" == "${rollback_container_id}" ]]; then
  echo "app container was not replaced between candidate and rollback" >&2
  exit 1
fi
if run_as_root test -e "${stale_marker}"; then
  echo "stale release marker survived rollback synchronization" >&2
  exit 1
fi

CURRENT_STAGE="post-rollback network and log checks"
run_as_root ss -lntp > "${EVIDENCE_DIR}/rollback-listeners.txt"
python3 "${ROOT_DIR}/scripts/e2e/check_loopback_listeners.py" \
  --input "${EVIDENCE_DIR}/rollback-listeners.txt" \
  --ports 8080 9090 9093 3000 3100 18081

log_marker="rollback-rehearsal-$(date -u +%s)-$$"
curl -sS -o /dev/null --user "monitor:${monitor_password}" \
  "http://127.0.0.1:8080/${log_marker}" || true
log_query='{}'
for _ in $(seq 1 60); do
  log_query=$(curl -fsS --get \
    --data-urlencode "query={service=\"nginx\"} |= \"${log_marker}\"" \
    --data-urlencode 'limit=20' \
    http://127.0.0.1:3100/loki/api/v1/query_range || true)
  printf '%s\n' "${log_query}" > "${EVIDENCE_DIR}/rollback-loki-query.json"
  if python3 -c '
import json, sys
marker = sys.argv[1]
result = json.load(sys.stdin).get("data", {}).get("result", [])
matched = any(marker in line for stream in result for _, line in stream.get("values", []))
raise SystemExit(0 if matched else 1)
' "${log_marker}" <<< "${log_query}"; then
    break
  fi
  sleep 1
done
python3 -c '
import json, sys
marker = sys.argv[1]
result = json.load(sys.stdin).get("data", {}).get("result", [])
assert any(marker in line for stream in result for _, line in stream.get("values", []))
' "${log_marker}" <<< "${log_query}"

compose ps > "${EVIDENCE_DIR}/rollback-compose-ps.txt"

CURRENT_STAGE="completed"
OVERALL="PASS"
echo "GIT_MODE_ROLLBACK_REHEARSAL=PASS"
