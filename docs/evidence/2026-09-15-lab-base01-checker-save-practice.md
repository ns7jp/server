# lab-base01：ログ検証ソース・9テストのGit保存と再検証（2026-09-15）

## 結果と範囲

本人がログ検証スクリプトの試験をunittestファイルへまとめ、9テスト成功を確認した。
試験用データを除外してソース3件を初回コミット88ece6dへ保存し、保存版でも9テスト成功・
終了0・前後HEAD一致・Git変更なしを確認した。**本人VM内のローカルGit保存と再検証**である。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIがコードと手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付） |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。Python版は今回再採録していない |
| リポジトリ | /home/opsadmin/ansible-log-checker。公開用serverやansible-first-labとは別 |
| 保存版 | main、短縮SHA88ece6d。完全SHAはE04/E05を参照 |
| 再検証直前のVM日時 | 2026-09-15T17:06:02+09:00（E05）。時計精度は未検証 |
| 原資料 | [本人提供画像5枚・ハッシュ](screenshots/2026-09-15-lab-base01-checker-save-practice/README.md) |

## 保存対象

| ファイル | コミット統計の追加行数 |
| --- | --- |
| .gitignore | 5 |
| check_logs.py | 60 |
| test_check_logs.py | 107 |

計3ファイル・172行追加。除外ルールは__pycache__/、*.pyc、/cases-*/、/manifest-cases-*/、
/permission-case-*/（E03）。既存試験データの削除は案内していない。
ステージ・コミット一覧に試験データはなく、除外されない未追跡ファイルの一覧も出力なしだった。
個別check-ignoreや保存後の試験データ存在確認は未採録。

## 確認結果

CS番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| CS-01 | 開始 | PASS | 既存check_logs.py・試験ディレクトリ・SHA表示、not a git repository（E01） |
| CS-02 | コミット前試験 | PASS | 9テストすべてok、Ran 9 tests、OK、tests exit=0、checker前後SHA一致（E02） |
| CS-03 | 保存対象選別 | PASS | init -b main、3ファイルのadd、空白検査終了0、3件172行、未追跡一覧出力なし（E03） |
| CS-04 | identity設定 | PASS | --localのname/email設定と読戻しを確認（E04） |
| CS-05 | コミット | PASS | root-commit 88ece6d、3件172行、main clean、show --stat（E04） |
| CS-06 | 保存版試験 | PASS | LC_ALL=C python3 -m unittest -v test_check_logs.pyで9件ok、終了0（E05） |
| CS-07 | 保存版維持 | PASS | 実行前後の完全HEAD一致、前後statusがmain行のみ（E05） |

## 9テストの観点

表示されたテスト名はbad_format、directory_error、empty_manifest、duplicate、mismatch、
missing、ok、parent_path、permission_error_and_restore。E02/E05ともスキップ表示はない。
作成を案内したテストは専用TemporaryDirectoryを使い、終了時にそのデータを片付ける構成である。
実テストファイル全文の独立読戻しとハッシュ、片付け後のファイル一覧は未採録。
107行のファイルとして保存されたことと9件の実行結果に限定して記録する。

前段のスクリプト4分類・不正一覧・権限不足の確認をファイル化する演習であり、
9テスト成功を全入力・全OS・全I/O条件の保証として扱わない。
コミット前の試験と、保存後の88ece6dでの試験は別実行として区別する。

## 未実施・限界

- VM内ソースのpush・PR・別媒体バックアップ・bundle作成はNOT RUN。
- ソース全体のステージ済みdiff表示、作成したtestファイル全文とハッシュの読戻しは未採録。
- author/署名の検証は未実施。Git identity設定はGitHub認証ではない。
- 特殊ファイル・競合状態・巨大入力・他OSでの検証はNOT RUN。
- Git変更なしは追跡対象の状態であり、除外データ全体の不変性保証ではない。
- ソース実体・試験データ・rawログを公開用作業では取得していない。画像をソースの配布物として扱わない。
- server側の文書追加コミット・CIと本人VMの88ece6dの試験を区別する。

- [前段：権限不足と復帰試験](2026-09-15-lab-base01-checker-permission-practice.md)
- [検証証跡台帳](README.md)
