# DHCPサーバー検証ラボ（network namespace + veth）

[SM-DHCP-001（DHCPサーバー構築案件パック）](../../docs/build-package-dhcp/README.md)のDORA（DISCOVER/OFFER/REQUEST/ACK）実演を、Dockerの既定bridgeに頼らずネットワーク名前空間で再現するためのトポロジです。DHCPクライアントはIPを取得するまで送信元`0.0.0.0`でブロードキャストするため、Dockerの既定bridgeネットワークがコンテナへ先にIPを払い出す構成とはかみ合いません（詳しくは[`topology.sh`](topology.sh)冒頭のコメントを参照）。`labs/routing/`と同じ方式です。

## このラボが用意するもの・用意しないもの

`compose.yaml`と`topology.sh`が用意するのは**トポロジ（network namespace・veth・IPアドレス）だけ**です。次は用意しません。自分で追加の手順を踏む必要があります。

- **`isc-dhcp-server`・`isc-dhcp-client`・`sshd`・Ansibleのインストールと起動**（`topology.sh`はnetnsとIPを作るのみで、パッケージ導入やデーモン起動は行いません）
- `ansible/playbooks/dhcp.yml`の自動適用（[構築手順書](../../docs/build-package-dhcp/05-build-procedure.md)の手順を自分でなぞる必要があります）

さらに、既定の`compose.yaml`が使う`nicolaka/netshoot`イメージは**Alpineベース**です。`dhcp_server` role（[`ansible/roles/dhcp_server/tasks/main.yml`](../../ansible/roles/dhcp_server/tasks/main.yml)）はDebian系（`ansible_os_family == 'Debian'`）以外を`assert`で拒否するため、**netshootのままではrole自体が適用できません**。実際にAnsibleロールを適用してDORAを実演するには、`services.dhcplab.image`をUbuntu/Debian系イメージへ差し替え、`apt`でPython・SSH・（必要なら）Ansibleを導入してから[構築手順書](../../docs/build-package-dhcp/05-build-procedure.md)の手順を実行してください。

2026-09-04の実機検証（[結果票](../../docs/evidence/2026-09-04-dhcp-build-validation-netns-lab.md)）は、このcompose.yamlを使わず、検証セッションのUbuntu 24.04ホスト自身の上に本トポロジと同型のnetwork namespaceを直接構築して実施しました（dockerdが利用できないセッション環境だったため）。`compose.yaml`は、Dockerが使える環境で同じトポロジを再現したい**将来のユーザー向けの土台**として用意していますが、現時点では上記の手動プロビジョニングが前提です。

## 使い方（トポロジのみ）

```bash
docker compose -f labs/dhcp-lab/compose.yaml up -d
docker compose -f labs/dhcp-lab/compose.yaml exec dhcplab sh /opt/topology.sh build
# ここから先（isc-dhcp-server / Ansibleの導入・適用）は上記の注意点を踏まえて手動で行う
docker compose -f labs/dhcp-lab/compose.yaml exec dhcplab sh /opt/topology.sh teardown
docker compose -f labs/dhcp-lab/compose.yaml down
```

## 構成

- `mgmt-ctrl`（root netns）— 管理端末役、`10.99.0.1/24`
- `dhcp01`（netns）— DHCPサーバー役、管理側`mgmt0=10.99.0.30/24`、払い出しセグメント側`seg0=192.168.50.5/24`
- `client01`（netns）— クライアント役、`seg0`はDHCPで取得（未設定）

管理リンクに`192.0.2.0/24`ではなく`10.99.0.0/24`を使う理由は[`topology.sh`](topology.sh)のコメントを参照してください（検証ホスト自身が`192.0.2.0/24`を使っていて衝突したため）。
