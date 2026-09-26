# lab-base01：Pythonログ検証スクリプトの4分類（2026-09-15）

## 結果と範囲

本人VMでSHA-256一覧を読むPythonスクリプトを作成し、既存の正常ログ5件と専用データ4ケースで検証した。
正常・内容不一致・欠落・ディレクトリによる読み取りエラーを区別し、4/4 PASS、テストランナー終了0を確認した。
**限定した入力形式と4ケースの演習**で、汎用ログ検証ツールの全入力・全環境保証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIがコードと手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01、Python 3.12.3（E01） |
| スクリプト | /home/opsadmin/ansible-log-checker/check_logs.py |
| 正常ログ | /home/opsadmin/ansible-change-extract/SHA256SUMS.txtと同ディレクトリの5ログ |
| 試験データ | ansible-log-checker配下のmkdtempで作ったcases-接頭辞のディレクトリ（E04） |
| 原資料 | [本人提供画像4枚・ハッシュ](../screenshots/2026-09-15-lab-base01-log-checker-practice/README.md) |

## 案内した実装

64桁SHA-256、空白2つ、英数字・下線・ピリオド・ハイフンからなるファイル名の形式を読み、
一覧の親ディレクトリを基準に各ファイルを照合する構成を提示した。
正常をOK、不一致をMISMATCH、FileNotFoundErrorをMISSING、ほかのOSErrorをERRORとし、
集計と終了コード（正常0、不一致/欠落1、エラー2）を返す。
サブディレクトリやシンボリックリンクを対象外とする案内である。
画像は作成入力の断片で、実スクリプト全体の独立した読戻し・ハッシュ採録ではない。

## 確認結果

PC番号は本結果票専用。PASSは画面で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| PC-01 | 前提 | PASS | Python 3.12.3、作成先NOT FOUND、一覧存在（E01） |
| PC-02 | 一覧形式 | PASS | 5行のSHA-256と単純ファイル名を確認（E02） |
| PC-03 | 既存ログ | PASS | 全5件OK、OK=5/MISMATCH=0/MISSING=0/ERROR=0、checker exit=0（E03） |
| PC-04 | okケース | PASS | OK: sample.log、OK=1、期待0/実際0、TEST=PASS（E04） |
| PC-05 | mismatchケース | PASS | MISMATCH: sample.log、MISMATCH=1、期待1/実際1、TEST=PASS（E04） |
| PC-06 | missingケース | PASS | MISSING: sample.log、MISSING=1、期待1/実際1、TEST=PASS（E04） |
| PC-07 | directoryケース | PASS | ERROR: sample.log、Errno 21 Is a directory、ERROR=1、期待2/実際2、TEST=PASS（E04） |
| PC-08 | 全体結果 | PASS | TESTS_PASSED=4/4、test runner exit=0（E04） |

各専用ケースはsample.logの期待ハッシュを一覧に書き、正常内容・変更内容・ファイル不在・
同名ディレクトリを用意する手順を提示した。元の5ログを変更する操作は案内していない。
テストランナーは終了コードと分類行を照合する構成で、集計値は画面で確認した。
全入力コードの採録ではなく、専用データ内容の独立した読み戻しも未実施。

## 未実施・限界

- 権限不足、一覧の欠落・不正形式・重複・空一覧、シンボリックリンクの実行試験はNOT RUN。
- 複数分類が同時にある場合の終了コード優先順位の試験はNOT RUN。
- 特殊ファイル、巨大ファイル、処理中のファイル変更、他OSでの試験はNOT RUN。
- directoryケースは権限拒否試験ではない。ERRORの全原因を網羅していない。
- 入力ファイル・スクリプト全文の独立読戻し、ソースのGit保存・ハッシュ・rawログは未採録。
- 元ログの今回作業前後のハッシュ比較や最終ファイル一覧は未採録。
- スクリプトと試験データはVM内に残す案内。実体を今回の公開用作業では取得・添付していない。
- この画像記録を新しい汎用ツールの配布・安全性保証とは扱わない。
- server側の文書検査・CIと本人のPython実行を区別する。

- [前段：欠落検出と名前復帰](2026-09-15-lab-base01-missing-log-practice.md)
- [検証証跡台帳](../README.md)
