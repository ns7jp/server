# 詳細設計書

> 💡 **初めて読む方へ**: この文書はコンポーネントごとの実装と「正常性の見分け方」を描く文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#02-詳細設計書)を参照してください。

要求と受け入れ条件は[要件定義書](00-requirements.md)、実現方式の全体像は[基本設計書](01-basic-design.md)を正本とし、本書では新規の監視サーバーホスト`zbx-01`上の3コンポーネント(postgres・zabbix-server・zabbix-web)と、既存の監視対象ホスト`monitor-01`へ追加するZabbix Agent2の実装・依存関係・正常性確認、配備設計、アクセス制御、監視・ログ設計、バックアップ・ロールバック設計を定義します。既存の中央監視基盤(`SM-LAB-001`)側の構成は変更しません。

## コンポーネント設計

| コンポーネント | 実装 | 依存先 | 正常性確認 |
| --- | --- | --- | --- |
| postgres | `postgres:16-alpine`。`zabbix-internal`(`internal: true`)限定、`POSTGRES_PASSWORD_FILE`でDocker secretsから注入 | なし(末端) | `pg_isready -U zabbix -d zabbix`(compose healthcheck、10秒間隔・10回retry) |
| zabbix-server | `zabbix/zabbix-server-pgsql:alpine-7.0.29`。trapper `10051/tcp`を公開 | postgres(`service_healthy`を待って起動) | `pgrep -x zabbix_server`によるプロセス存在確認(compose healthcheck。runtime control `-R`はログレベルを実際に変更してしまう副作用があるため使わない)。加えてZIT-03でmonitor-01のitemのlast dataが更新されることを確認 |
| zabbix-web | `zabbix/zabbix-web-nginx-pgsql:alpine-7.0.29`(Nginx同梱)。`127.0.0.1:${ZABBIX_WEB_PORT:-8081}`のみ公開 | postgres(`service_healthy`)、zabbix-server(`service_started`) | `GET /index.php`が200(compose healthcheck)。加えてZIT-04でSSH tunnel経由のログイン確認 |
| Zabbix Agent2(monitor-01) | 既存ホストmonitor-01へパッケージ導入し、`service_monitor.healthz` UserParameterを追加設定 | zbx-01:10051(active checkのpush先)、server-monitorアプリの`/healthz`(UserParameter経由でlocalhostからcurl) | ローカルでの`zabbix_agent2 -t agent.ping`等の単体テスト。ZIT-03(host metrics)・ZIT-05(healthz item)でzbx-01側のlast data更新を確認 |

## 配備設計

本パックは専用Ansible roleを持たず(「未実装」区分)、[構築手順書](05-build-procedure.md)のコマンド・UIクリック手順による「済(自動)」「済(手動)」が中心です。

