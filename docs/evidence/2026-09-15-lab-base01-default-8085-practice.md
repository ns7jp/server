# lab-base01：変更した既定値8085の実行確認（2026-09-15）

## 結果と範囲

本人VMで既定ポートを8085へ変更したコミットdac8a0fの入力検証付きroleを実行した。
未生成だったapp.confをtraining/8085で新規生成し、再実行ではchanged0・終了0と本文・ハッシュ維持を確認した。
**ホーム内の設定ファイル生成**であり、実際の8085番ポートでのサービス起動は未検証。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付） |
| VM表示日時 | 初回直前10:07:41+09:00、再実行直前10:08:47+09:00（E02/E03）。時計精度は未確認 |
| 環境 | プロンプトopsadmin@lab-base01。OS/Ansible版は今回未採録 |
| 実行場所 | /home/opsadmin/ansible-tagged-restore |
| ブランチ | practice/from-tag |
| コミット | 短縮SHAdac8a0f。完全SHAはE01〜E03の表示を参照 |
| 出力 | managed-role-validated/app.conf |
| 原資料 | [本人提供画像3枚・ハッシュ](screenshots/2026-09-15-lab-base01-default-8085-practice/README.md) |

## 確認結果

D8番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| D8-01 | 開始状態 | PASS | practice/from-tag clean、HEADdac8a0f、defaultsはtraining/8085、出力NOT FOUND（E01） |
| D8-02 | 初回生成 | PASS | assert通過、directory/template changed、ok3/changed2/failed0、終了0（E02） |
| D8-03 | 初回本文 | PASS | environment=training、listen_port=8085、SHA-256出力、Git変更なし（E02） |
| D8-04 | 再実行 | PASS | -eなしの通常実行入力を確認、全3タスクok、changed0/failed0、終了0（E03） |
| D8-05 | 最終状態 | PASS | 前後SHA-256一致、本文training/8085、HEADdac8a0f、Git変更なし（E03） |

初回は-eなしの実行を案内したが、E02ではそのコマンド入力行が画面外である。
初回の版表示・タスク結果・本文を確認し、再実行の-eなしはE03で直接確認した。
既定値ファイルの本文はE01で読戻したが、全入力ファイル群のハッシュによる同一性検査は未採録。

## ハッシュと版の区別

初回生成後、再実行前、再実行後のapp.confのSHA-256表示は一致した。
値の原本は画像を参照する。画像用SHA256SUMS.txtとは別であり、機械可読なログや実ファイルは取得していない。
前段のタグ起点コミット作成時にAnsible NOT RUNだった記録は保持し、本追補を新しい実行結果とする。
元タグ38559f2の検証結果へこの8085の結果を付け替えない。

## 未実施・限界

- 実サービス起動・ポート待受、複数ホストや別OSでの検証は**NOT RUN**。
- dac8a0fでの不正入力・境界値・実行時上書きの追加試験は今回未実施。
- 初回の構文確認、入力全ハッシュ、ファイル権限・mtime比較、連続rawログは未採録。
- タグ参照先の再取得、bundle更新、Windows同期は今回未実施。
- 最終作業場所はansible-tagged-restore、practice/from-tag。追加コミット・push・削除は案内していない。
- server側の公開文書コミット・CIと本人VMのdac8a0fの実行を区別する。

- [前段：タグ起点の変更コミット](2026-09-14-lab-base01-from-tag-practice.md)
- [検証証跡台帳](README.md)
