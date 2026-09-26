# lab-base01：ログ検証ツールのREADME作成と同期（2026-09-15）

## 結果と範囲

本人VMでログ検証ツールの使い方をREADME.mdに記載し、54行追加のコミット0e1a684を作成した。
同じVM内のclone先へgit pull --ff-onlyで取り込み、HEAD一致・追跡4ファイル・変更なしを確認した。
今回の変更は文書のみで、単体テストや保存ログの照合は再実行していない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順と文書案を提示し、本人がVMで実行・画像提供 |
| 日付 | 対話日2026-09-15 JST。操作時刻は今回未採録 |
| 環境 | プロンプト表示opsadmin@lab-base01。今回OS・Python版の再取得なし |
| 元リポジトリ | /home/opsadmin/ansible-log-checker |
| clone先 | /home/opsadmin/ansible-log-checker-reproduce |
| 文書コミット | 0e1a684、docs: add checksum checker usage guide（完全SHAは未採録） |
| 原資料 | [本人提供画像4枚・ハッシュ](../screenshots/2026-09-15-lab-base01-checker-readme-practice/README.md) |

## 確認結果

PASSは各画像で確認できる観点に限定する。

| 観点 | 判定 | 証拠 |
| --- | --- | --- |
| README作成 | PASS | ?? README.md、readme create exit=0（E01） |
| 文書内容 | PASS | 動作環境、manifest形式、結果・終了コード、テスト方法、検証範囲を表示（E01/E02） |
| 保存 | PASS | 1 file changed, 54 insertions、create mode 100644 README.md、0e1a684（E03） |
| 保存後状態 | PASS | main、変更行なし、readme commit exit=0（E03） |
| 取り込み | PASS | 元のローカルパスから88ece6d..0e1a684へFast-forward（E04） |
| 同期後状態 | PASS | HEAD・origin/mainが0e1a684、変更行なし、readme sync exit=0（E04） |
| 追跡対象 | PASS | .gitignore、README.md、check_logs.py、test_check_logs.pyの4件（E04） |

差分表示中はページャーをqで終了し、その後コミット処理の終了を確認した。
作成直後のREADMEは未追跡だったため、その時点のgit diff --checkだけではREADMEの空白検査を証明しない。
コミット手順にはステージ後のgit diff --cached --checkを含めたが、個別の終了コードは画像に未採録。

## 証拠の限界

- README内のPython版・9テスト成功・保存ログ5件の照合は前段の実績で、今回の再試験結果ではない。
- 原README実体の取得、完全コミットSHA・ファイルハッシュの比較は今回未実施。
- originはVM内の元リポジトリであり、GitHubへのツール公開や別媒体バックアップの証拠ではない。
- server側の文書検査・CIと本人VMの実行結果を区別する。

[前段：保存ログへの適用](2026-09-15-lab-base01-checker-real-logs-practice.md) / [検証証跡台帳](../README.md)
