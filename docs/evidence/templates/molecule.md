# Molecule フル実行記録テンプレート

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象 commit | `commit-sha` |
| 実行環境 | local Linux / GitHub Actions manual workflow |
| Python | `python --version` |
| Ansible | `ansible --version` |
| Molecule | `molecule --version` |
| Docker | `docker version` |

## 実行コマンド

```bash
cd ansible/roles/common
molecule test

cd ../docker
molecule test

cd ../nginx
molecule test

cd ../monitoring
molecule test
```

## 結果

| Role | create | converge | idemp | verify | destroy | Time |
| --- | --- | --- | --- | --- | --- | --- |
| common | P/F | P/F | P/F | P/F | P/F | 00:00 |
| docker | P/F | P/F | P/F | P/F | P/F | 00:00 |
| nginx | P/F | P/F | P/F | P/F | P/F | 00:00 |
| monitoring | P/F | P/F | P/F | P/F | P/F | 00:00 |

## ログ抜粋

```text
ここに失敗箇所または成功サマリを貼る
```

## 所見

- 良かった点:
- 見つかった課題:
- 次の対応:
