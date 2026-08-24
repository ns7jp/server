#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# B-4: L2 / L3 切り分け演習（静的ルーティングと VLAN）
#
# 「つながらない」を L1 -> L2 -> L3 -> L4 -> L7 の順に切り分ける練習。
# Docker の bridge に任せず、各ホストの経路を自分で書く構成にしてある。
#
# 実行するもの:
#   1. 経路を書く前は隣のセグメントへ届かないことを確認する（L3 未設定）
#   2. 静的ルートを入れて到達させる
#   3. ip_forward を落として「経路はあるのに通らない」を再現する
#   4. 802.1Q VLAN サブインターフェースを作り、同一物理線上で
#      VLAN 10 と VLAN 20 を分離する（L2）
#   5. VLAN ID を片側だけ変えて「L1/L3 は正しいのに通らない」を再現する
#
#   ./run-drill.sh
#
# 結果は docs/drills/logs/<date>-B-4.md に書き出す。
# ---------------------------------------------------------------------------
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LAB_DIR}/../.." && pwd)"
COMPOSE=(docker compose -f "${LAB_DIR}/compose.yaml")
EVIDENCE_DIR="${REPO_ROOT}/docs/drills/logs"
RUN_DATE="$(date -u '+%Y-%m-%d')"
EVIDENCE_FILE="${EVIDENCE_DIR}/${RUN_DATE}-B-4.md"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
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
  case "$verdict" in
    PASS)     PASS_COUNT=$((PASS_COUNT + 1)) ;;
    # 環境都合で実行できなかったものは PASS にも FAIL にもしない。
    # 「確認していない」ことが証跡に残るようにする。
    SKIP-ENV) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    *)        FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
  esac
  printf '    [%s] %s -> %s (%s)\n' "$id" "$title" "$observed" "$verdict"
}

on() { "${COMPOSE[@]}" exec -T "$1" sh -c "$2"; }

