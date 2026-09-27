# lab-base01：Windows上でのbundle復元（2026-09-14）

## 結果と範囲

本人がWindowsへ転送済みのpractice.bundleを確認し、新しいフォルダーへcloneした。
終了0、HEAD38559f2、履歴2件、追跡ファイル20件とGit変更なしを確認した。
**Windows上でのGitソース・履歴の復元**であり、Windows上のAnsible実行やホスト故障からの復旧試験ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | ホストWindowsのPowerShell、git version 2.55.0.windows.3（E01） |
| 転送済みbundle | Documents内AnsibleBundle-識別子フォルダーのpractice.bundle |
| 復元先 | Documents内の新規AnsibleBundleRestore-識別子フォルダー（E02） |
| 復元ブランチ | practice/save-ansible-exercises |
| 原資料 | [本人提供画像2枚・ハッシュ](../screenshots/2026-09-14-lab-base01-windows-bundle-practice/README.md) |

## 確認結果

WB番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| WB-01 | bundle属性 | PASS | 5138バイト、Get-FileHash SHA256が前段の転送時の値と一致（E01） |
| WB-02 | 収録ref | PASS | list-headsに38559f2と保存ブランチ、終了0（E01） |
| WB-03 | clone | PASS | 指定bundleと復元先の入力末尾、31 objects受信、clone exit=0、復元先表示（E02） |
| WB-04 | HEADと状態 | PASS | HEAD38559f2、ブランチの追跡表示のみで変更行なし（E02） |
| WB-05 | 履歴 | PASS | log -2に38559f2とa94c1d3（E02） |
| WB-06 | 追跡ファイル | PASS | git ls-filesにPlaybook・role・テンプレート等20件（E02） |

E02は画面上部が切れており、cloneコマンドの全オプションとGUID変数生成行は未採録。
--single-branchと--branchを使う手順を案内した後の結果として、表示された復元先・ref・履歴を記録する。
復元後originの追跡表示はbundleからのcloneの結果であり、GitHubへの同期済みを意味しない。

## 復元した追跡ファイル

- .gitignore
- block-demo.yml、handlers-demo.yml、loop-demo.yml
- env-staging.yml、env-training.yml、variables.yml
- first-before-change.yml、first.yml
- role-demo.yml、role-validated-demo.yml
- roles/practice_configのdefaults/main.yml、tasks/main.yml、templates/app.conf.j2
- roles/practice_config_validatedのdefaults/main.yml、tasks/main.yml、templates/app.conf.j2
- template-validated.yml、template.yml、templates/app.conf.j2

一覧に生成物やVault演習2ファイルはないが、それらの物理的な不在をTest-Path等で独立確認した結果ではない。
履歴の初回9件と後続の新規ソース11件に対応する20追跡ファイルを確認した。

## 未実施・限界

- 復元したWindowsソースからのAnsible実行は**NOT RUN**。
- Windows側のgit bundle verify、git fsck、ソース全文読戻し・個別ハッシュ比較は未実施。
- Git変更なしを、Linux/Windows間の改行や権限まで含めたファイルバイト列の同一性保証とはしない。
- 新規OS・別PC・ホスト故障からの復旧、外付け媒体や別拠点からの復元は**NOT RUN**。
- Windows ACL、時刻・所要時間、復元後bundleハッシュ再比較は未採録。
- bundle実体・復元ソース実体はこの公開作業では取得・添付していない。画像用ハッシュとは別。
- server側の公開用文書・CIと本人のWindows復元を区別する。

## 復習

保存したbundleをcloneし、終了コード・HEAD・履歴・追跡ファイルを確認する。
ソースの復元と実行環境の再構築は別の検証である。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：bundleのWindows転送](2026-09-14-lab-base01-bundle-transfer-practice.md)
- [検証証跡台帳](../README.md)
