#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# B-3: データベースのバックアップ・復元演習
#
# 「volume を tar で固めて展開できた」ではなく、
# 「論理バックアップから、失われた行を、時点を決めて戻せた」ことを実測する。
# 実務の復元試験はほぼこの形になる。
#
# 実行するもの:
#   1. 初期状態の件数を記録する
#   2. pg_dump で論理バックアップを取る（= 復旧目標時点 / RPO の基準）
#   3. バックアップ後に追加の書き込みを行う（= 失われる分）
#   4. 事故を再現する（テーブルを DROP する）
#   5. pg_restore で復元する
#   6. 件数・チェックサム・アプリからの見え方を突き合わせる
#   7. RTO（復旧所要時間）と RPO（失われたデータの時間幅）を実測する
#
#   ./run-restore-drill.sh
#
# 結果は docs/drills/logs/<date>-B-3.md に書き出す。
# ---------------------------------------------------------------------------
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LAB_DIR}/../.." && pwd)"
COMPOSE=(docker compose -f "${LAB_DIR}/compose.yaml")
BACKUP_DIR="${LAB_DIR}/.backups"
DB_NAME=inventory
DB_USER=app
EVIDENCE_DIR="${REPO_ROOT}/docs/drills/logs"
RUN_DATE="$(date -u '+%Y-%m-%d')"
EVIDENCE_FILE="${EVIDENCE_DIR}/${RUN_DATE}-B-3.md"

PASS_COUNT=0
FAIL_COUNT=0
declare -a RESULT_ROWS=()

log()  { printf '\n=== %s ===\n' "$*"; }
note() { printf '    %s\n' "$*"; }

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

psql_scalar() {
  "${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -tAc "$1" 2>/dev/null | tr -d ' \r\n'
}

