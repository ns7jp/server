# 試験仕様書・結果票

> 💡 **初めて読む方へ**: この文書は完成したかどうかを判定する「試験問題と模範解答」です。原本がなぜ常に `NOT RUN` のままなのかは[初心者ガイド](beginner-guide.md#06-試験仕様書・結果票)で先に説明しています。

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。

> ## この文書の読み方（先に読んでください）
>
> **下の表がすべて `NOT RUN` なのは、まだ何も試していないからではありません。**
> これは引き渡し対象ホストが決まっていない段階の**空白の原本**で、
> 対象ホストごとに複製して記入します。原本を後から上書きしない運用にしています。
>
> 実行済みの結果は、日付付きの別文書に分けて保存しています。
> どの試験 ID がどこまで実測済みかは、次の索引を見てください。
>
> | 実測済みの範囲 | 証跡 |
> | --- | --- |
> | `site.yml` 一括構築、冪等性、認証、network / UFW、D-1、backup restore（23/23 PASS） | [2026-08-22 Full-stack E2E](../evidence/2026-08-22-full-stack-e2e.md) |
> | Git SHA 指定の変更・ロールバック | [2026-08-23 rollback](../evidence/2026-08-23-change-CI-GIT-ROLLBACK.md) |
> | 試験 ID と証跡の対応表 | [検証証跡台帳](../evidence/README.md#試験idと現在の証跡の対応) |
>
> いずれも**使い捨て runner 上の結果**です。独立した引き渡し対象ホスト、
> 管理端末、組織 DNS での結果ではありません。
>
> ### 記入済みの見本
>
> 空白の原本だけでは「実際に記入するとどうなるか」が分かりません。
> ラボ環境に対して同じ形式で記入した結果票を、演習ごとに用意しています。
>
> | 演習 | 記入済み結果票 |
> | --- | --- |
> | B-1 ディスク設計・LVM 拡張 | `docs/drills/logs/<日付>-B-1.md`（[生成元](../../scripts/labs/lvm-drill.sh)） |
> | B-2 3 層構成の障害切り分け | `docs/drills/logs/<日付>-B-2.md`（[生成元](../../labs/three-tier/run-drill.sh)） |
> | B-3 DB バックアップ・復元 | `docs/drills/logs/<日付>-B-3.md`（[生成元](../../labs/three-tier/run-restore-drill.sh)） |
> | B-4 L2 / L3 切り分け | `docs/drills/logs/<日付>-B-4.md`（[生成元](../../labs/routing/run-drill.sh)） |
>
> これらは演習スクリプトが実行結果から自動生成します。手で PASS を
> 書き込む余地を残さないための作りです。
>
> ### この原本を埋めるには
>
> 引き渡し対象ホスト（VPS / VM / 物理）を 1 台用意して、その上で
> [`scripts/ops/acceptance-check.sh`](../../scripts/ops/acceptance-check.sh)
> を実行すると、**下の表と同じ試験 ID に対応した記入済みの結果票**が
> `docs/evidence/<日付>-host-acceptance.md` に生成されます。
> 手順は [10 立ち上げと受け入れ試験](10-host-bringup-and-acceptance.md)。
>
> 再起動後の永続性（`--mode after-reboot`）と 24 / 72 時間の連続稼働
> （`--mode soak`）も同じ script が担当します。**どちらも使い捨て CI runner
> では原理的に確認できない項目**です。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 環境 | `NOT RUN` |
| commit SHA | `NOT RUN` |
| OS / tool versions | `NOT RUN` |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入します。初期値の `NOT RUN` は成功実績ではありません。

## 単体・構成試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| UT-01 | Python tests | `pytest` | 全 test pass | NOT RUN | — |
| UT-02 | Compose config | `docker compose config --quiet` | exit 0 | NOT RUN | — |
| UT-03 | Prometheus rules | `promtool check rules ...` | SUCCESS | NOT RUN | — |
| UT-04 | Ansible syntax | `ansible-playbook ... --syntax-check` | exit 0 | NOT RUN | — |
| UT-05 | Terraform validate | `terraform validate` | Success | NOT RUN | — |
| UT-06 | 成果物リンク | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` | README / docs の相対リンクがすべてリポジトリ内で解決 | NOT RUN | — |

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| IT-01 | 新規構築 | `site.yml` 適用 | `failed=0` | NOT RUN | — |
| IT-02 | 冪等性 | `site.yml` 2 回目 | `changed=0`, `failed=0` | NOT RUN | — |
| IT-03 | host metrics | Prometheus query | linux-node `up=1` | NOT RUN | — |
| IT-04 | UI auth | 認証なし / ありで GET | 401 または 503 / 200 | NOT RUN | — |
| IT-05 | metrics auth | token なし / ありで GET | 401 または 503 / 200 | NOT RUN | — |
| IT-06 | Grafana | dashboard を表示 | datasource / panel 正常 | NOT RUN | — |
| IT-07 | logs | LogQL で Nginx log 検索 | 対象 log を取得 | NOT RUN | — |
| IT-08 | alert | test alert を発火 | 2 分以内に通知 | NOT RUN | — |
| IT-09 | D-1 復旧 | app process を停止 | 検知・自動復旧・正常化 | NOT RUN | — |
| IT-10 | backup restore | snapshot を別 volume へ復元 | 内容一致 | NOT RUN | — |
| IT-11 | network fault | 二セグメントラボを実行 | 失敗、原因特定、復旧 | NOT RUN | — |
| IT-12 | 実ホスト network | [NW-01〜09](09-network-validation-procedure.md)を実行 | IP / DNS / route / listen / HTTP / packet / FW が設計どおり | NOT RUN | [結果票テンプレート](../evidence/templates/network-host-validation.md) |
| IT-13 | 複数台 scrape | 2 台目の node_exporter を追加 | Prometheus が名前解決だけで対象を `up=1` に切り替える | NOT RUN | — |

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ST-01 | bind address | `ss -lntup` | 管理 UI は loopback のみ | NOT RUN | — |
| ST-02 | container user | `docker inspect` | app は root でない | NOT RUN | — |
| ST-03 | secret tracking | `git ls-files deploy/secrets` | 実値なし | NOT RUN | — |
| ST-04 | firewall | `ufw status verbose` | 許可通信だけ開放 | NOT RUN | — |
| ST-05 | secret scan | CI security scan | high severity なし | NOT RUN | — |
| ST-06 | storage 安全装置 | `storage-guard-test.sh`（negative test 7 ケース） | 意図した拒否がすべて成立 | NOT RUN | — |

## 終了判定

- 必須 ID: UT-01〜04、UT-06、IT-01〜09、IT-12、ST-01〜05
- `FAIL` または `BLOCKED` が 1 件でもあれば構築完了としません。
- 必須 ID に `NOT RUN` が残る場合も構築完了としません。
- AWS を使用しない検証では UT-05 を `BLOCKED (AWS credentials not used)` とせず、ローカル `validate` の結果を記録します。
- 結果はこの原本を直接上書きせず、`docs/evidence/YYYY-MM-DD-build-validation.md` にコピーして保存します。

2026-08-19の既存結果票は本項目追加前の履歴です。ephemeral runnerのIT-12は上記E2Eで
別途採録済みですが、引き渡し対象host/管理端末のIT-12へ読み替えず、その対象環境で別途採録します。

