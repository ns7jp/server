#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# storage role の安全装置が実際に効くことを確認する negative test。
#
# 「変数を間違えたときに止まること」は、正常系より重要なのに検証されにくい。
# 本番相当のディスクを壊さずに確かめるため、存在しないデバイス・マウント済み
# デバイス・既存署名を持つ loop device などを与えて、role が LVM 操作へ
# 進む前に失敗することを確認する。
#
# device-mapper が無い環境でも動く（どの case も LV 作成の手前で止まるため）。
#
#   sudo ./scripts/labs/storage-guard-test.sh
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${STORAGE_GUARD_WORK_DIR:-/var/tmp/server-monitor-storage-guard}"
DRILL_PYTHON="${STORAGE_GUARD_PYTHON:-/usr/bin/python3}"
[[ -x "$DRILL_PYTHON" ]] || DRILL_PYTHON="$(command -v python3)"

PASS_COUNT=0
FAIL_COUNT=0

log()  { printf '\n--- %s ---\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail "loop device を扱うため root で実行する"
command -v losetup >/dev/null 2>&1 || fail "losetup が無い"
command -v ansible-playbook >/dev/null 2>&1 || fail "ansible-playbook が無い"

cleanup() {
  local backing dev
  for backing in "${WORK_DIR}"/*.img; do
    [[ -f "$backing" ]] || continue
    while read -r dev; do
      [[ -n "$dev" ]] && losetup -d "$dev" 2>/dev/null || true
    done < <(losetup -j "$backing" 2>/dev/null | cut -d: -f1)
  done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cleanup
mkdir -p "$WORK_DIR"

# 既に ext4 が入っている loop device（= 中身のあるディスク）を用意する。
truncate -s 32M "${WORK_DIR}/used.img"
USED_DEVICE="$(losetup -f --show "${WORK_DIR}/used.img")"
mkfs.ext4 -q -F "$USED_DEVICE"

# まっさらな loop device。
truncate -s 32M "${WORK_DIR}/blank.img"
BLANK_DEVICE="$(losetup -f --show "${WORK_DIR}/blank.img")"

run_case() {
  local title="$1" expectation="$2" volumes_yaml="$3" extra_vars="${4:-}"
  local inventory="${WORK_DIR}/inventory.yml" output rc

  {
    echo "---"
    echo "all:"
    echo "  hosts:"
    echo "    storage-guard-localhost:"
    echo "      ansible_connection: local"
    echo "      ansible_python_interpreter: ${DRILL_PYTHON}"
    [[ -n "$extra_vars" ]] && echo "$extra_vars"
    echo "      storage_volumes:"
    echo "$volumes_yaml"
  } > "$inventory"

  set +e
  output="$(ANSIBLE_ROLES_PATH="${REPO_ROOT}/ansible/roles" \
    ansible-playbook -i "$inventory" "${REPO_ROOT}/ansible/playbooks/storage.yml" 2>&1)"
  rc=$?
  set -e

  log "$title"
  case "$expectation" in
    refuse)
      if [[ $rc -ne 0 ]] && grep -qE 'Refusing to use|Invalid storage volume definition' <<<"$output"; then
        echo "OK: 安全装置が LVM 操作の手前で止めた"
        grep -qE 'Ensure the volume group exists.*changed' <<<"$output" \
          && { echo "  しかし VG を作成していた"; FAIL_COUNT=$((FAIL_COUNT + 1)); return; }
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        echo "NG: 止まらなかった (rc=${rc})"
        sed -n '/TASK/,$p' <<<"$output" | tail -15
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      ;;
    pass_guard)
      if grep -qE 'Refusing to use|Invalid storage volume definition' <<<"$output"; then
        echo "NG: 正常な入力なのに安全装置が止めた"
        sed -n '/TASK/,$p' <<<"$output" | tail -15
        FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        echo "OK: 安全装置を通過し、LVM 操作まで到達した"
        PASS_COUNT=$((PASS_COUNT + 1))
      fi
      ;;
  esac
}

run_case "case 1: 存在しないデバイス" refuse \
"        - vg: vg_guard
          devices:
            - /dev/definitely-not-a-real-disk
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard"

run_case "case 2: mount point が / （システム破壊）" refuse \
"        - vg: vg_guard
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /" \
"      storage_allow_loop_devices: true"

run_case "case 3: vg 名に不正な文字" refuse \
"        - vg: 'vg guard; rm -rf /'
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard" \
"      storage_allow_loop_devices: true"

run_case "case 4: 未対応のファイルシステム" refuse \
"        - vg: vg_guard
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: btrfs
          mount: /mnt/guard" \
"      storage_allow_loop_devices: true"

run_case "case 5: 既存の ext4 署名を持つディスク" refuse \
"        - vg: vg_guard
          devices:
            - ${USED_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard" \
"      storage_allow_loop_devices: true"

run_case "case 6: loop device だが許可していない" refuse \
"        - vg: vg_guard
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard"

run_case "case 7: 空の loop device を明示的に許可（正常系）" pass_guard \
"        - vg: vg_guard
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard" \
"      storage_allow_loop_devices: true"

printf '\n========================================\n'
printf 'storage role 安全装置テスト: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
printf '========================================\n'
[[ $FAIL_COUNT -eq 0 ]]