1. **秘密値の準備(済・手動)**: `deploy/secrets/zabbix_db_password.txt.example`・`deploy/secrets/zabbix_slack_bot_token.txt.example`を複製し、実値を設定します(Gitでは追跡しません、NFR-05)。
2. **Compose起動(済・自動)**: zbx-01上で`docker compose -f compose.zabbix.yaml up -d`を実行します。`depends_on`と`healthcheck`により postgres → zabbix-server → zabbix-web の順で起動が待ち合わされ、非対話コマンド一発で完結します(NFR-01)。同一コマンドの2回目実行で不要な再作成が起きないことも確認します(NFR-02、ZIT-02)。
3. **Zabbix Agent2導入(済・手動)**: monitor-01へZabbix公式リポジトリからAgent2パッケージを導入し、`/etc/zabbix/zabbix_agent2.conf`の`Hostname`・`ServerActive`を設定します。`Server`は設定しません。Agent2にはclassic agentの`StartAgents=0`に相当する専用パラメータは無いものの、`Server`が空のときはpassive check自体を無効化して`10050/tcp`のlistenerを起動しない仕様のため、`Server`を設定しないことだけで無効化として十分です(念のため`monitor-01`の既存UFWも`10050/tcp`を許可しません)。`deploy/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf.example`を`/etc/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf`へコピーし、`sudo systemctl restart zabbix-agent2`で読み込み直します(zabbix_agent2.confの既定Includeは`zabbix_agent2.d/plugins.d/*.conf`のみが有効なため、`plugins.d`配下へ置く必要があります)。
4. **Frontend初期設定(済・手動)**: 初回アクセスのインストールウィザードでDB接続を確認したのち、Host group `SM-ZBX-001 Lab Hosts`の作成、Host `monitor-01`の登録、組み込みTemplate「Linux by Zabbix agent active」のリンク、カスタムTrigger・Actionの登録を行います。**Admin初期パスワードの変更を初回ログイン直後の必須手順**とします(ZST-02、詳細は後述)。
5. **Slack Media type登録(済・手動)**: bot tokenと受信先channelを用意した場合のみ、組み込み"Slack" media typeの`bot_token`パラメータへ`deploy/secrets/zabbix_slack_bot_token.txt`の値を設定します(ZIT-06)。
6. **バックアップ設定(済・手動)**: `deploy/systemd/zabbix-backup.service`・`.timer`を配置し、`systemctl enable --now zabbix-backup.timer`でzbx-01のsystemd timerへ登録します(詳細は後述「バックアップ・ロールバック」)。
7. **動作確認**: ZUT-01〜03、ZIT-01〜05・ZIT-07〜09(ZIT-06はbot tokenと受信先channelを用意した場合のみ必須)、ZST-01〜04を実施します。判定基準は[試験仕様書・結果票](06-test-specification.md)を正本とします。

上記1・3〜6の「済(手動)」は、既存の`site.yml`のような全自動構築(Ansible role)ではありません。`ansible/roles/zabbix_agent`のような専用roleはこの案件パックの範囲では「未実装」です。

## アクセス制御

zbx-01の公開serviceは`zabbix-internal`(内部通信用)に加え、公開対象だけが`zabbix-host-access`(`driver: bridge`)へ接続します。postgresはこのbridgeに参加させず、host / 他コンテナから直接到達させません。Frontendとtrapperは公開範囲の考え方が異なるため、詳細は[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします。

| 経路 | 公開範囲 | 認証 |
| --- | --- | --- |
| Zabbix Frontend | `127.0.0.1:${ZABBIX_WEB_PORT:-8081}`のみ。運用者はSSH tunnel経由 | Zabbixログイン(`Admin`、初回ログイン直後にパスワード変更必須) |
| Zabbix Server trapper | `10051/tcp`。monitor-01のIPのみ(`DOCKER-USER` iptables chainでの送信元制限。UFWはDockerが公開したportを経由しないため使えない、bind自体はゆるく設定) | 認証なし、送信元IP制限のみ(既存node-exporterと同じ思想) |
| PostgreSQL | 外部非公開。`zabbix-internal`(Docker internal network)限定 | Docker secretsによるパスワード認証 |
| Zabbix Agent2 passive listener(monitor-01側) | `Server`未設定によりAgent2がlistener自体を起動しない(既定では未使用) | 該当なし(listenerが存在しない。念のため`monitor-01`の既存UFWも許可しない) |

## ログ・監視設計

- Zabbixの"Host"オブジェクト名は`monitor-01`とし、Host group `SM-ZBX-001 Lab Hosts`に所属させます。Templateは組み込みの「Linux by Zabbix agent active」をそのままリンクし、カスタムテンプレートは自作しません。
- Check方式は**active check**を主方式とします。monitor-01のAgent2が`ServerActive=192.0.2.11:10051`(zbx-01)へpushする方式で、受動(passive) checkはネットワークの向きが逆(zbx-01→monitor-01:10050)になるため、複数の監視対象ホストがNATやFW越しに増えても双方向のFWルールを増やさずに済む利点があります。passive checkは既定では使用せず、任意拡張(残存リスク/ロードマップ)として設計のみ示します。
- **UserParameterによるhealthz監視の設計理由**: server-monitorアプリの`/healthz`は[Linux版ネットワーク設計](../build-package/04-network-ip-plan.md)により`127.0.0.1`限定で外部非公開です。そのためzbx-01のZabbix Serverはネットワーク越しに`/healthz`を直接probeできません。Zabbixの「web監視シナリオ」(ネットワーク経由でHTTPを叩く機能)を使うと、この非公開方針を崩して`/healthz`を外部到達可能にする必要が生じます。そこで、**monitor-01自身のAgent2に`service_monitor.healthz`というUserParameterを追加し、ホスト内部からcurlする**設計とすることで、既存の「管理UIを外部公開しない」方針を崩さずに死活監視を実現しています。実体は`deploy/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf.example`に定義し、`/healthz`が200を返せば`1`(正常)、それ以外は`0`(異常)を返します。
- Trigger例は、組み込みTrigger「Zabbix agent is not available」相当(`Linux by Zabbix agent active`テンプレートに含まれる、Severity: Average)、カスタムTrigger「`service_monitor.healthz`が1以外を3分間観測」(Severity: High)、テンプレート既定のCPU等閾値超過(Severity: Warning)です。
- 通知はSlack Bot Token(`chat:write`スコープ)を使う組み込み"Slack" media typeです。Zabbix 7.0の組み込みSlack統合はIncoming Webhook URLではなく`bot_token`パラメータでSlack Web APIを呼び出す方式のため、Slack側でBot付きのAppを作成し、対象channelへbotを招待しておく必要があります。bot tokenは`deploy/secrets/zabbix_slack_bot_token.txt`から取得し、Frontendの管理画面からパラメータとして手動登録します。実配信はbot tokenと受信先channelを用意した場合だけ試験する、既存Alertmanagerと同じ誠実な書き方を踏襲します(ZIT-06)。
- 障害演習は**D-Z1**(monitor-01のzabbix-agent2停止演習、既存の`D-1`と対になる名前)とします。手順は `sudo systemctl stop zabbix-agent2` → 検知(Trigger PROBLEM) → `sudo systemctl start zabbix-agent2` → 復旧(Trigger OK) → RTO記録です(ZIT-07)。
- 一次切り分けは既存パックと同じ「メトリクス → 直近変更 → ログ → プロセス」の順で行います。記録様式は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)を共用します。

