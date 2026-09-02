# Zabbix監視基盤構築案件パック

**一言でいうと**: 既存の監視はそのままに、新しいサーバー`zbx-01`へZabbixを構築し、2本目の監視経路を用意する案件の書類一式です。

初めての方は、先に[案件パック 初心者ガイド](beginner-guide.md)を読むと全体像がつかめます。

このディレクトリは、案件ID`SM-ZBX-001`の成果物を工程順にまとめたものです。新規のZabbixサーバーホスト`zbx-01`上に**Zabbix 7.0 LTS**を構築し、既存監視基盤と同じ監視対象ホスト`monitor-01`を、既存スタックとは独立した2本目の監視経路として監視できるようにします。`server-monitor`の既存監視基盤（案件ID`SM-LAB-001`、正本は[Linux版構築案件パック](../build-package/README.md)。Prometheus + Grafana + Loki + Alertmanager）は**変更しません**。

案件は「何を作るか決める → 設計する → 作る → 試験する → 報告して渡す」の順に進みます。工程ごとに書類が分かれるため、文書は00から11までの12個あります。番号は作られた順で、読む順とは一致しません。初めて読むときは、下の「最短レビュー順」に従ってください。

「Prometheus/Grafanaスタック一本で監視設計ができる」ことに加えて、日本のインフラ求人で頻出する**Zabbixでも同種の監視基盤を要件定義から引き渡しまで設計・構築できる**ことを示すのが、このパックをポートフォリオへ追加した狙いです。本文書にある「設計値」と、実機で取得した「実績値」は分けて管理します。

| 案件 ID | 対象 | 現在の引き渡し判定 |
| --- | --- | --- |
| `SM-ZBX-001` | Ubuntu Server 24.04 LTS の検証用 VM 1 台（新規・論理ホスト名 `zbx-01`）へ Zabbix 7.0 LTS（Server / Frontend / PostgreSQL）を構築し、既存監視対象ホスト `monitor-01`（[Linux版パック](../build-package/03-parameter-sheet.md)と同一）を Zabbix Agent2 の active check で追加監視 | **`NOT READY`** — 引き渡し対象ホストが未指定で、必須試験（`ZUT`/`ZIT`/`ZST`）が `NOT RUN` |

表中の `NOT READY` は、必須の試験が終わっておらず、引き渡せる状態ではないことを表します。

```mermaid
flowchart LR
    R["要件ID 00"] --> D["基本・詳細設計 01-04"]
    D --> B["構築 05 / Compose up + Agent2・Frontend手動設定"]
    B --> T["試験 06 / 09 / ZUT・ZIT・ZST・ZNW"]
    T --> E["日付付き実測証跡 docs/evidence"]
    E --> W["作業結果報告 11"]
    W --> H["引き渡し判定 07"]
```

次の3つは、それぞれ別の状態です。ひとまとめにしないでください。

- 文書が「作成済み」であること
- `compose.zabbix.yaml`がCIで構文検証されていること
- 特定の引き渡し対象ホスト（`zbx-01`）で受け入れが完了したこと

最終判定は[作業結果・引き渡し報告書](11-work-result-report.md)と[引き渡しチェックリスト](07-handover-checklist.md)を使います。

### 初めての方はまずこちら

`NFR`（非機能要件。速さ・止まりにくさ・安全性など、機能以外の要求）、`Gate`（次の工程へ
進んでよいかを判断する関門）、`Trigger`、`ZIT-xx`のような言葉が初見の場合は、12文書を読み始める前に
[案件パック 初心者ガイド](beginner-guide.md)で、案件パックとは何か、各文書の役割、
読む順とかかる時間の目安を確認してください。

## 既存監視基盤との関係

本パックは[Linux版パック](../build-package/README.md)、[Windows版パック](../build-package-windows/README.md)、[AD版パック](../build-package-ad/README.md)と同じ構成・文体・厳格さを踏襲しますが、次の3点が異なります。

