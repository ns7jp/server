# lab-base01：Git bundle作成・復元演習（2026-09-14）

## 結果と範囲

本人VMで保存ブランチの履歴をbundle化し、verifyとlist-headsを確認した。
bundleから別フォルダーへcloneし、入力検証付きroleの初回生成changed2と同条件再実行changed0、
双方終了0を確認した。**同じVM内でのGit履歴・ソース復元練習**であり、別媒体や新規OSからの復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付） |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。OS/Git/Ansible版は今回未採録 |
| 元リポジトリ | /home/opsadmin/ansible-first-lab |
| 保存対象 | refs/heads/practice/save-ansible-exercises、短縮SHA38559f2 |
| bundle | /home/opsadmin/ansible-bundle-backups/practice.bundle |
| 復元先 | /home/opsadmin/ansible-bundle-restore |
| VM表示日時 | 初回直前2026-09-14T16:37:00+09:00、再実行直前16:38:39+09:00（E04/E05） |
| 証拠 | [本人提供画像5枚・ハッシュ](../screenshots/2026-09-14-lab-base01-bundle-practice/README.md) |

## 確認結果

GB番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| GB-01 | 開始状態 | PASS | ユーザー・ホスト、作業ブランチclean、HEAD38559f2、保存先と復元先NOT FOUND（E01） |
| GB-02 | bundle作成 | PASS | 指定refでcreate、31 objectsの書込み、終了0（E02） |
| GB-03 | bundle検査 | PASS | complete history、is okay、verify終了0、list-headsが指定refと38559f2（E02） |
| GB-04 | 復元 | PASS | bundleファイルからbranch指定clone、終了0、復元先pwd、HEAD38559f2、Git変更なし（E03） |
| GB-05 | 復元内容 | PASS | logに38559f2とa94c1d3、生成先とVault演習2ファイルNOT FOUND（E03） |
| GB-06 | 新規生成 | PASS | staging/8091で通常実行、assert通過、ok3/changed2/failed0、終了0、本文・ハッシュを表示（E04） |
| GB-07 | 同条件再実行 | PASS | 全3タスクok、changed0/failed0、終了0、前後ハッシュ一致（E05） |
| GB-08 | 最終状態 | PASS | 本文staging/8091、HEAD38559f2、Git変更なし（E05） |

verifyのcomplete historyは今回指定したrefからたどれる履歴についての出力である。
他の練習ブランチすべてを保存したという意味ではない。未追跡・除外対象はGit履歴には含まれず、
E03で生成先とVault2件の不在を個別に確認した。他の全パスの不在検査ではない。

## 実行とハッシュ

復元先のrole-validated-demo.ymlを-i localhost,、-e practice_config_environment=staging、
-e practice_config_port=8091で通常実行した。roleは復元先配下へ設定を新規生成した。
初回生成後と再実行前後のapp.confのSHA-256は一致し、本文も維持した。
bundle自身のSHA-256はE02で表示したが、復元後のbundle再ハッシュ比較は未実施。
画像用SHA256SUMS.txtはこれらVM内ファイルのハッシュとは別である。

復元先statusのorigin追跡表示は今回のbundleをcloneした結果であり、GitHubと同期した証拠ではない。
今回の復元ソースでの実行を、過去の演習結果へ遡って付け替えない。

## 未実施・限界

- bundleは同じVM内に保存。別媒体・別PCへの転送、VMやホスト喪失からの復旧は**NOT RUN**。
- 新規OS・別Ansible環境、他Playbook・不正入力の復元先での再実行は**NOT RUN**。
- 元リポジトリを利用不能にした状態や、bundle破損時の拒否試験は**NOT RUN**。
- mkdir -m 700とumask 077は入力で確認したが、保存後の権限読戻しは未採録。
- 全入力ハッシュ・依存関係固定、機械可読なログ・bundle実体の取得は未実施。
- 日時はVM内時計の表示で、時刻同期精度・復旧所要時間の測定ではない。
- 実サービス起動・ポート待受・サーバー全体の復元は**NOT RUN**。
- server側の公開用文書・CIと本人VMの38559f2での実行を区別する。

## 復習

指定ブランチの履歴を1ファイルにまとめ、検査してから復元し、復元ソースが動くことを確認した。
保存できることと復元して使えることを分けて確かめる。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：ログ復元](2026-09-14-lab-base01-log-restore-practice.md)
- [検証証跡台帳](../README.md)
