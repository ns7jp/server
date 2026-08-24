#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# B-2: 3 層構成の障害切り分け演習
#
# Web / AP / DB のどの層で止まっているかを、層ごとの health endpoint と
# 到達確認で 1 段ずつ絞り込む。3 種類の障害を注入し、
# 「利用者から見た症状は似ているが原因が違う」ことを実測で示す。
#
#   障害 A: DB プロセス停止        -> web 5xx / ap healthz 200 / ap readyz 503
#   障害 B: AP プロセス停止        -> web 502 / web-healthz 200
#   障害 C: AP を db-tier から切断  -> A と同じ症状だが原因が経路側
#
# A と C は利用者から見ると同じ「DB に繋がらない」だが、
# A は DB 側、C は経路側。区別できることがこの演習の目的。
#
#   ./run-drill.sh
#
# 結果は docs/drills/logs/<date>-B-2.md に書き出す。
# ---------------------------------------------------------------------------
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LAB_DIR}/../.." && pwd)"
COMPOSE=(docker compose -f "${LAB_DIR}/compose.yaml")
DB_NETWORK=server-monitor-3t-db
EVIDENCE_DIR="${REPO_ROOT}/docs/drills/logs"
RUN_DATE="$(date -u '+%Y-%m-%d')"
EVIDENCE_FILE="${EVIDENCE_DIR}/${RUN_DATE}-B-2.md"

PASS_COUNT=0
FAIL_COUNT=0
declare -a RESULT_ROWS=()