1. **独立した2本目の監視経路であること**: 既存の中央監視基盤（Prometheus + Grafana + Loki + Alertmanager）は変更しません。同じ監視対象ホスト`monitor-01`を、新規の`zbx-01`上のZabbixからも監視できるようにする、独立した経路を追加するだけです。Windows版・AD版パックにある「中央監視基盤への統合待ち`BLOCKED`」の区分は、本パックには存在しません。
2. **実装区分がAnsible roleではなくDocker Compose手動構築中心であること**: Windows版パックと同じ次の3区分だけを使いますが、内容が異なります。

   | 区分 | 意味 |
   | --- | --- |
   | 済(自動) | `compose.zabbix.yaml`による`docker compose up -d`のように、コード化された非対話コマンド一発で完結するもの（Ansible化はしていない） |
   | 済(手動) | 手順書のコマンド・UIクリックで今すぐ実施できるもの（monitor-01へのZabbix Agent2導入、Frontend初期設定とAdmin初期パスワードの変更、Host/Template/Trigger/Action登録） |
   | 未実装 | 設計のみでコードが無いもの（`ansible/roles/zabbix_agent`のような専用Ansible role、monitor-01側の自動プロビジョニング） |

   「済(自動)」は既存の`site.yml`のような全自動構築とは異なります。混同しないでください。
3. **単一フェーズで完結する構成であること**: Windows版・AD版パックは「フェーズ1（ホスト単体構築）」「フェーズ2（中央監視統合）」に分かれます。本パックは中央監視基盤への統合を必要としない独立構成のため、Linux版パックと同じ単一フェーズの工程ゲート（G0〜G5）で完結します。

## 最短レビュー順

1. [要件定義書](00-requirements.md) — 何を作り、何を作らないか。どうなれば合格かを決める（要件 ID と受け入れ条件を定義）
2. [基本設計書](01-basic-design.md) — 全体の構成と、非機能（NFR）の設計方針
3. [パラメータシート](03-parameter-sheet.md) — 実際に入力する設定値の一覧（OS・ネットワーク・Docker・Zabbix監視設計）
4. [構築手順書](05-build-procedure.md) — `zbx-01`をDocker Composeと手作業で組み立てる手順
5. [試験仕様書・結果票](06-test-specification.md) — 何を確かめれば合格かと、実測結果を書き込む用紙（`ZUT`/`ZIT`/`ZST`）
6. [ネットワーク実機検証手順](09-network-validation-procedure.md) — `zbx-01`と`monitor-01`の間で通信できるかの確認（名前が引けるか、経路は正しいか、待ち受けているか。名前解決/route/listen/HTTP/packet/firewall）
7. [作業結果・引き渡し報告書](11-work-result-report.md) — 計画対実績（予定と実際の比較）、試験の集計、差異、残存リスク（残ったままの危険）、完了判定
8. [検証証跡台帳](../evidence/README.md) — 実測済み・未実測の境界（どこまで実機で確かめ、どこからが未確認か）

## 成果物一覧

| 工程 | 成果物 | 状態 |
| --- | --- | --- |
| 要件定義 | [00-requirements.md](00-requirements.md) | 作成済み |
| 基本設計 | [01-basic-design.md](01-basic-design.md) | 作成済み |
| 詳細設計 | [02-detailed-design.md](02-detailed-design.md) | 作成済み |
| パラメータ設計 | [03-parameter-sheet.md](03-parameter-sheet.md) | 作成済み |
| ネットワーク設計 | [04-network-ip-plan.md](04-network-ip-plan.md) | 作成済み |
| 構築 | [05-build-procedure.md](05-build-procedure.md) | 手順作成済み。`compose.zabbix.yaml`はCIで構文検証済み（ZUT-01）。実機結果は証跡台帳で管理 |
| 試験 | [06-test-specification.md](06-test-specification.md) | 仕様作成済み・未実施欄は `NOT RUN` |
| 引き渡し | [07-handover-checklist.md](07-handover-checklist.md) | 作成済み |
| 変更・ロールバック | [08-change-rollback-plan.md](08-change-rollback-plan.md) | 計画・記録様式作成済み。実施結果は `NOT RUN` |
| ネットワーク実機検証 | [09-network-validation-procedure.md](09-network-validation-procedure.md) | 手順作成済み。実施結果は `NOT RUN` |
| 立ち上げ・受け入れ | [10-host-bringup-and-acceptance.md](10-host-bringup-and-acceptance.md) | 最短手順を作成済み |
| 作業結果報告 | [11-work-result-report.md](11-work-result-report.md) | 原本作成済み。対象ホストごとの実績は日付付き evidence へ複製して記録 |
| ネットワーク結果票 | [実機検証テンプレート](../evidence/templates/network-host-validation.md) | テンプレート作成済み（Linux版と共用。本パック専用テンプレートは作らない） |
| 一次切り分け記録 | [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md) | テンプレート作成済み（既存3パックと共用） |

