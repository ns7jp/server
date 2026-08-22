# 試験仕様書・結果票

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。

これは未指定の引き渡し対象host用に複製して記入する`NOT RUN`初期値の原本です。
使い捨てrunnerで実行済みの項目は[2026-08-22 Full-stack E2E](../evidence/2026-08-22-full-stack-e2e.md)に
別結果として保存しており、本原本を後から上書きしていません。

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

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ST-01 | bind address | `ss -lntup` | 管理 UI は loopback のみ | NOT RUN | — |
| ST-02 | container user | `docker inspect` | app は root でない | NOT RUN | — |
| ST-03 | secret tracking | `git ls-files deploy/secrets` | 実値なし | NOT RUN | — |
| ST-04 | firewall | `ufw status verbose` | 許可通信だけ開放 | NOT RUN | — |
| ST-05 | secret scan | CI security scan | high severity なし | NOT RUN | — |

## 終了判定

- 必須 ID: UT-01〜04、IT-01〜09、IT-12、ST-01〜05
- `FAIL` または `BLOCKED` が 1 件でもあれば構築完了としません。
- 必須 ID に `NOT RUN` が残る場合も構築完了としません。
- AWS を使用しない検証では UT-05 を `BLOCKED (AWS credentials not used)` とせず、ローカル `validate` の結果を記録します。
- 結果はこの原本を直接上書きせず、`docs/evidence/YYYY-MM-DD-build-validation.md` にコピーして保存します。

2026-08-19の既存結果票は本項目追加前の履歴です。ephemeral runnerのIT-12は上記E2Eで
別途採録済みですが、引き渡し対象host/管理端末のIT-12へ読み替えず、その対象環境で別途採録します。

