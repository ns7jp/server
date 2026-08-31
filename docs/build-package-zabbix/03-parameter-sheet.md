# OS・ミドルウェア パラメータシート

> 💡 **初めて読む方へ**: この文書はOS・ネットワーク・Docker・Zabbix監視の具体的な設定値を一覧にした表です。「設計値」と「実績値」の違いは[案件パック 初心者ガイド](beginner-guide.md#03-パラメータシート)で先に確認してください。

値の正本は`compose.zabbix.yaml`、`deploy/zabbix/`、`deploy/secrets/`、`scripts/ops/zabbix-backup.sh`、Zabbix Frontend上のHost/Template/Trigger/Action設定です。この表はレビューと引き渡し用の索引です。監視対象ホスト`monitor-01`は本パックのために変更しないため、そのOS・ネットワーク設定値は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を正本とし、本書ではmonitor-01へ追加したZabbix Agent2関連の設定値のみを扱います。

「設計値」はコードから確認できる値、「実績値」は対象ホストでコマンド出力を採録した値です。実績欄の`NOT RUN`を、設計値から推測して埋めません。

## 文書管理

| 項目 | 設計値 / 状態 |
| --- | --- |
| 案件ID | `SM-ZBX-001` |
| 対象環境 | 検証(基準)。引き渡し時に実環境名へ置換 |
| 対象ホスト(新規) | `zbx-01`(論理名)。実FQDN / IPは`NOT SET` |
| 対象ホスト(既存、変更なし) | `monitor-01`(論理名)。詳細は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)を参照 |
| 設定値の正本 | `compose.zabbix.yaml`、`deploy/zabbix/`、`deploy/secrets/`、`scripts/ops/zabbix-backup.sh`、Zabbix Frontend上の設定 |
| 実績値の正本 | 対象ホストごとの日付付きevidence |
| 適用commit SHA | `NOT SET` — branch名ではなく40桁SHAを記録 |
| 最終レビュー / 承認 | `NOT SET` |

## ホスト識別・ネットワーク

| 項目 | 設計値 | 実績値 | 正本 / 確認方法 |
| --- | --- | --- | --- |
| zbx-01 inventory hostname | `zbx-01` | `NOT RUN` | 本書 / `hostnamectl --static` |
| zbx-01 FQDN(例示) | `zbx.example.test`(RFC 2606の例示用ドメイン) | `NOT RUN` | 本書 / `hostname --fqdn` |
| zbx-01 IPv4 / prefix(例示) | `192.0.2.11/24`(TEST-NET-1、RFC 5737の例示用アドレス) | `NOT RUN` | 本書 / `ip -br addr` |
| monitor-01 FQDN(例示、既存・変更なし) | `monitor.example.test` | `NOT RUN` | [Linux版09](../build-package/09-network-validation-procedure.md) |
| monitor-01 IPv4 / prefix(例示、既存・変更なし) | `192.0.2.10/24` | `NOT RUN` | [Linux版09](../build-package/09-network-validation-procedure.md) / `ip -br addr` |
| 管理端末IP(例示) | `192.0.2.20/24` | `NOT RUN` | [Linux版09](../build-package/09-network-validation-procedure.md) |
| default gateway(zbx-01) | 環境ごとに決定 | `NOT RUN` | `ip route` |
| DNS resolver(zbx-01) | 環境ごとに決定 | `NOT RUN` | `resolvectl status` |
| 管理元CIDR | production受入では必須。本パックの既定はUFW `LIMIT`(全送信元) | `NOT RUN` | UFW / `ss -lntup` |
| SSH port(zbx-01) | `22/tcp` | `NOT RUN` | UFW / `ss -lntup` |
| timezone(zbx-01) | `Asia/Tokyo` | `NOT RUN` | `timedatectl` |

## OS

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| OS(zbx-01) | Ubuntu Server 24.04 LTS、新規の検証用VM1台 | 本書 |
| 管理方式 | SSH公開鍵 + sudo | 対象ホスト |
| 時刻同期 | chrony(unit名`chrony`) | Ubuntu既定 |
| firewall | UFW、default deny incoming | 本パックの[構築手順書](05-build-procedure.md)(専用role未実装のため手動設定) |
| SSHブルートフォース対策 | `ufw limit 22/tcp` | 同上 |
| SSH | root login禁止、password login禁止 | [構築手順書 2.1節](05-build-procedure.md)(`/etc/ssh/sshd_config.d/99-zabbix-lab-hardening.conf`、手動設定) |
| 自動更新 | unattended-upgrades | 同上 |

