# OS・ミドルウェア パラメータシート

値の正本は Ansible variables、Compose、各設定ファイルです。この表はレビューと引き渡し用の索引です。

## OS

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| 対象 OS | Ubuntu 22.04 / 24.04 LTS | `docs/deployment-ansible.md` |
| timezone | `Asia/Tokyo` | `ansible/roles/common/defaults/main.yml` |
| 管理方式 | SSH 公開鍵 + sudo | inventory / 対象ホスト |
| アプリ用ユーザー | `monitor` | `ansible/group_vars/all/main.yml` |
| firewall | UFW、default deny incoming | `ansible/roles/common/` |
| SSH | root login 禁止、password login 禁止 | `ansible/roles/common/` |
| 自動更新 | unattended-upgrades | `ansible/roles/common/` |
| 時刻同期 | systemd-timesyncd / OS 標準 | 対象ホスト |

## Docker・アプリ

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| install dir | `/opt/server-monitor` | `ansible/roles/app/defaults/main.yml` |
| restart policy | `unless-stopped` | `compose.yaml` |
| app user | Dockerfile の非 root ユーザー | `Dockerfile` |
| UI listen | `127.0.0.1:8080` | `compose.yaml` |
| hostname display | 既定 `false` | `.env.example` |
| username display | 既定 `false` | `.env.example` |
| secrets directory | host `0700` | `ansible/roles/app/tasks/main.yml` |
| secrets files | host `0644`（非 root container UID の読み取り用、親 directory で host access を制限） | `deploy/secrets/*.txt`（実値は非追跡） |

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
| 22/tcp | SSH | 管理元 CIDR に制限 | 構築・運用 |
| 8080/tcp | Nginx | `127.0.0.1` | Server Monitor UI |
| 3000/tcp | Grafana | `127.0.0.1` | 可視化 |
| 9090/tcp | Prometheus | `127.0.0.1` | query / status |
| 9093/tcp | Alertmanager | `127.0.0.1` | alert status |
| 3100/tcp | Loki | `127.0.0.1` | API（ブラウザ UI なし） |

## 実機記入欄

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| OS / kernel | `NOT RUN` | — | — |
| CPU / memory / disk | `NOT RUN` | — | — |
| Docker / Compose version | `NOT RUN` | — | — |
| Ansible version | `NOT RUN` | — | — |
| 適用 commit SHA | `NOT RUN` | — | — |
