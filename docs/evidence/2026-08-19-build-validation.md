# 試験仕様書・結果票 — 2026-08-19

[docs/build-package/06-test-specification.md](../build-package/06-test-specification.md) の原本をコピーし、
実際に確認できた項目だけ結果を記入したもの。**全件を埋めていない。** 空欄のまま残っている `NOT RUN` は
未確認であることの表明であり、恥じるべきものではない（原本の運用ルールどおり）。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | 2026-08-19（複数の確認を集約。個別の実行日時は各行に記載） |
| 実施者 | 島田則幸 |
| 環境 | ローカル Linux（WSL2 Ubuntu 24.04）+ GitHub Actions（`ubuntu-latest`） |
| commit SHA | `cc7e478`（`main`、PR #61 マージ後） |
| OS / tool versions | pytest 8.x→CIでは9.1.1、Docker Compose 2.40.3、ansible-core 2.19.12、詳細は各行の実行 URL 参照 |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入する。空欄のままの `NOT RUN` は成功実績ではない。

## 単体・構成試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| UT-01 | Python tests | `pytest` | 全 test pass | **PASS** | 14 passed（[CI](https://github.com/ns7jp/server-monitor/actions/runs/32227795483)、2026-08-19T07:25:57Z） |
| UT-02 | Compose config | `docker compose config --quiet` | exit 0 | **PASS** | exit 0（ローカル実行、2026-08-19） |
| UT-03 | Prometheus rules | `promtool check rules ...` | SUCCESS | **PASS** | CI 内で `promtool check config` / `check rules` を実行（[CI](https://github.com/ns7jp/server-monitor/actions/runs/32227795483)、同上） |
| UT-04 | Ansible syntax | `ansible-playbook playbooks/site.yml --syntax-check` | exit 0 | **PASS** | `playbook: playbooks/site.yml` を出力し exit 0（ローカル実行、ansible-core 2.19.12、2026-08-19） |
| UT-05 | Terraform validate | `terraform validate` | Success | **PASS** | `validate (dev)` / `validate (prod)` 両ジョブ success（[CI](https://github.com/ns7jp/server-monitor/actions/runs/32223863869)、2026-08-19T06:32:46Z） |

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| IT-01 | 新規構築 | `site.yml` 適用 | `failed=0` | NOT RUN | 個別ロールの Molecule 検証は完了しているが、`site.yml` を通した複数ロール一括適用は未実施 |
| IT-02 | 冪等性 | `site.yml` 2 回目 | `changed=0`, `failed=0` | NOT RUN | 同上 |
| IT-03 | host metrics | Prometheus query | linux-node `up=1` | NOT RUN | Grafana ダッシュボード上の scrape 状態は確認したが、Prometheus targets ページでの直接確認は未実施 |
| IT-04 | UI auth | 認証なし / ありで GET | 401 または 503 / 200 | NOT RUN | — |
| IT-05 | metrics auth | token なし / ありで GET | 401 または 503 / 200 | NOT RUN | — |
| IT-06 | Grafana | dashboard を表示 | datasource / panel 正常 | **PASS** | [ローカル可観測性証跡 2026-08-18](2026-08-18-local-observability.md)（Infrastructure Lab / SLO 両ダッシュボードで実データ表示を確認） |
| IT-07 | logs | LogQL で Nginx log 検索 | 対象 log を取得 | **PASS** | [同上](2026-08-18-local-observability.md)（nginx エラーログ 103 行を実取得） |
| IT-08 | alert | test alert を発火 | 2 分以内に通知 | NOT RUN | Alertmanager UI 上の FIRING 表示は別の機会に確認したが、証跡ファイルが残っていない。Slack 等の実通知配信も未確認 |
| IT-09 | D-1 復旧 | app process を停止 | 検知・自動復旧・正常化 | **PASS** | [D-1 演習記録 2026-08-19](../drills/logs/2026-08-19-D-1.md)（RTO 13 秒、`RestartCount` 0→1） |
| IT-10 | backup restore | snapshot を別 volume へ復元 | 内容一致 | NOT RUN | — |
| IT-11 | network fault | 二セグメントラボを実行 | 失敗、原因特定、復旧 | **PASS** | [二セグメント障害ラボ証跡 2026-08-19](2026-08-19-network-drill.md)（`proxy` を `backend` から切断→502確認→`docker network inspect`/`ip route`で原因特定→再接続で復旧、6段階すべてPASS） |

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ST-01 | bind address | `ss -lntup` | 管理 UI は loopback のみ | NOT RUN | `compose.yaml` は全ポートを `127.0.0.1:PORT:PORT` で宣言している（静的事実）が、稼働中スタックへ `ss -lntup` を実行しての確認はしていない |
| ST-02 | container user | `docker inspect` | app は root でない | NOT RUN | `Dockerfile` は `USER monitor`（非 root）を宣言している（静的事実）が、稼働中コンテナへの `docker inspect` 確認はしていない |
| ST-03 | secret tracking | `git ls-files deploy/secrets` | 実値なし | **PASS** | `.example` ファイル 4 件のみが追跡対象（ローカル実行、2026-08-19） |
| ST-04 | firewall | `ufw status verbose` | 許可通信だけ開放 | NOT RUN | UFW ルールの妥当性は Molecule の idempotence テストで検証済み（[Molecule フル実行記録](2026-08-17-molecule.md)）だが、実ホストでの `ufw status verbose` による確認ではない |
| ST-05 | secret scan | CI security scan | high severity なし | **PASS** | Trivy スキャン success（[CI](https://github.com/ns7jp/server-monitor/actions/runs/32227795460)、2026-08-19T07:25:56Z） |

## 終了判定

必須 ID（UT-01〜04、IT-01〜09、ST-01〜05）のうち、**UT-01〜05、IT-06・07・09・11、ST-03・05 は PASS**（21 項目中 11 項目）。
IT-01・02・03・04・05・08・10、ST-01・02・04 は **NOT RUN** のまま残っている。

**この状態を「構築完了」とは判定しない。** 特に IT-01/02（`site.yml` を通した複数ロール一括適用）が
未実施である点は、個々のロールが Molecule で検証済みであることと混同してはならない。

## 関連

- [試験仕様書（原本）](../build-package/06-test-specification.md)
- [検証証跡台帳](README.md)
- [Molecule フル実行記録 2026-08-17](2026-08-17-molecule.md)
- [ローカル可観測性証跡 2026-08-18](2026-08-18-local-observability.md)
- [D-1 演習記録 2026-08-19](../drills/logs/2026-08-19-D-1.md)
- [既存 CI 成功ログ証跡 2026-08-19](2026-08-19-ci-baseline.md)
