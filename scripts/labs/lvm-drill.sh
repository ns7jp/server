#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# B-1: ディスク設計・LVM 拡張演習
#
# 予備ディスクの無い PC でも「VG を作る / LV を切る / mount する /
# 容量が足りなくなって online で拡張する」までを実測できるようにする演習。
# loop device を 2 本作り、storage role をそのまま適用する。
#
# 実行するもの:
#   1. loop device 2 本を用意する
#   2. storage role で VG / LV / filesystem / fstab を作る
#   3. 2 回目を流して changed=0（冪等性）を確認する
#   4. LV をわざと使い切り、"No space left on device" を再現する
#   5. 2 本目の PV を足して online で LV とファイルシステムを拡張する
#   6. 拡張後に書き込めることを確認する
#
# 結果は docs/drills/logs/<date>-B-1.md に証跡として書き出す。
# 実行者が自分で読み、数値を確認してから採録する前提。
#
#   sudo ./scripts/labs/lvm-drill.sh
#
# 後始末は --cleanup。
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${LVM_DRILL_WORK_DIR:-/var/tmp/server-monitor-lvm-drill}"
VG_NAME="${LVM_DRILL_VG:-vg_drill}"
LV_NAME="${LVM_DRILL_LV:-lv_drill}"
MOUNT_POINT="${LVM_DRILL_MOUNT:-/mnt/server-monitor-drill}"
BACKING_SIZE="${LVM_DRILL_BACKING_SIZE:-256M}"
FSTYPE="${LVM_DRILL_FSTYPE:-ext4}"
EVIDENCE_DIR="${REPO_ROOT}/docs/drills/logs"
RUN_DATE="$(date -u '+%Y-%m-%d')"
EVIDENCE_FILE="${EVIDENCE_DIR}/${RUN_DATE}-B-1.md"

