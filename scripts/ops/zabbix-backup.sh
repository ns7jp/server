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

# -f には PROJECT_DIR と結合した絶対パスを渡す。相対パスのままだと、呼び出し元の
# カレントディレクトリを基準に解決されてしまい、--project-directory を指定していても
# PROJECT_DIR 以外の場所から実行したときに compose file が見つからない。
COMPOSE=(docker compose -f "${PROJECT_DIR}/${COMPOSE_FILE}" --project-directory "${PROJECT_DIR}")

TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
DUMP_FILE="${TARGET_DIR}/zabbix-${TIMESTAMP}.dump"
DUMP_BASENAME="$(basename -- "${DUMP_FILE}")"
TMP_DUMP_FILE="${DUMP_FILE}.part"
SHA256_FILE="${TARGET_DIR}/${DUMP_BASENAME}.sha256"
COUNTS_FILE="${TARGET_DIR}/${DUMP_BASENAME}.counts"

# dumpが最終ファイル名(*.dump)として現れるのは末尾のmvだけであり、それより前に
# 失敗したりSIGTERM等で打ち切られたりした場合は、このtrapが一時dumpと(部分的に
# 書けていたかもしれない)sidecarをまとめて削除する。復元手順が探す"zabbix-*.dump"
# は、checksumとcountsが揃っているものしか現れない。
cleanup_partial() {
  rm -f -- "${TMP_DUMP_FILE}" "${SHA256_FILE}" "${COUNTS_FILE}"
}
trap cleanup_partial EXIT

# host数・item数は、pg_dumpが取得するsnapshotとは別接続で読むため、この直後に
# 実行するpg_dump自体との間にわずかな時間差がある。pg_dumpの開始直前に読むことで
# ずれの窓を最小化しているが、実行中にhosts/itemsが変更されると記録される件数と
# dump内容が食い違う可能性はゼロではない。この件数比較はDB復元が明らかに
# 壊れていないかを確認する目安であり、完全な整合性の証明ではない
# (08-change-rollback-plan.md 7節でもFrontend上の内容確認をあわせて求めている)。
echo "==> recording host/item counts before dumping"
if ! HOST_COUNT="$("${COMPOSE[@]}" exec -T postgres psql -U zabbix -d zabbix -Atc 'select count(*) from hosts;')"; then
  echo "failed to record host count" >&2
  exit 1
fi
if ! ITEM_COUNT="$("${COMPOSE[@]}" exec -T postgres psql -U zabbix -d zabbix -Atc 'select count(*) from items;')"; then
  echo "failed to record item count" >&2
  exit 1
fi

echo "==> dumping zabbix database to ${DUMP_FILE}"
# pg_dump の失敗を "if !" の条件として扱うことで、set -e による即時終了を避け、
# 部分的に書き込まれた dump を最終ファイル名へ残さないようにする(mv より前で必ず弾く)。
if ! "${COMPOSE[@]}" exec -T postgres pg_dump -U zabbix --format=custom zabbix > "${TMP_DUMP_FILE}"; then
  echo "pg_dump failed, discarding partial dump: ${TMP_DUMP_FILE}" >&2
  exit 1
fi

if [[ ! -s "${TMP_DUMP_FILE}" ]]; then
  echo "dump file is empty, refusing to keep it: ${TMP_DUMP_FILE}" >&2
  exit 1
fi

# checksum/countsはdumpの最終rename(mv)より前に、最終ファイル名で書き出す。mvが
# 完了するまで、この最終ファイル名のdumpは復元手順のls -t検索に現れないため、
# 両方のsidecarが揃う前にdumpだけが「見つかる」状態にはならない。
if ! DUMP_HASH="$(sha256sum -- "${TMP_DUMP_FILE}" | awk '{print $1}')"; then
  echo "checksum failed, discarding partial dump: ${TMP_DUMP_FILE}" >&2
  exit 1
fi
printf '%s  %s\n' "${DUMP_HASH}" "${DUMP_BASENAME}" > "${SHA256_FILE}"
printf 'hosts=%s\nitems=%s\n' "${HOST_COUNT}" "${ITEM_COUNT}" > "${COUNTS_FILE}"

mv -- "${TMP_DUMP_FILE}" "${DUMP_FILE}"
trap - EXIT

echo "==> wrote ${DUMP_BASENAME}.sha256 and ${DUMP_BASENAME}.counts"

echo "==> pruning dumps older than ${RETENTION_DAYS} day(s) in ${TARGET_DIR}"
find "${TARGET_DIR}" -maxdepth 1 -type f -name 'zabbix-*.dump' -mtime "+${RETENTION_DAYS}" -print -delete
find "${TARGET_DIR}" -maxdepth 1 -type f -name 'zabbix-*.dump.sha256' -mtime "+${RETENTION_DAYS}" -print -delete
find "${TARGET_DIR}" -maxdepth 1 -type f -name 'zabbix-*.dump.counts' -mtime "+${RETENTION_DAYS}" -print -delete

echo "==> backup complete: ${DUMP_FILE}"
