# lab-base01：WindowsからVMへのログ復元（2026-09-14）

## 結果と範囲

Windowsにコピー済みの2ログをVMの新規フォルダーへscpで戻し、サイズ・SHA-256一致と
コマンド説明・集計・終了コードの読取りを確認した。
**同じホストPC内でのログファイル復元練習**であり、ホスト故障・別拠点・新規OSからの復旧試験ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 転送元 | WindowsのDocuments内AnsibleLogs-識別子フォルダー（E02） |
| 復元先 | lab-base01、/home/opsadmin/ansible-log-restore |
| 対象 | 正常ログ1件、失敗ログ1件 |
| 原資料 | [本人提供画像3枚・ハッシュ](../screenshots/2026-09-14-lab-base01-log-restore-practice/README.md) |

## 確認結果

LR番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| LR-01 | 復元先の前提 | PASS | whoami=opsadmin、hostname=lab-base01、復元先NOT FOUND（E01） |
| LR-02 | 復元先作成 | PASS | mkdir -m 700を実行し、エラー表示なし。その後同じパスへの転送が成功（E02） |
| LR-03 | 転送元ハッシュ | PASS | Windowsで2件のGet-FileHash SHA256を表示（E02） |
| LR-04 | 復元転送 | PASS | ログ各件をscp、双方100%、個別scp exit=0（E02） |
| LR-05 | サイズ一致 | PASS | 復元先pwd、失敗1321バイト・正常1395バイト（E03） |
| LR-06 | ハッシュ一致 | PASS | 復元先sha256sumの2件がWindows側E02と一致（大小文字は正規化して比較） |
| LR-07 | 内容読取り | PASS | 失敗70000/failed1/ANSIBLE_EXIT2、正常8091/failed0/ANSIBLE_EXIT0を抽出（E03） |

Windows側でログ候補2件を確認する手順の後、foreachで各ファイルを転送した。
mkdir単独の終了コードや復元先の権限読戻しは未採録のため、mode700が実測確認済みとはしない。
各scpの終了コード0は明示的に採録した。

## 読み取りと復元の意味

復元先でgrepを使い、保存済みログからCOMMAND・localhost集計・ANSIBLE_EXIT行を抽出した。
これは過去の実行ログが読めることの確認で、Ansibleを新しく実行した結果ではない。
COMMAND行は前段保存スクリプトが出力した説明で、自動シェルトレースではない。
対象のログ内容一致はSHA-256で確認し、今回本文は指定行だけを読んだ。

元ログとは別のansible-log-restoreを使い、元の保存先への上書きは案内していない。
元VMログ・Windowsコピーの削除操作も案内していないが、転送後の両方の存在を再検査した結果は未採録。

## 未実施・限界

- ホスト故障、新規OS・別VM、外付け媒体・別拠点からの復旧は**NOT RUN**。
- Windows ACL、復元後のファイル権限・所有者・mtimeの比較は未実施。
- ログ実体は公開用作業で取得・添付していない。SHA原本は画像参照で、画像用SHA256SUMSとは別。
- 復元後に元の処理を再実行する試験、アプリやサーバー全体の復元は**NOT RUN**。
- OS/SSH版、転送所要時間、復旧時間目標、ログ署名・改ざん防止は未検証。
- server側の公開コミット・CIと本人のファイル転送を区別する。

## 復習

コピーを戻した後に、ハッシュと必要な内容を確認する。転送成功だけで復元確認を終わらせない。
これはAIによる復習用説明で、本人独力の説明を採録したものではない。

- [前段：Windows側のログ確認](2026-09-14-lab-base01-windows-log-review-practice.md)
- [VMからWindowsへの転送](2026-09-14-lab-base01-log-transfer-practice.md)
- [検証証跡台帳](../README.md)