log()  { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
declare -a RESULT_ROWS=()

# 判定は必ずこの関数を通す。証跡の表に PASS を直接書かないことで、
# 「実行はしたが比較していない」項目が混ざらないようにする。
record() {
  local id="$1" title="$2" expected="$3" observed="$4" verdict="$5"
  RESULT_ROWS+=("| ${id} | ${title} | ${expected} | ${observed} | ${verdict} |")
  if [[ "$verdict" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  printf '    [%s] %s -> %s (%s)\n' "$id" "$title" "$observed" "$verdict"
}

verdict_for() { if [[ "$1" == "$2" ]]; then echo PASS; else echo FAIL; fi; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || fail "この演習は loop device と mount を扱うため root で実行する"
}

require_tools() {
  local missing=()
  for tool in losetup pvcreate vgcreate lvcreate lvextend vgextend blkid dmsetup \
    mountpoint df ansible-playbook; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] || fail "不足しているコマンド: ${missing[*]} (lvm2 と ansible-core を入れる)"
}

# LVM の PV / VG は userspace のメタデータ操作だけで完結するが、LV の作成は
# kernel の device-mapper driver を必要とする。一部のコンテナや制限付き VM では
# /dev/mapper/control が無く、VG を作った後で分かりにくいエラーになる。
# 先に検査して、環境の問題であることが分かる形で止める。
require_device_mapper() {
  if [[ ! -e /dev/mapper/control ]]; then
    fail "/dev/mapper/control が無い。この環境の kernel は device-mapper を提供していないため LVM は使えない。
       物理 PC / VirtualBox / Hyper-V の VM など、通常の Linux kernel を持つ環境で実行する。"
  fi
  if ! dmsetup version >/dev/null 2>&1; then
    fail "device-mapper driver と通信できない。通常の Linux kernel を持つ環境で実行する。"
  fi
}

detach_loop_for() {
  local backing="$1" dev
  while read -r dev; do
    [[ -n "$dev" ]] && losetup -d "$dev" 2>/dev/null || true
  done < <(losetup -j "$backing" 2>/dev/null | cut -d: -f1)
}

cleanup() {
  log "cleanup"
  umount "$MOUNT_POINT" 2>/dev/null || true
  sed -i "\#[[:space:]]${MOUNT_POINT}[[:space:]]#d" /etc/fstab 2>/dev/null || true
  lvremove -f "/dev/${VG_NAME}/${LV_NAME}" 2>/dev/null || true
  vgremove -f "$VG_NAME" 2>/dev/null || true
  for index in 1 2; do
    local backing="${WORK_DIR}/disk${index}.img"
    [[ -f "$backing" ]] || continue
    local dev
    dev="$(losetup -j "$backing" 2>/dev/null | cut -d: -f1 | head -1)"
    [[ -n "$dev" ]] && pvremove -f "$dev" 2>/dev/null || true
    detach_loop_for "$backing"
  done
  rm -rf "$WORK_DIR"
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  echo "cleanup 完了"
}

if [[ "${1:-}" == "--cleanup" ]]; then
  require_root
  cleanup
  exit 0
fi

require_root
require_tools
require_device_mapper
cleanup_note() {
  echo "演習が途中で失敗した。後始末は $0 --cleanup" >&2
}
trap cleanup_note ERR

# --- 1. loop device を用意する -------------------------------------------
log "1. backing file と loop device を用意する"
cleanup >/dev/null 2>&1 || true
mkdir -p "$WORK_DIR"
declare -a LOOP_DEVICES=()
for index in 1 2; do
  backing="${WORK_DIR}/disk${index}.img"
  truncate -s "$BACKING_SIZE" "$backing"
  device="$(losetup -f --show "$backing")"
  LOOP_DEVICES+=("$device")
  echo "  disk${index}: ${backing} -> ${device} (${BACKING_SIZE})"
done
FIRST_DEVICE="${LOOP_DEVICES[0]}"
SECOND_DEVICE="${LOOP_DEVICES[1]}"

# --- 2. storage role で構築する ------------------------------------------
log "2. storage role を適用する（1 回目）"
INVENTORY="${WORK_DIR}/inventory.yml"
# OS の package manager を操作するので、venv ではなく OS の python3 を使う。
# apt / dnf の Python バインディングはディストリビューション側にしかない。
DRILL_PYTHON="${LVM_DRILL_PYTHON:-/usr/bin/python3}"
[[ -x "$DRILL_PYTHON" ]] || DRILL_PYTHON="$(command -v python3)"
cat > "$INVENTORY" <<INVENTORY_EOF
---
all:
  hosts:
    lvm-drill-localhost:
      ansible_connection: local
      ansible_python_interpreter: ${DRILL_PYTHON}
      storage_allow_loop_devices: true
      storage_volumes:
        - vg: ${VG_NAME}
          devices:
            - ${FIRST_DEVICE}
          lv: ${LV_NAME}
          size: 100%FREE
          fstype: ${FSTYPE}
          mount: ${MOUNT_POINT}
          opts: defaults
INVENTORY_EOF

run_playbook() {
  ANSIBLE_ROLES_PATH="${REPO_ROOT}/ansible/roles" \
    ansible-playbook -i "$INVENTORY" "${REPO_ROOT}/ansible/playbooks/storage.yml"
}

FIRST_RUN_LOG="${WORK_DIR}/apply-1.log"
run_playbook | tee "$FIRST_RUN_LOG"

# --- 3. 冪等性を確認する --------------------------------------------------
log "3. storage role を適用する（2 回目・冪等性）"
SECOND_RUN_LOG="${WORK_DIR}/apply-2.log"
run_playbook | tee "$SECOND_RUN_LOG"

CHANGED_SECOND="$(grep -oE 'changed=[0-9]+' "$SECOND_RUN_LOG" | tail -1 | cut -d= -f2)"
# 実測欄は必ず観測した内容にする。結果に関わらず「適用完了」と書くと、
# mount できていないのに「適用完了 / FAIL」という自己矛盾した行が証跡へ残る。
if mountpoint -q "$MOUNT_POINT"; then
  record "B1-01" "storage role の初回適用" "VG / LV / filesystem / fstab が作られる" \
    "${MOUNT_POINT} に mount 済み" "PASS"
else
  record "B1-01" "storage role の初回適用" "VG / LV / filesystem / fstab が作られる" \
    "${MOUNT_POINT} が mount されていない" "FAIL"
fi
record "B1-02" "冪等性" "2 回目の適用で changed=0" \
  "changed=${CHANGED_SECOND}" "$(verdict_for "$CHANGED_SECOND" 0)"

SIZE_BEFORE="$(df -h --output=size "$MOUNT_POINT" | tail -1 | tr -d ' ')"
echo "  拡張前のサイズ: ${SIZE_BEFORE}"

# --- 4. 容量を使い切って ENOSPC を再現する --------------------------------
log "4. わざと容量を使い切る（No space left on device の再現）"
# 失敗を承知で実行する箇所では、set +e だけでは足りない。
# bash は set +e でも ERR trap を実行するので、後始末を促す注意書きが
# 「正常に進んでいるのに中断したように見える」形で証跡と画面へ出てしまう。
# 意図した失敗の間は trap も外し、終わったら必ず張り直す。
trap - ERR
set +e
dd if=/dev/zero of="${MOUNT_POINT}/filler.bin" bs=1M count=10000 status=none 2>"${WORK_DIR}/enospc.log"
DD_RC=$?
set -e
trap cleanup_note ERR
ENOSPC_MESSAGE="$(tr -d '\0' < "${WORK_DIR}/enospc.log" | tail -1)"
DF_FULL="$(df -h "$MOUNT_POINT" | tail -1)"
if [[ $DD_RC -eq 0 ]]; then
  record "B1-03" "容量枯渇の再現" "書き込みが ENOSPC で失敗する" \
    "使い切れなかった（BACKING_SIZE を小さくする）" "FAIL"
  fail "容量を使い切れなかった。BACKING_SIZE を小さくして再実行する"
fi
record "B1-03" "容量枯渇の再現" "書き込みが ENOSPC で失敗する" \
  "${ENOSPC_MESSAGE}" "PASS"
echo "  ${DF_FULL}"

# --- 5. PV を足して online 拡張する ---------------------------------------
log "5. 2 本目の PV を追加し、LV とファイルシステムを online 拡張する"
pvcreate -f "$SECOND_DEVICE"
vgextend "$VG_NAME" "$SECOND_DEVICE"
lvextend -r -l +100%FREE "/dev/${VG_NAME}/${LV_NAME}"

SIZE_AFTER="$(df -h --output=size "$MOUNT_POINT" | tail -1 | tr -d ' ')"
echo "  拡張後のサイズ: ${SIZE_AFTER}"
# umount せずに広がったこと、かつ実際にサイズが増えたことの両方を見る。
if mountpoint -q "$MOUNT_POINT" && [[ "$SIZE_AFTER" != "$SIZE_BEFORE" ]]; then
  record "B1-04" "PV 追加による online 拡張" "umount せずに LV と fs が広がる" \
    "${SIZE_BEFORE} -> ${SIZE_AFTER}、mount 維持" "PASS"
else
  record "B1-04" "PV 追加による online 拡張" "umount せずに LV と fs が広がる" \
    "${SIZE_BEFORE} -> ${SIZE_AFTER}、mount=$(mountpoint -q "$MOUNT_POINT" && echo 維持 || echo 外れた)" "FAIL"
fi

# --- 6. 拡張後に書き込めることを確認する ----------------------------------
log "6. 拡張後に書き込めることを確認する"
if dd if=/dev/zero of="${MOUNT_POINT}/after-extend.bin" bs=1M count=32 status=none 2>/dev/null; then
  record "B1-05" "拡張後の書き込み" "追記できる" "32MiB 追記成功" "PASS"
else
  record "B1-05" "拡張後の書き込み" "追記できる" "追記できない" "FAIL"
fi

# shellcheck source=/dev/null
OS_PRETTY_NAME="$( [ -r /etc/os-release ] && . /etc/os-release && echo "${PRETTY_NAME}" )"
PVS_OUT="$(pvs --noheadings -o pv_name,vg_name,pv_size | sed 's/^[[:space:]]*/    /')"
LVS_OUT="$(lvs --noheadings -o lv_name,vg_name,lv_size | sed 's/^[[:space:]]*/    /')"
FSTAB_LINE="$(grep -F "$MOUNT_POINT" /etc/fstab || echo '    (fstab 行なし)')"

# --- 証跡を書き出す -------------------------------------------------------
log "証跡を書き出す"
mkdir -p "$EVIDENCE_DIR"
{
cat <<EVIDENCE_HEAD
# B-1 ディスク設計・LVM 拡張演習 — ${RUN_DATE}

> このファイルは \`scripts/labs/lvm-drill.sh\` が実行結果から生成した。
> 数値は実行時の測定値で、書き換えていない。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| 実施環境 | ${OS_PRETTY_NAME} / kernel $(uname -r) |
| commit SHA | $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown') |
| 対象デバイス | ${FIRST_DEVICE} (${BACKING_SIZE}) + ${SECOND_DEVICE} (${BACKING_SIZE}) ※loop device |
| VG / LV | ${VG_NAME} / ${LV_NAME} |
| ファイルシステム | ${FSTYPE} |
| mount point | ${MOUNT_POINT} |

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
EVIDENCE_HEAD
printf '%s\n' "${RESULT_ROWS[@]}"
cat <<EVIDENCE_TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL

## 拡張前後

\`\`\`text
拡張前: ${SIZE_BEFORE}
枯渇時: ${DF_FULL}
拡張後: ${SIZE_AFTER}
\`\`\`

## 構成

\`\`\`text
pvs:
${PVS_OUT}

lvs:
${LVS_OUT}

fstab:
    ${FSTAB_LINE}
\`\`\`

## この演習で確認していないこと

- loop device による演習であり、物理ディスク / 仮想ディスクの追加・認識・
  \`/dev/sdX\` の採番は対象外。
- パーティションテーブルを使わない whole-disk PV 構成であり、
  \`parted\` / \`fdisk\` による分割は対象外。
- RAID、マルチパス、ディスク障害時の縮退運転は対象外。
- ファイルシステムの縮小（\`lvreduce\`）は storage role が禁止しているため未実施。

## 後始末

\`\`\`bash
sudo ./scripts/labs/lvm-drill.sh --cleanup
\`\`\`
EVIDENCE_TAIL
} > "$EVIDENCE_FILE"

trap - ERR
log "完了"
printf '合計: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
echo "証跡: ${EVIDENCE_FILE}"
echo
echo "内容を自分で確認してから採録すること。後始末は:"
echo "  sudo $0 --cleanup"
[[ $FAIL_COUNT -eq 0 ]]
