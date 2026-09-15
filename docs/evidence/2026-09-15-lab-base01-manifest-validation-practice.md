# lab-base01：不正ハッシュ一覧の拒否試験（2026-09-15）

## 結果と範囲

本人VMでcheck_logs.pyの実ソースとSHA-256を読み、空一覧・形式不正・重複名・親パス指定の
4ケースを専用データで試した。全件期待したERROR・終了2、テストランナー4/4 PASS・終了0、
スクリプトの前後ハッシュ一致を確認した。**4つの不正一覧の試験**であり、全入力の安全性保証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが試験コードを提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01、Python 3.12.3（E01） |
| 対象 | /home/opsadmin/ansible-log-checker/check_logs.py |
| 試験先 | 同ディレクトリ内のmanifest-cases-接頭辞付き一時ディレクトリ（E03） |
| 原資料 | [本人提供画像3枚・ハッシュ](screenshots/2026-09-15-lab-base01-manifest-validation-practice/README.md) |

## 実ソース確認

E01/E02でcatによる実スクリプト本文を分割採録し、sha256sum表示を確認した。
一覧の全行を検査してentriesを作り、不正ならreturn 2、完了後にファイル照合へ進む構成である。
前段のソース全文未採録を今回補ったが、過去の実行時点で同じソースだったと遡って保証しない。
この公開作業ではスクリプト実体や機械可読なrawログは取得していない。

## 確認結果

MV番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | ケース | ERROR出力 | 実際の終了コード | 判定 |
| --- | --- | --- | --- | --- |
| MV-01 | empty | empty manifest | 2 | PASS |
| MV-02 | bad_format | invalid manifest line 2 | 2 | PASS |
| MV-03 | duplicate | invalid or duplicate filename at line 2 | 2 | PASS |
| MV-04 | parent_path | invalid manifest line 2 | 2 | PASS |

E03でTESTS_PASSED=4/4、test runner exit=0を確認した。
案内したランナーは終了2・標準出力の期待エラー完全一致・標準エラーなしを判定する構成。
空一覧以外は正常行の後に不正行を置いた。E03には結果の全ケース名とERRORがあるが、
ケース定義と判定式全体は画面外であるため、提示コードと実ランナーの完全同一性は未検証。
正常ファイルのOK行やSUMMARYは表示されず、実ソースの事前検査構造とも整合する。
システムコール追跡によるファイル未アクセスの独立証明は実施していない。

## スクリプトの維持

E02で表示されたスクリプトSHA-256とE03のCHECKER_SHA256_BEFORE/AFTERは一致し、
CHECKER_UNCHANGED=Trueを確認した。値の原本は画像を参照する。
画像用SHA256SUMS.txtはスクリプトのハッシュとは別である。

## 未実施・限界

- 試験データは新しいディレクトリへ作る手順。元ログ・既存一覧の前後ハッシュ比較は今回未実施。
- 一覧の読取り権限不足・欠落・不正UTF-8、特殊ファイル、競合状態、巨大入力はNOT RUN。
- ../outside.logの拒否1件を全パス表記・全OSの検証へ一般化しない。
- スクリプト自体のGit保存・変更は今回案内していない。試験データは復習用に残す手順である。
- タイムアウト分岐・ランナー自身の失敗分岐は未検証。
- ログや一覧、スクリプト実体を公開資料へ添付しない。
- server側の文書検査・CIと本人のPython試験を区別する。

- [前段：ログ検証4分類](2026-09-15-lab-base01-log-checker-practice.md)
- [検証証跡台帳](README.md)
