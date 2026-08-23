# OS・ミドルウェア パラメータシート

値の正本は Ansible variables、Compose、各設定ファイルです。この表はレビューと引き渡し用の索引です。

## OS

対象 OS は 2 系統。値が分かれるものは両方を書く。片方だけ書くと、
もう片方のファミリーで構築したときに手順書と実物がずれる。

| 項目 | Debian 系（Ubuntu 22.04 / 24.04） | RHEL 系（AlmaLinux / Rocky 9） | 正本 |
| --- | --- | --- | --- |
| timezone | `Asia/Tokyo` | `Asia/Tokyo` | `ansible/roles/common/defaults/main.yml` |
| 管理方式 | SSH 公開鍵 + sudo | SSH 公開鍵 + sudo | inventory / 対象ホスト |
| 時刻同期 | **chrony**（unit 名 `chrony`） | **chrony**（unit 名 `chronyd`） | `ansible/roles/common/vars/*.yml` |
| firewall | UFW、default deny incoming | firewalld、zone `public` | `ansible/roles/common/tasks/firewall-*.yml` |
| SSH ブルートフォース対策 | `ufw limit 22/tcp` | rich rule `limit value="4/m"`（既定 ssh service は削除） | `ansible/roles/common/tasks/firewall-*.yml` |
| SSH | root login 禁止、password login 禁止 | 同左 + `sshd_config.d/*.conf` の上書き検査 | `ansible/roles/common/tasks/ssh.yml` |
| SELinux | 該当なし | `enforcing` を維持（`targeted`） | `ansible/roles/common/tasks/selinux.yml` |
| 自動更新 | unattended-upgrades | dnf-automatic（`upgrade_type = security`） | `ansible/roles/common/tasks/auto-updates.yml` |
| sshd unit 名 | `ssh` | `sshd` | `ansible/roles/common/vars/*.yml` |

## ユーザー・グループ・権限

| 項目 | 設定値 | 理由 | 正本 |
| --- | --- | --- | --- |
| アプリ用ユーザー | `monitor`（system account） | 一般ユーザーと分ける | `ansible/inventory/group_vars/all/main.yml` |
| プライマリグループ | `monitor` | — | 同上 |
| ログインシェル | `/usr/sbin/nologin` | 対話ログインさせない | `ansible/roles/common/tasks/account.yml` |
| ホームディレクトリ | `/opt/server-monitor`（作成しない） | 配備先と兼ねる | 同上 |
| `docker` グループ | **付与しない** | docker グループは root 相当 | `ansible/roles/docker/tasks/main.yml` |
| install dir の所有・権限 | `monitor:monitor` / `0750` | 他ユーザーから読めない | `ansible/roles/common/tasks/account.yml` |
| secrets dir の権限 | `0700` | 同上 | `ansible/roles/app/tasks/main.yml` |

## ディスク・ファイルシステム

追加ディスクを使う場合のみ記入する。`storage_volumes` が空なら
storage role は何も実行しない（既定は「触らない」）。

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| 構成方式 | LVM（パーティションを切らない whole-disk PV） | `ansible/roles/storage/tasks/apply.yml` |
| ファイルシステム | `xfs` または `ext4` | `ansible/roles/storage/defaults/main.yml` |
| fstab の書き方 | `UUID=` 指定 | `ansible/roles/storage/tasks/apply.yml` |
| 縮小 | **禁止**（`shrink: false`） | 同上 |
| 既存署名のあるディスク | **拒否**（`wipefs` で実読み） | `ansible/roles/storage/tasks/main.yml` |

### 実機記入欄（ディスク）

| 項目 | 値 | 記録日 |
| --- | --- | --- |
| 対象デバイス | `NOT RUN` | — |
| VG 名 / LV 名 | `NOT RUN` | — |
| サイズ | `NOT RUN` | — |
| ファイルシステム | `NOT RUN` | — |
| mount point / オプション | `NOT RUN` | — |

