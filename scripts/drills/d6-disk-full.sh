#!/usr/bin/env bash
# D-6: ディスク逼迫（disk full）→ 検知・復旧演習
#
# 目的:
#   ディスクの空き容量が減ったときに、しきい値の判定が「超過」を検知できるか、
#   そして runbook (docs/runbooks/disk-full.md) の手順どおりに
#   不要データを削除して復旧できるかを、実際に手を動かして確かめる。
#
# 使い方:
#   scripts/drills/d6-disk-full.sh --dry-run --target-dir ./perf-results/disk-drill
#   scripts/drills/d6-disk-full.sh [--target-dir DIR] [--max-fill-mb 512]
#                                  [--keep-free-mb 1024] [--threshold 85]
#                                  [--timeout 120] [--project-dir DIR]
#   scripts/drills/d6-disk-full.sh --rollback
#
# 出力:
#   人間向けサマリーを stdout、機械可読 JSON を最終行に "RESULT_JSON=" で出力。
#
# この演習で分かること:
#   - 作業用ディレクトリを意図的に埋めたとき、しきい値判定
#     (scripts/ops/df-over-threshold.awk) が「超過」を検知できるか。
#   - 検知してから、埋めたファイルを消して使用率が戻るまで何秒かかるか
#     （RTO = Recovery Time Objective / 復旧までの所要時間）。
#   - runbook が、読みながらそのまま辿れる粒度になっているか。
#
# この演習で分からないこと:
#   - 本番のディスクが本当に 100% になったときの挙動。この演習は
#     「専用の作業用ディレクトリを一定量だけ埋める」ものであり、
#     ファイルシステム全体を枯渇させるものではない。
#   - ログローテーション設定や Docker ボリュームの肥大など、
#     実運用で容量を食う原因そのものの妥当性。
#   - Prometheus / Alertmanager が実際に発報し通知先まで届くかどうか。
#     ここで確認するのは、しきい値の判定ロジックだけ。
#
# 安全装置（このスクリプトが必ず守る 6 点）:
#   (1) 対象パスを絶対パスへ正規化する            → normalize_path()
#   (2) / , /home , /var , $HOME そのものを拒否し、既定ではリポジトリ配下に限る
#                                                  → assert_not_forbidden()
#   (3) 対象が存在しなければ作る                   → prepare_target_dir()
#   (4) 既存ファイルがあるディレクトリを拒否する   → prepare_target_dir()
#   (5) 埋めるサイズを --max-fill-mb で制限する    → compute_fill_mb()
#   (6) 埋めた後も --keep-free-mb の余白を残す     → compute_fill_mb()
#
# 状態:
#   このスクリプトは「実装済み（未実施 / NOT RUN）」。
#   実行して初めて数値が出る。実行していない数値を記録に書かないこと。

set -euo pipefail

DRILL_ID="D-6"
DRILL_TITLE="ディスク逼迫（disk full）→ 検知・復旧演習"
RUNBOOK_PATH="docs/runbooks/disk-full.md"

TARGET_DIR="./perf-results/disk-drill"
MAX_FILL_MB=512
KEEP_FREE_MB=1024
THRESHOLD_PERCENT=85
TIMEOUT_SECONDS=120
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOW_OUTSIDE_REPO=0
# JSON に出すときは true / false の文字列にする（数値 0/1 だと真偽値として読めないため）
allow_outside_json() { [[ "$ALLOW_OUTSIDE_REPO" -eq 1 ]] && printf true || printf false; }
DRY_RUN=0
ROLLBACK_ONLY=0

FILL_BASENAME="d3-fill.bin"
TARGET_ABS=""
FILL_FILE=""
TARGET_CREATED=0
CLEANUP_DONE=0

