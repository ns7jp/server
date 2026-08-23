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
| ネットワーク露出 | local/CIは全管理portを`127.0.0.1`へ限定。AWSはNginx 8080だけを全interfaceへbindし、EC2 SGのALB SG参照をauthoritative boundaryにする。UFWは意図を記録するがDocker NATの防御境界とは主張しない。その他はloopback |
| リバースプロキシ | Nginx で基本的なセキュリティヘッダーを付与し、TLS 配備例も同梱 |
| ログ収集の権限分離 | Alloyは`/var/log`だけをread-only mountし、Docker discovery/log取得は専用proxyの`CONTAINERS=1` / `NETWORKS=1` / `POST=0` APIを使用。proxyとAlloyだけをprivate networkへ接続し、host portは公開しない |
| hostユーザーの権限 | `root` account/groupと`docker` primary groupをhost mutation前に拒否。専用`monitor`ユーザーからroot相当のDocker補助groupだけを除去し、無関係な補助groupは保持 |
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
3. `deploy/secrets/` の親 directory は `700`、配下の `*.txt` は `644` にする（コンテナ内の別 UID から読む必要があるため、file を `600` にすると該当コンテナが起動しない。実機で確認済み）。親 directory の traversal 制限で host 上の他 user から保護する。`/etc/server-monitor/server-monitor.env` は所有者のみ読み取り可能（`600`）にする。
4. 認証無効化を設定した状態で `0.0.0.0` に bind しない。
5. アラート通知の Webhook URL は Git にコミットせず、秘密ファイルとして配置する。

## 残存リスク

- Basic 認証はユーザー管理や MFA を持たない。複数利用者や業務利用では SSO / VPN 側に認証を移す。
- Compose ラボは単一ホスト構成であり、ホスト故障時には監視基盤自体も停止する。
- UI 表示用のディスク情報は認証済み利用者には見える。必要に応じ API 出力の制限を追加する。
- Docker socketを直接mountするのは`docker-socket-proxy`だけで、Alloyは
  `tcp://docker-socket-proxy:2375`を使用する。socketの`:ro`はsocket経由のAPIを
  read-onlyにする機構ではないため、proxy側で`POST=0`とし、container/network関連の
  GET/HEADだけを許可する。E2Eは固有Nginx logがDocker APIとAlloy経由でLokiへ届くこと、
  `/_ping`のGET成功、POSTの`403 Forbidden`を検査する。
- proxy自体はDocker daemonへ到達する信頼対象であり、侵害時のroot相当リスクを完全には消せない。
  imageはversionとmanifest digestを固定し、`cap_drop: ALL`、`no-new-privileges`、read-only rootfsで起動する。
  Alloy以外を`docker-api` networkへ接続せず、host portも公開しない。Docker APIのGET応答にも
  `/containers/*/json`、`logs`、`archive`など、metadata・log・container内fileやsecret mountを
  読み得る強い権限が残る。POSTを止めることでroot相当の変更操作を低減する設計であり、完全な
  least-privilegeではない。異なるtrust boundaryのtenantを同居させない。
- Loki は無認証である。`127.0.0.1:3100` のみで待ち受けるため、ホスト上の他ユーザーから到達可能な場合は LAN への露出と同等のリスクになる。多人数ホストでは Grafana 側でアクセス制御し、Loki ポートはコンテナ内部に閉じる構成を検討する。
- `host-access`はLinux hostへのport転送を成立させる非internal bridgeであり、接続した管理serviceには外向き経路も生じる。`app`、exporter、collectorは接続せず、管理portのloopback bindとUFW denyを配備後試験で継続確認する。
- Docker API proxy以外のcontainer imageはversion tag、Python依存はversion rangeであり、manifest digestやlock fileによる完全なimmutable固定ではない。Dependabot、脆弱性scan、構成検査で更新を監視するが、tag差し替えのリスクは残る。更新時は対象digest / dependency解決結果を記録し、Full-stack E2Eを再実行する。
