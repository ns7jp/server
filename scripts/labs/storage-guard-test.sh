#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# storage role の安全装置が実際に効くことを確認する negative test。
#
# 「変数を間違えたときに止まること」は、正常系より重要なのに検証されにくい。
# 本番相当のディスクを壊さずに確かめるため、存在しないデバイス・マウント済み
# デバイス・既存署名を持つ loop device などを与えて、role が LVM 操作へ
# 進む前に失敗することを確認する。
#
# case 1〜6 は LV 作成の手前で止まるため device-mapper が無い環境でも動く。
# case 7 だけは正常系で、LVM 操作まで到達する。device-mapper が無い環境では
# この case を SKIP-ENV とし、PASS には数えない。
#
#   sudo ./scripts/labs/storage-guard-test.sh
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${STORAGE_GUARD_WORK_DIR:-/var/tmp/server-monitor-storage-guard}"
DRILL_PYTHON="${STORAGE_GUARD_PYTHON:-/usr/bin/python3}"
[[ -x "$DRILL_PYTHON" ]] || DRILL_PYTHON="$(command -v python3)"
# sudo は既定で secure_path により PATH をリセットするため、pip/venv で
# 入れた ansible-playbook が呼び出し元の PATH 上にあっても root からは
# 見えないことがある（full-stack-e2e の run_as_root env 経由の呼び出しで
# 実際に "ansible-playbook が無い" で落ちた）。呼び出し元が解決済みの絶対
# パスを渡せるようにし、無ければ通常どおり PATH から探す。
ANSIBLE_PLAYBOOK_BIN="${STORAGE_GUARD_ANSIBLE_PLAYBOOK:-ansible-playbook}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
RUN_DATE="$(date -u '+%Y-%m-%d')"
EVIDENCE_DIR="${STORAGE_GUARD_EVIDENCE_DIR:-${REPO_ROOT}/docs/drills/logs}"
EVIDENCE_FILE="${EVIDENCE_DIR}/${RUN_DATE}-B-1-guard.md"
declare -a RESULT_ROWS=()

# device-mapper が無いと LVM 操作そのものが行えない。case 7（正常系）は
# そこへ到達するので、無い環境では実行せず SKIP-ENV として記録する。
has_device_mapper() {
  [[ -c /dev/mapper/control ]] && command -v dmsetup >/dev/null 2>&1
}

log()  { printf '\n--- %s ---\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail "loop device を扱うため root で実行する"
command -v losetup >/dev/null 2>&1 || fail "losetup が無い"
command -v "$ANSIBLE_PLAYBOOK_BIN" >/dev/null 2>&1 || fail "ansible-playbook が無い"

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
    "$ANSIBLE_PLAYBOOK_BIN" -i "$inventory" "${REPO_ROOT}/ansible/playbooks/storage.yml" 2>&1)"
  rc=$?
  set -e

  log "$title"
  local case_id="${title%%:*}" case_title="${title#*: }" expected observed verdict
  case "$expectation" in
    refuse)
      expected="安全装置が LVM 操作の手前で止める"
      if [[ $rc -ne 0 ]] && grep -qE 'Refusing to use|Invalid storage volume definition' <<<"$output"; then
        if grep -qE 'Ensure the volume group exists.*changed' <<<"$output"; then
          echo "NG: 止めたが VG を作成していた"
          observed="止めたが VG を作成していた"; verdict=FAIL
        else
          echo "OK: 安全装置が LVM 操作の手前で止めた"
          observed="rc=${rc} で LVM 操作の手前で停止"; verdict=PASS
        fi
      else
        echo "NG: 止まらなかった (rc=${rc})"
        sed -n '/TASK/,$p' <<<"$output" | tail -15
        observed="止まらなかった (rc=${rc})"; verdict=FAIL
      fi
      ;;
    pass_guard)
      # ガード文言が出ないことだけでは「通過した」証明にならない。
      # 別の理由で play が落ちていても同じ見え方になるため、
      # 終了コードそのものを見る。
      expected="安全装置を通過し rc=0"
      if grep -qE 'Refusing to use|Invalid storage volume definition' <<<"$output"; then
        echo "NG: 正常な入力なのに安全装置が止めた"
        sed -n '/TASK/,$p' <<<"$output" | tail -15
        observed="正常な入力なのに安全装置が止めた"; verdict=FAIL
      elif [[ $rc -ne 0 ]]; then
        echo "NG: 安全装置ではない理由で play が失敗した (rc=${rc})"
        sed -n '/TASK/,$p' <<<"$output" | tail -15
        observed="安全装置ではない理由で失敗 (rc=${rc})"; verdict=FAIL
      else
        echo "OK: 安全装置を通過し、LVM 操作まで到達した (rc=0)"
        observed="通過し LVM 操作まで到達 (rc=0)"; verdict=PASS
      fi
      ;;
  esac
  RESULT_ROWS+=("| ${case_id} | ${case_title} | ${expected} | ${observed} | ${verdict} |")
  if [[ "$verdict" == PASS ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
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

if ! has_device_mapper; then
  echo
  echo "--- case 7: 空の loop device を明示的に許可（正常系） ---"
  echo "SKIP-ENV: device-mapper が無いため LVM 操作へ到達できない。PASS には数えない。"
  SKIP_COUNT=$((SKIP_COUNT + 1))
  RESULT_ROWS+=("| case 7 | 空の loop device を明示的に許可（正常系） | 安全装置を通過し rc=0 | device-mapper が無く実行不能 | SKIP-ENV |")
else
run_case "case 7: 空の loop device を明示的に許可（正常系）" pass_guard \
"        - vg: vg_guard
          devices:
            - ${BLANK_DEVICE}
          lv: lv_guard
          fstype: ext4
          mount: /mnt/guard" \
"      storage_allow_loop_devices: true"
fi

printf '\n========================================\n'
printf 'storage role 安全装置テスト: %d PASS / %d FAIL / %d SKIP-ENV\n' \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
printf '========================================\n'

# 実行結果から証跡を生成する。手で PASS を書き込む余地を残さないため、
# 判定行は run_case が積んだものだけを出力する。
mkdir -p "$EVIDENCE_DIR"
{
  cat <<EVIDENCE_HEAD
# B-1 補足: storage role 安全装置 negative test — ${RUN_DATE}

> このファイルは \`scripts/labs/storage-guard-test.sh\` が実行結果から生成した。
> 判定は script が実測値と期待値を比較した結果で、手で書き換えていない。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| 実施環境 | $(uname -srm) |
| 実行ホスト | $(id -un 2>/dev/null || echo unknown) @ $(hostname 2>/dev/null || echo unknown) |
| 実行者 | ${DRILL_OPERATOR:-未設定（DRILL_OPERATOR 環境変数で指定する）} |
| commit SHA | $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown) |
| device-mapper | $(has_device_mapper && echo あり || echo なし) |

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
EVIDENCE_HEAD
  printf '%s\n' "${RESULT_ROWS[@]}"
  cat <<EVIDENCE_TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL / ${SKIP_COUNT} SKIP-ENV

> SKIP-ENV は「この環境で確認できなかった」であり、合格ではありません。
EVIDENCE_TAIL
} > "$EVIDENCE_FILE"
printf '証跡: %s\n' "$EVIDENCE_FILE"

[[ $FAIL_COUNT -eq 0 ]]