usage() {
  cat <<EOF
Usage: $0 [--target-dir DIR] [--max-fill-mb N] [--keep-free-mb N]
          [--threshold N] [--timeout SECONDS] [--project-dir DIR]
          [--dry-run] [--rollback] [--help]

D-6: ディスク逼迫演習。リポジトリ配下の専用ディレクトリだけを一定量まで埋め、
しきい値の検知と runbook どおりの復旧（不要ファイルの削除）を秒単位で計測する。

  --target-dir    埋める対象ディレクトリ (default: ./perf-results/disk-drill)
                  / , /home , /var , HOME ディレクトリそのものは拒否する。
                  既にファイルがあるディレクトリも拒否する。
  --max-fill-mb   埋めるサイズの上限 MiB (default: 512)
  --keep-free-mb  埋めた後に必ず残す空き容量 MiB (default: 1024)
  --allow-outside-repo
                  リポジトリの外のディレクトリを対象にすることを明示的に許可する。
                  既定では拒否する（列挙式の禁止リストだけでは漏れるため）。
                  別ディスクで測る場合にだけ使い、指定したことは記録に残る。
  --threshold     使用率のしきい値 % (default: 85 — runbook の発火条件と同じ)
  --timeout       復旧完了を待つ上限秒 (default: 120)
  --project-dir   リポジトリのルート (default: このスクリプトの 2 つ上)
  --dry-run       実際には埋めず、何をするかだけ表示する
  --rollback      後始末（埋めたファイルの削除）だけを実行する
  --help          このヘルプ

結果コード:
  PASS      … 検知でき、かつ復旧を確認できた
  FAIL      … 制限時間内に使用率がしきい値を下回らなかった
  SKIP-ENV  … この環境ではしきい値まで埋められず、演習が成立しなかった
              （ディスクに余裕がありすぎる場合など）

関連 runbook: $RUNBOOK_PATH
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

now_epoch() {
  date -u +%s
}

iso_of() {
  date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'
}

# ---------------------------------------------------------------------------
# 安全装置 (1): 対象パスを絶対パスへ正規化する。
# 相対パスはリポジトリのルート基準で解決し、"." と ".." を必ず解決してから
# 安全装置 (2) の判定にかける。これをしないと
# `--target-dir ./perf-results/../../../` のような指定が /home を指してしまい、
# 保護パスの判定をすり抜ける。存在しないパスでも解決できる必要がある。
# ---------------------------------------------------------------------------
normalize_path() {
  local raw="$1"

  if [[ "$raw" != /* ]]; then
    raw="${PROJECT_DIR%/}/${raw#./}"
  fi

  # GNU coreutils があれば realpath -m に任せる（存在しないパスも解決でき、
  # 途中に symlink があればそれも辿る）。
  if command -v realpath >/dev/null 2>&1; then
    local resolved
    if resolved="$(realpath -m -- "$raw" 2>/dev/null)" && [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  # realpath が無い環境向けの、シェルだけで行う字句的な正規化。
  local part
  local -a stack=()
  local IFS='/'
  # shellcheck disable=SC2206  # IFS='/' で分割したいので意図的にクォートしない
  local -a parts=( $raw )
  for part in "${parts[@]}"; do
    case "$part" in
      ''|'.') ;;
      '..')   [[ ${#stack[@]} -gt 0 ]] && unset 'stack[-1]' && stack=( "${stack[@]}" ) ;;
      *)      stack+=( "$part" ) ;;
    esac
  done
  if [[ ${#stack[@]} -eq 0 ]]; then
    printf '/\n'
  else
    printf '/%s\n' "${stack[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 安全装置 (2): 絶対に埋めてはいけないパスを拒否する。
# / , /home , /var , HOME ディレクトリそのもの、その他の system directory、
# リポジトリのルートそのもの、ルート直下（/foo）を拒否する。
# ---------------------------------------------------------------------------
assert_not_forbidden() {
  local path="$1"
  local stripped="${path%/}"
  [[ -n "$stripped" ]] || stripped="/"

  local forbidden=(
    "/" "/home" "/var" "/usr" "/etc" "/boot" "/root"
    "/tmp" "/opt" "/srv" "/dev" "/proc" "/sys" "/mnt" "/media"
  )
  local home_stripped="${HOME%/}"
  [[ -n "$home_stripped" ]] && forbidden+=("$home_stripped")
  forbidden+=("${PROJECT_DIR%/}")

  local f
  for f in "${forbidden[@]}"; do
    if [[ "$stripped" == "$f" ]]; then
      die "安全装置(2): 対象ディレクトリ '$path' は保護対象のため使えない。リポジトリ配下の作業用ディレクトリ（例: ./perf-results/disk-drill）を指定すること。"
    fi
  done

  if [[ "$stripped" =~ ^/[^/]+$ ]]; then
    die "安全装置(2): 対象ディレクトリ '$path' はルート直下のため使えない。リポジトリ配下の作業用ディレクトリを指定すること。"
  fi

  # 既定では「リポジトリ配下であること」を必須にする。
  # 禁止リストは列挙式なので、リストに無い場所（/data, /mnt2, 誰かのプロジェクト
  # ディレクトリなど）は素通りしてしまう。列挙の漏れに依存せず、
  # 「安全と分かっている範囲の中だけ」を許す形にする。
  #
  # 別ディスクで測りたい場合は --allow-outside-repo を明示的に付ける。
  # 付けたことは実行ログと RESULT_JSON に残る。
  if [[ "$ALLOW_OUTSIDE_REPO" -eq 0 ]]; then
    local project_prefix="${PROJECT_DIR%/}/"
    if [[ "$stripped" != "${project_prefix}"* ]]; then
      die "安全装置(2): 対象ディレクトリ '$path' はリポジトリ (${PROJECT_DIR}) の外にある。意図的に外で測る場合は --allow-outside-repo を付けること。"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 安全装置 (3): 対象が存在しなければ作る（既存の大事なディレクトリを流用しない）。
# 安全装置 (4): 既存ファイルがあるディレクトリを拒否する（他人の資産を消さない）。
#               ただし前回の演習が残した埋め込みファイル (d3-fill.bin) は例外。
# ---------------------------------------------------------------------------
prepare_target_dir() {
  local path="$1"
  local existing

  if [[ -e "$path" && ! -d "$path" ]]; then
    die "安全装置(3): '$path' はディレクトリではない。"
  fi

  if [[ ! -d "$path" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "[dry-run] 安全装置(3): 対象ディレクトリを作成する予定: $path"
      return 0
    fi
    mkdir -p "$path"
    TARGET_CREATED=1
    log "安全装置(3): 対象ディレクトリを作成した: $path"
    return 0
  fi

  existing="$(find "$path" -mindepth 1 -maxdepth 1 ! -name "$FILL_BASENAME" -print -quit 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    die "安全装置(4): 対象ディレクトリ '$path' には既にファイルやディレクトリがある（例: $existing）。空のディレクトリを指定すること。"
  fi
}

# ---------------------------------------------------------------------------
# 安全装置 (5): 埋めるサイズを --max-fill-mb 以下に制限する。
# 安全装置 (6): 空き容量を確認し、埋めた後も --keep-free-mb の余白を残す。
# ---------------------------------------------------------------------------
compute_fill_mb() {
  local path="$1"
  local avail allowed fill

  avail="$(df -Pm "$(nearest_existing_dir "$path")" | awk 'NR==2 {print $4}')"
  [[ "$avail" =~ ^[0-9]+$ ]] || die "空き容量を取得できなかった: $path"
  AVAIL_MB="$avail"

  # (6) 埋めた後も KEEP_FREE_MB は必ず残す。
  allowed=$(( avail - KEEP_FREE_MB ))
  if (( allowed <= 0 )); then
    die "安全装置(6): 空きが ${avail} MiB しかなく、残すべき余白 ${KEEP_FREE_MB} MiB を確保できない。--keep-free-mb を見直すか、別のディスクで実施すること。"
  fi

  # (5) 上限 MAX_FILL_MB を超えない。
  fill="$allowed"
  if (( fill > MAX_FILL_MB )); then
    fill="$MAX_FILL_MB"
  fi
  if (( fill <= 0 )); then
    die "安全装置(5): 埋めるサイズが 0 MiB 以下になった。--max-fill-mb / --keep-free-mb を見直すこと。"
  fi

  FILL_MB="$fill"
}

# ---------------------------------------------------------------------------
# 後始末。trap から必ず呼ばれる。壊したまま終わらない。
# ---------------------------------------------------------------------------
cleanup() {
  local rc=$?
  if [[ "$CLEANUP_DONE" -eq 1 ]]; then
    return "$rc"
  fi
  CLEANUP_DONE=1

  if [[ -n "$FILL_FILE" && -f "$FILL_FILE" ]]; then
    if rm -f "$FILL_FILE"; then
      log "後始末: 埋めたファイルを削除した: $FILL_FILE"
    fi
  fi
  if [[ "$TARGET_CREATED" -eq 1 && -d "$TARGET_ABS" ]]; then
    if rmdir "$TARGET_ABS" 2>/dev/null; then
      log "後始末: 作成したディレクトリを削除した: $TARGET_ABS"
    fi
  fi
  return "$rc"
}

usage_percent() {
  df -P "$(nearest_existing_dir "$1")" | awk 'NR==2 {gsub("%","",$5); print $5}'
}

# df は存在するパスしか見られないため、対象がまだ無い場合は
# 一番近い既存の祖先ディレクトリまで遡る（同じファイルシステム上にある）。
nearest_existing_dir() {
  local p="$1"
  while [[ -n "$p" && ! -d "$p" ]]; do
    local parent
    parent="$(dirname "$p")"
    [[ "$parent" == "$p" ]] && break
    p="$parent"
  done
  printf '%s\n' "${p:-/}"
}

# scripts/ops/df-over-threshold.awk は `df --output=pcent,target` を読む前提。
# GNU df が無い環境では内蔵判定（df -P + awk）にフォールバックする。
threshold_check() {
  local path="$1"
  local threshold="$2"
  local awk_script="${PROJECT_DIR%/}/scripts/ops/df-over-threshold.awk"
  local out pct

  path="$(nearest_existing_dir "$path")"
  if [[ -f "$awk_script" ]] && df --output=pcent,target "$path" >/dev/null 2>&1; then
    DETECTOR="scripts/ops/df-over-threshold.awk"
    out="$(df --output=pcent,target "$path" | awk -v threshold="$threshold" -f "$awk_script" || true)"
    DETECTOR_OUTPUT="${out:-（しきい値超過なし）}"
    [[ -n "$out" ]] && return 0
    return 1
  fi

  DETECTOR="内蔵判定 (df -P + awk)"
  pct="$(usage_percent "$path")"
  DETECTOR_OUTPUT="usage=${pct}% threshold=${threshold}%"
  if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct > threshold )); then
    return 0
  fi
  return 1
}

# --- 引数処理 ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir)    [[ $# -ge 2 ]] || die "--target-dir に値がない";    TARGET_DIR="$2"; shift 2 ;;
    --target-dir=*)  TARGET_DIR="${1#*=}"; shift ;;
    --max-fill-mb)   [[ $# -ge 2 ]] || die "--max-fill-mb に値がない";   MAX_FILL_MB="$2"; shift 2 ;;
    --max-fill-mb=*) MAX_FILL_MB="${1#*=}"; shift ;;
    --keep-free-mb)  [[ $# -ge 2 ]] || die "--keep-free-mb に値がない";  KEEP_FREE_MB="$2"; shift 2 ;;
    --keep-free-mb=*) KEEP_FREE_MB="${1#*=}"; shift ;;
    --threshold)     [[ $# -ge 2 ]] || die "--threshold に値がない";     THRESHOLD_PERCENT="$2"; shift 2 ;;
    --threshold=*)   THRESHOLD_PERCENT="${1#*=}"; shift ;;
    --timeout)       [[ $# -ge 2 ]] || die "--timeout に値がない";       TIMEOUT_SECONDS="$2"; shift 2 ;;
    --timeout=*)     TIMEOUT_SECONDS="${1#*=}"; shift ;;
    --allow-outside-repo) ALLOW_OUTSIDE_REPO=1; shift ;;
    --project-dir)   [[ $# -ge 2 ]] || die "--project-dir に値がない";   PROJECT_DIR="$2"; shift 2 ;;
    --project-dir=*) PROJECT_DIR="${1#*=}"; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --rollback)      ROLLBACK_ONLY=1; shift ;;
    --help|-h)       usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for v in MAX_FILL_MB KEEP_FREE_MB THRESHOLD_PERCENT TIMEOUT_SECONDS; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || die "$v は 0 以上の整数で指定すること（現在: ${!v}）"
done
[[ -d "$PROJECT_DIR" ]] || die "--project-dir が存在しない: $PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

AVAIL_MB=0
FILL_MB=0
DETECTOR=""
DETECTOR_OUTPUT=""

# 安全装置 (1) → (2) は、何かを書き込む前に必ず通す。
TARGET_ABS="$(normalize_path "$TARGET_DIR")"
assert_not_forbidden "$TARGET_ABS"
FILL_FILE="${TARGET_ABS%/}/${FILL_BASENAME}"

# EXIT では後始末だけを行う。INT / TERM では後始末をしたうえで必ず終了する。
# cleanup は値を返すだけなので、INT / TERM にそのまま仕掛けると Ctrl+C を押しても
# 本体が走り続け、「中断したのに完走したかのようなサマリー」が出てしまう。
# 演習記録で最もやってはいけないことなので、ここでは明示的に exit する。
trap cleanup EXIT
trap 'cleanup || true; exit 130' INT
trap 'cleanup || true; exit 143' TERM

# --- --rollback: 後始末だけ --------------------------------------------------
if [[ "$ROLLBACK_ONLY" -eq 1 ]]; then
  log "後始末のみを実行する (--rollback)"
  REMOVED=false
  if [[ -f "$FILL_FILE" ]]; then
    rm -f "$FILL_FILE"
    REMOVED=true
    log "削除した: $FILL_FILE"
  else
    log "削除対象はなかった: $FILL_FILE"
  fi
  if [[ -d "$TARGET_ABS" ]]; then
    if rmdir "$TARGET_ABS" 2>/dev/null; then
      log "空になったディレクトリを削除した: $TARGET_ABS"
    fi
  fi
  CLEANUP_DONE=1

  cat <<SUMMARY

================ $DRILL_ID rollback summary ================
target_dir        : $TARGET_ABS
fill_file         : $FILL_FILE
removed           : $REMOVED
runbook           : $RUNBOOK_PATH
============================================================
SUMMARY

  printf 'RESULT_JSON={"drill":"%s","mode":"rollback","verdict":"OK","target_dir":"%s","removed":%s,"allow_outside_repo":%s,"runbook":"%s","at":"%s"}\n' \
    "$DRILL_ID" "$TARGET_ABS" "$REMOVED" "$(allow_outside_json)" "$RUNBOOK_PATH" "$(iso_of "$(now_epoch)")"
  exit 0
fi

# --- --dry-run: 説明だけ -----------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  prepare_target_dir "$TARGET_ABS"
  compute_fill_mb "$TARGET_ABS"

  FILL_TOOL_PLAN="dd (fallocate が無いため)"
  if command -v fallocate >/dev/null 2>&1; then
    FILL_TOOL_PLAN="fallocate"
  fi

  if [[ -d "$TARGET_ABS" ]]; then
    TARGET_STATE="既にある"
  else
    TARGET_STATE="実行時に作成する"
  fi
  USAGE_NOW="$(usage_percent "$TARGET_ABS")"

  cat <<SUMMARY

================ $DRILL_ID dry-run ================
実際には 1 バイトも書き込まない。

安全装置の確認結果:
  (1) 絶対パスへの正規化 : $TARGET_ABS
  (2) 保護パスの拒否     : OK（ルート・home・var・HOME ディレクトリではない）
  (3) 対象が無ければ作成 : $TARGET_STATE
  (4) 既存ファイルの拒否 : OK（空、または未作成）
  (5) 埋める上限         : ${MAX_FILL_MB} MiB (--max-fill-mb)
  (6) 残す余白           : ${KEEP_FREE_MB} MiB (--keep-free-mb)

実行したときの動作:
  1. $TARGET_ABS に ${FILL_MB} MiB のファイル ($FILL_BASENAME) を作る
     使う道具: $FILL_TOOL_PLAN
  2. しきい値 ${THRESHOLD_PERCENT}% を超えたかを判定する
     判定に使う: scripts/ops/df-over-threshold.awk
  3. $RUNBOOK_PATH の「復旧操作」に従い、不要ファイルを削除する
  4. 使用率がしきい値を下回るまでの時間 (RTO) を計測する（上限 ${TIMEOUT_SECONDS} 秒）
  5. trap により、埋めたファイルは何があっても削除する

現在の状況:
  空き容量          : ${AVAIL_MB} MiB
  埋める予定        : ${FILL_MB} MiB
  埋めた後の空き    : 約 $(( AVAIL_MB - FILL_MB )) MiB
  現在の使用率      : ${USAGE_NOW}%
  runbook           : $RUNBOOK_PATH
===================================================
SUMMARY

  printf 'RESULT_JSON={"drill":"%s","mode":"dry-run","verdict":"DRY-RUN","target_dir":"%s","avail_mb":%s,"planned_fill_mb":%s,"max_fill_mb":%s,"keep_free_mb":%s,"threshold_percent":%s,"allow_outside_repo":%s,"runbook":"%s","at":"%s"}\n' \
    "$DRILL_ID" "$TARGET_ABS" "$AVAIL_MB" "$FILL_MB" "$MAX_FILL_MB" "$KEEP_FREE_MB" \
    "$THRESHOLD_PERCENT" "$(allow_outside_json)" "$RUNBOOK_PATH" "$(iso_of "$(now_epoch)")"
  exit 0
fi

# --- 本番実行 ---------------------------------------------------------------
log "$DRILL_ID 開始: $DRILL_TITLE"
log "runbook: $RUNBOOK_PATH"

prepare_target_dir "$TARGET_ABS"
compute_fill_mb "$TARGET_ABS"

USAGE_BEFORE="$(usage_percent "$TARGET_ABS")"
log "開始時: 使用率 ${USAGE_BEFORE}% / 空き ${AVAIL_MB} MiB"
log "これから ${FILL_MB} MiB を ${FILL_FILE} に書き込む（上限 ${MAX_FILL_MB} MiB / 余白 ${KEEP_FREE_MB} MiB を確保）"

# 1. 障害発生: 作業用ディレクトリだけを埋める
FILL_TOOL="dd"
FILL_START_EPOCH="$(now_epoch)"
if command -v fallocate >/dev/null 2>&1 && fallocate -l "${FILL_MB}M" "$FILL_FILE" 2>/dev/null; then
  FILL_TOOL="fallocate"
else
  rm -f "$FILL_FILE"
  dd if=/dev/zero of="$FILL_FILE" bs=1M count="$FILL_MB" status=none
fi
sync 2>/dev/null || true
log "書き込み完了: ${FILL_TOOL} / $(( $(now_epoch) - FILL_START_EPOCH )) 秒"

USAGE_FILLED="$(usage_percent "$TARGET_ABS")"
log "書き込み後: 使用率 ${USAGE_FILLED}%"

# 2. 検知
DETECT_EPOCH="$(now_epoch)"
if threshold_check "$TARGET_ABS" "$THRESHOLD_PERCENT"; then
  DETECTED=1
  log "検知: しきい値 ${THRESHOLD_PERCENT}% を超えた（判定: ${DETECTOR}）"
else
  DETECTED=0
  log "検知なし: 使用率 ${USAGE_FILLED}% はしきい値 ${THRESHOLD_PERCENT}% を超えていない（判定: ${DETECTOR}）"
  log "この環境はディスクに余裕があり、${MAX_FILL_MB} MiB ではしきい値に届かなかった。"
fi
log "判定の出力: ${DETECTOR_OUTPUT}"

# 3. 復旧: runbook「復旧操作」の手順 = 不要データを削除し df で確認する
RECOVERY_START_EPOCH="$(now_epoch)"
log "復旧開始: ${RUNBOOK_PATH} の『復旧操作』に従い、不要ファイルを削除する"
rm -f "$FILL_FILE"
sync 2>/dev/null || true

RECOVERY_END_EPOCH=0
RECOVERED=0
DEADLINE=$(( RECOVERY_START_EPOCH + TIMEOUT_SECONDS ))
while :; do
  PCT="$(usage_percent "$TARGET_ABS")"
  if [[ "$PCT" =~ ^[0-9]+$ ]] && (( PCT <= THRESHOLD_PERCENT )); then
    RECOVERED=1
    RECOVERY_END_EPOCH="$(now_epoch)"
    break
  fi
  if (( $(now_epoch) >= DEADLINE )); then
    RECOVERY_END_EPOCH="$(now_epoch)"
    log "タイムアウト: ${TIMEOUT_SECONDS} 秒以内に使用率が下がらなかった"
    break
  fi
  sleep 1
done
RTO_SECONDS=$(( RECOVERY_END_EPOCH - RECOVERY_START_EPOCH ))
USAGE_AFTER="$(usage_percent "$TARGET_ABS")"

# 4. 評価
if (( DETECTED == 1 && RECOVERED == 1 )); then
  VERDICT="PASS"
elif (( DETECTED == 0 && RECOVERED == 1 )); then
  # 埋めてもしきい値に届かなかった＝演習の条件を作れていない。
  # 「成功」ではなく「実施できなかった」として明示的に区別する。
  VERDICT="SKIP-ENV"
else
  VERDICT="FAIL"
fi
log "復旧完了: verdict=${VERDICT} / RTO ${RTO_SECONDS} 秒 / 使用率 ${USAGE_AFTER}%"

cleanup || true
CLEANUP_DONE=1

# 5. サマリー
cat <<SUMMARY

================ $DRILL_ID drill summary ================
target_dir         : $TARGET_ABS
fill_mb            : $FILL_MB (tool: $FILL_TOOL)
max_fill_mb        : $MAX_FILL_MB
keep_free_mb       : $KEEP_FREE_MB
threshold_percent  : $THRESHOLD_PERCENT
usage_percent      : ${USAGE_BEFORE}% -> ${USAGE_FILLED}% -> ${USAGE_AFTER}%
detected           : $DETECTED ($DETECTOR)
detector_output    : $DETECTOR_OUTPUT
detect_at          : $(iso_of "$DETECT_EPOCH")
recovery_start_at  : $(iso_of "$RECOVERY_START_EPOCH")
recovery_end_at    : $(iso_of "$RECOVERY_END_EPOCH")
rto_seconds        : $RTO_SECONDS
verdict            : $VERDICT
runbook            : $RUNBOOK_PATH
=========================================================

補足:
- SKIP-ENV は「この環境では条件を作れなかった」という意味です。
  失敗ではありませんが、成功でもありません。記録にそのまま残してください。

次の手順:
1. このサマリーを Slack 演習チャンネルに貼る (docs/incident-comms.md)
2. docs/drill-template.md をコピーして docs/drills/logs/$(date -u +%Y-%m-%d)-D-3.md を作る
3. 発見事項と改善アクションを記入して PR

SUMMARY

printf 'RESULT_JSON={"drill":"%s","mode":"run","verdict":"%s","target_dir":"%s","fill_mb":%s,"fill_tool":"%s","max_fill_mb":%s,"keep_free_mb":%s,"threshold_percent":%s,"usage_before_percent":"%s","usage_filled_percent":"%s","usage_after_percent":"%s","detected":%s,"detector":"%s","detect_at":"%s","recovery_start_at":"%s","recovery_end_at":"%s","rto_seconds":%s,"allow_outside_repo":%s,"runbook":"%s"}\n' \
  "$DRILL_ID" "$VERDICT" "$TARGET_ABS" "$FILL_MB" "$FILL_TOOL" "$MAX_FILL_MB" "$KEEP_FREE_MB" \
  "$THRESHOLD_PERCENT" "$USAGE_BEFORE" "$USAGE_FILLED" "$USAGE_AFTER" "$DETECTED" "$DETECTOR" \
  "$(iso_of "$DETECT_EPOCH")" "$(iso_of "$RECOVERY_START_EPOCH")" "$(iso_of "$RECOVERY_END_EPOCH")" \
  "$RTO_SECONDS" "$(allow_outside_json)" "$RUNBOOK_PATH"

[[ "$VERDICT" == "PASS" || "$VERDICT" == "SKIP-ENV" ]]
