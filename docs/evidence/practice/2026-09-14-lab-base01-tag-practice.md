# lab-base01：注釈付きタグの作成（2026-09-14）

## 結果と範囲

本人VMで保存コミット38559f2に注釈付きタグpractice-validated-v1を作成した。
作成終了0、オブジェクト種類tag、検証範囲の注釈、参照先コミットと作業状態を確認した。
**VM内の版識別用タグ作成**であり、新しいAnsible動作検証やGitHub上のリリース作成ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付） |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。Git/OS版は今回未採録 |
| 実行場所 | /home/opsadmin/ansible-first-lab |
| ブランチ | practice/save-ansible-exercises |
| 対象コミット | 短縮SHA38559f2。完全SHAはE01/E02の表示を参照 |
| タグ | practice-validated-v1 |
| タグ表示日時 | Mon Sep 14 17:51:47 2026 +0900（E02）。時計精度・撮影時刻は未検証 |
| 証拠 | [本人提供画像2枚・ハッシュ](../screenshots/2026-09-14-lab-base01-tag-practice/README.md) |

## 確認結果

TG番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| TG-01 | 開始状態 | PASS | VM名・ユーザー、作業ブランチclean、HEAD38559f2、タグ一覧の該当出力なし（E01） |
| TG-02 | 作成 | PASS | git tag -aで対象コミットと注釈を指定、tag create exit=0（E02） |
| TG-03 | 種類 | PASS | git cat-file -t refs/tags/practice-validated-v1がtagを返す（E02） |
| TG-04 | 注釈 | PASS | show --no-patchにタグ名・tagger・日時・検証範囲の本文（E02） |
| TG-05 | 参照先 | PASS | rev-parseでタグをcommitへ解決し、開始時の38559f2と一致（E02） |
| TG-06 | 作業状態 | PASS | statusは作業ブランチ行のみ。未コミット変更なし（E02） |

## 注釈の範囲

注釈は検証付きroleのstaging/8091、lab-base01での正常再実行とローカルclone/bundleからの
新規生成を対象にし、他Playbook・他環境は対象外と明示した。
これは既存の実施記録を参照する目印であり、タグ作成によって検証が追加されたわけではない。
author/taggerの表示はGitに記録された識別情報で、本人性や署名検証の証明とはしない。

## 未実施・限界

- タグのpush、GitHub Release作成、既存bundleへのタグ追加、Windowsコピーへの同期は**NOT RUN**。
- 今回のタグ名を使ったcheckout・clone・Playbook実行は**NOT RUN**。
- 電子署名付きタグ、タグオブジェクトSHAの独立採録、機械可読なGitデータ取得は未実施。
- タグはVM内だけに作成。既存bundleやコピーには自動追加されない。
- 新しいAnsible試験や全Playbook・全環境の検証済み宣言には使わない。
- server側の証跡文書PRと、VM内のタグ作成は対象リポジトリ・実行主体が異なる。

- [保存版role再実行](2026-09-14-lab-base01-saved-rerun-practice.md)
- [ローカルclone再現](2026-09-14-lab-base01-reproduce-practice.md)
- [bundle作成・復元](2026-09-14-lab-base01-bundle-practice.md)
- [検証証跡台帳](../README.md)
