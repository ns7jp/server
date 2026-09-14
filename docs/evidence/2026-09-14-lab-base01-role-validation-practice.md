# lab-base01：role入力検証演習（2026-09-14）

## 結果と範囲

本人VMで入力検証付きroleを新設し、staging/8091を受け付けて設定ファイルを生成した。
70000は最初のassertで拒否され、生成ファイルの前後SHA-256が一致した。
8091で再実行すると全3タスクok・changed0となり、本文とSHA-256の維持を確認した。
**ホーム内の設定生成前の入力検証**であり、実ポート待受や全入力パターンの検証ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。whoami/hostnameの出力をE01で確認 |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 入力 | role-validated-demo.yml、roles/practice_config_validated配下 |
| 出力 | managed-role-validated/app.conf |
| 原資料 | [本人提供画像4枚・ハッシュ](screenshots/2026-09-14-lab-base01-role-validation-practice/README.md) |

## 案内構成と既存role

E01で既存practice_configの2タスク、defaultsのtraining/8080、出力staging/8091を確認した。
既存roleを残し、新規practice_config_validatedにassert→ディレクトリ作成→templateの順で
処理を置く手順を案内した。assertは環境名の候補、数字形式、1以上65535以下を確認する構成。
新規作成先の存在時は停止するガードを案内し、E02に作成完了メッセージを確認した。
実入力ファイル全文・ハッシュの読戻しは未採録で、全入力の同一性は未検証。

## 確認結果

RV番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| RV-01 | 開始状態 | PASS | whoami=opsadmin、hostname=lab-base01、既存role本文とmainの未追跡状態（E01） |
| RV-02 | 構文確認 | PASS | syntax-check後、AND連結で通常実行に進む（E02）。単独数値終了コードは未採録 |
| RV-03 | 正常値受入 | PASS | staging/8091、All assertions passed、ok3/changed2/failed0、終了0、本文一致（E02） |
| RV-04 | 範囲外拒否 | PASS（想定失敗） | 70000でint <= 65535がfalse。最初のassertで停止、ok0/changed0/failed1、終了2（E03） |
| RV-05 | 拒否前後の不変 | PASS | app.confの前後SHA-256が一致、本文staging/8091を維持（E03） |
| RV-06 | 正常再実行 | PASS | assert通過、全3タスクok、changed0/failed0、終了0。本文とSHA-256維持（E04） |
| RV-07 | 最終Git状態 | PASS | main、新規role-validated-demo.yml・managed-role-validated/が未追跡。roles/も未追跡（E04） |

E04の入力行は上部が切れており、ポート8091は見えるがコマンド全体は未採録。
Play名・role名・assert通過・本文・終了コードは画面で確認できる。
拒否回のエラーメッセージだけではなく、後続タスクが表示されないことと対象ファイルのハッシュを照合した。

## ハッシュの扱い

E03には同じapp.confに対する拒否前後のSHA-256が表示され、E04の再実行後も同じ値である。
値の原本は各画像を参照する。機械可読なログ・ファイル自体は取得していない。
これは当該ファイル内容の一致確認で、mtime・権限・全ディレクトリの不変性検査ではない。
添付SHA256SUMS.txtは画像ファイルのハッシュであり、VM内app.confのハッシュとは別である。

## 最終状態・未実施

- 最後の生成本文はstaging/8091。今回のソースと生成物はVM内で未追跡のまま保持。
- 入力検証付きroleは別の出力先を使用。既存roleの実行後のハッシュ比較は未実施。
- 境界値1・65535、0・65536、数字以外・小数・不正環境名の実行試験は**NOT RUN**。
- OS/Ansible版の再取得、全入力全文・ハッシュ・実行コミット・連続rawログは未採録。
- 実サービス起動・ポート待受、site.ymlへの組込み、複数ホスト配備は**NOT RUN**。
- ソースのGitコミット・ignore追加・生成物削除は未実施。
- server側の文書検査・CIは本人VM内の実行主体・対象とは別。

## 復習

ファイルを書き換えるタスクより前にassertを置き、今回の範囲外入力を拒否した。
正しい値での再実行は変更なしとなり、拒否後も既存設定を利用できた。
これはAIによる復習用説明で、本人独力による説明の採録ではない。

- [前段：role入門](2026-09-14-lab-base01-role-practice.md)
- [検証証跡台帳](README.md)
