# 試験仕様書・結果票

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

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| ST-01 | bind address | `ss -lntup` | 管理 UI は loopback のみ | NOT RUN | — |
| ST-02 | container user | `docker inspect` | app は root でない | NOT RUN | — |
| ST-03 | secret tracking | `git ls-files deploy/secrets` | 実値なし | NOT RUN | — |
| ST-04 | firewall | `ufw status verbose` | 許可通信だけ開放 | NOT RUN | — |
| ST-05 | secret scan | CI security scan | high severity なし | NOT RUN | — |

## 終了判定

- 必須 ID: UT-01〜04、IT-01〜09、ST-01〜05
- `FAIL` または `BLOCKED` が 1 件でもあれば構築完了としません。
- AWS を使用しない検証では UT-05 を `BLOCKED (AWS credentials not used)` とせず、ローカル `validate` の結果を記録します。
- 結果はこの原本を直接上書きせず、`docs/evidence/YYYY-MM-DD-build-validation.md` にコピーして保存します。

