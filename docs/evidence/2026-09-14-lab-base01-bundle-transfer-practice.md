# lab-base01：Git bundleのWindows転送（2026-09-14）

## 結果と範囲

本人がVM内のpractice.bundleをホストWindowsへscpし、終了0、5138バイト、SHA-256一致を確認した。
**同じホストPC内のVM外への複製**であり、外付け媒体・別拠点へのバックアップではない。
Windows側コピーからの復元試験も今回は行っていない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| コピー元 | lab-base01、/home/opsadmin/ansible-bundle-backups/practice.bundle |
| コピー先 | ホストWindowsのDocuments内、新規AnsibleBundle-識別子フォルダー（E02） |
| bundle対象 | practice/save-ansible-exercises、短縮SHA38559f2（E01） |
| 原資料 | [本人提供画像2枚・ハッシュ](screenshots/2026-09-14-lab-base01-bundle-transfer-practice/README.md) |

## 確認結果

BT番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| BT-01 | コピー元 | PASS | whoami=opsadmin、hostname=lab-base01、bundleサイズ5138バイトとSHA-256（E01） |
| BT-02 | 収録ref | PASS | list-headsにrefs/heads/practice/save-ansible-exercisesと38559f2（E01） |
| BT-03 | 保存先作成 | PASS | MyDocumentsとGUIDで新規パス生成、New-Itemと保存先表示（E02） |
| BT-04 | scp | PASS | IdentitiesOnlyと既存鍵指定、100%・5138、scp exit=0（E02） |
| BT-05 | コピー一致 | PASS | Windows側Length=5138、Get-FileHash SHA256がE01と一致（大小文字は正規化して比較） |

## 保存と検証の意味

指定ブランチからたどれるソース・履歴を含むbundleを、VM外にも保存した。
前段で確認したVM内bundleのverify・復元と、今回のWindows転送を別の実施記録として扱う。
今回、Windows側でverifyやcloneを行ったという意味ではない。

SSH鍵パスフレーズの入力プロンプトの後に転送成功が表示されるが、入力文字・鍵本文は画像にない。
元bundleの削除は案内していない。転送後のVM側存在・ハッシュ再確認は未採録。
Windows保存先のACL・暗号化状態・ファイル属性の保全は未検証。

## 原資料と限界

VM側sha256sumとWindows側Get-FileHashの一致を画像で確認した。値の原本は画像を参照する。
この公開用作業ではbundle実体を取得・添付していない。画像用SHA256SUMS.txtはbundleのハッシュとは別。
転送の終了コードと内容一致は、ホストPC全体の故障への保護や履歴全体の内容レビューを保証しない。

## 未実施

- Windowsコピーからのverify・clone・Playbook実行は**NOT RUN**。
- 外付け媒体・別PC・別拠点への保存、ホスト喪失からの復旧は**NOT RUN**。
- Windows ACL、OS/SSH/Git版、転送日時・所要時間・署名検証は未採録。
- GitHubへのbundle公開やVM演習リポジトリのpushは未実施。
- server側の公開コミット・CIと本人の転送操作を区別する。

## 復習

コピー後は終了コードだけでなくサイズとハッシュを照合する。ホストへの複製と別媒体へのバックアップは区別する。
この説明はAIによる復習用で、本人独力の説明を採録したものではない。

- [前段：bundle作成・VM内復元](2026-09-14-lab-base01-bundle-practice.md)
- [検証証跡台帳](README.md)
