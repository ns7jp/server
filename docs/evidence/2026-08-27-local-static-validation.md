# 2026-08-27 ローカル静的・単体検証

## 目的

現行 `main` を基点に、作業結果報告書と案件導線を追加した作業ツリーについて、この Windows 環境で実行できるコード・成果物検査を再実行する。Linux ホスト、Docker、Ansible、Terraform を必要とする試験は実行せず、過去の runtime 証跡を現行作業ツリーの結果へ読み替えない。

## 対象と再現性の境界

| 項目 | 値 |
| --- | --- |
| 実施日 | 2026-08-27 JST |
| 基点 commit | `b97ccbc30b6c57cbf13bc283bdf0ffbbb4313083` |
| 作業ツリー | 上記 commit + 作業結果報告書、案件導線、パラメータ欄、関連 test の未コミット差分 |
| 状態 | **dirty**。基点 commit だけではこの文書追加後の状態を再現できない |
| OS | Microsoft Windows NT 10.0.26200.0 |
| Python | 3.12.13 |
| pytest | 9.1.1 |
| Git | 2.55.0.windows.5 |

依存パッケージは `requirements-dev.txt` から作業用 `.venv` へ導入した。`.venv` と `__pycache__` は Git 追跡外で、成果物へ含めない。変更が commit された後に CI を再実行し、その commit SHA と run URL を別途固定する必要がある。

## 実行結果

`python` は作業用 `.venv` の Python 3.12.13 を指す。

| ID | 対応する試験 / 対象 | コマンド | 実測結果 | exit code | 所要時間 | 判定 |
| --- | --- | --- | --- | ---: | ---: | --- |
| LOCAL-01 | UT-01、全 pytest | `python -m pytest -q` | `149 passed in 4.21s` | 0 | 4.651 秒 | PASS |
| LOCAL-02 | Python compile | `python -m compileall -q app.py tests scripts` | 出力なし | 0 | 0.119 秒 | PASS |
| LOCAL-03 | shell 構文 | tracked `*.sh` ごとに `bash -n <file>` | 15 files、0 failures | 0 | 0.753 秒 | PASS |
| LOCAL-04 | Grafana dashboard JSON | `python -m json.tool <file>` を 2 dashboard に実行 | 2 files、0 failures | 0 | 0.205 秒 | PASS |
| LOCAL-05 | YAML parse | PyYAML `safe_load` を `.yml` / `.yaml` へ実行 | 100 files、0 failures | 0 | 0.320 秒 | PASS |
| LOCAL-06 | ST-03 secret tracking | `git ls-files 'deploy/secrets/*'` を `.example` 以外がないか判定 | tracked 4 files、unexpected non-example 0 | 0 | 0.200 秒 | PASS |
| LOCAL-07 | UT-06 相対リンク | `python -m pytest -q tests/test_portfolio_artifacts.py -k internal_markdown_links` | `1 passed, 46 deselected in 0.14s` | 0 | 0.538 秒 | PASS |

LOCAL-01 は application unit test に加え、Ansible / Compose / Terraform の成果物を文字列・構造として検査する repository test を含む。ただし、実ツールによる構文検査や Linux runtime の代替ではない。

## この環境で実行できなかった試験

| 試験 | 状態 | 理由 / 解除条件 |
| --- | --- | --- |
| UT-02 Compose config | NOT RUN | Docker CLI / daemon なし。Docker が使える Linux か CI で実行 |
| UT-03 Prometheus / Alertmanager config | NOT RUN | `promtool` / `amtool` なし。固定 image を使う CI で実行 |
| UT-04 Ansible syntax / lint | NOT RUN | `ansible-playbook` / `ansible-lint` なし。Linux または CI で実行 |
| UT-05 Terraform fmt / validate | NOT RUN | Terraform CLI なし。CI で実行 |
| IT-01〜13 | NOT RUN | 対象 Linux ホストと Docker runtime なし |
| ST-01、ST-02、ST-04 | NOT RUN | 実ホスト / container runtime なし |
| ST-05 security scan | NOT RUN | Trivy / pip-audit workflow をこの場で再実行していない |
| ST-06 storage safety | NOT RUN | device-mapper を持つ Linux 環境なし |
| Slack、D-2、AWS、再起動・24h / 72h | NOT RUN | 外部受信先、別ホスト、AWS、恒久ホストなし |

WSL の executable は存在したが、Linux distribution は未導入だった。Docker、Ansible、Terraform のコマンドも存在しなかった。したがって、2026-08-22 / 23 の使い捨て runner E2E や 2026-08-18 / 19 の WSL2 実測は履歴として参照できるが、基点 commit またはこの作業ツリーの runtime 再検証とは扱わない。

## 判定

- この Windows 環境で実行可能だった静的・単体検証: **PASS**
- Linux runtime、監視、障害復旧、対象ホスト受け入れ: **NOT RUN**
- 案件の引き渡し判定: **`NOT READY`**

次の有効な gate は、変更を commit した SHA に対する CI と Full-stack E2E、その後の独立した Ubuntu Server 24.04 LTS VM での[受け入れ手順](../build-package/10-host-bringup-and-acceptance.md)です。
