# 試験仕様書・結果票

> 💡 **初めて読む方へ**: この文書は完成したかどうかを判定する「試験問題と模範解答」です。原本がなぜ常に `NOT RUN` のままなのかは[初心者ガイド](beginner-guide.md#06-試験仕様書結果票)で先に説明しています。

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
| ST-06 | storage 安全装置 | `storage-guard-test.sh`（negative test 6 ケース + 許可される正常系 1 ケース） | 意図した拒否がすべて成立し、正常系ケースは拒否されない | NOT RUN | — |

## 性能試験

負荷をかけて、スループット（秒あたり処理本数）・レイテンシ分布（応答時間のばらつき）・
エラー率・飽和点（さばききれなくなる点）を測る試験です。測り方と結果の読み方は
[負荷試験の手順と読み方](../performance-test.md)にまとめています。

合否条件の `p95 <= 500ms` は [docs/slo.md](../slo.md) の
[2.2 レイテンシ](../slo.md#22-レイテンシ)の値をそのまま使います。この章で新しい
目標値は作りません。エラー率 `0.01` は
[`scripts/perf/run-perf.sh`](../../scripts/perf/run-perf.sh) が判定に使う値です。

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| PT-01 | 集計ロジック単体 | `pytest tests/test_perf.py` | 全 test pass（パーセンタイル・エラー率・SLO 判定の境界） | PASS | 2026-09-17 CI [python-check](https://github.com/ns7jp/server/actions/runs/35197884833)。GitHub hosted runner（PR ブランチ） |
| PT-02 | perf overlay 構文 | `docker compose -f compose.yaml -f compose.perf.yaml config --quiet` | exit 0 | PASS | 2026-09-17 CI [python-check](https://github.com/ns7jp/server/actions/runs/35197884833)。GitHub hosted runner（PR ブランチ） |
| PT-03 | 基準計測 | `scripts/perf/run-perf.sh --steps 1` | 並列 1 の段が `p95 <= 500ms` かつ `error_rate <= 0.01` で PASS | NOT RUN | — |
| PT-04 | 段階負荷・飽和候補 | `scripts/perf/run-perf.sh --steps 1,2,4,8,16,32` | 全段の結果表、飽和候補、各段のSLO判定を保存。単発の候補を容量の確定値にしない | **部分実行・分析済み／一部FAIL** | [2026-09-17 保存結果の再評価](../evidence/2026-09-17-performance-ci-analysis.md)。並列1,2,4,8,16・各20秒・助走は最初に5秒だけ。並列4/8はHTTP502を含めると失敗率1%超、並列4はCI基準5%超。32並列は未実施 |
| PT-05 | worker 数の比較 | `--workers` の値を変えて PT-04 を 2 回 | 2 回の結果が別の run directory に保存され、飽和点と p95 を比較できる | NOT RUN | — |
| PT-06 | 重いエンドポイント | `load.py` で `/stats` を計測（認証 header 付き） | `status_counts` が 200 のみ。`/healthz` との p95 の差が記録される | NOT RUN | — |
| PT-07 | 過負荷時の挙動 | PT-04 の飽和点を超える並列数で実行 | エラー率と p95 は悪化してよいが、`app` / `nginx` は終了せず `RestartCount` が増えない。負荷停止後に `/healthz` が 200 へ戻る | NOT RUN | — |
| PT-08 | エラーの内訳 | PT-07 の `step-c<並列数>.json` を確認 | `error_counts` に種別（timeout / connection_error）が分かれ、`latency_ms.count` と `response_requests` が一致する（タイムアウトが応答時間に混入していない） | NOT RUN | — |
| PT-09 | SLO 未達時の判定 | 全段が SLO を満たさない条件で実行 | 全体 verdict が `FAIL`、終了コードが非 0。PASS として記録されない | NOT RUN | — |
| PT-10 | 疎通不可時の中止 | `app` を停止した状態で `run-perf.sh --no-compose` | 120 秒待って exit 4。結果 directory も数値も作られない | NOT RUN | — |
| PT-11 | 不正な引数の拒否 | `--steps 8,4` / `--duration 0` / `--url ftp://example` | いずれも exit 2。負荷をかけずに停止する | NOT RUN | — |
| PT-12 | 途中打ち切り | 計測中に SIGINT (Ctrl+C) | 結果 JSON の `partial` が `true` になり、部分的な計測である旨が出力に明記される | NOT RUN | — |
| PT-13 | CI 実行 | Actions → [Performance test](../../.github/workflows/perf-test.yml) → Run workflow | artifactに各段JSONとログを保存。HTTP・通信失敗の合計率が基準超過、値欠測、途中打切りなら失敗する | **旧版実行済み・判定欠陥あり** | [旧runの再評価](../evidence/2026-09-17-performance-ci-analysis.md)。新しい判定コードの実行状態は当該変更のCIで別確認。本人環境の実施ではない |

PT-07 の「飽和点を超える並列数」は PT-04 の実測から決めます。事前に数字を決め打ちしません。

PT-05 は `compose.perf.yaml` が起動コマンドを上書きしてworker数を変更します。
`--no-compose` 時は既存の起動状態を測るため、指定値は反映されません。
指定値・実適用の有無・app起動ログを分けて確認します。

判定の境界について。`load.py` はしきい値ちょうどを PASS とします（`p95 <= 500`）。
`docs/slo.md` の表記は `p95 < 500ms`（未満）のため、ちょうど 500.0ms のときだけ
判断が分かれます。この表の期待結果は `load.py` の判定（`<=`）に合わせています。

PT-13 の CI は GitHub hosted runner の性能ばらつきを踏まえ、絶対値では合否を出しません。
**CI の成功は SLO の達成を意味しません。**

この章の試験はいずれも 1 台・ローカル・コンテナ内の計測であり、本番環境の性能保証値
にはなりません（[測定の限界](../performance-test.md#9-測定の限界)）。

> **2026-09-17 の CI 実行について**
>
> PT-01・PT-02・PT-04 は、この試験項目書を追加した PR の CI で自動実行されました。
> 実行環境は **GitHub hosted runner（PR ブランチ、使い捨て）**、実行者は **CI（人手ではない）**です。
> 本人の手元の環境で実施したものではありません。
>
> PT-04の原本を分析し、HTTP502の集計漏れを確認しました。元のCI成功は性能合格ではありません。
> [日付付き分析と原本](../evidence/2026-09-17-performance-ci-analysis.md)に、p95、再計算した失敗率、容量を確定できない理由を保存しています。

## 終了判定

- 必須 ID: UT-01〜04、UT-06、IT-01〜09、IT-12、ST-01〜05
- `FAIL` または `BLOCKED` が 1 件でもあれば構築完了としません。
- 必須 ID に `NOT RUN` が残る場合も構築完了としません。
- AWS を使用しない検証では UT-05 を `BLOCKED (AWS credentials not used)` とせず、ローカル `validate` の結果を記録します。
- 結果はこの原本を直接上書きせず、`docs/evidence/YYYY-MM-DD-build-validation.md` にコピーして保存します。
- 性能試験 PT-01〜PT-13 は必須 ID に含めません（1 台・ローカルの参考計測のため）。実施した場合は結果を `docs/evidence/YYYY-MM-DD-performance-test.md` に保存し、SLO の達成主張には使いません。

2026-08-19の既存結果票は本項目追加前の履歴です。ephemeral runnerのIT-12は上記E2Eで
別途採録済みですが、引き渡し対象host/管理端末のIT-12へ読み替えず、その対象環境で別途採録します。

