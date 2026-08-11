# ローカルコード検証記録 — 2026-08-11

## 対象

| 項目 | 値 |
| --- | --- |
| 実施日時 | 2026-08-11 JST |
| 基点 commit | `aeabde9dedb5758b5bb573c38a5edc3f6ff332ce` |
| 対象差分 | 構築案件パック、二セグメント障害ラボ、成果物検査 test を追加した差分 |
| OS | Windows（Codex desktop workspace） |
| Python | 3.12.13 |
| pytest | 8.4.2 |

確定後の revision は、GitHub 上で本ファイルを最後に変更した commit を正本とします。この検証は Linux host、Docker、Ansible、AWS の実測ではありません。

## 実行コマンド

```powershell
python -m pip install -r requirements-dev.txt
python -m compileall app.py tests
python -m pytest
python -c "import pathlib,yaml; yaml.safe_load(pathlib.Path('labs/network-troubleshooting/compose.yaml').read_text())"
```

## 結果

```text
collected 14 items
tests/test_app.py ...........
tests/test_portfolio_artifacts.py ...
14 passed in 1.77s
```

| ID | 結果 | 備考 |
| --- | --- | --- |
| UT-01 Python tests | PASS | API / auth / metrics / artifact tests、14 件 |
| Python compile | PASS | `app.py` と `tests/` |
| YAML syntax | PASS | network lab Compose と変更した workflow を parse |
| Docker Compose config | NOT RUN | 実行端末に Docker がないため CI で検査予定 |
| Linux 新規構築 | NOT RUN | Ubuntu host が必要 |
| 二セグメント障害ラボ | NOT RUN | Linux + Docker が必要 |
| AWS validation | NOT RUN | 実 AWS 操作と費用発生を伴うため未実施 |

## 判断

Python コードと、追加した成果物の存在・未実測表示・二つの subnet 宣言は自動検査に合格しました。サーバー構築完了とは判定しません。次は Linux + Docker 環境で Compose 構文検査、全 stack 起動、D-1、二セグメント障害ラボを実行します。
