# lab-base01：ローカルcloneからの設定再現（2026-09-14）

## 結果と範囲

保存コミット38559f2のブランチを同じVM内の別フォルダーへcloneし、出力未生成の状態から
入力検証付きroleでstaging/8091を新規生成した。初回changed2、同条件再実行changed0、
双方failed0・終了0。再実行前後の対象ファイルSHA-256と本文、保存コミットの維持を確認した。
**同じVM・既存Ansible環境内でのフォルダー単位の再現確認**であり、新規OS・別マシンの構築試験ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付） |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。OS/Ansible版は今回未取得 |
| clone元 | /home/opsadmin/ansible-first-lab |
| clone先 | /home/opsadmin/ansible-reproduce-lab |
| ブランチ | practice/save-ansible-exercises |
| 保存版 | 短縮SHA 38559f2。完全SHAはE01〜E04の表示を参照 |
| 初回直前のVM日時 | 2026-09-14T14:29:33+09:00（E03） |
| 再実行直前のVM日時 | 2026-09-14T14:32:04+09:00（E04） |
| 原資料 | [本人提供画像4枚・ハッシュ](screenshots/2026-09-14-lab-base01-reproduce-practice/README.md) |

## 実行した内容

E02で--no-hardlinks、--single-branch、--branch practice/save-ansible-exercisesを指定した
ローカルcloneを確認した。元はVM内のパスであり、GitHubからのcloneではない。
clone先でpwd・HEAD・statusを読み、managed-role-validatedとVault演習2ファイルが
存在しないことを確認した。他の全パスについて独立した不在検査をしたわけではない。

E03/E04ではclone先からrole-validated-demo.ymlを-i localhost,、
-e practice_config_environment=staging、-e practice_config_port=8091で通常実行した。
生成先はclone先配下のmanaged-role-validated/app.confである。

## 確認結果

CR番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| CR-01 | 元の状態 | PASS | VM名・ユーザー、作業ブランチclean、HEAD38559f2、再現先NOT FOUND（E01） |
| CR-02 | clone | PASS | 指定パスへのclone完了、移動後pwd、HEAD38559f2、status変更行なし（E02） |
| CR-03 | 未生成・除外対象 | PASS | managed-role-validated、vault-demo.yml、vault-demo-vars.ymlがNOT FOUND（E02） |
| CR-04 | 初回生成 | PASS | assert通過、directoryとtemplateがchanged。ok3/changed2/failed0、終了0（E03） |
| CR-05 | 初回本文 | PASS | staging/8091、SHA-256出力、Git変更行なし（E03） |
| CR-06 | 同条件再実行 | PASS | 全3タスクok、changed0/failed0、終了0（E04） |
| CR-07 | 最終状態 | PASS | 再実行前後のSHA-256一致、本文staging/8091、HEAD38559f2とGit変更なし（E04） |

初回生成後の対象ファイルSHA-256と再実行前後に表示された値は一致した。
値の原本は画像を参照する。画像用SHA256SUMS.txtとは別である。
Git statusにはorigin/practice/save-ansible-exercisesの追跡表示があるが、originは今回のローカルclone元。
これをGitHubへの同期済み状態とは扱わない。

## 未実施・限界

- 同じVMにある既存Ansible/Python等を使用。新規OS、別VM、別ホストでの再現は**NOT RUN**。
- 他Playbook、不正入力、境界値のclone先での試験は**NOT RUN**。
- 実サービス起動・配備・ポート待受・site.yml実行は**NOT RUN**。
- 同じVM内のcloneを別媒体バックアップや災害復旧の証明にはしない。
- ファイル権限・mtime・全入力ハッシュ、依存関係固定、連続rawログ、Git bundleは未採録。
- 日時はVM時計の表示。時計精度・実行所要時間は未検証。
- 元フォルダーの実行後ハッシュ比較や全ファイル不変性は未検証。
- 終了時はclone先にいる。削除・push・追加コミットは今回案内・記録していない。
- server側の公開用コミット・CIと、本人VM内の38559f2の実行を区別する。

## 復習

保存したソースだけを別フォルダーへ展開し、必要な出力を新規生成してから再実行の変更なしを確認した。
ソースの保存、生成物、実行環境を分けて考える。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：保存コミットの再実行](2026-09-14-lab-base01-saved-rerun-practice.md)
- [検証証跡台帳](README.md)
