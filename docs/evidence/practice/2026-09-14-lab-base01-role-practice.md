# lab-base01：Ansible role入門演習（2026-09-14）

## 結果と範囲

本人VMでpractice_config roleを呼び出し、既定値での初回生成・同条件再実行・
実行時変数による上書き・上書き条件での再実行を確認した。
VM内のchangedは2→0→1→0、全回failed0・終了コード0。最終本文はstaging/8091。
**ホーム内の設定ファイル生成**であり、実サービスの起動や複数ホストへのrole配備の実績ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。OS・Ansible版は今回再取得していない |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 入力 | role-demo.yml、roles/practice_configのtasks・defaults・templates |
| 出力 | managed-role/app.conf |
| 証拠 | [本人提供のVM側原画像5枚・ハッシュ](../screenshots/2026-09-14-lab-base01-role-practice/README.md) |

## 実行環境の区別

最初の実行画像はVMと異なるユーザー名・ホスト名のプロンプトで、初回生成成功を示していた。
それをlab-base01の実績には含めず、SSHでVMに戻った後に3パス未使用を確認し（E01）、
VM内で作り直した結果（E02〜E05）だけを本結果票の確認結果とした。
別環境のOS種別や実パスは独立確認していない。別環境側のファイル削除も未実施・未確認。
当該画像は対話内資料にとどめ、この公開資料には添付しない。

## 案内した構成

| ファイル | 役割 |
| --- | --- |
| role-demo.yml | localhostへのlocal接続でpractice_config roleを呼ぶ |
| roles/practice_config/tasks/main.yml | 出力ディレクトリ作成とtemplateによる生成 |
| roles/practice_config/defaults/main.yml | practice_config_environment: training、practice_config_port: 8080 |
| roles/practice_config/templates/app.conf.j2 | role用の変数を参照する2行のひな形 |

既存テンプレートを移動せず、同じ形式のひな形をrole内へ新設する手順を案内した。
作成時はユーザー名・ホスト名を検査するガードを提示し、E02に作成完了メッセージを確認した。
実ファイル全4件の独立した全文読戻し・ハッシュは未採録。既定値の本文はE04で確認した。

## 確認結果

RP番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| RP-01 | VM側開始状態 | PASS | opsadmin@lab-base01、main、既存8パス未追跡、role用3パスNOT FOUND（E01） |
| RP-02 | 構文確認 | PASS | syntax-check後にAND連結で通常実行へ進んだ（E02）。単独数値終了コードは未採録 |
| RP-03 | 初回生成 | PASS | role名付き2タスクchanged、ok2/changed2/failed0、終了0、training/8080（E02） |
| RP-04 | 同条件再実行 | PASS | 2タスクok、changed0/failed0、終了0、training/8080を維持（E03） |
| RP-05 | 変数上書き | PASS | -eでstaging/8091を指定、templateだけchanged、changed1/failed0、終了0（E04） |
| RP-06 | 既定値ファイル | PASS | 生成本文staging/8091に対し、defaults本文はtraining/8080（E04） |
| RP-07 | 上書き条件再実行 | PASS | 同じ-e指定でchanged0/failed0、終了0、本文staging/8091維持（E05） |
| RP-08 | 最終Git状態 | PASS | main、新規role-demo.yml・roles/・managed-role/と前段8パスが未追跡（E05） |

既定値ファイルにtraining/8080があることはE04の読戻しで確認した。
ただし変更前後のハッシュ比較は行っておらず、ファイル全体の不変性証明とは扱わない。
この2タスクの冪等性を、全role・全モジュール・実サービスの保証へ一般化しない。

## 最終状態・未実施

- 最終出力はstaging/8091。引数なしで既定値へ戻す再実行は未実施。
- 新規ソースと生成物は未追跡のまま保持。Gitコミット・ignore追加・削除は未実施。
- 実サービス起動・ポート待受、複数VM配備、site.yml/foundation.ymlへの組込みは**NOT RUN**。
- roleの依存関係・handlers・別Playbookからの再利用・入力検証は**NOT RUN**。
- 全入力ハッシュ、実行対象コミット、連続rawログ、ファイル権限の独立検査は未採録。
- server側の公開用コミットとCIは、本人VMでの実行主体・対象とは別。

## 復習

処理をtasks、既定値をdefaults、ひな形をtemplatesへ分け、Playbookからroleを呼び出す。
今回の-eは実行時に使う値を上書きし、生成結果に反映された。
これはAIによる復習用説明で、本人独力による説明を採録したものではない。

- [前段：Vault](2026-09-14-lab-base01-vault-practice.md)
- [検証証跡台帳](../README.md)
