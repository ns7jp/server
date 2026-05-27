# 構築・配備手順

## Docker Compose ラボ

### 前提

- Linux ホスト
- Docker Engine と Docker Compose plugin
- 外部公開をしない検証環境、または VPN / SSH ポートフォワード経由の接続

`node-exporter` は Linux の `/proc` と `/sys` を読み取る設計のため、この Compose 構成は Linux ホスト向けである。

### 1. 秘密値を準備

```bash
cp .env.example .env
mkdir -p deploy/secrets
openssl rand -base64 32 > deploy/secrets/dashboard_password.txt
openssl rand -base64 32 > deploy/secrets/metrics_token.txt
openssl rand -base64 32 > deploy/secrets/grafana_admin_password.txt
chmod 600 deploy/secrets/*.txt
```

秘密値のファイルは `.gitignore` で除外される。`.example` ファイルは構成を理解するためのダミーであり、運用に利用しない。

### 2. 起動

```bash
docker compose up -d --build
docker compose ps
```

| 画面 | URL | 認証 |
| --- | --- | --- |
| Flask dashboard | `http://127.0.0.1:8080/` | `.env` のユーザー名と `dashboard_password.txt` |
| Grafana | `http://127.0.0.1:3000/` | `admin` と `grafana_admin_password.txt` |
| Prometheus | `http://127.0.0.1:9090/` | loopback 限定 |
| Alertmanager | `http://127.0.0.1:9093/` | loopback 限定 |

### 3. 検証

```bash
curl http://127.0.0.1:8080/healthz
curl -u "monitor:$(cat deploy/secrets/dashboard_password.txt)" http://127.0.0.1:8080/api/stats
curl -H "Authorization: Bearer $(cat deploy/secrets/metrics_token.txt)" http://127.0.0.1:8080/metrics
```

Prometheus の `Status > Targets` で `server-monitor` と `linux-node` が `UP` となり、Grafana の `Infrastructure Lab / Server Monitor Infrastructure Lab` に履歴が表示されれば構築完了である。

### 4. Slack 通知を有効化する場合

通常のラボ設定では Alertmanager UI でアラートを確認し、外部通知は行わない。Slack を使う場合は Webhook URL を秘密ファイルで提供し、設定例を有効化する。

```bash
printf '%s' 'https://hooks.slack.com/services/REPLACE/ME' > deploy/secrets/slack_webhook_url.txt
chmod 600 deploy/secrets/slack_webhook_url.txt
docker compose -f compose.yaml -f compose.slack.yaml.example up -d alertmanager
```

`compose.slack.yaml.example` は Slack 用設定ファイルと secret mount のみを基本構成に追加する。実 Webhook URL はコミットしない。

## Native Linux 配備例

Docker を使わない構成では、`deploy/systemd/server-monitor.service` と `deploy/nginx/server-monitor-tls.conf.example` を土台にする。

```bash
sudo useradd --system --home /opt/server-monitor --shell /usr/sbin/nologin monitor
sudo install -d -o monitor -g monitor /opt/server-monitor
sudo install -d -m 700 -o monitor -g monitor /etc/server-monitor
sudo cp deploy/systemd/server-monitor.env.example /etc/server-monitor/server-monitor.env
sudo chmod 600 /etc/server-monitor/server-monitor.env
```

環境ファイルのダミー資格情報をランダムな値に変更し、アプリを `/opt/server-monitor` に配備して仮想環境を作成した後、ユニットを導入する。

```bash
sudo cp deploy/systemd/server-monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now server-monitor
sudo systemctl status server-monitor
```

Nginx 設定例は HTTPS 証明書の配置先を環境に合わせて変更して使用する。HTTP のみで資格情報を送らない。
