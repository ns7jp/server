#!/usr/bin/env bash
# SM-ZBX-001 Zabbix監視基盤構築案件パック用のDBバックアップ。
#
# zbx-01 上で `docker compose -f compose.zabbix.yaml` によって起動している postgres
# コンテナから `pg_dump` (custom format) を採取し、保持世代を超えた古いdumpを削除する。
# systemd timer からの日次実行を想定している(設計値は毎日03:45 Asia/Tokyo、
# docs/build-package-zabbix/05-build-procedure.md 参照)。
#
# 復元手順はこのスクリプトの範囲外。docs/build-package-zabbix/08-change-rollback-plan.md
# の手順に従い、別コンテナ/別DBへ `pg_restore` して確認する。
#
# 使い方:
#   scripts/ops/zabbix-backup.sh [--target-dir /var/backups/zabbix] \
#     [--retention-days 14] [--project-dir /opt/zabbix-lab] \
#     [--compose-file compose.zabbix.yaml]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

TARGET_DIR="/var/backups/zabbix"
RETENTION_DAYS=14
PROJECT_DIR="${ROOT_DIR}"
COMPOSE_FILE="compose.zabbix.yaml"

usage() {
  cat <<EOF
Usage: $0 [--target-dir DIR] [--retention-days N] [--project-dir DIR] [--compose-file FILE]

  --target-dir      dumpの保存先 (default: ${TARGET_DIR})
  --retention-days  保持世代(日数)。これより古いdumpを削除する (default: ${RETENTION_DAYS})
  --project-dir     compose.zabbix.yaml がある配備先 (default: scriptから解決したrepository root)
  --compose-file    使用するcompose file名 (default: ${COMPOSE_FILE})
  --help            このヘルプ
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)
      [[ $# -ge 2 ]] || { echo "--target-dir requires a value" >&2; exit 1; }
      TARGET_DIR="$2"
      shift 2
      ;;
    --retention-days)
      [[ $# -ge 2 ]] || { echo "--retention-days requires a value" >&2; exit 1; }
      RETENTION_DAYS="$2"
      shift 2
      ;;
    --project-dir)
      [[ $# -ge 2 ]] || { echo "--project-dir requires a value" >&2; exit 1; }
      PROJECT_DIR="$2"
      shift 2
      ;;
    --compose-file)
      [[ $# -ge 2 ]] || { echo "--compose-file requires a value" >&2; exit 1; }
      COMPOSE_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! "${RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [[ "${RETENTION_DAYS}" -lt 1 ]]; then
  echo "--retention-days must be a positive integer, got: ${RETENTION_DAYS}" >&2
  exit 2
fi
if [[ "${TARGET_DIR}" != /var/backups/* && "${TARGET_DIR}" != /srv/backups/* ]]; then
  echo "--target-dir must be under /var/backups or /srv/backups, got: ${TARGET_DIR}" >&2
  exit 2
fi
if [[ ! -f "${PROJECT_DIR}/${COMPOSE_FILE}" ]]; then
  echo "compose file not found: ${PROJECT_DIR}/${COMPOSE_FILE}" >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "docker command not found" >&2; exit 1; }

install -d -m 0750 -- "${TARGET_DIR}"

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
DUMP_FILE="${TARGET_DIR}/zabbix-${TIMESTAMP}.dump"

echo "==> dumping zabbix database to ${DUMP_FILE}"
docker compose -f "${COMPOSE_FILE}" --project-directory "${PROJECT_DIR}" \
  exec -T postgres pg_dump -U zabbix --format=custom zabbix > "${DUMP_FILE}"

if [[ ! -s "${DUMP_FILE}" ]]; then
  echo "dump file is empty, refusing to keep it: ${DUMP_FILE}" >&2
  rm -f -- "${DUMP_FILE}"
  exit 1
fi

( cd -- "${TARGET_DIR}" && sha256sum -- "$(basename -- "${DUMP_FILE}")" > "$(basename -- "${DUMP_FILE}").sha256" )
echo "==> wrote $(basename -- "${DUMP_FILE}").sha256"

echo "==> pruning dumps older than ${RETENTION_DAYS} day(s) in ${TARGET_DIR}"
find "${TARGET_DIR}" -maxdepth 1 -type f -name 'zabbix-*.dump' -mtime "+${RETENTION_DAYS}" -print -delete
find "${TARGET_DIR}" -maxdepth 1 -type f -name 'zabbix-*.dump.sha256' -mtime "+${RETENTION_DAYS}" -print -delete

echo "==> backup complete: ${DUMP_FILE}"
