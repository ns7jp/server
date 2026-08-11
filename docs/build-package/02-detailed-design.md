# 詳細設計書

## コンポーネント設計

| コンポーネント | 実装 | 依存先 | 正常性確認 |
| --- | --- | --- | --- |
| Nginx | Compose、loopback 公開 | app | `GET /healthz` が 200 |
| app | Flask + Gunicorn、非 root | host kernel metrics | 認証付き UI/API が 200 |
| Prometheus | scrape / rule evaluation | app、exporters | `/-/ready` が 200 |
| Grafana | provisioning | Prometheus、Loki | `/api/health` が正常 |
| Alertmanager | route / inhibit | Prometheus | `/-/ready` が 200 |
| node-exporter | host metrics | Linux host | `up{job="linux-node"}=1` |
| blackbox-exporter | HTTP probe | Nginx | `probe_success=1` |
| Alloy | Docker / host log collection | Docker socket、`/var/log` | Loki でログ検索可能 |
| Loki | filesystem store | Alloy | `/ready` が 200 |

## 配備設計

1. `common` role でユーザー、timezone、SSH、UFW、更新を設定
2. `docker` role で Docker Engine と Compose plugin を導入
3. `nginx` role で TLS 前提を準備
4. `monitoring` role で監視設定を配付・構文検査
5. `app` role で秘密値をレンダリングし Compose stack を起動
6. `backup` role で systemd timer を登録
7. `verify.yml` で配備後確認

## アクセス制御

| 経路 | 公開範囲 | 認証 |
| --- | --- | --- |
| UI / API | `127.0.0.1:8080` | Basic 認証 |
| Grafana | `127.0.0.1:3000` | Grafana ログイン |
| Prometheus | `127.0.0.1:9090` | loopback / SSH tunnel 前提 |
| Alertmanager | `127.0.0.1:9093` | loopback / SSH tunnel 前提 |
| Loki API | `127.0.0.1:3100` | 外部公開禁止 |
| metrics | Compose 内部 | Bearer token |

## ログ・監視設計

- 固定値だけを Loki ラベルにし、IP、URL、ユーザー ID は本文へ残します。
- アラートには severity、summary、description、runbook URL を持たせます。
- アラート確認時は「メトリクス → 直近変更 → ログ → プロセス」の順で切り分けます。
- アラート通知先の秘密値は `compose.slack.yaml.example` とローカル secret で注入します。

## バックアップ・ロールバック

- Prometheus、Grafana、Loki の named volume を日次で tar 化します。
- 構成変更は Git の直前 commit へ戻し、Ansible の `deploy.yml` を再適用します。
- データ破損時は [スナップショット復元ランブック](../runbooks/restore-from-snapshot.md)を使用します。
- 復旧後は必ず `verify.yml` と必須試験を再実行します。