## 工程ゲート

表中の `NOT SET` は、値や承認がまだ決まっていないことを表します。

| Gate | 完了条件 | 現在の状態 |
| --- | --- | --- |
| G0 要件確定 | 要件 ID、対象、対象外、受け入れ条件が合意済み | 文書作成済み。実案件での承認は `NOT SET` |
| G1 設計確定 | 基本・詳細・パラメータ・ネットワーク設計のレビュー完了 | 文書作成済み。実案件での承認は `NOT SET` |
| G2 構築完了 | `zbx-01`への初回`docker compose up -d`が成功し（ZIT-01）、2回目実行で不要なコンテナ再作成が発生しない（ZIT-02）ことを記録 | 手順・`compose.zabbix.yaml`は作成済み（構文はZUT-01でCI検証済み）。引き渡し対象ホストは `NOT RUN` |
| G3 試験完了 | 必須ID（`ZUT-01`〜`03`、`ZIT-01`〜`05`、`ZIT-07`〜`09`、`ZST-01`〜`04`）がすべて `PASS` | `NOT READY` |
| G4 作業完了 | 作業結果報告書に実績、障害、差異、残存リスクを記録 | 原本のみ。実案件報告は `NOT SET` |
| G5 引き渡し | 受領者、日時、秘密値受け渡し、未解決事項を記録 | `NOT READY` |

## 検証環境

基準環境は Ubuntu Server 24.04 LTS の単一ホスト（`zbx-01`）です。監視対象ホスト`monitor-01`は[Linux版パック](../build-package/README.md)がすでに構築した既存VMをそのまま使い、本パックはこのホストを新規構築しません。

構築コードはリポジトリルートの`compose.zabbix.yaml`です。CI（`python-check.yml`）で`docker compose -f compose.zabbix.yaml config --quiet`により構文検証済み（ZUT-01）ですが、`zbx-01`実機への適用実績はまだなく、初回適用・冪等性の確認（ZIT-01/ZIT-02）は`NOT RUN`です。

ポート設計はFrontendとtrapperで思想が異なります。Frontend（`${ZABBIX_WEB_PORT:-8081}/tcp`）はloopback限定でSSH tunnel経由の利用を前提とし、trapper（`10051/tcp`）だけは`monitor-01`からの着信を`DOCKER-USER` iptables chainでの送信元制限（DockerがPublishしたportにはUFWが効かないため）で受け入れます。詳細は[04-network-ip-plan.md](04-network-ip-plan.md)を参照してください。

ネットワーク実機検証は、[Linux版パック](../build-package/README.md)と共用の[結果票テンプレート](../evidence/templates/network-host-validation.md)を使い、「管理端末→`zbx-01`」「`monitor-01`→`zbx-01:10051`（trapper）」の2方向を確認します。日付付きの結果票が保存されるまで`NOT RUN`です。

## 完了の定義

次をすべて満たした時点で「構築・試験完了」とします。

- `zbx-01`で`docker compose -f compose.zabbix.yaml up -d`が成功し、全コンテナが`running`/`healthy`になる（NFR-01 / ZIT-01）
- 2回目の適用が不要なコンテナ再作成なく完了する（NFR-02 / ZIT-02）
- [試験仕様書](06-test-specification.md)の必須ID（`ZUT-01`〜`03`、`ZIT-01`〜`05`、`ZIT-07`〜`09`、`ZST-01`〜`04`）がすべて`PASS`。`ZIT-06`（Slack実配信）はbot tokenと受信先channelを用意した場合のみPASS対象とし、Trigger発火までの確認は必須のまま残す
- Zabbix Frontendの既定管理者アカウント（`Admin`/`zabbix`）を初回ログイン直後に変更したことをZST-02で確認する
- Zabbix Trigger発火、D-Z1（`monitor-01`のZabbix Agent2停止演習）の復旧、DBバックアップ/復元の証跡がcommit SHA付きで保存される
- 未解決事項、秘密値（DBパスワード・Slack bot token）の受け渡し方法、ロールバック方法が引き渡し記録に残る
- 管理端末→`zbx-01`、`monitor-01`→`zbx-01:10051`の両方向で名前解決、経路、待受、HTTP、firewallを確認し、実行出力を保存する
- [作業結果・引き渡し報告書](11-work-result-report.md)の計画対実績、試験集計、差異、残存リスク、受領判定を記入する