Ubuntu 24.04 LTS以外のOSファミリーは本パックの対象外です。RHEL系で構築する場合は[Linux版パラメータシート](../build-package/03-parameter-sheet.md)のRHEL系列の値を参考にしつつ、Zabbix公式リポジトリのRHEL向けパッケージへ読み替えます。

## Docker・イメージversion一覧

| 対象 | 設定値 | 正本 |
| --- | --- | --- |
| Zabbix | 7.0 LTS(2029年6月30日までサポート)。イメージタグは`alpine-7.0.29`に固定 | `compose.zabbix.yaml` |
| zabbix-server | `zabbix/zabbix-server-pgsql:alpine-7.0.29`(trapper `10051/tcp`を公開) | `compose.zabbix.yaml` |
| zabbix-web | `zabbix/zabbix-web-nginx-pgsql:alpine-7.0.29`(Nginx同梱、コンテナ内部は`8080/tcp`) | `compose.zabbix.yaml` |
| postgres | `postgres:16-alpine`(外部非公開) | `compose.zabbix.yaml` |
| Zabbix Agent2(monitor-01) | Zabbix公式リポジトリのパッケージ。version固定方針は`NOT SET`(実機決定時に「実機記入欄」へ記録) | 「実機記入欄」参照 |
| Compose file | `compose.zabbix.yaml`(トップレベル`name: zabbix-lab`)。既存の`compose.yaml`本体・`compose.ansible.yaml`とは独立した「追加compose file」 | 本書 |
| network | `zabbix-internal`(`internal: true`、server/web/postgres間)、`zabbix-host-access`(`driver: bridge`、公開serviceのpublished portだけをhostへ転送) | `compose.zabbix.yaml` |
| volume | `zabbix_db_data`(postgres)、`zabbix_server_data`(`/var/lib/zabbix`配下) | `compose.zabbix.yaml` |

すべてversion tagで固定しており、Docker API proxy(`compose.yaml`)のようなdigest固定は行っていません。更新時はZUT-01(`docker compose -f compose.zabbix.yaml config --quiet`)を再実行します。

## 監視設定値

| 項目 | 設定値 | 正本 |
| --- | --- | --- |
| Zabbix Host名 | `monitor-01`("Host"オブジェクト名もこれと一致させる) | Frontend設定 |
| Host group | `SM-ZBX-001 Lab Hosts`(案件IDに紐づく専用グループとして新規作成) | Frontend設定 |
| Template | 組み込み「Linux by Zabbix agent active」(カスタムテンプレートは自作しない) | Frontend設定 |
| Check方式 | active check(monitor-01のAgent2→zbx-01:10051へpush)を主方式とする。passive checkは既定未使用の任意拡張 | [02-detailed-design.md](02-detailed-design.md) |
| Agent2 `Hostname`(monitor-01) | `monitor-01` | `/etc/zabbix/zabbix_agent2.conf`(monitor-01) |
| Agent2 `ServerActive`(monitor-01) | `192.0.2.11:10051`(zbx-01のIP) | 同上 |
| Agent2 `Server`(monitor-01) | 未設定(コメントアウトのまま。passive checkの送信元許可リストを空にする) | 同上 |
| カスタムItem key | `service_monitor.healthz` | `deploy/zabbix/zabbix_agent2.d/service_monitor_healthz.conf.example` |
| UserParameter実体 | `UserParameter=service_monitor.healthz,curl --silent --fail --max-time 3 http://127.0.0.1:8080/healthz >/dev/null && echo 1 || echo 0` | 同上 |
| カスタムTrigger | `service_monitor.healthz`が1以外を3分間観測 → Problem(Severity: High) | Frontend設定 |
| 組み込みTrigger | 「Zabbix agent is not available」相当(Severity: Disaster、Templateに含まれる) | Template |
| 通知Media type | Slack Incoming Webhook(組み込み"Slack (webhook)")。webhook URLは`deploy/secrets/zabbix_slack_webhook_url.txt`から手動登録 | Frontend設定 |
| 障害演習ID | `D-Z1`(monitor-01のzabbix-agent2停止演習) | [02-detailed-design.md](02-detailed-design.md) |
| Zabbix Frontend既定管理者 | `Admin` / `zabbix`(Zabbix既定値)。初回ログイン直後にパスワード変更必須(ZST-02) | Frontend設定 |
| backup schedule | 毎日03:45(Asia/Tokyo、host timezone)。既存server-monitorの03:30から時間をずらす | `scripts/ops/zabbix-backup.sh` |
| backup retention | 14日 | 同上 |
| backup保存先 | `/var/backups/zabbix` | 同上 |
| backup方式 | `pg_dump`によるカスタムformat dump。復元は別ボリューム/別DBへの`pg_restore`(ZIT-08) | [02-detailed-design.md](02-detailed-design.md) |

