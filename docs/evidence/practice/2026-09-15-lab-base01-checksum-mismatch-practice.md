# lab-base01：ログのハッシュ不一致検出（2026-09-15）

## 結果と範囲

本人VMで既存アーカイブを試験用の別フォルダーへ展開し、正常時は5件OKを確認した。
試験用finalログだけに1行追記した後、同じSHA一覧による検査でその1件だけFAILED・終了1となった。
その後、元ログと前段の検証済み展開先は各5件OK・終了0を確認した。
**内容変更の検出演習**であり、変更者の特定や暗号学的な真正性保証の検証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01） |
| 元アーカイブ | /home/opsadmin/ansible-change-archive/change-logs.tar.gz |
| 試験用展開先 | /home/opsadmin/ansible-change-tamper-test |
| 元ログ | /home/opsadmin/ansible-practice-logs |
| 検証済み展開先 | /home/opsadmin/ansible-change-extract |
| 原資料 | [本人提供画像3枚・ハッシュ](../screenshots/2026-09-15-lab-base01-checksum-mismatch-practice/README.md) |

## 確認結果

CM番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| CM-01 | 前提 | PASS | 元アーカイブ存在、試験先NOT FOUND、ユーザー・ホスト名（E01） |
| CM-02 | 正常検査 | PASS | 新規展開先でsha256sum -c、5件すべてOK、baseline verify exit=0（E02） |
| CM-03 | 試験変更 | PASS | finalログ1件を選択しMODIFY表示、演習用1行を追記する入力（E02） |
| CM-04 | 不一致検出 | PASS（想定不一致） | finalのみFAILED、他4件OK、1 computed checksum did NOT match、終了1（E02） |
| CM-05 | 元ログ | PASS | 元ログディレクトリで検証済み展開先のSHA一覧を指定、5件OK、original verify exit=0（E03） |
| CM-06 | 検証済みコピー | PASS | ansible-change-extractで5件OK、verified copy exit=0（E03） |

追記した文字列はPRACTICE: checksum mismatch testである。編集対象は新しい試験用コピーで、
同じSHA一覧を再生成せずに検査した。実際の追記後本文をcatで読む操作は未採録だが、入力と不一致を確認した。
元ログ・検証済み展開先の内容は、それぞれ使用したSHA一覧と一致した。

## 検証の意味

正常時だけでなく、意図的に内容を変えたファイルを拒否する結果も確認した。
ハッシュ検査は一覧との差異を見つけるもので、いつ・誰が・なぜ変更したかを特定しない。
比較対象と一覧の両方を書き換えられる場合の改ざん防止や署名検証は今回対象外。
試験用コピーは不一致のまま残す手順で、削除・再修正を案内していない。

## 未実施・限界

- 元アーカイブ自身の作業前後ハッシュ比較、元一覧とのバイト単位比較は未採録。
- ファイル欠落、一覧破損、複数ファイル変更、アーカイブ破損の検出試験はNOT RUN。
- 実行日時・OS/sha256sum版、展開後の権限・所有者・mtime読戻しは未採録。
- ログ本文・SHA一覧・アーカイブの実体はこの公開作業では取得していない。
- 別媒体バックアップ、別ホストや新規OSでの復元、実サービス検証はNOT RUN。
- 画像用SHA256SUMS.txtは今回検査に使ったログ用一覧とは別である。
- server側の文書検査・CIと本人のVM内実行を区別する。

- [前段：元ログ照合](2026-09-15-lab-base01-original-log-check.md)
- [検証証跡台帳](../README.md)
