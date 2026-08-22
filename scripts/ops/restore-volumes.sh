#!/usr/bin/env bash
# Restore server-monitor volume archives into an explicitly named Docker project.
# The default path is non-destructive: every target volume must not exist yet.

set -euo pipefail

BACKUP_DIR=""
TARGET_PROJECT=""
FORCE=0
VOLUMES=(prometheus_data grafana_data loki_data)

usage() {
  cat <<'EOF'
Usage: scripts/ops/restore-volumes.sh --backup-dir DIR --target-project NAME [--force]

  --backup-dir      Directory containing SHA256SUMS and *_data.tgz files
  --target-project  Compose project prefix for restored volumes
  --force           Remove and recreate existing target volumes (destructive)

Without --force, the command refuses to touch an existing volume. For a restore
test, use a new name such as server-monitor-restore-20260822.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    --target-project) TARGET_PROJECT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${BACKUP_DIR}" || -z "${TARGET_PROJECT}" ]]; then
  usage
  exit 2
fi
if [[ ! "${TARGET_PROJECT}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "invalid target project name: ${TARGET_PROJECT}" >&2
  exit 2
fi

BACKUP_DIR=$(cd -- "${BACKUP_DIR}" && pwd -P)
test -f "${BACKUP_DIR}/SHA256SUMS" || {
  echo "missing checksum manifest: ${BACKUP_DIR}/SHA256SUMS" >&2
  exit 1
}

(
  cd "${BACKUP_DIR}"
  sha256sum --check SHA256SUMS
)

for volume in "${VOLUMES[@]}"; do
  archive="${BACKUP_DIR}/${volume}.tgz"
  target="${TARGET_PROJECT}_${volume}"
  test -s "${archive}" || { echo "missing archive: ${archive}" >&2; exit 1; }

  listing=$(mktemp)
  if ! tar tzf "${archive}" > "${listing}"; then
    rm -f -- "${listing}"
    echo "cannot list archive: ${archive}" >&2
    exit 1
  fi
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "${listing}"; then
    rm -f -- "${listing}"
    echo "unsafe path found in archive: ${archive}" >&2
    exit 1
  fi
  rm -f -- "${listing}"

  if docker volume inspect "${target}" >/dev/null 2>&1; then
    if [[ "${FORCE}" -ne 1 ]]; then
      echo "target volume already exists (use --force only after stopping services): ${target}" >&2
      exit 1
    fi
    docker volume rm "${target}"
  fi

  docker volume create "${target}" >/dev/null
  docker run --rm \
    -v "${target}:/data" \
    -v "${BACKUP_DIR}:/backup:ro" \
    alpine:3.20 \
    tar xzf "/backup/${volume}.tgz" -C /data
  printf 'restored %s -> %s\n' "${archive}" "${target}"
done
