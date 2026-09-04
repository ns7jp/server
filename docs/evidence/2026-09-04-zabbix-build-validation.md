# Zabbix構築・試験結果票 — 2026-09-04

[試験仕様書・結果票](../build-package-zabbix/06-test-specification.md)の原本をコピーし、AI支援セッションのクラウドsandboxコンテナ上で実施できた範囲の結果を記入したものです。

> **この証跡が示す範囲**: `zbx-01`・`monitor-01`に相当する実VM・実ホストは用意していません。実施したのは、単一のsandboxコンテナ(root権限、実dockerd、実PostgreSQL、実sshd/ufw/iptablesが動作)上で、Docker Hub・`repo.zabbix.com`へのegressに依存しない範囲の実機的検証です。**本セッションの組織ポリシーにより、Docker Hub(`production.cloudfront.docker.com`)と`repo.zabbix.com`の両方へのegressが完全にブロックされており**(`curl`は`403 Forbidden`、`docker pull`は同じCDNで失敗)、Zabbix Server/Frontend/PostgreSQLのcontainer imageもZabbix Agent2のaptパッケージも取得できませんでした。そのため、これらに依存する検証(ZIT-01〜09の大半、ZST-01/02、ZNW-01〜09)は引き続き`NOT RUN`です。Ubuntu標準のaptアーカイブ(`archive.ubuntu.com`)は到達可能だったため、それだけで完結する範囲(SSH強化、UFW、DOCKER-USER chain、実PostgreSQLに対するbackup/restoreスクリプトの実データ検証)は実施しました。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | ZUT-01〜03、ZST-03を`PASS`。ZST-04相当のDOCKER-USER chain設定・順序を実機で`PASS`確認(送信元IPによる遮断そのものは別記事由でNOT RUN)。backup/restoreスクリプトの中核ロジック(dump・checksum・counts記録・flock直列化・restore・件数比較)を実PostgreSQLに対して`PASS`。他は環境制約により`NOT RUN` |
| 実施日時 | 2026-09-04 |
| 実施者 | AI支援セッション(クラウドsandboxコンテナ) |
| 対象環境 | 単一sandboxコンテナ(root、systemd無し)。`zbx-01`/`monitor-01`相当の実VMは無し |
| commit SHA | `44cf16abd510a617820c2ef87fcf3b90cd207ab6`(mainブランチ、Zabbixパック本体マージ後) |
| ブロックされたegress | `production.cloudfront.docker.com:443`(Docker Hub registry blob、`docker pull`/`docker compose up`が失敗)、`repo.zabbix.com:443`(Zabbix Agent2 apt repo)。両方とも`403`でゲートウェイに拒否される。到達可能: `archive.ubuntu.com`等のUbuntu標準アーカイブ |

秘密値(実際のDBパスワード等)は記載していません。

## 単体試験（ZUT）

