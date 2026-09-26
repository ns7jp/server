# lab-base01：保存コミットでのrole正常再実行（2026-09-14）

## 結果と範囲

本人VMでコミット38559f2の作業状態から入力検証付きroleをstaging/8091で通常再実行した。
全3タスクok、changed0、failed0、終了0。前後のHEADと対象ファイルのSHA-256が一致し、
本文staging/8091とGitの変更なしを確認した。
**保存版の入力検証付きroleの正常再実行**であり、全Playbook・不正入力・実サービスの検証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付） |
| VM表示日時 | 実行直前のdate -Isは2026-09-14T14:14:18+09:00（E02）。時計精度・終了時刻は未確認 |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。OS/Ansible版は今回未採録 |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| ブランチ | practice/save-ansible-exercises |
| コミット | 短縮SHA 38559f2。完全SHAはE01/E02のgit rev-parse HEAD出力を参照 |
| 証拠 | [本人提供画像2枚・ハッシュ](../screenshots/2026-09-14-lab-base01-saved-rerun-practice/README.md) |

## 実行したコマンド

E02で次の通常実行コマンドを確認した。

```bash
ansible-playbook -i localhost, role-validated-demo.yml   -e practice_config_environment=staging   -e practice_config_port=8091
```

## 確認結果

SR番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| SR-01 | 開始状態 | PASS | ユーザー・ホスト名、ブランチ行のみのstatus、HEADとlogの38559f2、本文staging/8091（E01） |
| SR-02 | 実行の対応付け | PASS | date、HEAD、対象ファイルSHA-256と、通常実行の入力行を確認（E02） |
| SR-03 | 正常再実行 | PASS | assert通過、ディレクトリ・templateともok。ok3/changed0/failed0、終了0（E02） |
| SR-04 | 生成ファイル | PASS | 前後のSHA-256一致、本文staging/8091維持（E02） |
| SR-05 | 保存版の維持 | PASS | 実行後もブランチ行のみのstatus、HEADは実行前と一致（E02） |

この画像群により保存コミット・作業状態・入力引数・今回の結果を対応付けた。
過去の演習結果を38559f2の結果へ付け替えず、前段の保存時点で再実行NOT RUNだった記録は保持する。

## 証拠の限界

- 完全SHAと生成ファイルのSHA-256は画像表示での確認。機械可読なログやGit bundleは未取得。
- Gitの変更なしは追跡対象の状態であり、除外ファイルや実行環境全体の同一性を保証しない。
- 対象ファイルのハッシュ一致は内容の比較で、権限・mtime・全ディレクトリの不変性検査ではない。
- 日時はVM内時計の表示。時刻同期や実行時間は未検証。
- 入力ファイル群の全ハッシュ・全設定・依存パッケージの固定は未採録。

## 未実施

- この保存版での他Playbook、不正ポート・環境名・境界値の再検証は**NOT RUN**。
- 実サービスの起動・配備・ポート待受・複数ホスト実行は**NOT RUN**。
- VMリポジトリのpush・別媒体バックアップは**NOT RUN**。
- 今回のserver側の文書追加・CIと、本人VMの38559f2での実行を区別する。

## 復習

実行前にコミットと作業状態を確認し、日時・入力引数・結果・実行後状態を組にして記録する。
これはAIによる復習用説明で、本人独力による説明を採録したものではない。

- [前段：演習ソース保存](2026-09-14-lab-base01-save-ansible-practice.md)
- [検証証跡台帳](../README.md)