# curl は接続失敗時にも "000" を出力したうえで非ゼロ終了する。
# `|| echo "000"` を付けると値が二重に出て "000000" になり、
# 後続の比較が「200 ではない」で通ってしまう（誤った理由での PASS）。
# 出力を採ってから、空のときだけ既定値を入れる。
http_status() {
  local code
  code="$("${COMPOSE[@]}" exec -T client \
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

wait_for_ready() {
  local remaining=40
  while (( remaining-- > 0 )); do
    [[ "$(http_status http://web/readyz)" == "200" ]] && return 0
    sleep 2
  done
  return 1
}

trap 'printf "\n演習が途中で終了した。後始末: docker compose -f %s down -v\n" "${LAB_DIR}/compose.yaml" >&2' ERR

log "0. 3 層スタックを起動する"
"${COMPOSE[@]}" up -d --build
wait_for_ready || { echo "起動に失敗した" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"

# --- 1. 初期状態 ----------------------------------------------------------
log "1. 初期状態を記録する"
ROWS_BEFORE="$(psql_scalar 'SELECT count(*) FROM items;')"
# 行の中身まで一致しているかを見るため、順序を固定した内容ハッシュを取る。
# 件数だけの一致は「行数は同じだが中身が違う」を見逃す。
CHECKSUM_BEFORE="$(psql_scalar "SELECT md5(string_agg(sku || ':' || name || ':' || quantity, ',' ORDER BY id)) FROM items;")"
note "件数=${ROWS_BEFORE} / 内容ハッシュ=${CHECKSUM_BEFORE}"

# --- 2. バックアップ ------------------------------------------------------
log "2. pg_dump で論理バックアップを取る"
BACKUP_AT_EPOCH="$(date -u +%s)"
BACKUP_AT="$(date -u '+%Y-%m-%d %H:%M:%S')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}-$(date -u '+%Y%m%dT%H%M%SZ').dump"
"${COMPOSE[@]}" exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" --format=custom > "$BACKUP_FILE"
BACKUP_BYTES="$(stat -c %s "$BACKUP_FILE")"
BACKUP_SHA="$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)"
note "バックアップ: ${BACKUP_FILE} (${BACKUP_BYTES} bytes)"
note "sha256=${BACKUP_SHA}"
if [[ "$BACKUP_BYTES" -gt 0 ]]; then
  record "B3-01" "論理バックアップの取得" "0 バイトでないダンプが作られる" "${BACKUP_BYTES} bytes" "PASS"
else
  record "B3-01" "論理バックアップの取得" "0 バイトでないダンプが作られる" "0 bytes" "FAIL"
fi

# --- 3. バックアップ後の書き込み ------------------------------------------
log "3. バックアップ後に追加の書き込みを行う（= 復元時に失われる分）"
sleep 2
"${COMPOSE[@]}" exec -T client curl -fsS --max-time 10 -X POST http://web/api/items \
  -H 'Content-Type: application/json' \
  -d '{"sku":"SKU-9001","name":"バックアップ後に追加した行","quantity":1}' >/dev/null
LAST_WRITE_EPOCH="$(date -u +%s)"
LAST_WRITE_AT="$(date -u '+%Y-%m-%d %H:%M:%S')"
ROWS_AFTER_WRITE="$(psql_scalar 'SELECT count(*) FROM items;')"
note "追加後の件数=${ROWS_AFTER_WRITE}"

# --- 4. 事故の再現 --------------------------------------------------------
log "4. 事故を再現する: items テーブルを DROP する"
INCIDENT_EPOCH="$(date -u +%s)"
INCIDENT_AT="$(date -u '+%Y-%m-%d %H:%M:%S')"
"${COMPOSE[@]}" exec -T db psql -U "$DB_USER" -d "$DB_NAME" -c 'DROP TABLE items;' >/dev/null
APP_STATUS_BROKEN="$(http_status http://web/)"
note "事故後のトップ画面 status=${APP_STATUS_BROKEN}"
if [[ "$APP_STATUS_BROKEN" != "200" ]]; then
  record "B3-02" "データ消失がアプリから観測できる" "トップ画面が 200 以外" "status=${APP_STATUS_BROKEN}" "PASS"
else
  record "B3-02" "データ消失がアプリから観測できる" "トップ画面が 200 以外" "status=200（消えていない）" "FAIL"
fi

# --- 5. 復元 --------------------------------------------------------------
log "5. pg_restore で復元する"
RESTORE_START_EPOCH="$(date -u +%s)"
# --clean --if-exists で、途中まで残った定義があっても決定的に戻す。
#
# pg_restore は無視した警告があると非ゼロで終了することがある
# ("warning: errors ignored on restore: N")。set -e のままだと演習全体が
# ERR trap で中断し、証跡が 1 行も残らない。復元の成否は後段の件数・
# 内容ハッシュ照合で判定するので、ここでは終了コードを控えるだけにする。
RESTORE_LOG="${BACKUP_DIR}/pg_restore.log"
set +e
"${COMPOSE[@]}" exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" \
  --clean --if-exists < "$BACKUP_FILE" >"$RESTORE_LOG" 2>&1
RESTORE_RC=$?
set -e
RESTORE_END_EPOCH="$(date -u +%s)"
if [[ $RESTORE_RC -ne 0 ]]; then
  note "pg_restore が rc=${RESTORE_RC} で終了した（後段の照合で成否を判定する）"
  tail -5 "$RESTORE_LOG" | sed 's/^/      /'
fi
RTO_SECONDS=$((RESTORE_END_EPOCH - RESTORE_START_EPOCH))
note "復元所要時間 (RTO) = ${RTO_SECONDS} 秒"

# --- 6. 突き合わせ --------------------------------------------------------
log "6. 件数・内容ハッシュ・アプリからの見え方を突き合わせる"
ROWS_RESTORED="$(psql_scalar 'SELECT count(*) FROM items;')"
CHECKSUM_RESTORED="$(psql_scalar "SELECT md5(string_agg(sku || ':' || name || ':' || quantity, ',' ORDER BY id)) FROM items;")"
note "復元後の件数=${ROWS_RESTORED} / 内容ハッシュ=${CHECKSUM_RESTORED}"

record "B3-02b" "復元コマンドの終了コード" "0" "rc=${RESTORE_RC}" \
  "$( [[ $RESTORE_RC -eq 0 ]] && echo PASS || echo FAIL )"

if [[ "$ROWS_RESTORED" == "$ROWS_BEFORE" ]]; then
  record "B3-03" "復元後の件数一致" "バックアップ時点の ${ROWS_BEFORE} 件" "${ROWS_RESTORED} 件" "PASS"
else
  record "B3-03" "復元後の件数一致" "バックアップ時点の ${ROWS_BEFORE} 件" "${ROWS_RESTORED} 件" "FAIL"
fi

if [[ "$CHECKSUM_RESTORED" == "$CHECKSUM_BEFORE" ]]; then
  record "B3-04" "復元後の内容一致" "内容ハッシュがバックアップ時点と一致" "一致 (${CHECKSUM_RESTORED})" "PASS"
else
  record "B3-04" "復元後の内容一致" "内容ハッシュがバックアップ時点と一致" \
    "不一致 (${CHECKSUM_BEFORE} -> ${CHECKSUM_RESTORED})" "FAIL"
fi

# バックアップ後に入れた行は復元されない = これが失われるデータ。
MISSING_ROW="$(psql_scalar "SELECT count(*) FROM items WHERE sku = 'SKU-9001';")"
if [[ "$MISSING_ROW" == "0" ]]; then
  record "B3-05" "RPO の範囲が想定どおり" "バックアップ後の行は戻らない" "SKU-9001 は 0 件（想定どおり失われた）" "PASS"
else
  record "B3-05" "RPO の範囲が想定どおり" "バックアップ後の行は戻らない" "SKU-9001 が ${MISSING_ROW} 件残った" "FAIL"
fi

if wait_for_ready; then
  APP_STATUS_RECOVERED="$(http_status http://web/)"
else
  APP_STATUS_RECOVERED="000"
fi
if [[ "$APP_STATUS_RECOVERED" == "200" ]]; then
  record "B3-06" "アプリから見た復旧" "トップ画面が 200 に戻る" "status=200" "PASS"
else
  record "B3-06" "アプリから見た復旧" "トップ画面が 200 に戻る" "status=${APP_STATUS_RECOVERED}" "FAIL"
fi

RPO_SECONDS=$((LAST_WRITE_EPOCH - BACKUP_AT_EPOCH))
DETECT_TO_RESTORE=$((RESTORE_END_EPOCH - INCIDENT_EPOCH))

# --- 証跡 -----------------------------------------------------------------
log "証跡を書き出す"
mkdir -p "$EVIDENCE_DIR"
{
  cat <<EVIDENCE_HEAD
# B-3 データベースのバックアップ・復元演習 — ${RUN_DATE}

> このファイルは \`labs/three-tier/run-restore-drill.sh\` が実行結果から生成した。
> 判定は script が実測値と期待値を比較した結果で、手で書き換えていない。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| 実施環境 | $(uname -srm) / Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown) |
| commit SHA | $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown) |
| DBMS | PostgreSQL 16 (compose の \`db\` サービス) |
| バックアップ方式 | \`pg_dump --format=custom\`（論理バックアップ） |
| 復元方式 | \`pg_restore --clean --if-exists\` |
| ダンプ sha256 | \`${BACKUP_SHA}\` |
| ダンプサイズ | ${BACKUP_BYTES} bytes |

## 時系列

| 時刻 (UTC) | 出来事 |
| --- | --- |
| ${BACKUP_AT} | \`pg_dump\` 取得（= 復旧できる時点） |
| ${LAST_WRITE_AT} | バックアップ後の書き込み（SKU-9001） |
| ${INCIDENT_AT} | 事故発生（\`DROP TABLE items\`） |
| $(date -u -d "@${RESTORE_START_EPOCH}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-') | \`pg_restore\` 開始 |
| $(date -u -d "@${RESTORE_END_EPOCH}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '-') | \`pg_restore\` 完了 |

## 実測した RTO / RPO

| 指標 | 実測値 | 定義 |
| --- | --- | --- |
| RTO（復元操作の所要時間） | ${RTO_SECONDS} 秒 | \`pg_restore\` の開始から完了まで |
| 事故から復元完了まで | ${DETECT_TO_RESTORE} 秒 | 手動での検知・判断時間を含まない下限値 |
| RPO（失われたデータの時間幅） | ${RPO_SECONDS} 秒 | 最後のバックアップから事故直前の書き込みまで |

> この RTO は「復元コマンドの実行時間」であり、検知・連絡・判断・
> 切り戻し可否の確認を含む実際の復旧時間ではない。
> RPO はこのラボの操作間隔に依存しており、運用設計上の目標値ではない。

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
EVIDENCE_HEAD
  printf '%s\n' "${RESULT_ROWS[@]}"
  cat <<EVIDENCE_TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL

## この演習で確認したこと

- 件数の一致だけでは「行数は同じだが中身が違う」を見逃す。
  順序を固定した内容ハッシュまで突き合わせて初めて、復元できたと言える。
- バックアップ後に入った行は戻らない。復元は「いつの時点に戻すか」を
  選ぶ操作であり、失われる範囲（RPO）を先に決めておく必要がある。
- DB を戻しただけでは終わらない。アプリ側から 200 が返ることまで
  確認して初めて復旧。

## この演習で確認していないこと

- PITR（Point-in-Time Recovery）は対象外。WAL アーカイブを使えば
  事故直前まで戻せるが、この演習は論理バックアップのみを扱う。
- 別ホストへの復元、レプリカからの昇格、フェイルオーバーは対象外。
- 大容量データでの所要時間は対象外（このラボは数行規模）。
- バックアップの遠隔地保管、暗号化、保存期間管理は対象外。

## 後始末

\`\`\`bash
docker compose -f labs/three-tier/compose.yaml down -v
rm -rf labs/three-tier/.backups
\`\`\`
EVIDENCE_TAIL
} > "$EVIDENCE_FILE"

trap - ERR
printf '\n証跡: %s\n' "$EVIDENCE_FILE"
printf '合計: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
