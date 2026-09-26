# lab-base01：注釈付きタグを含むbundle復元（2026-09-14）

## 結果と範囲

本人VMで保存ブランチと注釈付きタグを明示して新しいbundleを作成し、別フォルダーへcloneした。
復元先でタグの種類・オブジェクトSHA・参照先コミット・注釈を確認し、元の表示と一致した。
**同じVM内でのGitデータ復元**であり、新しいAnsible動作検証や別媒体からの復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影時刻は未採録 |
| 環境 | プロンプトopsadmin@lab-base01。OS/Git版・whoami/hostnameの再取得は今回未採録 |
| 元リポジトリ | /home/opsadmin/ansible-first-lab |
| bundle | /home/opsadmin/ansible-bundle-backups/practice-tagged.bundle |
| 復元先 | /home/opsadmin/ansible-tagged-restore |
| 保存対象 | refs/heads/practice/save-ansible-exercisesとrefs/tags/practice-validated-v1 |
| 参照先 | 短縮SHA38559f2。完全SHAは画像の表示を参照 |
| 原資料 | [本人提供画像3枚・ハッシュ](../screenshots/2026-09-14-lab-base01-tagged-bundle-practice/README.md) |

## 確認結果

TB番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| TB-01 | 開始状態 | PASS | Git変更なし、HEADとタグのcommit解決結果が一致、種類tag、保存先・復元先NOT FOUND（E01） |
| TB-02 | 作成 | PASS | ブランチとタグを指定してbundle create、32 objects、作成終了0（E02） |
| TB-03 | 検査 | PASS | 2 refs、complete history、is okay、verify終了0（E02） |
| TB-04 | タグ収録 | PASS | list-headsのタグSHAと元リポジトリのrev-parse結果が一致（E02） |
| TB-05 | clone | PASS | bundleからブランチ指定でclone、32 objects受信、終了0（E03） |
| TB-06 | タグ復元 | PASS | 種類tag、タグオブジェクトSHAがE02と一致、commit解決結果38559f2（E03） |
| TB-07 | 注釈と状態 | PASS | 元と同じ検証範囲の注釈、tagger/日時、参照先、Git変更なし（E03） |

タグオブジェクトのSHA（cd7b92で始まる表示）とコミットSHA38559f2は別である。
注釈付きタグをcommitへ解決する指定と、タグオブジェクトそのもののrev-parseを分けて確認した。
完全な値はE02/E03を原本とする。機械可読なGitデータは取得していない。

## 注釈と履歴の範囲

注釈は検証付きroleのstaging/8091、lab-base01での正常再実行とclone/bundleからの新規生成を対象とし、
他Playbook・他環境は対象外とする既存タグの本文だった。
表示された日時はタグ・コミットに記録された日時で、今回の復元時刻ではない。
complete historyは指定refからたどれる履歴であり、全練習ブランチ保存の意味ではない。

## 未実施・限界

- 復元先でのAnsible実行、生成物作成、実サービス試験は**NOT RUN**。
- 新しいbundleのWindows転送・別媒体保存・新規OSやホスト故障からの復旧は**NOT RUN**。
- タグpush、GitHub Release、署名検証、復元先fsckは未実施。
- bundle自体のSHA-256はE02で表示。復元後のbundleハッシュ再比較は未採録。
- ソース全文比較、依存環境固定、権限・mtime・全ファイルハッシュは未採録。
- 旧practice.bundleやWindowsコピーを更新する操作は案内していない。
- 画像用SHA256SUMS.txtはbundleやタグのハッシュとは別である。
- server側の文書追加・CIと本人VMでのタグ復元を区別する。

- [前段：注釈付きタグ作成](2026-09-14-lab-base01-tag-practice.md)
- [検証証跡台帳](../README.md)