# 到達したら 0、しなかったら 1 を返す（set -e に巻き込まれないようにする）。
can_ping() {
  local from="$1" target="$2"
  if "${COMPOSE[@]}" exec -T "$from" ping -c 2 -W 2 "$target" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

trap 'printf "\n演習が途中で終了した。後始末: docker compose -f %s down\n" "${LAB_DIR}/compose.yaml" >&2' ERR

# 802.1Q VLAN サブインターフェースは host 側の 8021q カーネルモジュールを使う。
# 無い環境では ip link add ... type vlan が分かりにくいエラーで落ちるので、
# 演習を始める前に検査して、環境の問題だと分かる形で止める。
# （LVM ラボの device-mapper 検査と同じ方針）
check_vlan_support() {
  if [[ -d /sys/module/8021q ]]; then
    return 0
  fi
  if modprobe 8021q 2>/dev/null && [[ -d /sys/module/8021q ]]; then
    note "8021q モジュールを読み込んだ"
    return 0
  fi
  cat >&2 <<'MSG'
FAIL: host 側に 8021q (802.1Q VLAN) カーネルモジュールがない。

  L3 の演習 (NW-L3-*) は動くが、VLAN の演習 (NW-L2-02〜04) は実行できない。
  通常の Linux kernel を持つ環境で実行するか、
  sudo modprobe 8021q を実行してから再試行する。
MSG
  return 1
}

log "0. ラボを起動する"
"${COMPOSE[@]}" up -d
sleep 3

# Docker は各ネットワークの gateway 経由の default route を自動で入れる。
# 「自分で経路を書く」演習にするため、まず default route を外す。
log "0-b. 各ホストの default route を外す（自分で経路を書く演習にするため）"
for host in host-a host-b host-c; do
  on "$host" 'ip route del default 2>/dev/null || true'
  note "${host}: $(on "$host" 'ip route show' | tr '\n' ' ')"
done

# --- 1. L3 未設定 ---------------------------------------------------------
log "1. 経路を書く前: host-a から host-b へ届かないこと"
if can_ping host-a 172.30.20.10; then
  record "B4-L3-01" "経路未設定では隣セグメントへ届かない" "到達しない" "到達してしまった" "FAIL"
else
  record "B4-L3-01" "経路未設定では隣セグメントへ届かない" "到達しない" "到達しない" "PASS"
fi
note "host-a の経路表:"
on host-a 'ip route show' | sed 's/^/      /'
note "同一セグメント内（host-a -> router 172.30.10.1）は L2 だけで届くはず:"
if can_ping host-a 172.30.10.1; then
  record "B4-L2-01" "同一セグメント内は経路なしで到達" "到達する" "到達する" "PASS"
else
  record "B4-L2-01" "同一セグメント内は経路なしで到達" "到達する" "到達しない" "FAIL"
fi

# --- 2. 静的ルート --------------------------------------------------------
log "2. 静的ルートを入れて host-a <-> host-b を到達させる"
on host-a 'ip route add 172.30.20.0/24 via 172.30.10.1'
on host-b 'ip route add 172.30.10.0/24 via 172.30.20.1'
note "host-a: ip route add 172.30.20.0/24 via 172.30.10.1"
note "host-b: ip route add 172.30.10.0/24 via 172.30.20.1"
if can_ping host-a 172.30.20.10; then
  record "B4-L3-02" "静的ルート追加後の到達" "到達する" "到達する" "PASS"
else
  record "B4-L3-02" "静的ルート追加後の到達" "到達する" "到達しない" "FAIL"
fi

note "経路上のホップ（traceroute）:"
on host-a 'traceroute -n -w 1 -q 1 -m 4 172.30.20.10 2>/dev/null || true' | sed 's/^/      /'

# 片道だけ経路がある状態を作る = 応答が返らない典型例
log "3. 戻りの経路だけ消す（行きは通るが応答が返らない状態）"
on host-b 'ip route del 172.30.10.0/24 via 172.30.20.1'
if can_ping host-a 172.30.20.10; then
  record "B4-L3-03" "戻り経路が無いと往復しない" "到達しない" "到達してしまった" "FAIL"
else
  record "B4-L3-03" "戻り経路が無いと往復しない" "到達しない" "到達しない（片道のみ）" "PASS"
fi
note "行きだけ通っていることを router 側で確認できる（tcpdump の例）:"
note "  docker compose exec router tcpdump -nn -i any icmp"
on host-b 'ip route add 172.30.10.0/24 via 172.30.20.1'

# --- 4. ip_forward ---------------------------------------------------------
log "4. router の ip_forward を落とす（経路はあるのに通らない）"
on router 'sysctl -w net.ipv4.ip_forward=0' >/dev/null
if can_ping host-a 172.30.20.10; then
  record "B4-L3-04" "転送無効時は中継されない" "到達しない" "到達してしまった" "FAIL"
else
  record "B4-L3-04" "転送無効時は中継されない" "到達しない" "到達しない" "PASS"
fi
note "両端の経路表は正しいまま。router 側の設定を見ないと分からない:"
note "  router: net.ipv4.ip_forward = $(on router 'sysctl -n net.ipv4.ip_forward')"

log "5. ip_forward を戻す"
on router 'sysctl -w net.ipv4.ip_forward=1' >/dev/null
if can_ping host-a 172.30.20.10; then
  record "B4-L3-05" "転送を戻すと復旧する" "到達する" "到達する" "PASS"
else
  record "B4-L3-05" "転送を戻すと復旧する" "到達する" "到達しない" "FAIL"
fi

# --- 6. VLAN (L2) ---------------------------------------------------------
log "6. 802.1Q VLAN: 同一物理線上に VLAN 10 / VLAN 20 を作る"
# L3 の演習はここまでで完了しているので、VLAN が使えない環境では
# ここまでの結果を証跡に残してから止める。
if ! check_vlan_support; then
  record "B4-L2-02" "同じ VLAN ID どうしは疎通する" "到達する" "8021q が無く実行不能" "SKIP-ENV"
  record "B4-L2-03" "VLAN ID 不一致では疎通しない" "到達しない" "8021q が無く実行不能" "SKIP-ENV"
  record "B4-L2-04" "VLAN ID を揃えると復旧する" "到達する" "8021q が無く実行不能" "SKIP-ENV"
  VLAN_SKIPPED=1
fi
if [[ "${VLAN_SKIPPED:-0}" -eq 0 ]]; then
# segment-c 側の物理インターフェース名を実際に取得する（eth0 とは限らない）。
ROUTER_IF="$(on router "ip -o -4 addr show | awk '/172\.30\.30\.1\//{print \$2}'" | tr -d ' \r\n')"
HOST_C_IF="$(on host-c "ip -o -4 addr show | awk '/172\.30\.30\.10\//{print \$2}'" | tr -d ' \r\n')"
note "router 側 interface=${ROUTER_IF} / host-c 側 interface=${HOST_C_IF}"

on router "ip link add link ${ROUTER_IF} name ${ROUTER_IF}.10 type vlan id 10"
on router "ip addr add 192.168.10.1/24 dev ${ROUTER_IF}.10"
on router "ip link set ${ROUTER_IF}.10 up"

on host-c "ip link add link ${HOST_C_IF} name ${HOST_C_IF}.10 type vlan id 10"
on host-c "ip addr add 192.168.10.10/24 dev ${HOST_C_IF}.10"
on host-c "ip link set ${HOST_C_IF}.10 up"

note "作成した VLAN インターフェース:"
on host-c "ip -d link show ${HOST_C_IF}.10 | head -2" | sed 's/^/      /'

if can_ping host-c 192.168.10.1; then
  record "B4-L2-02" "同じ VLAN ID どうしは疎通する" "到達する" "到達する（VLAN 10）" "PASS"
else
  record "B4-L2-02" "同じ VLAN ID どうしは疎通する" "到達する" "到達しない" "FAIL"
fi

# --- 7. VLAN ID 不一致 -----------------------------------------------------
log "7. 片側だけ VLAN 20 に付け替える（L1 / L3 は正しいのに通らない）"
on host-c "ip link set ${HOST_C_IF}.10 down"
on host-c "ip link del ${HOST_C_IF}.10"
on host-c "ip link add link ${HOST_C_IF} name ${HOST_C_IF}.20 type vlan id 20"
on host-c "ip addr add 192.168.10.10/24 dev ${HOST_C_IF}.20"
on host-c "ip link set ${HOST_C_IF}.20 up"
note "host-c だけ VLAN 20。IP アドレスも subnet も同じままにしてある。"

if can_ping host-c 192.168.10.1; then
  record "B4-L2-03" "VLAN ID 不一致では疎通しない" "到達しない" "到達してしまった" "FAIL"
else
  record "B4-L2-03" "VLAN ID 不一致では疎通しない" "到達しない" "到達しない" "PASS"
fi
note "IP / subnet / link state はすべて正常に見える:"
on host-c "ip -br addr show ${HOST_C_IF}.20" | sed 's/^/      /'
note "VLAN ID を見るまで原因が分からない典型例:"
note "  host-c: $(on host-c "ip -d link show ${HOST_C_IF}.20 | grep -o 'id [0-9]*' | head -1")"
note "  router: $(on router "ip -d link show ${ROUTER_IF}.10 | grep -o 'id [0-9]*' | head -1")"

log "8. VLAN ID を揃えて復旧する"
on host-c "ip link set ${HOST_C_IF}.20 down"
on host-c "ip link del ${HOST_C_IF}.20"
on host-c "ip link add link ${HOST_C_IF} name ${HOST_C_IF}.10 type vlan id 10"
on host-c "ip addr add 192.168.10.10/24 dev ${HOST_C_IF}.10"
on host-c "ip link set ${HOST_C_IF}.10 up"
sleep 2
if can_ping host-c 192.168.10.1; then
  record "B4-L2-04" "VLAN ID を揃えると復旧する" "到達する" "到達する" "PASS"
else
  record "B4-L2-04" "VLAN ID を揃えると復旧する" "到達する" "到達しない" "FAIL"
fi

fi  # VLAN セクション

# --- 証跡 -----------------------------------------------------------------
log "証跡を書き出す"
mkdir -p "$EVIDENCE_DIR"
{
  cat <<EVIDENCE_HEAD
# B-4 L2 / L3 切り分け演習（静的ルーティングと VLAN） — ${RUN_DATE}

> このファイルは \`labs/routing/run-drill.sh\` が実行結果から生成した。
> 判定は script が実測値と期待値を比較した結果で、手で書き換えていない。

## 実施情報

| 項目 | 値 |
| --- | --- |
| 実施日時 (UTC) | $(date -u '+%Y-%m-%d %H:%M:%S') |
| 実施環境 | $(uname -srm) / Docker $(docker_server_version) |
| commit SHA | $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown) |
| 構成 | host-a — router — host-b / host-c（3 セグメント、default route なし） |
| セグメント | a 172.30.10.0/24 / b 172.30.20.0/24 / c 172.30.30.0/24 |
| VLAN | VLAN 10 = 192.168.10.0/24（segment-c 上の 802.1Q サブインターフェース） |

## 判定

| ID | 試験 | 期待結果 | 実測 | 結果 |
| --- | --- | --- | --- | --- |
EVIDENCE_HEAD
  printf '%s\n' "${RESULT_ROWS[@]}"
  cat <<EVIDENCE_TAIL

合計: ${PASS_COUNT} PASS / ${FAIL_COUNT} FAIL / ${SKIP_COUNT} SKIP

## 切り分けの順序（この演習で使った形）

| 層 | 見るもの | 使ったコマンド |
| --- | --- | --- |
| L1 / L2 | link state、VLAN ID、同一セグメント内の到達 | \`ip -br link\`、\`ip -d link show <if>.<vlan>\`、同セグメントへの \`ping\` |
| L3 | 経路表、往復の経路、転送設定 | \`ip route show\`、\`traceroute -n\`、\`sysctl net.ipv4.ip_forward\` |
| L4 | ポート単位の到達 | \`nc -z\`、\`ss -lntup\` |
| L7 | アプリの応答 | \`curl -v\` |

## この演習が示していること

- **同一セグメント内が通るのに隣が通らない** → L3（経路）を疑う。
- **片方向だけ通る** → 戻りの経路が無い。行きだけ見て「経路は正しい」と
  判断しない。
- **両端の経路表が正しいのに通らない** → 中継側の \`ip_forward\`。
  端末だけ見ていても分からない。
- **IP / subnet / link state がすべて正常なのに通らない** → VLAN ID 不一致。
  L3 の情報だけでは原因にたどり着けない。

## この演習で確認していないこと

- Linux の network namespace 上の再現であり、物理スイッチ、ケーブル、
  ポート VLAN の設定、リンクアグリゲーション（bonding / LACP）、
  スパニングツリーは対象外。
- 動的ルーティング（OSPF / BGP）は対象外。静的ルートのみ。
- IPv6、NAT、ファイアウォール機器は対象外。
- 実機のスイッチ設定（Cisco IOS 等）は対象外。CCNA 学習と組み合わせて
  Packet Tracer 側で補う。

## 後始末

\`\`\`bash
docker compose -f labs/routing/compose.yaml down
\`\`\`
EVIDENCE_TAIL
} > "$EVIDENCE_FILE"

trap - ERR
printf '\n証跡: %s\n' "$EVIDENCE_FILE"
printf '合計: %d PASS / %d FAIL / %d SKIP\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
printf '\n後始末:\n  docker compose -f %s down\n' "${LAB_DIR}/compose.yaml"
[[ $FAIL_COUNT -eq 0 ]]