## バックアップ・ロールバック

- 対象はZabbix DB(PostgreSQL、`pg_dump`によるカスタムformat dump)です。`scripts/ops/zabbix-backup.sh`が`/var/backups/zabbix`へdumpを採取し、保持世代を超えた古いdumpを削除します。
- `deploy/systemd/zabbix-backup.service`・`deploy/systemd/zabbix-backup.timer`をzbx-01の`/etc/systemd/system/`へ配置し、`systemctl enable --now zabbix-backup.timer`で登録します(手順は[構築手順書 7節](05-build-procedure.md)。スクリプト本体があるだけでは実行されず、この登録手順まで実施して初めて日次実行されます)。
- zbx-01のsystemd timerから毎日**03:45 Asia/Tokyo**に実行する設計です。`zabbix-backup.timer`の`OnCalendar`にタイムゾーンを明示しているため、host自体のtimezone設定(UTCのままの場合も含む)に依存せず03:45 JSTで実行されます。既存server-monitorのbackupが03:30のため、実行時刻をずらしています。保持世代は**14日**(既存server-monitorのbackupと同じ方針)です。
- 復元は別ボリューム/別DBへ`pg_restore`し、host数・item数を確認します(ZIT-08、PASS/FAILの判定基準は[試験仕様書](06-test-specification.md#構築結合試験)を正本とする)。
- 構成変更のロールバックは、専用Ansible roleが無いため、Gitの直前commitへ戻したうえで`docker compose -f compose.zabbix.yaml up -d`を再適用する手順を基本とします。Go/No-Go条件、実施結果記録の様式は[変更・ロールバック計画](08-change-rollback-plan.md)に定義します。
- D-Z1(Agent停止復旧演習)の実測、構成commitを戻すrollback rehearsal、DBバックアップ/復元(ZIT-08)は別試験として扱います。それぞれ日付付きのevidenceへ記録するまで、現時点ではいずれも`NOT RUN`です。
