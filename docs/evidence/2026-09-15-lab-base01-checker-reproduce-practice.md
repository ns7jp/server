# lab-base01：ログ検証ツールのローカルclone再現（2026-09-15）

## 結果と範囲

本人VMで保存版88ece6dのmainを別フォルダーへcloneし、追跡ファイル3件と9テストの成功を確認した。
cloneとtestsの終了コードは0、スキップ表示なし、実行前後のHEADは一致しGit変更なしだった。
**同じVM内の既存Python環境での再現試験**であり、新規OS・別ホストの検証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。Python/OS版は今回再取得していない |
| 元 | /home/opsadmin/ansible-log-checker |
| clone先 | /home/opsadmin/ansible-log-checker-reproduce |
| 保存版 | main、短縮SHA88ece6d。完全SHAはE01/E02参照 |
| 原資料 | [本人提供画像2枚・ハッシュ](screenshots/2026-09-15-lab-base01-checker-reproduce-practice/README.md) |

## 確認結果

CP番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| CP-01 | 前提 | PASS | 元main clean、HEAD88ece6d、追跡3件、clone先NOT FOUND（E01） |
| CP-02 | clone | PASS | --no-hardlinks --single-branch --branch mainでローカルclone、終了0（E02） |
| CP-03 | clone先 | PASS | pwdが再現先、HEAD一致、status変更なし、.gitignore/check_logs.py/test_check_logs.py（E02） |
| CP-04 | 試験 | PASS | LC_ALL=C python3 -m unittest -v test_check_logs.py、9件すべてok、OK、終了0（E02） |
| CP-05 | 最終状態 | PASS | main...origin/main、変更行なし、HEADは実行前と一致（E02） |

## 試験の範囲

9件はbad_format、directory_error、duplicate、empty_manifest、mismatch、missing、ok、
parent_path、permission_error_and_restore。スキップは表示されていない。
表示されたRan 9 tests in 0.554sはこの実行のunittest計測値で、性能保証ではない。
前段の保存版試験とは別の実行であり、今回のclone先での結果として記録する。

originはVM内の元リポジトリで、GitHubへ同期した証拠ではない。
Git管理対象3件が復元されたことは確認したが、clone先の全ファイル一覧や除外データの不在を
独立に検査したわけではない。依存関係は同じVMの既存環境を使用している。

## 未実施・限界

- 新規OS・別VM・Windows上の実行、異なるPython版での再現はNOT RUN。
- 特殊ファイル・競合状態・巨大入力などの追加試験はNOT RUN。
- 元とclone先の全ファイルハッシュ比較、権限・mtime比較、実ソース全文再取得は未採録。
- 試験用一時データの生成・片付け後の独立した一覧検査は今回未採録。
- 原リポジトリの作業後状態比較や別媒体バックアップは未実施。
- ソース・試験データ・機械可読な実行ログ実体は公開用作業で取得していない。
- server側の公開コミット・CIと本人VMの88ece6dでの試験を区別する。

- [前段：ソース保存と再検証](2026-09-15-lab-base01-checker-save-practice.md)
- [検証証跡台帳](README.md)