## 配備パス・サービス

| 対象 | 設計値 | 確認方法 |
| --- | --- | --- |
| 配備ルート(zbx-01) | 本リポジトリのcheckout先。実機での配置パスは`NOT SET`(実機決定時に「実機記入欄」へ記録) | `docker compose -f compose.zabbix.yaml ps` |
| Compose files | `compose.zabbix.yaml`(既存の`compose.yaml`本体・`compose.ansible.yaml`とは独立) | `docker compose -f compose.zabbix.yaml config --quiet` |
| backup script | `scripts/ops/zabbix-backup.sh` | `bash -n scripts/ops/zabbix-backup.sh` |
| backup unit(systemd timer) | `zabbix-backup.service` / `zabbix-backup.timer`(`deploy/systemd/`が正本。[構築手順書 7節](05-build-procedure.md)で`/etc/systemd/system/`へ配置・enable) | `systemctl status zabbix-backup.service` / `systemctl list-timers zabbix-backup.timer` |
| backup directory | `/var/backups/zabbix` | `findmnt` / directory owner・mode |
| Agent2設定ファイル(monitor-01) | `/etc/zabbix/zabbix_agent2.conf`、`/etc/zabbix/zabbix_agent2.d/service_monitor_healthz.conf` | `zabbix_agent2 -t agent.ping` |
| 主要ログ | Docker logs(`docker compose -f compose.zabbix.yaml logs`)、monitor-01側`journalctl -u zabbix-agent2` | 本書 / [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md) |

## 公開ポート

| Port | Service | Bind / 許可範囲 | 理由 |
| --- | --- | --- | --- |
| 22/tcp | SSH | UFW `LIMIT`。production受入では管理元CIDR限定(既存パックと同方針) | 構築・運用 |
| `${ZABBIX_WEB_PORT:-8081}/tcp` | Zabbix Frontend(Nginx同梱) | `127.0.0.1`のみ。運用者はSSH tunnel経由 | 既存パックと同じ「管理UIは外部公開しない」方針 |
| 10051/tcp | Zabbix Server trapper(active check受信) | monitor-01のIPのみ許可(`DOCKER-USER` iptables chainでの送信元制限。UFWはDockerが公開したportに効かない)。loopback限定にはできない — 他ホストから着信する唯一の監視系ポート | monitor-01のAgent2がactive checkでzbx-01へpushするために必須 |
| 5432/tcp | PostgreSQL | 外部非公開。Docker internal networkのみ | DBは他ホストから直接繋がせない |
| 10050/tcp(monitor-01側) | Zabbix Agent2 listener(passive check用) | Agent2の仕様上listenし続ける(Agent1の`StartAgents=0`相当が無い)。`Server`未設定(protocol層拒否)と`monitor-01`の既存UFW(Docker非経由のため有効。`10050/tcp`のallowルールを追加しない)の2段構えでネットワーク到達を遮断 | active checkを主方式とし、passive checkは使わない設計(将来使う場合は`Server`と`zbx-01`のIP限定のUFW allowを別途設計) |

Frontendとtrapperはbindの考え方が異なります。設計理由は[詳細設計書](02-detailed-design.md)と[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします。

## 実機記入欄

下表は引き渡し対象host(`zbx-01`・`monitor-01`)ごとの記入欄なので、未指定の現時点では`NOT RUN`を維持します。記録時は[検証証跡台帳](../evidence/README.md)の様式に従い、日付付きのevidenceファイルへ分けて記録します。

| 項目 | 実測値 | 記録日 | 証跡 |
| --- | --- | --- | --- |
| zbx-01 OS / kernel | `NOT RUN` | — | — |
| zbx-01 CPU / memory / disk | `NOT RUN` | — | — |
| zbx-01 firewallの許可範囲(`ufw status verbose`) | `NOT RUN` | — | — |
| zbx-01 Docker / Compose version | `NOT RUN` | — | — |
| Zabbix Server / Web / Agent2 実バージョン | `NOT RUN` | — | — |
| Zabbix Frontend Admin初期パスワード変更実施(ZST-02) | `NOT RUN` | — | — |
| monitor-01 Agent2導入・設定(ZIT-03) | `NOT RUN` | — | — |
| 適用commit SHA | `NOT RUN` | — | — |
