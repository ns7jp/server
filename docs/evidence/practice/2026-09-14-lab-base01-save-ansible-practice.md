# lab-base01：Ansible演習ソースのGit保存（2026-09-14）

## 結果と範囲

本人VMで未追跡の演習ソースを選別し、作業ブランチpractice/save-ansible-exercisesに
コミット38559f2として保存した。.gitignoreの変更1件とソース11件、計12ファイル・191行追加。
生成物とVault演習2ファイルは除外し、コミット後のstatusはブランチ行のみだった。
**VM内のローカルGit保存**であり、演習リポジトリのGitHub pushや別媒体へのバックアップではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順・レビューを支援し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | プロンプトopsadmin@lab-base01。今回whoami/hostnameの出力は画像に未収録 |
| 実行場所 | 継続する/home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 保存ブランチ | practice/save-ansible-exercises |
| コミット | 短縮SHA 38559f2、Save Ansible practice playbooks and roles |
| 原資料 | [本人提供画像10枚・ハッシュ](../screenshots/2026-09-14-lab-base01-save-ansible-practice/README.md) |

## 保存対象

| 区分 | ファイル |
| --- | --- |
| 除外設定 | .gitignore（変更） |
| Playbook 5件 | block-demo.yml、handlers-demo.yml、loop-demo.yml、role-demo.yml、role-validated-demo.yml |
| 通常role 3件 | roles/practice_configのdefaults/main.yml、tasks/main.yml、templates/app.conf.j2 |
| 検証付きrole 3件 | roles/practice_config_validatedのdefaults/main.yml、tasks/main.yml、templates/app.conf.j2 |

E02でステージ一覧、E03〜E09でソース差分、E10でコミット後の同じ12件を確認した。
既存のtemplates/app.conf.j2等はこの追加コミットの変更対象ではない。

## 確認結果

SG番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| SG-01 | 開始一覧 | PASS | main、未追跡ソース・生成物・Vault2件と既存ignoreルール（E01） |
| SG-02 | 保存対象の選別 | PASS | 作業ブランチ、.gitignore変更と11件追加、12 files/191 insertions（E02） |
| SG-03 | 除外設定 | PASS | 生成5ディレクトリとVault2件のルール追加。ステージに対象生成物なし（E02） |
| SG-04 | 空白検査 | PASS | git diff --cached --checkの診断なし、exit=0（E03） |
| SG-05 | Playbookレビュー | PASS | block/handlers/loopのステージ済み本文を分割画像で確認（E03〜E06） |
| SG-06 | roleレビュー | PASS | 呼び出し2件、通常role、検証付きroleの本文を確認（E07〜E09） |
| SG-07 | コミット | PASS | 38559f2、12 files changed/191 insertions、11件create mode（E10） |
| SG-08 | 保存後状態 | PASS | statusは作業ブランチ行のみ、logとshow --statで同じSHA・対象を確認（E10） |

E10では空白検査のAND連結でcommitへ進むことも確認できる。commitの数値終了コードは未採録。
ブランチ作成・git add・ignore追記の入力操作自体は未採録で、操作後の状態と差分に限定する。

## 除外ルール

今回追加したルールは/managed-block/、/managed-handlers/、/managed-loop/、/managed-role/、
/managed-role-validated/、/vault-demo.yml、/vault-demo-vars.ymlである。
もともとの/managed/、/managed-vars/、/managed-template/、/.venv/、*.retryは維持した。

これらはGitへの追加対象から除外する設定で、ファイルの削除や暗号化を行うものではない。
今回のステージ・コミット一覧に除外対象がないことを確認したが、独立したcheck-ignoreの実行や
コミット後の除外対象ファイル存在確認は未採録。削除操作は案内・記録していない。

## ソース差分から確認した内容

- blockはホーム内の結果・マーカーを扱い、意図的なfailとrescue/alwaysを持つ。
- handlersは演習用出力にtemplate/copyを行い、通知されたfileのtouchでマーカーを更新する。
- loopは3対象のディレクトリ・設定生成と環境別結果のdebugを持つ。
- roleは演習用出力先へのfile/template、検証付きroleはそれらより前にassertを持つ。
- 提供された差分には実サービス操作・演習外の削除処理・秘密値本文は見当たらない。

これは今回ステージされたソースのレビューであり、過去の全演習時点で同じ内容だったことを
遡って保証するものではない。以前の結果票の入力全文未採録は当時の来歴として保持する。

## 未実施・限界

- コミット38559f2を使ったPlaybook再実行・構文確認は**NOT RUN**。
- VM演習リポジトリのpush・PR・mainへのマージ・別媒体へのバックアップは**NOT RUN**。
- 完全コミットSHA、親SHA、author/署名、Git bundle、ソースの機械可読な取得は未採録。
- 過去の実行をこのコミットの検証実績へ付け替えない。
- 画像のソース差分は実ファイルそのもののエクスポートではない。
- server側の公開用文書コミットとCIは、VM内の38559f2と対象・実行主体が異なる。

## 復習

保存対象を選ぶ、ステージ済み差分を読む、コミットする。cleanでも除外ファイルが存在し得る。
ローカルコミットと別媒体へのバックアップは別である。
この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：環境名入力検証](2026-09-14-lab-base01-env-validation-practice.md)
- [検証証跡台帳](../README.md)
