# lab-base01：ログ検証の権限不足と復帰試験（2026-09-15）

## 結果と範囲

本人VMで専用sample.logの読み取り権限を外し、check_logs.pyがMISSINGではなくERROR・終了2を返すことを確認した。
権限を600へ戻すとOK・終了0となり、両テストPASS、CHECKER_UNCHANGED=True、ランナー終了0を確認した。
**所有ファイルの権限による拒否1ケース**であり、すべてのI/OエラーやACL環境の保証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが試験コードを提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01、id -u=1001（E01） |
| スクリプト | /home/opsadmin/ansible-log-checker/check_logs.py、1901バイトとSHA-256表示（E01） |
| 試験データ | ansible-log-checker配下のpermission-case-接頭辞ディレクトリ（E02） |
| 原資料 | [本人提供画像2枚・ハッシュ](screenshots/2026-09-15-lab-base01-checker-permission-practice/README.md) |

## 試験の構成

非rootを確認し、新しい一時ディレクトリにダミーsample.logと期待SHA一覧を作る手順を提示した。
chmod(0o000)後に検査を実行し、finallyでchmod(0o600)に戻して再検査する構成。
元ログを操作するコードは案内していない。E02にはコード断片と実行結果があるが、
ケース生成・判定式全体の入力画面と試験データの独立読戻しは未採録。

## 確認結果

PE番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| PE-01 | 非root前提 | PASS | UID1001とVMユーザー・ホスト、スクリプト属性・ハッシュ（E01） |
| PE-02 | 権限不足検出 | PASS | ERROR: sample.log、Errno 13 Permission denied、MISSING=0/ERROR=1、ACTUAL_EXIT=2（E02） |
| PE-03 | 権限復帰 | PASS | RESTORED_MODE=600（E02） |
| PE-04 | 再検査 | PASS | OK: sample.log、OK=1/ERROR=0、ACTUAL_EXIT=0（E02） |
| PE-05 | ランナー | PASS | DENIED_TEST=PASS、RESTORE_TEST=PASS、CHECKER_UNCHANGED=True、終了0（E02） |

CHECKER_UNCHANGEDはランナー内の前後SHA比較による表示である。E02には両ハッシュ値そのものは表示されていない。
権限000の独立したstat表示は未採録だが、chmodの入力とPermission deniedの結果を確認した。
600復帰はstatからのモード表示を含む。今回finallyを確認したのは通常完走時で、強制終了時の復帰保証ではない。

## 未実施・限界

- manifest自体の権限拒否、親ディレクトリ権限、ACL・Windows権限、別ユーザー/別OSの試験はNOT RUN。
- 処理中のファイル差替え、特殊ファイル、巨大ファイル・タイムアウト分岐は未検証。
- スクリプト全体の今回の読戻し・Git保存、元ログの前後ハッシュ比較は未採録。
- 試験用ディレクトリは復習用に残す手順。削除や元ログ変更を案内していない。
- 実スクリプト・試験データ・機械可読なrawログをこの公開作業で取得していない。
- 画像用ハッシュとスクリプト・試験ファイルのハッシュは別である。
- server側の文書検査・CIと本人のVM内Python実行を区別する。

- [前段：不正一覧検証](2026-09-15-lab-base01-manifest-validation-practice.md)
- [検証証跡台帳](README.md)
