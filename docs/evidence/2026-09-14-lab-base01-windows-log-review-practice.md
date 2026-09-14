# lab-base01：Windows側でのログ確認（2026-09-14）

## 結果と範囲

本人がWindowsへコピー済みの正常・失敗ログをPowerShellで読み、COMMAND・集計・ANSIBLE_EXITを抽出した。
正常は8091/failed0/終了0、失敗は70000/failed1/終了2と照合できた。
**保存済みログの読み取り**であり、Ansibleを再実行した結果ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。実行・撮影の正確な時刻は未採録 |
| 環境 | ホストWindowsのPowerShell。OS/PowerShell版は今回未採録 |
| 対象 | Documents内のAnsibleLogs-識別子フォルダーにコピー済みのrole-fail/role-runログ各1件 |
| 原資料 | [本人提供画像1枚・ハッシュ](screenshots/2026-09-14-lab-base01-windows-log-review-practice/README.md) |

## 実施した読み取り

Get-ChildItemでファイル名・Lengthを表示し、各ログをSelect-Stringで検索した。
検索パターンはCOMMAND行、ANSIBLE_EXIT行、localhostの集計行を対象とする。
画像にはファイルパス・行番号・一致した行が表示されており、折返し部分を含めて結果を確認した。

## 確認結果

WR番号は本結果票専用。すべてE01の画面で確認した範囲である。

| ID | 観点 | 判定 | 結果 |
| --- | --- | --- | --- |
| WR-01 | 対象一覧 | PASS | 失敗ログ1321バイト、正常ログ1395バイトの2件 |
| WR-02 | 失敗ログの条件 | PASS | COMMANDにstagingとポート70000 |
| WR-03 | 失敗ログの結果 | PASS | ok0/changed0/failed1とANSIBLE_EXIT=2 |
| WR-04 | 正常ログの条件 | PASS | COMMANDにstagingとポート8091 |
| WR-05 | 正常ログの結果 | PASS | ok3/changed0/failed0とANSIBLE_EXIT=0 |

ログ名だけで結果を判断せず、保存されたコマンド説明・集計・終了コードを照合した。
COMMANDは前段の保存手順が出力した説明行で、自動シェルトレースではない。
Select-String自体の数値終了コードは未採録で、今回の確認は表示された抽出結果に限定する。

## 未実施・限界

- 今回Ansible再実行、scp再転送、SHA-256再比較は行っていない。ハッシュ一致は前段結果票の記録。
- ログ全文ではなく指定3種類の行を抽出した。全内容のレビュー・自動判定器の検証ではない。
- Windows ACL、コピー後ファイルの改ざん防止、別媒体バックアップや復元試験は**NOT RUN**。
- ログ実体はこの公開用作業では取得・添付していない。画像をrawログとして扱わない。
- ファイル変更を伴う操作は案内していないが、読取り前後のハッシュ比較は今回未採録。
- server側の文書検査・CIと本人によるWindows上の読み取りを区別する。

## 復習

ログ名の印象だけでなく、何を実行したか・失敗数・終了コードを組にして読む。
これはAIによる復習用説明で、本人独力による説明を採録したものではない。

- [前段：Windowsへのログ転送](2026-09-14-lab-base01-log-transfer-practice.md)
- [検証証跡台帳](README.md)