log()  { printf '\n=== %s ===\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# docker version は daemon へ繋がらないとき stdout へ空行を出したうえで非 0 で
# 終わる。`|| echo unknown` だけでは値が "空行 + unknown" の 2 行になり、
# markdown の表がその行で崩れて証跡が読めなくなる。必ず 1 行へ畳む。
docker_server_version() {
  local v
  v="$(docker version --format '{{.Server.Version}}' 2>/dev/null | tr -d '\n')" || true
  printf '%s' "${v:-unknown}"
}

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

# client から見た HTTP status を返す。到達できない場合は 000。
# curl は接続失敗時にも "000" を出力したうえで非ゼロ終了する。
# `|| echo "000"` を付けると値が二重に出て "000000" になり、
# 後続の比較が「200 ではない」で通ってしまう（誤った理由での PASS）。
# 出力を採ってから、空のときだけ既定値を入れる。
http_status() {
  local url="$1" code
  code="$("${COMPOSE[@]}" exec -T client \
    curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

# AP の health endpoint は web 経由で叩く（client は app-tier にいないため）。
ap_status() { http_status "http://web/$1"; }

wait_for_ready() {
  local remaining=40
  while (( remaining-- > 0 )); do
    if [[ "$(ap_status readyz)" == "200" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

cleanup_note() {
  printf '\n演習が途中で終了した。後始末:\n  %s down -v\n' "docker compose -f ${LAB_DIR}/compose.yaml" >&2
}
trap cleanup_note ERR

# --- 起動 -----------------------------------------------------------------
log "0. 3 層スタックを起動する"
"${COMPOSE[@]}" up -d --build
if ! wait_for_ready; then
  echo "起動後に readyz が 200 にならない。docker compose logs を確認する" >&2
  exit 1
fi
note "readyz=200 を確認"

# --- 1. 正常系 ------------------------------------------------------------
log "1. 正常系: client -> web -> ap -> db"
BASELINE_STATUS="$(http_status http://web/)"
BASELINE_COUNT="$("${COMPOSE[@]}" exec -T client curl -fsS --max-time 10 http://web/api/items/count 2>/dev/null | tr -d ' \n' || echo 'n/a')"
if [[ "$BASELINE_STATUS" == "200" ]]; then
  record "B2-01" "正常系の通し疎通" "HTTP 200 と件数取得" "status=${BASELINE_STATUS}, ${BASELINE_COUNT}" "PASS"
else
  record "B2-01" "正常系の通し疎通" "HTTP 200 と件数取得" "status=${BASELINE_STATUS}" "FAIL"
fi

# --- 2. 層の分離が実際に効いているか --------------------------------------
log "2. 層の分離: web から db へ直接届かないこと"
# 「設計上そうなっている」ではなく「実際に届かない」ことを確認する。
#
# 判定は fail-closed にする。到達できなかった理由が「遮断されている」なのか
# 「道具が無くて確かめられなかった」なのかを区別せずに PASS にすると、
# 遮断されていないのに PASS する偽陽性になる。
# netprobe-web は web と network namespace を共有しているので、
# ここからの到達性は web 自身からの到達性と同一。
#
# 遮断されていれば nc は非ゼロで終わる。それが期待どおりの結果なので、
# set -e に巻き込まれないよう一時的に外す。外さないと、代入文そのものが
# 非ゼロを返して次の行（isolation_rc=$?）へ到達する前に script が落ち、
# 下の fail-closed 判定が丸ごと死ぬ。
# しかも落ちるのは「遮断できている」= PASS のときなので、
# 分離が壊れている環境でしか演習が最後まで走らない、という逆の挙動になる。
# 失敗を承知で実行する箇所では、set +e だけでは足りない。
# bash は set +e でも ERR trap を実行するので、後始末を促す注意書きが
# 「正常に進んでいるのに中断したように見える」形で証跡と画面へ出てしまう。
# 意図した失敗の間は trap も外し、終わったら必ず張り直す。
trap - ERR
set +e
isolation_out="$("${COMPOSE[@]}" exec -T netprobe-web nc -z -w 3 db 5432 2>&1)"
isolation_rc=$?
set -e
trap cleanup_note ERR
if [[ $isolation_rc -eq 0 ]]; then
  record "B2-02" "web から db への直接到達を遮断" "接続できない" "接続できてしまった" "FAIL"
elif grep -qiE 'not found|no such file|unknown option|invalid option' <<<"$isolation_out"; then
  # 道具側の問題。遮断の証明になっていないので PASS にしない。
  record "B2-02" "web から db への直接到達を遮断" "接続できない" \
    "probe を実行できず検証不能: ${isolation_out%%$'\n'*}" "FAIL"
else
  record "B2-02" "web から db への直接到達を遮断" "接続できない" "接続不可を確認" "PASS"
fi
note "web が参加しているネットワーク:"
"${COMPOSE[@]}" exec -T netprobe-web ip -br addr | grep -v LOOPBACK || true

# --- 3. 障害 A: DB 停止 ---------------------------------------------------
log "3. 障害 A: DB プロセスを停止する"
"${COMPOSE[@]}" stop db >/dev/null
sleep 3
A_WEB_HEALTH="$(http_status http://web/web-healthz)"
A_AP_HEALTH="$(ap_status healthz)"
A_AP_READY="$(ap_status readyz)"
A_TOP="$(http_status http://web/)"
note "web-healthz=${A_WEB_HEALTH} / ap healthz=${A_AP_HEALTH} / ap readyz=${A_AP_READY} / トップ=${A_TOP}"
note "readyz が返した理由:"
"${COMPOSE[@]}" exec -T client curl -s --max-time 10 http://web/readyz 2>/dev/null || true
echo
if [[ "$A_WEB_HEALTH" == "200" && "$A_AP_HEALTH" == "200" && "$A_AP_READY" == "503" ]]; then
  record "B2-03" "DB 停止時に DB 層まで切り分けられる" "web 200 / ap healthz 200 / ap readyz 503" \
    "web-healthz=${A_WEB_HEALTH}, healthz=${A_AP_HEALTH}, readyz=${A_AP_READY}" "PASS"
else
  record "B2-03" "DB 停止時に DB 層まで切り分けられる" "web 200 / ap healthz 200 / ap readyz 503" \
    "web-healthz=${A_WEB_HEALTH}, healthz=${A_AP_HEALTH}, readyz=${A_AP_READY}" "FAIL"
fi

log "4. 障害 A から復旧する"
"${COMPOSE[@]}" start db >/dev/null
if wait_for_ready; then
  record "B2-04" "DB 復帰後の自動回復" "readyz が 200 に戻る" "readyz=200" "PASS"
else
  record "B2-04" "DB 復帰後の自動回復" "readyz が 200 に戻る" "200 に戻らない" "FAIL"
fi

# --- 5. 障害 B: AP 停止 ---------------------------------------------------
# AP が落ちたときに web が返す code は、止めてから何秒後に見たかで変わる。
# nginx.conf の `resolver 127.0.0.11 valid=10s` が効いている間は、消えた
# コンテナの IP がまだキャッシュに残っているので、そこへ繋ぎに行って
# proxy_connect_timeout で 504 になる。キャッシュが切れると名前解決自体が
# 失敗して 502 になる。実測した遷移:
#
#   t=3s, 6s -> 504   ("upstream timed out")
#   t>=7s    -> 502   ("ap could not be resolved (3: Host not found)")
#
# どちらも「web は生きていて、その先が死んでいる」を示すが、示している
# 中身が違う。504 は「名前は引けるが応答が無い」= プロセス側、502 は
# 「名前が引けない」= サービス登録 / DNS 側。切り分けではこの差が効くので、
# 両方の窓を別々の試験として観測する。
log "5. 障害 B: AP プロセスを停止する"
"${COMPOSE[@]}" stop ap >/dev/null
sleep 3
B_WEB_HEALTH="$(http_status http://web/web-healthz)"
B_TOP="$(http_status http://web/)"
note "web-healthz=${B_WEB_HEALTH} / トップ=${B_TOP}（resolver のキャッシュが有効な間）"
if [[ "$B_WEB_HEALTH" == "200" && "$B_TOP" == "504" ]]; then
  record "B2-05" "AP 停止直後は上流無応答として現れる" "web-healthz 200 / トップ 504" \
    "web-healthz=${B_WEB_HEALTH}, トップ=${B_TOP}" "PASS"
else
  record "B2-05" "AP 停止直後は上流無応答として現れる" "web-healthz 200 / トップ 504" \
    "web-healthz=${B_WEB_HEALTH}, トップ=${B_TOP}" "FAIL"
fi

# resolver の valid=10s を跨ぐまで待つ。ここを跨ぐと症状が 504 から 502 へ
# 変わる。同じ障害でも観測した時刻で見え方が変わる、という実例。
note "resolver のキャッシュ（valid=10s）が切れるまで待つ"
sleep 10
B_TOP_AFTER="$(http_status http://web/)"
B_RESOLVE="$("${COMPOSE[@]}" exec -T netprobe-web sh -c 'getent hosts ap >/dev/null && echo 引ける || echo 引けない' 2>/dev/null | tr -d ' \r\n')"
note "トップ=${B_TOP_AFTER} / ap の名前解決=${B_RESOLVE}"
if [[ "$B_TOP_AFTER" == "502" && "$B_RESOLVE" == "引けない" ]]; then
  record "B2-05b" "キャッシュ失効後は名前解決の失敗として現れる" "トップ 502 / ap を引けない" \
    "トップ=${B_TOP_AFTER}, 名前解決=${B_RESOLVE}" "PASS"
else
  record "B2-05b" "キャッシュ失効後は名前解決の失敗として現れる" "トップ 502 / ap を引けない" \
    "トップ=${B_TOP_AFTER}, 名前解決=${B_RESOLVE}" "FAIL"
fi

log "6. 障害 B から復旧する"
"${COMPOSE[@]}" start ap >/dev/null
if wait_for_ready; then
  record "B2-06" "AP 復帰後の自動回復" "readyz が 200 に戻る" "readyz=200" "PASS"
else
  record "B2-06" "AP 復帰後の自動回復" "readyz が 200 に戻る" "200 に戻らない" "FAIL"
fi

# --- 7. 障害 C: 経路断 ----------------------------------------------------
log "7. 障害 C: AP を db-tier ネットワークから切り離す（A と同じ症状・別の原因）"
AP_ID="$("${COMPOSE[@]}" ps -q ap)"
docker network disconnect "$DB_NETWORK" "$AP_ID"
sleep 3
C_AP_HEALTH="$(ap_status healthz)"
C_AP_READY="$(ap_status readyz)"
note "ap healthz=${C_AP_HEALTH} / ap readyz=${C_AP_READY}（A と同じ並び）"

note "ここから A と C を区別する。DB コンテナ自身は動いているか:"
DB_STATE="$("${COMPOSE[@]}" ps --format '{{.Service}} {{.State}}' | grep '^db ' || echo 'db unknown')"
note "  docker compose ps -> ${DB_STATE}"
note "AP から見た経路と名前解決:"
# ap は python:3.12-slim で iproute2 が入っていないため、
# network namespace を共有する netprobe-ap から見る。
"${COMPOSE[@]}" exec -T netprobe-ap ip -br addr | grep -v LOOPBACK || true
"${COMPOSE[@]}" exec -T netprobe-ap sh -c 'getent hosts db || echo "  名前解決できない -> 経路/所属ネットワーク側の問題"' || true

# A では db が Exited、C では db は Up のまま。この差が切り分けの決め手。
if [[ "$C_AP_READY" == "503" && "$DB_STATE" == *"running"* ]]; then
  record "B2-07" "経路断と DB 停止を区別できる" "readyz 503 だが db は running" \
    "readyz=${C_AP_READY}, ${DB_STATE}" "PASS"
else
  record "B2-07" "経路断と DB 停止を区別できる" "readyz 503 だが db は running" \
    "readyz=${C_AP_READY}, ${DB_STATE}" "FAIL"
fi

log "8. 障害 C から復旧する"
docker network connect --ip 172.29.30.20 "$DB_NETWORK" "$AP_ID"
# ap を restart すると network namespace が作り直され、それを共有している
# netprobe-ap が孤立する。診断を続けられるよう一緒に作り直す。
"${COMPOSE[@]}" restart ap >/dev/null
"${COMPOSE[@]}" restart netprobe-ap >/dev/null 2>&1 || true
if wait_for_ready; then
  record "B2-08" "経路復旧後の回復" "readyz が 200 に戻る" "readyz=200" "PASS"
else
  record "B2-08" "経路復旧後の回復" "readyz が 200 に戻る" "200 に戻らない" "FAIL"
fi

FINAL_COUNT="$("${COMPOSE[@]}" exec -T client curl -fsS --max-time 10 http://web/api/items/count 2>/dev/null | tr -d ' \n' || echo 'n/a')"

# --- 証跡 -----------------------------------------------------------------
log "証跡を書き出す"
mkdir -p "$EVIDENCE_DIR"
{
  cat <<EVIDENCE_HEAD
# B-2 3 層構成の障害切り分け演習 — ${RUN_DATE}

> このファイルは \`labs/three-tier/run-drill.sh\` が実行結果から生成した。
> 判定は script が実測値と期待値を比較した結果で、手で書き換えていない。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| 実施環境 | $(uname -srm) / Docker $(docker_server_version) |
| commit SHA | $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown) |
| 構成 | client -> web(nginx) -> ap(gunicorn/Flask) -> db(PostgreSQL 16) |
| ネットワーク | dmz 172.29.10.0/24 / app-tier 172.29.20.0/24 (internal) / db-tier 172.29.30.0/24 (internal) |
| 初期データ件数 | ${BASELINE_COUNT} |
| 終了時データ件数 | ${FINAL_COUNT} |

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
EVIDENCE_HEAD
  printf '%s\n' "${RESULT_ROWS[@]}"
  cat <<EVIDENCE_TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL

## この演習で確認したこと

- 層ごとに独立した health endpoint を持たせると、利用者から見て同じ
  「画面が出ない」でも、どの層で止まっているかを HTTP status の並びだけで
  絞り込める。
- \`/healthz\`（プロセス生存）と \`/readyz\`（依存先込み）を分けていないと、
  障害 A（DB 停止）と障害 B（AP 停止）を区別できない。
- 障害 A と障害 C は AP から見た症状が同じ（readyz 503）。
  DB コンテナ自身の稼働状態と、AP 側の所属ネットワーク・名前解決を見て
  初めて区別できる。症状だけで原因を決めない。
- **同じ障害でも、観測した時刻で見え方が変わる。** AP を止めた直後は
  504（名前解決のキャッシュが生きていて、消えた IP へ繋ぎに行き無応答）、
  \`resolver\` の \`valid=10s\` を過ぎると 502（名前解決そのものが失敗）に
  変わる。504 は上流のプロセス側、502 はサービス登録 / DNS 側を指すので、
  拾った時刻を書かずに「502 だった」とだけ報告すると切り分けを誤らせる。

## この演習で確認していないこと

- 単一ホスト上のコンテナ構成であり、物理的に分かれた 3 台のサーバー、
  L2 スイッチ、VLAN、ファイアウォール機器は対象外。
- DB のレプリケーション、フェイルオーバー、コネクションプールの枯渇は対象外。
- 負荷をかけた状態での挙動（遅延、タイムアウトの連鎖）は対象外。
- TLS 終端、認証、WAF は対象外。

## 後始末

\`\`\`bash
docker compose -f labs/three-tier/compose.yaml down -v
\`\`\`
EVIDENCE_TAIL
} > "$EVIDENCE_FILE"

trap - ERR
printf '\n証跡: %s\n' "$EVIDENCE_FILE"
printf '合計: %d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"
printf '\n後始末:\n  docker compose -f %s down -v\n' "${LAB_DIR}/compose.yaml"
[[ $FAIL_COUNT -eq 0 ]]
