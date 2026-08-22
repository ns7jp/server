# OS・ミドルウェア パラメータシート

値の正本は Ansible variables、Compose、各設定ファイルです。この表はレビューと引き渡し用の索引です。

## OS

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| 対象 OS | Ubuntu 22.04 / 24.04 LTS | `docs/deployment-ansible.md` |
| timezone | `Asia/Tokyo` | `ansible/roles/common/defaults/main.yml` |
| 管理方式 | SSH 公開鍵 + sudo | inventory / 対象ホスト |
| アプリ用ユーザー | `monitor` | `ansible/inventory/group_vars/all/main.yml` |
| firewall | UFW、default deny incoming | `ansible/roles/common/` |
| SSH | root login 禁止、password login 禁止 | `ansible/roles/common/` |
| 自動更新 | unattended-upgrades | `ansible/roles/common/` |
| 時刻同期 | systemd-timesyncd / OS 標準 | 対象ホスト |

## Docker・アプリ

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| install dir | `/opt/server-monitor` | `ansible/inventory/group_vars/all/main.yml` |
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
| CPU / memory / disk | `NOT RUN` | — | — |
| Docker / Compose version | `NOT RUN` | — | — |
| Ansible version | `NOT RUN` | — | — |
| 適用 commit SHA | `NOT RUN` | — | — |
