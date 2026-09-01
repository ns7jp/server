# 要件定義書

> 💡 **初めて読む方へ**: この文書は「何を作るか」「完成の合格基準」を先に決める文書です。`NFR`（非機能要件）や `ZIT-xx` のような略語につまずいたら、先に[案件パック 初心者ガイド](beginner-guide.md#00-要件定義書)を確認してください。文書番号（00〜11）と役割はLinux版と共通です。

## 1. 文書の位置づけ

既存の中央監視基盤（案件ID `SM-LAB-001`、正本は[Linux版構築案件パック](../build-package/README.md)。Prometheus + Grafana + Loki + Alertmanager）は**変更しません**。本パック（案件ID `SM-ZBX-001`）は、同じ監視対象ホスト `monitor-01`（既存、論理ホスト名。実体は[パラメータシート](../build-package/03-parameter-sheet.md)で定義済み）を、新しい監視サーバーホスト `zbx-01` 上に構築する **Zabbix 7.0 LTS** で、既存スタックとは独立した2本目の監視経路として監視できるようにする案件です。本書は要求と受け入れ条件を定義し、設計値の正本は後続資料と構成コード、実行結果の正本は[検証証跡台帳](../evidence/README.md)に分離します。

Windows監視対象追加パック（案件ID `SM-WIN-001`）が「既存中央監視基盤の拡張」であるのに対し、本パックは「独立した新しい監視サーバー一式（DB・Server・Frontend）を1から構築する」という点でLinux版基盤構築パック（`docs/build-package/`）に近い構成です。ただし Ansible role は新規に作らず、Docker Compose（`compose.zabbix.yaml`）による手動構築が中心です。

本書に「済(自動)」「済(手動)」「未実装」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。本パック全体を通じて実装状態は次の3区分のみを使い、混同しません。

| 区分 | 意味 |
| --- | --- |
| 済(自動) | 本パックのために新規に用意した、実行可能なコードで今すぐ実行できるもの。`compose.zabbix.yaml` による `docker compose up -d` がこれに当たる（Ansible化はしていないが、コード化された非対話コマンド一発で完結する） |
| 済(手動) | コード化されていないが、本パックの手順書（コマンド・UIクリック手順）で今すぐ実施できるもの（monitor-01へのZabbix Agent2導入、Zabbix Frontend初期設定、Host/Template/Trigger/Action登録） |
| 未実装 | 本パックは設計のみを示し、コードが無いもの（`ansible/roles/zabbix_agent` のような専用Ansible role、monitor-01側の自動プロビジョニング） |

「済(自動)」を、既存の `site.yml` のような全自動構築（Ansible role）と混同しないでください。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | `SM-ZBX-001` |
| 利用者 | Zabbixで監視基盤を構築・運用する担当者（既存Linux監視基盤の運用者と共通） |
| 対象環境 | Ubuntu Server 24.04 LTS、新規の検証用VM1台（論理ホスト名 `zbx-01`） |
| 監視対象ホスト | `monitor-01`（既存、[Linux版パラメータシート](../build-package/03-parameter-sheet.md)で定義済み。本パックのために変更しない） |
| 構築方式 | `compose.zabbix.yaml` による Docker Compose 手動構築が中心。専用Ansible roleは未実装 |
| 提供機能 | Zabbix Frontend、monitor-01のホストメトリクス収集（active check）、アプリ死活監視（UserParameter）、Slack通知、DBバックアップ、Agent停止演習(D-Z1) |
| 引き渡し単位 | 構成コード（`compose.zabbix.yaml`、`deploy/zabbix/`、`scripts/ops/zabbix-backup.sh`）、設計書、パラメータシート、構築手順、試験結果、作業結果報告、既存の運用・変更手順への追記差分 |
| 完了判定 | 必須試験がすべて `PASS` し、計画対実績・差異・未解決事項・残存リスクが作業結果報告と受領記録に記載済み |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 |
| --- | --- | --- |
| FR-01 | 運用者がSSH tunnel経由でZabbix Frontendへアクセスし、監視対象ホストの状態を確認できること | ZIT-04 |
| FR-02 | monitor-01のCPU/メモリ/ディスク等のホストメトリクスを、Zabbix Agent2のactive checkでzbx-01のZabbix Serverが収集できること | ZIT-03 |
| FR-03 | monitor-01上のアプリ(`/healthz`)の死活を、Agent2側のUserParameterを介してZabbix Itemとして収集できること | ZIT-05 |
| FR-04 | 閾値超過またはアプリ停止を検知した場合に、Zabbix Trigger/ActionからSlackへ通知できること(Slack bot tokenと受信先channelを用意した場合のみ試験) | ZIT-06 |
| FR-05 | Zabbixの設定・履歴データ(PostgreSQL)を日次バックアップし、別ボリュームへ復元できること | ZIT-08 |
| FR-06 | monitor-01のZabbix Agent2停止(D-Z1)を検知し、検知から復旧までの時間を記録できること | ZIT-07 |
| FR-07 | 管理端末からzbx-01・monitor-01間の名前解決、経路、待受、HTTP、firewallを確認できること | ZIT-09、ZST-01、ZST-04 |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 再現性 | 未構築のzbx-01へ`compose.zabbix.yaml`を適用し、全コンテナがhealthy/runningになること | ZIT-01 |
| NFR-02 | 冪等性 | `docker compose -f compose.zabbix.yaml up -d`を2回目実行しても不要な再作成が発生しないこと | ZIT-02 |
| NFR-03 | セキュリティ | Zabbix FrontendはloopbackのみでSSH tunnel経由の利用を前提とし、外部へ直接公開しないこと | ZST-01 |
| NFR-04 | セキュリティ | Zabbix既定管理者アカウント(Admin/zabbix)のパスワードを初回ログイン直後に変更すること | ZST-02 |
| NFR-05 | 最小権限 | DBパスワード・Slack bot token等の秘密値をDocker secretsファイルで注入し、実値をGitで追跡しないこと | ZST-03 |
| NFR-06 | ネットワーク | trapper port(10051/tcp)はmonitor-01のIPのみ許可し、それ以外の送信元は拒否すること | ZST-04 |
| NFR-07 | 可観測性 | Agent停止・閾値超過・アプリ死活異常をSeverityに応じて通知に関連付け、一次切り分けできること | ZIT-06、ZIT-07 |
| NFR-08 | 復旧性 | D-Z1演習で検知から復旧までのRTOを記録すること | ZIT-07 |
| NFR-09 | 保守性 | 変更前後のcommit・設定、検証、ロールバック条件と結果を記録すること | [08-change-rollback-plan.md](08-change-rollback-plan.md) |
| NFR-10 | 追跡性 | 実行日時、環境、commit SHA、コマンド、実出力、判定を証跡へ残すこと | 全必須試験 |
| NFR-11 | 完了管理 | 計画対実績、試験集計、設計差異、障害、未実施、受領可否を1件の報告へまとめること | [11-work-result-report.md](11-work-result-report.md) |

## 5. 制約と対象外

- 単一のzbx-01ホストの検証用構成であり、ホスト障害時の無停止継続は提供しません。
- 24時間有人監視、複数拠点、SSO、商用SLA、実組織の個人情報は対象外です。
- 既存の中央監視基盤（`SM-LAB-001`、Prometheus/Grafana/Loki/Alertmanagerの構成）の変更は対象外です。[Linux版詳細設計書](../build-package/02-detailed-design.md)のまま変更しません。
- 専用Ansible role（`ansible/roles/zabbix_agent`相当）によるzbx-01・monitor-01の自動プロビジョニングは対象外です。設計のみを示し、`apply`実行証跡がない限り本案件の構築実績には含めません。
- 受動(passive) checkはZabbix Agent2の任意拡張として設計のみ示し、既定では未使用です。複数の監視対象ホストが増えた場合の残存リスク・ロードマップとして扱い、本案件の構築実績には含めません。
- カスタムZabbixテンプレートの自作は対象外です。組み込みテンプレート「Linux by Zabbix agent active」をそのままリンクする設計とします。
- Slack実通知は bot token と受信先channelを用意した場合だけ試験します。Trigger の PROBLEM 表示を実通知成功として扱いません。

## 6. 前提条件

- zbx-01用の新規VMが用意され、Ubuntu Server 24.04 LTSがインストール済みであること。
- 管理端末からzbx-01・monitor-01へ公開鍵SSHで接続でき、接続ユーザーがsudoを利用できること。
- 対象IP、管理元CIDR、DNS名、作業時間帯、費用上限が作業前に確定していること。
- `deploy/secrets/zabbix_db_password.txt`・`deploy/secrets/zabbix_slack_bot_token.txt`の秘密値をGit管理外で受け渡せること。
- 対象commit SHAと、直前の正常なcommit SHAを変更記録へ残すこと。
- Zabbix Frontend初期ログイン直後にAdminパスワードを変更できる運用担当者が立ち会うこと。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きのevidenceへコピーして保存します。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。
