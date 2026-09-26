# lab-base01：入力境界値・形式検証（2026-09-14）

## 結果と範囲

本人VMで既存の入力検証付きroleを使い、ポート値1・65535の受入、0・65536の範囲外拒否、
abc・80.5の形式拒否を確認した。**今回はcheck modeでの検証**であり、許可した値での
実書き込みや実ポート待受の実績ではない。保存済みapp.confはstaging/8091を維持した。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | lab-base01、opsadmin。whoami/hostname出力をE01で確認。OS/Ansible版は今回未採録 |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 対象 | role-validated-demo.ymlとpractice_config_validated role |
| 観測ファイル | managed-role-validated/app.conf |
| 証拠 | [本人提供画像6枚・ハッシュ](../screenshots/2026-09-14-lab-base01-boundary-practice/README.md) |

## 開始状態と入力条件

E01でtasks/main.ymlの本文を読み、環境名候補、数字形式、1以上65535以下のassertが
ディレクトリ作成・templateより前にあることを確認した。開始本文はstaging/8091。
環境名はstagingに固定し、ポートだけを変える手順を案内した。
今回の入力はCLIのkey=value形式で、整数型・浮動小数型などの型別入力比較ではない。

## 確認結果

BC番号は本結果票専用。全件check modeの結果。PASSは画像で確認できた観点に限定する。

| ID | 入力 | 判定 | 実測結果・証拠 |
| --- | --- | --- | --- |
| BC-01 | 1 | PASS（受入） | All assertions passed、ok3/changed1/failed0、終了0、本文・ハッシュ維持（E06） |
| BC-02 | 65535 | PASS（受入） | port=65535/check mode見出し、assert通過、ok3/changed1/failed0、終了0（E02） |
| BC-03 | 0 | PASS（想定拒否） | int >= 1がfalse、ok0/changed0/failed1、終了2、ハッシュ維持（E03） |
| BC-04 | 65536 | PASS（想定拒否） | int <= 65535がfalse、ok0/changed0/failed1、終了2（E03末尾〜E04冒頭） |
| BC-05 | abc | PASS（想定拒否） | 数字形式のmatchがfalse、ok0/changed0/failed1、終了2（E04） |
| BC-06 | 80.5 | PASS（想定拒否） | 数字形式のmatchがfalse、ok0/changed0/failed1、終了2（E04末尾〜E05） |

許可値のchanged1はtemplateが予測した変更である。実際のapp.confを書き換えたものではない。
拒否値はassertで止まり、後続の作成・生成タスクは表示されない。
今回のファイル不変はcheck modeで観測したもので、通常実行の拒否時不変を再検証したものではない。
通常実行での70000拒否は前段結果票の実績として区別する。

## 画面の対応とハッシュ

E03には4入力を順番に処理するループ全体と開始ハッシュが写っている。
E04冒頭の集計は直前の65536、E05の集計は直前の80.5に対応する分割画像として記録した。
各入力後に表示されたapp.confのSHA-256は開始値と一致し、E02・E05・E06で本文staging/8091を確認した。
機械可読なrawログは取得していないため、値の原本は画像を参照する。
画像用SHA256SUMS.txtとVM内app.confのハッシュは別物である。

最初の下限試験はE02上部で見出しが切れていたため、その成功結果を1の確定証拠にはせず、
E06で入力1・--check・結果が同じ画面に入るよう再採録した。
65535は見出しと結果を採録しているが、E02には実コマンド入力行が写っていない。

## 未実施・限界

- 1・65535を使った通常実行での書き込み・実サービス起動は**NOT RUN**。
- 不正環境名、空文字、負数、符号付き数値、空白・改行、型別入力の比較は**NOT RUN**。
- 6入力の確認を全入力パターンの保証としない。
- 今回の最終Git status、入力ファイル群の全ハッシュ、権限・mtimeの比較は未採録。
- 実行コミット、連続rawログ、全入力全文の独立した読戻しは未採録。tasks本文はE01の範囲で確認。
- Gitコミット・生成物削除の操作は案内・記録していない。
- server側の文書検査・CIは本人VMの実行主体・対象とは別。

## 復習

許可範囲の両端、そのすぐ外、形式違いを試す。check modeのchangedは変更予測として読む。
この説明はAIによる復習用で、本人独力による説明を採録したものではない。

- [前段：通常実行のrole入力検証](2026-09-14-lab-base01-role-validation-practice.md)
- [検証証跡台帳](../README.md)
