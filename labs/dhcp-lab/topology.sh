#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# SM-DHCP-001 の検証トポロジを network namespace で組む。
#
#   [ 管理端末 netns (root) ]
#          | mgmt-ctrl  192.0.2.1/24
#          | mgmt0      192.0.2.30/24
#   [ dhcp01 netns ]  (isc-dhcp-server が動く。ansible_host = 192.0.2.30)
#          | seg0(dhcp側) 192.168.50.5/24 -- 払い出し対象セグメント
#          | seg0(client側) 未設定（DHCPで取得する）
#   [ client01 netns ]
#
# なぜ Docker の network を使わないか（labs/routing/topology.sh と同じ理由）:
#
#   DHCP は DISCOVER を 255.255.255.255 へブロードキャストし、応答が来るまで
#   クライアント側は IP を持たない（送信元 0.0.0.0）。Docker の既定 bridge は
#   コンテナの IP を自分の IPAM で払い出してしまうため、コンテナ内から実際に
#   DISCOVER を送って dhcpd に応答させる構成にはひと手間要る
#   （docs/build-package-dhcp/README.md にも同じ理由を記載）。
#
#   bridge を経由しない veth の直結（point-to-point）にすれば、この問題は
#   最初から発生しない。dhcp01 と client01 を 1 本の veth で直結し、
#   その上で本物の DISCOVER/OFFER/REQUEST/ACK を流す。
#
# dhcp01 は「管理用 NIC」と「払い出し対象セグメント用 NIC」の 2 本を持つ。
# これは docs/build-package-dhcp/04-network-ip-plan.md の設計（SSHは管理面、
# DHCPペイロードは払い出し対象セグメント側interfaceだけに絞る）をそのまま
# ネットワーク構成に反映したもの。
#
# 管理リンクを 10.99.0.0/24 にしている理由: パラメータシート等の記入例が使う
# 192.0.2.0/24（RFC 5737 TEST-NET-1）は、あくまで文書上のプレースホルダの
# つもりだったが、このラボを動かすホスト自身（クラウドsandboxコンテナの
# eth0）が実際にその番地帯を使っていることがあり、衝突して管理リンクが
# 疎通しなくなった。ラボの管理リンクは host 側の実アドレス体系と独立させる
# 必要があるため、文書のプレースホルダとは別の帯域を使う。
# ---------------------------------------------------------------------------
set -eu

MGMT_CTRL_IP='10.99.0.1/24'
MGMT_DHCP01_IP='10.99.0.30/24'
SEG_DHCP01_IP='192.168.50.5/24'

teardown() {
  for ns in dhcp01 client01; do
    ip netns del "$ns" 2>/dev/null || true
  done
  ip link del mgmt-ctrl 2>/dev/null || true
}

build() {
  teardown

  ip netns add dhcp01
  ip netns add client01
  ip netns exec dhcp01 ip link set lo up
  ip netns exec client01 ip link set lo up

  # --- 管理リンク: root netns (管理端末役) <-> dhcp01 ------------------------
  ip link add mgmt-ctrl type veth peer name mgmt0
  ip link set mgmt0 netns dhcp01
  ip addr add "$MGMT_CTRL_IP" dev mgmt-ctrl
  ip link set mgmt-ctrl up
  ip netns exec dhcp01 ip addr add "$MGMT_DHCP01_IP" dev mgmt0
  ip netns exec dhcp01 ip link set mgmt0 up

  # --- 払い出し対象セグメント: dhcp01 <-> client01（veth 直結） --------------
  ip link add seg-dhcp01 type veth peer name seg-client01
  ip link set seg-dhcp01 netns dhcp01
  ip link set seg-client01 netns client01
  ip netns exec dhcp01 ip link set seg-dhcp01 name seg0
  ip netns exec dhcp01 ip addr add "$SEG_DHCP01_IP" dev seg0
  ip netns exec dhcp01 ip link set seg0 up
  ip netns exec client01 ip link set seg-client01 name seg0 up
  # client01 側は意図的に IP を設定しない。DHCPで取得させる。
}

case "${1:-build}" in
  build)    build; echo "topology ready" ;;
  teardown) teardown; echo "topology removed" ;;
  *) echo "usage: $0 [build|teardown]" >&2; exit 2 ;;
esac