## Docker・アプリ

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| install dir | `/opt/server-monitor` | `ansible/inventory/group_vars/all/main.yml` |
| Docker リポジトリ | Debian 系: apt keyring / RHEL 系: `yum_repository` + `rpm_key` | `ansible/roles/docker/tasks/repo-*.yml` |
| restart policy | `unless-stopped` | `compose.yaml` |
| app user | Dockerfile の非 root ユーザー | `Dockerfile` |
| UI listen | `127.0.0.1:8080` | `compose.yaml` |
| hostname display | 既定 `false` | `.env.example` |
| username display | 既定 `false` | `.env.example` |
| secrets directory | host `0700` | `ansible/roles/app/tasks/main.yml` |
| secrets files | host `0644`（非 root container UID の読み取り用、親 directory で host access を制限） | `deploy/secrets/*.txt`（実値は非追跡） |

### コンテナ・アプリのversion基準

| 対象 | 設定値 | 正本 |
| --- | --- | --- |
| app base | `python:3.12-slim` | `Dockerfile` |
| app packages | Flask `>=3.0,<4`、psutil `>=5.9,<8`、prometheus-client `>=0.26.0,<1`、Gunicorn `>=22,<24` | `requirements.txt` |
| Nginx | `nginx:1.27-alpine` | `compose.yaml` |
| Prometheus | `prom/prometheus:v2.55.1` | `compose.yaml` |
| Alertmanager | `prom/alertmanager:v0.27.0` | `compose.yaml` |
| Grafana | `grafana/grafana:11.2.2` | `compose.yaml` |
| Loki | `grafana/loki:2.9.0` | `compose.yaml` |
| Grafana Alloy | `grafana/alloy:v1.16.1` | `compose.yaml` |
| blackbox-exporter | `prom/blackbox-exporter:v0.25.0` | `compose.yaml` |
| node-exporter | `prom/node-exporter:v1.8.2` | `compose.yaml` |
| Docker API proxy | `ghcr.io/tecnativa/docker-socket-proxy:v0.5.0` + manifest digest | `compose.yaml` |

Docker API proxyはtagとdigestを固定しています。その他はversion tagまたはpackage rangeであり、
registry上のtag不変性まで保証するdigest固定ではありません。更新時はCIとFull-stack E2Eを再実行します。

## 監視・ログ

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| global scrape interval | 15 秒 | `deploy/prometheus/prometheus.yml` |
| blackbox scrape interval | 30 秒 | `deploy/prometheus/prometheus.yml` |
| Prometheus retention | 35 日 | `compose.yaml` |
| Loki retention | 720 時間（30 日） | `deploy/loki/loki-config.yml` |
| 可用性 SLO | 99.5% / 30 日 | `docs/slo.md` |
| latency SLO | p95 500 ms 未満 / 28 日 | `docs/slo.md` |
| backup schedule | 毎日 03:30（host timezone: Asia/Tokyo） | `ansible/roles/backup/defaults/main.yml` |
| backup retention | 14 日 | `ansible/roles/backup/defaults/main.yml` |

## 公開ポート

| Port | Service | Bind | 用途 |
| --- | --- | --- | --- |
| 22/tcp | SSH | UFW `LIMIT`（全送信元）。production受入では上流FW / VPNまたはsource指定UFW ruleで管理元CIDRへ制限 | 構築・運用 |
| 8080/tcp | Nginx | `127.0.0.1` | Server Monitor UI |
| 3000/tcp | Grafana | `127.0.0.1` | 可視化 |
| 9090/tcp | Prometheus | `127.0.0.1` | query / status |
| 9093/tcp | Alertmanager | `127.0.0.1` | alert status |
| 3100/tcp | Loki | `127.0.0.1` | API（ブラウザ UI なし） |

## 実機記入欄

下表は引き渡し対象hostごとの記入欄なので、未指定の現時点では`NOT RUN`を維持します。
使い捨てrunnerの実測値は[2026-08-22 Full-stack E2E](../evidence/2026-08-22-full-stack-e2e.md)に分けて記録しています。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OS / kernel | `NOT RUN` | — | — |
| OS ファミリー（Debian / RHEL） | `NOT RUN` | — | — |
| CPU / memory / disk | `NOT RUN` | — | — |
| ディスク構成（`lsblk` / `pvs` / `lvs`） | `NOT RUN` | — | — |
| firewall の許可範囲（`ufw status` / `firewall-cmd --list-all`） | `NOT RUN` | — | — |
| SELinux の状態（`getenforce`） | `NOT RUN` | — | — |
| Docker / Compose version | `NOT RUN` | — | — |
| Ansible version | `NOT RUN` | — | — |
| 適用 commit SHA | `NOT RUN` | — | — |
