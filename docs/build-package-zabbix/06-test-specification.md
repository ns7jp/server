# 試験仕様書・結果票

> 💡 **初めて読む方へ**: この文書は完成したかどうかを判定する「試験問題と模範解答」です。原本がなぜ常に `NOT RUN` のままなのかは、先に[初心者ガイド](beginner-guide.md#06-試験仕様書結果票)で説明しています。文書番号（00〜11）と役割はLinux版と共通です。

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。試験ID体系(ZUT / ZIT / ZST)の正本は本書とし、他の文書(特に[ネットワーク実機検証手順](09-network-validation-procedure.md))は本書のIDを参照するだけに留めます。

> ## この文書の読み方(先に読んでください)
>
> **下の表がすべて `NOT RUN` なのは、まだ何も試していないからではありません。**
> [Linux版試験仕様書・結果票](../build-package/06-test-specification.md)と同じく、これは
> 対象ホストが決まっていない段階の**空白の原本**です。`zbx-01` に相当する検証用ホストを
> 用意するたびに複製して記入し、原本自体は後から上書きしません。
>
> Linux版には既に実測済みの証跡([検証証跡台帳](../evidence/README.md)参照)へのリンクが
> ありますが、本書(Zabbix版)には**現時点で1件もありません**。本パックはまだ設計・手順書の
> 整備段階であり、`zbx-01` の構築そのものが行われていないためです。したがって
> ZUT / ZIT / ZST のいずれのIDについても、結果欄は `NOT RUN` が唯一の正しい値です。これは
> 「Linux版より試験項目が緩い」ことを意味せず、単に「この構築案件がまだ実施段階に
> 入っていない」ことを示しています。
>
> ### ZIT-06はwebhook環境が無いとBLOCKEDが前提です
>
> `ZIT-06`(alert通知)は、[要件定義書](00-requirements.md)の対象外節にあるとおり、Slack
> Incoming Webhookと受信先チャンネルを用意した場合にだけ実配信まで試験します。用意できない
> 環境では、Trigger発火(PROBLEM遷移)まで確認できれば必須条件を満たし、実配信部分は
> `BLOCKED`(理由: webhook未用意)として記録します。Trigger発火の確認そのものは省略できません。
> `BLOCKED` は失敗ではなく、前提条件と解除条件を記録した状態です。ただし本書は実行そのものを
> していない空白の原本なので、結果欄はここでもなお `NOT RUN` のままにし、実際に実行して
> `BLOCKED` か `PASS` かが確定した時点で日付付きの証跡へ理由とともに記入します。
>
> ### この原本を埋めるには
>
> `zbx-01` に相当する検証用ホストを1台用意し([立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)参照)、
> [構築手順書](05-build-procedure.md)に沿って構築したうえで、本書の表と同じ試験IDに対応する
> 結果を記入します。記入した結果はこの原本を直接上書きせず、日付付きの証跡ファイル
> (例: `docs/evidence/YYYY-MM-DD-zabbix-build-validation.md`)へコピーして保存します。
> 命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
>
> ネットワーク実機検証(ZNW-01〜09)の記入様式は
> [結果票テンプレート](../evidence/templates/network-host-validation.md)(Linux版と共用)を使います。
> 手順の詳細は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 環境 | `NOT RUN` |
| commit SHA | `NOT RUN` |
| Zabbix server/frontend/agent2 実行バージョン(設計値`alpine-7.0.29`固定に対する実装確認) | `NOT SET` |
| PostgreSQL実行バージョン(設計値`postgres:16-alpine`固定に対する実装確認) | `NOT SET` |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入します。初期値の `NOT RUN` は成功実績ではありません。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は `NOT SET` / `NOT RUN` のいずれかを使います。安易に `PASS` へ書き換えないでください。

## 単体・構成試験

evidence列が「—」のIDは、CIで継続的に検証されるため個別の日付付き証跡を必要としません(base packのUT-01〜04と同じ扱い)。

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ZUT-01 | Compose config | `docker compose -f compose.zabbix.yaml config --quiet` | exit 0 | NOT RUN | — |
| ZUT-02 | backup scriptの構文 | `bash -n scripts/ops/zabbix-backup.sh` / shellcheck | 問題なし | NOT RUN | — |
| ZUT-03 | 成果物リンク | 既存の`pytest tests/test_portfolio_artifacts.py -k internal_markdown_links`に本パックのMarkdownも含まれる | 相対リンクがすべてリポジトリ内で解決 | NOT RUN | — |

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ZIT-01 | 新規構築 | `docker compose -f compose.zabbix.yaml up -d` | 全サービスが`running`/`healthy` | NOT RUN | — |
| ZIT-02 | 冪等性 | 同一コマンドを2回目実行 | 予期しないコンテナ再作成が無い | NOT RUN | — |
| ZIT-03 | host active check | `monitor-01`のAgent2登録後、Zabbix上で`monitor-01`のitem(`agent.ping`等)のlast dataが直近interval以内に更新される | 更新される | NOT RUN | — |
| ZIT-04 | Frontend認証 | 未ログインで管理画面へアクセス／ログイン後にアクセス | 未ログインはログイン画面へ、ログイン後は200 | NOT RUN | — |
| ZIT-05 | healthz item | `service_monitor.healthz` itemの値を確認 | `1`(正常) | NOT RUN | — |
| ZIT-06 | alert通知 | 閾値超過またはhealthz異常を模擬し、Trigger発火を確認(webhookと受信先を用意した場合はSlack配信まで) | TriggerがPROBLEMになり、用意した場合は数分以内にSlack通知 | NOT RUN | — |
| ZIT-07 | D-Z1 Agent停止演習 | `sudo systemctl stop zabbix-agent2`→検知→`sudo systemctl start zabbix-agent2`→復旧確認 | 検知(Trigger PROBLEM)・復旧(Trigger OK)・RTOを記録 | NOT RUN | — |
| ZIT-08 | DB backup/restore | `scripts/ops/zabbix-backup.sh`のdumpを別DBへ`pg_restore`し、host/item件数を比較 | 件数一致 | NOT RUN | — |
| ZIT-09 | 実ホストnetwork | [ネットワーク実機検証手順](09-network-validation-procedure.md)のZNW-01〜09を実行 | IP/DNS/route/listen/HTTP/packet/FWが設計どおり | NOT RUN | [結果票テンプレート](../evidence/templates/network-host-validation.md) |

ZIT-09の詳しい手順・結果票様式は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とし、本書はID・操作・期待結果の一覧だけを保持します。「管理端末→`zbx-01`」「`monitor-01`→`zbx-01`:10051(trapper)」の2方向を確認します。

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ZST-01 | bind address | `zbx-01`で`ss -lntup` | Frontendは`127.0.0.1`のみ | NOT RUN | — |
| ZST-02 | 既定パスワード変更 | `Admin`/`zabbix`でログイン試行 | 失敗する(変更済みであることの確認) | NOT RUN | — |
| ZST-03 | secret tracking | `git ls-files deploy/secrets` | `zabbix_db_password.txt`等の実値ファイルが含まれない | NOT RUN | — |
| ZST-04 | firewall | `zbx-01`で`ufw status verbose` | 10051/tcpが`monitor-01`のIPのみ許可 | NOT RUN | — |

ZST-02は「未実装」ではなく、初回ログイン直後に必ず踏む「済(手動)」の必須手順です。既定パスワード(`Admin`/`zabbix`)のままログインできてしまう状態は、この試験では`FAIL`として扱います。

## 終了判定

- 必須ID: `ZUT-01`〜`ZUT-03`、`ZIT-01`〜`ZIT-05`、`ZIT-07`〜`ZIT-09`、`ZST-01`〜`ZST-04`
- `ZIT-06`(Slack実配信)はwebhookと受信先が無い環境では`BLOCKED`となり得ますが、Trigger発火(PROBLEM遷移)までの確認は必須です。`BLOCKED`とする場合は理由(webhook未用意)を証跡へ明記します。
- `FAIL`または`BLOCKED`(必須の解除条件を満たさないもの)が残る場合は構築完了としません。
- 必須IDに`NOT RUN`が残る場合も構築完了としません。
- 結果はこの原本を直接上書きせず、日付付きの証跡ファイル(例: `docs/evidence/YYYY-MM-DD-zabbix-build-validation.md`)へコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。
