#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# B-4 のトポロジを network namespace で組む。
#
#   host-a --[ br-a ]-- router --[ br-b ]-- host-b
#                         |
#                      [ br-c ]-- host-c
#
# なぜ Docker の network を使わないか:
#
# Docker は endpoint ごとに次の規則を入れる。
#
#   iptables -t raw -A PREROUTING -d <IP> ! -i <その bridge> -j DROP
#
# このため別セグメントから router 宛に来たパケットが FORWARD へ届く前に
# 落ち、router を経由した L3 疎通が原理的に成立しない。実際に該当規則を
# 一時的に迂回すると疎通し、戻すと不通になることを実測して確認した。
#
# あわせて Docker の network では
#   - router に各セグメントの .1 を要求すると bridge 自身と衝突して起動できない
#   - コンテナ内の /proc/sys が read-only で ip_forward を切り替えられない
# という問題もある。
#
# bridge も veth も netns も自分で作れば、これらはすべて Docker の外側の
# 話になる。「ネットワークを自分で組む」という演習の目的にも合っている。
# ---------------------------------------------------------------------------
set -eu

SEGMENTS='a:172.30.10 b:172.30.20 c:172.30.30'

teardown() {
  for ns in host-a host-b host-c router; do
    ip netns del "$ns" 2>/dev/null || true
  done
  for seg in a b c; do
    ip link del "br-${seg}" 2>/dev/null || true
  done
}

build() {
  teardown

  for pair in $SEGMENTS; do
    seg="${pair%%:*}"
    ip link add "br-${seg}" type bridge
    ip link set "br-${seg}" up
  done

  ip netns add router
  # router は転送する側なので有効にしておく。演習で 0 に落として
  # 「経路はあるのに通らない」を再現する。
  ip netns exec router sysctl -qw net.ipv4.ip_forward=1
  ip netns exec router ip link set lo up

  for pair in $SEGMENTS; do
    seg="${pair%%:*}"; net="${pair#*:}"

    # router 側の足
    ip link add "r-${seg}" type veth peer name "br-r-${seg}"
    ip link set "br-r-${seg}" master "br-${seg}"
    ip link set "br-r-${seg}" up
    ip link set "r-${seg}" netns router
    ip netns exec router ip addr add "${net}.1/24" dev "r-${seg}"
    ip netns exec router ip link set "r-${seg}" up

    # host 側
    host="host-${seg}"
    ip netns add "$host"
    ip netns exec "$host" ip link set lo up
    ip link add "h-${seg}" type veth peer name "br-h-${seg}"
    ip link set "br-h-${seg}" master "br-${seg}"
    ip link set "br-h-${seg}" up
    ip link set "h-${seg}" netns "$host"
    ip netns exec "$host" ip link set "h-${seg}" name eth0
    ip netns exec "$host" ip addr add "${net}.10/24" dev eth0
    ip netns exec "$host" ip link set eth0 up
    # default route は敢えて入れない。経路を自分で書く演習にするため。
  done
}

case "${1:-build}" in
  build)    build; echo "topology ready" ;;
  teardown) teardown; echo "topology removed" ;;
  *) echo "usage: $0 [build|teardown]" >&2; exit 2 ;;
esac