| ID | 確認対象 | 結果 | 実出力（要点） |
| --- | --- | --- | --- |
| ZUT-01 | Compose config | PASS | `docker compose -f compose.zabbix.yaml config --quiet` → exit 0 |
| ZUT-02 | backup scriptの構文 | PASS | `bash -n scripts/ops/zabbix-backup.sh` → exit 0。`shellcheck`(apt導入、v0.9.0)→ 指摘0件・exit 0 |
| ZUT-03 | 成果物リンク | PASS | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` → `1 passed, 52 deselected` |

## 結合試験（ZIT）

| ID | 確認対象 | 結果 | 実出力（要点） |
| --- | --- | --- | --- |
| ZIT-01〜07、09 | 新規構築、冪等性、host active check、Frontend認証、healthz item、alert通知、D-Z1、実ホストnetwork | NOT RUN | Zabbix Server/Frontend/PostgreSQLのcontainer imageとZabbix Agent2のaptパッケージが取得できないため未実施(上記のegress制約) |
| ZIT-08 | DB backup/restore | **中核ロジックのみPASS(実環境の代替)** | `docker compose exec postgres`を実ローカルPostgreSQL(apt `postgresql` 16、`zabbix`ロール・DB作成)へリダイレクトするstubを介し、`scripts/ops/zabbix-backup.sh`を無改変のまま実行。実`pg_dump`(custom format)を採取、`file`コマンドで実PostgreSQLダンプであることを確認、`sha256sum -c`で検証、`.counts`(`hosts=1`, `items=2`)を記録。別データベース(`zabbix_restore_check`)へ`pg_restore --clean --if-exists`で復元し、復元後の件数(`hosts=1`, `items=2`)が`.counts`と完全一致することを確認。同時実行2本を実PostgreSQLに対して起動し、`flock`により2本目が即座に`another zabbix-backup.sh run is already in progress`で終了、1本目は正常完了して両方のdumpが無傷で残ることを確認。コンテナ化されたrestore-validation flow(08-change-rollback-plan.md 7節の`docker run postgres:16-alpine ...`部分)自体はcontainer imageが無いため`NOT RUN` |

## セキュリティ試験（ZST）

| ID | 確認対象 | 結果 | 実出力（要点） |
| --- | --- | --- | --- |
| ZST-01 | bind address | NOT RUN | Frontendコンテナが起動できないため未実施 |
| ZST-02 | 既定パスワード変更 | NOT RUN | Frontendコンテナが起動できないため未実施 |
| ZST-03 | secret tracking | PASS | `git ls-files deploy/secrets` → `*.example`のみ6件。`zabbix_db_password.txt`・`zabbix_slack_bot_token.txt`の実値ファイルは含まれない |
| ZST-04 | firewall | **chain設定・順序のみPASS** | `sudo apt-get install -y openssh-server ufw`で実sshd・実ufwを導入し、[構築手順書 2.1節](../build-package-zabbix/05-build-procedure.md#21-osパッケージとufwdocker-userの初期設定)のSSH強化コマンドをそのまま実行。`50-cloud-init.conf`相当の`PasswordAuthentication yes`fragmentを再現した状態で`00-zabbix-lab-hardening.conf`を追加・`sshd`をreloadし、`sshd -T`の2つのassertion(`permitrootlogin no`、`passwordauthentication no`)が実際にPASSすることを確認。`ufw default deny incoming`等も実行し`ufw status verbose`で反映を確認。dockerdは実プロセスとして稼働しているため`DOCKER-USER`chainも実際に作成され、`sudo iptables -I DOCKER-USER -p tcp --dport 10051 -j DROP`→`-s 192.0.2.10 -j ACCEPT`の順で追加した結果、`iptables -L DOCKER-USER -n --line-numbers`で`192.0.2.10`のACCEPTがDROPより上の行になることを確認(文書どおりの順序)。レジストリ不要で`FROM scratch`+`busybox`のみのimageを`docker build`でローカル作成し、`-p 0.0.0.0:10051:10051`で公開・DOCKER-USER配下で動作することを確認。ただし**送信元IPによる実際の遮断/許可の検証は、単一コンテナに閉じたsandboxでは実施できていません**(下記「実施中に得た知見」参照)。文書自体が想定する「zbx-01とmonitor-01/管理端末は別ホスト」という前提でのテスト(loopbackを使わない)は、この環境では再現不可能です |

## 実施中に見つかった手順書・設計書の欠陥

**今回のPASS範囲では欠陥は見つかりませんでした。** マージ済みのPR #116で28ラウンドの自動レビューを経て修正済みの箇所(SSH fragmentの命名順序、DOCKER-USER chainの投入順序、backup scriptのflock/atomic publish/timestamp衝突対策など)が、実際のsshd・実ufw・実dockerd・実PostgreSQLに対してすべて設計どおりに動作することを確認できました。

## 実施中に得た知見（文書の欠陥ではないが記録する価値があるもの）

- **`docker-proxy`はloopback経由の接続をDOCKER-USER chainの外側で処理する**: `ZABBIX_SERVER_BIND_ADDRESS`を`0.0.0.0`にして公開したport 10051へ、sandboxコンテナ自身の`127.0.0.1`から接続すると、`DOCKER-USER`のDROPルール(送信元`0.0.0.0/0`)にヒットしそうに見えて実際には接続が成功しました。これはDockerの`docker-proxy`(userspace proxy、`docker port`で確認可能)がpublished portへの接続を直接acceptし、`FORWARD`/`DOCKER-USER`chainを経由しない経路があるためです(`ps aux`で`/usr/bin/docker-proxy -host-ip 0.0.0.0 -host-port 10051 ...`のプロセスを確認)。**したがって、`ZST-04`/`ZNW-09`の実機検証を将来行う際は、zbx-01自身からのloopback接続で「制限が効いているか」を確認してはいけません**(常に成功してしまい誤って安全と判断する)。文書([09-network-validation-procedure.md](../build-package-zabbix/09-network-validation-procedure.md))が最初から「管理端末」「monitor-01」という別ホストからの接続だけをテスト対象にしているのは、この観点からも正しい設計です。ドキュメント自体の修正は不要と判断しました(すでにloopbackでのテストを想定していないため)。
- Ubuntu標準の`apt`アーカイブ(`archive.ubuntu.com`)はこのsandbox環境でも到達可能でしたが、Docker Hub・`repo.zabbix.com`・Launchpad PPAは組織ポリシーにより一律`403`でした。今後同様のクラウドsandbox環境で追加検証を試みる場合、まずこの3系統への到達性を`curl -sS -o /dev/null -w '%{http_code}'`で先に確認すると手戻りが少なくなります。

## 終了判定

- ZUT-01〜03、ZST-03: `PASS`
- ZST-04: DOCKER-USER chainの設定・順序は`PASS`。送信元IPによる実遮断確認は環境制約により`NOT RUN`
- ZIT-08: dump/checksum/counts/flock/restoreの中核ロジックは実PostgreSQLに対して`PASS`。コンテナ化されたrestore-validation flow自体は`NOT RUN`
- ZIT-01〜07、09、ZST-01〜02、ZNW-01〜09: `NOT RUN`(Docker Hub / `repo.zabbix.com`のegressブロックのため)
- 構築案件パックとしての「実ホストでの完全な構築・試験実績」には未到達。次回、Docker Hub・`repo.zabbix.com`へ到達可能な環境(または実VM 2台)が用意できた時点で、本票の`NOT RUN`項目を埋める続きの検証が必要
