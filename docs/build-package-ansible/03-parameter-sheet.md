# OS・Ansible パラメータシート

> 💡 **初めて読む方へ**: この文書はOS・firewall・SSH・Dockerの具体的な設定値を一覧にした表です。「設計値」と「実績値」の違いは[初心者ガイド](beginner-guide.md#3-12文書カード)で先に確認してください。

値の正本はAnsible variables（`ansible/roles/*/defaults/`、`ansible/inventory/group_vars/`）です。この表はレビューと引き渡し用の索引です。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-ANS-001` |
| 対象環境 | `foundation`（`ansible/inventory/group_vars/foundation/`） |
| 対象ホスト | `ans-01`（論理名、フェーズ1）、`ans-el9-01`（論理名、フェーズ2） |
| 設定値の正本 | `ansible/roles/common/defaults/`、`ansible/roles/docker/defaults/`、`ansible/inventory/group_vars/foundation/main.yml` |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用commit SHA | `NOT SET` — branch名ではなく40桁SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

「設計値」はコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値です。実績欄の`NOT RUN`を、設計値から推測して埋めません。

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| inventory hostname | `ans-01` | `ans-01`（Hyper-V VM名一致。`hostnamectl --static`は未実施） | `ansible/inventory/foundation.local.yml` / `hostnamectl --static` |
| IPv4 / prefix | 環境ごとに決定 | `192.168.11.95/24`（DHCP割当） | inventory / `ip -br addr` |
| default gateway | 環境ごとに決定 | `NOT RUN`（`ip route`未実施、AFNW-02） | `ip route` |
| DNS resolver | 環境ごとに決定 | `NOT RUN` | `resolvectl status` |
| SSH user | 例は`ubuntu`（Ubuntu）/ `rocky`（Rocky） | 初期接続`usr722`（Hyper-V Quick Create既定）、以後`ansible-admin`（鍵認証） | local inventory / `id` |
| SSH port | `22/tcp` | `22/tcp`（IPv4/v6とも`LISTEN`を`ss -lntup`で確認） | firewall status / `ss -lntup` |
| 管理者アカウント | `server_monitor_admin_user`（例: `ansible-admin`） | `ansible-admin`（鍵認証のみ、sudo NOPASSWD。[欠陥台帳](../evidence/defects-found.md)#30参照） | `ansible/inventory/foundation.local.yml` / `id` |
| timezone | `Asia/Tokyo` | `NOT RUN`（`timedatectl`未実施） | `timedatectl` |

## OS

対象OSは2系統。値が分かれるものは両方を書きます。片方だけ書くと、もう片方のファミリーで構築したときに手順書と実物がずれます。

| 項目 | Debian系（Ubuntu 22.04 / 24.04） | RHEL系（AlmaLinux / Rocky 9） | 正本 |
| --- | --- | --- | --- |
| timezone | `Asia/Tokyo` | `Asia/Tokyo` | `ansible/roles/common/defaults/main.yml` |
| 時刻同期 | chrony（unit名`chrony`） | chrony（unit名`chronyd`） | `ansible/roles/common/vars/*.yml` |
| firewall backend | UFW、`default deny incoming` | firewalld、zone`public` | `ansible/roles/common/tasks/firewall-*.yml` |
| SSHブルートフォース対策 | `ufw limit 22/tcp` | rich rule `limit value="4/m"`（既定sshサービスは削除） | `ansible/roles/common/tasks/firewall-*.yml` |
| SSHハードニング | root login禁止、password login禁止、`sshd_config.d/10-hardening.conf`のdrop-in | 同左 | `ansible/roles/common/tasks/ssh.yml` |
| SELinux | 該当なし | `enforcing`を維持（`targeted`） | `ansible/roles/common/tasks/selinux.yml` |
| 自動更新 | unattended-upgrades | dnf-automatic（`upgrade_type = security`） | `ansible/roles/common/tasks/auto-updates.yml` |
| sshd unit名 | `ssh` | `sshd` | `ansible/roles/common/vars/*.yml` |
| Dockerリポジトリ | apt keyring + repo | `rpm_key` + `yum_repository`（CentOSチャネル） | `ansible/roles/docker/tasks/repo-*.yml` |
| Docker前提パッケージ | `apt`経由 | `dnf`経由（`allowerasing: true`でcurl-minimal等との競合を回避） | `ansible/roles/docker/tasks/main.yml` |

## ユーザー・グループ・権限（`foundation` group専用の上書き）

`group_vars/all/main.yml`の既定値（`monitor`）は監視アプリを前提にした名前です。本パックの`foundation` groupは`group_vars/foundation/main.yml`で案件非依存な値へ上書きします。

| 項目 | group_vars/all の既定値 | foundation groupでの値 | 理由 |
| --- | --- | --- | --- |
| アプリ用ユーザー | `monitor` | `svc-baseline` | 監視アプリに限らない汎用の下地であることを名前で示す |
| プライマリグループ | `monitor` | `svc-baseline` | 同上 |
| install dir | `/opt/server-monitor` | `/opt/ansible-foundation` | 監視アプリの配備先と混同しないディレクトリにする |
| ログインシェル | `/usr/sbin/nologin` | （変更なし） | 対話ログインさせない |
| `docker`グループ | 付与しない | 付与しない（変更なし） | `docker`グループはroot相当 |
| install dirの所有・権限 | `<user>:<group>` / `0750` | `svc-baseline:svc-baseline` / `0750` | 他ユーザーから読めない |

## Docker

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| パッケージ | `docker-ce`、`docker-ce-cli`、`containerd.io`、`docker-buildx-plugin`、`docker-compose-plugin` | `ansible/roles/docker/defaults/main.yml` |
| 競合パッケージの扱い | `podman`、`buildah`、`runc`を除去（`docker_remove_conflicting_packages: true`） | 同上 |
| ログドライバー | `json-file` | 同上 |
| ログローテーション | `max-size: 10m`、`max-file: 5` | 同上 |
| `live-restore` | `true`（daemon再起動時もコンテナを継続稼働） | 同上 |
| daemon再起動のタイミング | ワークロード配備前に`meta: flush_handlers`で確定させる | `ansible/roles/docker/tasks/main.yml` |

## SSH・firewall

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| root SSHログイン | 禁止 | `ansible/roles/common/tasks/ssh.yml` |
| password認証 | 禁止（鍵認証のみ） | 同上 |
| sudo | role既定は`common_admin_sudo_nopasswd: false`（passwordを要求）。`foundation` groupではVaultを使わずパスワードを渡す手段が無いため`true`（鍵認証のみでsudo可）へ上書き（[欠陥台帳](../evidence/defects-found.md)#30参照） | `ansible/roles/common/defaults/main.yml` / `ansible/inventory/group_vars/foundation/main.yml` |
| UFW既定 | 着信deny、送信元CIDR未指定時は全送信元へのrate limitのみ | `ansible/roles/common/tasks/firewall-ufw.yml` |
| 管理元CIDR制限 | `server_monitor_ssh_source_cidr`を設定すると有効化（既定は空 = 制限なし） | `ansible/roles/common/defaults/main.yml` |
| 許可ポート | `22/tcp`のみ（`server_monitor_allowed_tcp_ports`） | `ansible/inventory/group_vars/foundation/main.yml` |

## 実機記入欄

下表は引き渡し対象hostごとの記入欄です。`ans-01`（フェーズ1、Hyper-V VM）で実測した値を記入しています。フェーズ2（`ans-el9-01`）は未着手のため`NOT RUN`のままです。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OS / kernel | Ubuntu 24.04.4 LTS | 2026-09-04 | [構築・試験結果票](../evidence/2026-09-04-ansible-foundation-build.md) |
| OSファミリー（Debian / RHEL） | Debian | 2026-09-04 | 同上 |
| firewallの許可範囲（`ufw status verbose`） | `22/tcp`（IPv4/v6）のみ`LIMIT IN Anywhere`、他は`deny` | 2026-09-04 | 同上 |
| SELinuxの状態（`getenforce`） | `NOT RUN`（フェーズ2、RHEL系のみ対象） | — | — |
| Docker / Compose version | Docker `29.8.0`（Client/Server） / Compose `v5.5.1` | 2026-09-04 | 同上 |
| Ansible controller version | ansible-core（`pipx install ansible-core`、WSL2上） | 2026-09-04 | 同上 |
| `sshd -T`の`passwordauthentication` / `permitrootlogin` | `no` / `no` | 2026-09-04 | 同上 |
| 適用commit SHA | `44cf16a` | 2026-09-04 | 同上 |
