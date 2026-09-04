# Ansible自動化基盤 フェーズ2（RHEL系）構築・試験結果票 — 2026-09-04

[試験仕様書・結果票](../build-package-ansible/06-test-specification.md)のフェーズ2項目（AFIT-06、AFST-06）について、Hyper-V上に構築した`ans-el9-01`（AlmaLinux 9.7）へ`ansible/playbooks/foundation.yml`を`--limit ans-el9-01`で適用した結果を記入したものです。[フェーズ1（Ubuntu、`ans-01`）の結果票](2026-09-04-ansible-foundation-build.md)と対になる記録です。

> **この証跡が示す範囲、および重要な制約**: 対象VM`ans-el9-01`は、**今回新規に作ったホストではなく、以前に別の用途（Zabbixサーバー・MySQL・Apache httpdなどを含む検証）で使っていたVMを再利用**したものです。そのため、[00-requirements.md](../build-package-ansible/00-requirements.md)や[04-network-ip-plan.md](../build-package-ansible/04-network-ip-plan.md)が前提とする「まっさらな新規ホストへの適用」「SSHのみの最小公開」という条件では**成立しません**。`common`/`docker` role自体が正しく動作すること、冪等性、SELinux/sshd/chrony/dnf-automaticの設定は実測できましたが、「新規構築」「最小公開」の証跡としては別途、専用の新規VMでの再実施が必要です。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | `common`/`docker` role の RHEL系（AlmaLinux 9.7）実機適用・冪等性を実測`PASS`。ただし対象VMが再利用環境のため、「新規構築」「最小公開」の証跡としては不完全（下記参照） |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | ns7jp |
| 対象環境 / host | `ans-el9-01`（`192.168.11.147/24`、DHCP割当）、Hyper-V VM（世代2、AlmaLinux 9.7 "Moss Jungle Cat"）。**以前の用途（Zabbix Server / MySQL / Apache httpd / cockpit 等を含む検証）からの再利用VM** |
| 管理端末 / controller | フェーズ1と同じWSL2 `Ubuntu-24.04`（`ans-01`と同じSSH鍵ペアを再利用） |
| 初期ログインユーザー | `fulike`（インストール時に作成、`wheel`グループでNOPASSWD sudo） |
| 作成した管理者アカウント | `ansible-admin`（`server_monitor_admin_user`、鍵認証のみ、NOPASSWD sudo） |
| commit SHA | `537d9be`相当（本PRのSELinux boolean修正を含むcommit） |
| OS / kernel | AlmaLinux release 9.7 (Moss Jungle Cat) |

## 見つかった欠陥と修正

実行して初めて見つかった実装上の欠陥が1件あります。詳細は[欠陥台帳](defects-found.md)（#31）を参照してください。

`common` roleの`selinux.yml`が、`docker` role適用前（`container-selinux`パッケージ未導入の時点）に`container_manage_cgroup` SELinux booleanを有効化しようとしており、`--limit ans-el9-01`の初回適用が

```
TASK [common : Ensure the container SELinux boolean is enabled]
fatal: [ans-el9-01]: FAILED! =>
  changed: false
  msg: SELinux boolean container_manage_cgroup is not defined in persistent policy
```

で失敗した（play recap `ok=43 changed=6 unreachable=0 failed=1 skipped=8`）。CIの`ansible-integration.yml`（`geerlingguy/docker-rockylinux9-ansible`イメージでのMolecule test）は2026-09-04 02:25の実行（run 33829463334）で成功していたが、これはそのテスト用イメージが`container-selinux`を最初から同梱していたためで、実際のパッケージ導入順序の問題を再現できていなかった。

該当taskを`common` roleから`docker` role（Dockerリポジトリ追加＋engine導入の直後）へ移し、`container-selinux`がdocker-ceの依存として確実に入った後で設定するように修正した。修正後、`--limit ans-el9-01`で再適用し、`failed=0`（play recap `ok=63 changed=4 unreachable=0 failed=0 skipped=11`）を確認した。

## 実測結果

| 項目 | 結果 | 実出力（要点） |
| --- | --- | --- |
| 新規構築（修正前、`--check`なしの本適用） | FAIL（欠陥#31、上記） | `failed=1`（`container_manage_cgroup`） |
| 新規構築（修正後） | PASS | `ok=63 changed=4 failed=0 skipped=11` |
| 冪等性（修正後の2回目適用） | PASS | `ok=62 changed=0 failed=0 skipped=11`。`Ensure the container SELinux boolean is enabled`タスクも`ok`（2回目は変更なし） |
| Docker動作確認 | PASS | `sudo docker version`（Client/Server起動確認）、`docker compose version`、`systemctl is-active docker` → `active` |
| password認証禁止 | PASS | `sudo sshd -T \| grep -i passwordauthentication` → `no` |
| rootログイン禁止 | PASS | `sudo sshd -T \| grep -i permitrootlogin` → `no` |
| SELinux enforcing（AFST-06） | PASS | `getenforce` → `Enforcing` |
| 時刻同期 | PASS | `systemctl is-active chronyd` → `active`（Ubuntu版は`chrony`、RHEL系は`chronyd`で unit名が設計どおり異なる） |
| 自動更新設定 | PASS | `rpm -q dnf-automatic` → 導入済み。`systemctl is-enabled dnf-automatic.timer` → `enabled`（`dnf-automatic-install.timer`は`disabled`のままで設計どおり） |
| firewalld（`common` roleが追加したルール） | PASS（ただし下記の限定つき） | `sudo firewall-cmd --list-all`の`rich rules`に`rule family="ipv4" port port="22" protocol="tcp" accept limit value="4/m"`が設計どおり追加されている |
| 最小公開（AFST-03相当） | **対象外（再利用VMのため不成立）** | 同じ`firewall-cmd --list-all`に、`services: cockpit dhcpv6-client http`、`ports: 10051/tcp 10050/tcp`が残っている。`ss -lntup`でも`zabbix_server`（多数）、`zabbix_agent2`（10050/tcp）、`mysqld`、`httpd`（80/tcp）、`cupsd`、`rpcbind`のLISTENが確認できた。**これらは`common`/`docker` roleが追加したものではなく、VM再利用前の環境から残っているもの。** `common` roleのfirewalld管理は「必要なルールを追加する」設計であり、無関係な既存ルールを削除しないため、この状態は roleの欠陥ではない |

## 未実施・今後の課題

- **専用の新規AlmaLinux/Rocky 9 VMでの再実施**: 「新規構築」「最小公開」を厳密に確認するには、Zabbix等が入っていないまっさらなVMが必要。次回の課題とする
- AFNW-02〜06のRHEL系版（`ip route`、`ss -lntup`の待受確認は実施済みだが、正式なAFNW結果票としては未整理）
- この検証環境でのCIとの突き合わせ（`ansible-integration.yml`の次回実行で、修正後のコードが引き続きMoleculeを通過するか確認）
