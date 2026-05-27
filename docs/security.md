# セキュリティ設計

## 保護する情報

ダッシュボードは CPU やメモリの状態だけでなく、ディスク構成、プロセス名、ネットワーク量を扱う。これらは攻撃者の偵察に利用され得るため、公開 Web サイトと同じ扱いで外部公開しない。

## 実装済みの制御

| 項目 | 実装 |
| --- | --- |
| UI / JSON API 認証 | `MONITOR_USERNAME` と秘密ファイルのパスワードを使う HTTP Basic 認証 |
| Prometheus 収集認証 | `/metrics` 専用の Bearer token。ダッシュボード資格情報と分離 |
| Fail closed | パスワードまたは metrics token 未設定時は対象エンドポイントを `503` で停止 |
| ヘルスチェック | `/healthz` のみ無認証で `{"status":"ok"}` を返し、ホスト情報を返さない |
| 機微情報の最小化 | ホスト名は論理ノード名に置換、プロセスのユーザー名は `hidden` が既定 |
| レスポンスヘッダー | `X-Content-Type-Options: nosniff`、`X-Frame-Options: DENY`、`Referrer-Policy: no-referrer`、`/healthz` を除き `Cache-Control: no-store` を付与 |
| 秘密管理 | Compose secrets の実体 `*.txt` は `.gitignore` 対象。リポジトリには例のみ保存 |
| 実行権限 | アプリコンテナは `monitor` ユーザー、`read_only`、`no-new-privileges` で実行 |
| ネットワーク露出 | Compose で公開するポートはすべて `127.0.0.1` にバインド |
| リバースプロキシ | Nginx で基本的なセキュリティヘッダーを付与し、TLS 配備例も同梱 |
| ログ収集の権限分離 | Promtail は `/var/log`、`/var/lib/docker/containers`、Docker socket を **読み取り専用** でマウントし、`no-new-privileges` で起動 |
| ログラベルの最小化 | ラベルにはクライアント IP / URL / リクエスト ID 等の高カーディナリティ値を入れず、ログ本文に残す |

## 設定値

| 変数 | 既定 | 意図 |
| --- | --- | --- |
| `MONITOR_PASSWORD_FILE` | 未設定 | 未設定のままでは UI / API を利用不可 |
| `MONITOR_METRICS_TOKEN_FILE` | 未設定 | 未設定のままでは metrics を利用不可 |
| `MONITOR_AUTH_DISABLED` | `false` | loopback 上の一時開発時のみ明示的に `true` を許容 |
| `MONITOR_SHOW_HOSTNAME` | `false` | 実ホスト名を表示しない |
| `MONITOR_SHOW_USERNAMES` | `false` | OS ユーザー名を表示しない |

## 運用ルール

1. Internet に直接公開しない。遠隔利用は VPN、SSH ポートフォワード、または組織の SSO 対応プロキシを前段に置く。
2. Basic 認証を loopback 以外で使用する場合は必ず HTTPS を終端する。
3. `deploy/secrets/*.txt` と `/etc/server-monitor/server-monitor.env` のパーミッションを所有者のみ読み取り可能にする。
4. 認証無効化を設定した状態で `0.0.0.0` に bind しない。
5. アラート通知の Webhook URL は Git にコミットせず、秘密ファイルとして配置する。

## 残存リスク

- Basic 認証はユーザー管理や MFA を持たない。複数利用者や業務利用では SSO / VPN 側に認証を移す。
- Compose ラボは単一ホスト構成であり、ホスト故障時には監視基盤自体も停止する。
- UI 表示用のディスク情報は認証済み利用者には見える。必要に応じ API 出力の制限を追加する。
- Promtail は Docker socket をマウントするためコンテナ列挙の権限を持つ。socket は `:ro` で渡しているが、Docker daemon の API は読み取りでも機密情報（環境変数、ラベル等）を含む。同一ホストで信頼境界を越える別テナントを動かさないこと。
- Loki は無認証である。`127.0.0.1:3100` のみで待ち受けるため、ホスト上の他ユーザーから到達可能な場合は LAN への露出と同等のリスクになる。多人数ホストでは Grafana 側でアクセス制御し、Loki ポートはコンテナ内部に閉じる構成を検討する。
