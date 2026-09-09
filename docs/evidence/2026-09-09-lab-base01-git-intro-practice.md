# lab-base01：Ansible演習ファイルのGit管理開始（2026-09-09）

## 結果と範囲

本人のUbuntu VMの演習フォルダーでGit管理を開始し、Playbook・変数ファイル・テンプレート・
.gitignoreの9ファイルを初回コミットa94c1d3として保存した。
コミット用identity未設定のエラーに対してローカル設定を案内し、再実行後のコミット成功と
mainの変更なしを確認した。

**本人VM内のローカルGit管理の入門演習**である。
このローカルリポジトリをGitHubへpushした実績ではなく、ns7jp/serverへの本記録PRとは別物である。
過去のAnsible演習すべてがこのコミットを使って実行されたとは扱わない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-09 JST（対話の日付）。各操作の正確な時刻は未採録 |
| 環境 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| リポジトリ | `/home/opsadmin/ansible-first-lab`。serverリポジトリとは別の練習フォルダー |
| 初回コミット | 短縮SHA `a94c1d3`、Add Ansible practice playbooks and templates、root-commit（[E04]） |
| 変更数 | 9 files changed, 127 insertions（[E02]、[E04]） |
| 証拠 | [本人提供の原画像4枚・ハッシュ](screenshots/2026-09-09-lab-base01-git-intro/README.md)。連続rawログ・Git bundle・実ファイル全文は未提供 |

## 記録した対象

以下の9ファイルの追加をステージ一覧とコミット出力で確認した。

| ファイル | 用途 |
| --- | --- |
| .gitignore | 生成物等の除外設定 |
| first.yml | 初期Playbookの変更後版 |
| first-before-change.yml | 変更前の退避版 |
| variables.yml | 実行時変数の練習 |
| env-training.yml | training用変数 |
| env-staging.yml | staging用変数 |
| template.yml | テンプレート生成 |
| template-validated.yml | 入力検証付き生成 |
| templates/app.conf.j2 | 設定ファイルのひな形 |

案内した.gitignoreは次のとおり。実ファイル全文の再取得ではない。

```gitignore
/managed/
/managed-vars/
/managed-template/
/.venv/
*.retry
```

生成ディレクトリが初期一覧に存在した状態から、ステージには指定の9ファイルだけが表示され、
コミット後statusに変更行がないことを確認。独立したgit check-ignoreの出力や
グローバル除外設定の有無までは採録していない。

## 確認結果

GI番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果・限界 |
| --- | --- | --- | --- |
| GI-01 | 開始状態 | PASS | pwdが演習フォルダー、git rev-parseがnot a git repository、ファイル一覧あり（[E01]） |
| GI-02 | 保存対象の選別 | PASS | statusに9ファイルがA、diff --cached --statに9 files/127 insertions、生成ディレクトリ行なし（[E02]） |
| GI-03 | ステージ済み空白検査 | 出力確認 | git diff --cached --checkに診断出力なし（[E02]）。終了コードは未採録 |
| GI-04 | identity未設定の検出 | PASS（想定分岐） | Author identity unknown、メールアドレス自動判定失敗でコミット停止（[E03]） |
| GI-05 | 初回コミット | PASS | identity設定の案内後、9ファイルのroot commit a94c1d3を確認（[E04]） |
| GI-06 | 履歴と作業状態 | PASS | log -1に同じSHA/メッセージ、status --short --branchが## mainのみ（[E04]） |

## identity設定の扱い

初回commitがidentity未設定で失敗したため、--localでuser.nameをns7jp、
user.emailをGitHub IDに基づくnoreply形式に設定する手順を案内した。
設定コマンドと設定値の読戻し、コミットのauthor/emailを表示した画面は未提供。
確認できたのは、その案内後にcommitが成功したことである。
Gitのauthor設定はGitHub認証ではなく、GitHubアカウントへの帰属が確認済みとも記載しない。

## 最終状態・未実施範囲

- ローカルmainに初回コミットを作り、statusに変更行なし。演習ソース・生成ファイルは復習用に残す方針。
- 短縮SHAのみ採録。完全SHA・git showによる全内容・署名・Git bundle・各入力ファイルのハッシュは未採録。
- git initのコマンド出力とidentity設定そのものの画面は未採録。前後状態と結果に限定する。
- コミット後のPlaybook再実行は **NOT RUN**。過去の試験結果をa94c1d3の実行結果へ付け替えない。
- VM内リポジトリのremote設定・push・PR・ブランチ操作・変更コミット・checkoutによる復元は **NOT RUN**。
- ローカル履歴作成を別媒体へのバックアップと同一視しない。
- 本PRは本人提供画像を整理する記録追加。AIの文書検査・Gitコミットとは実行主体と対象を分ける。

- [検証証跡台帳](README.md)
- [前段の入力検証](2026-09-09-lab-base01-validation-practice.md)
- [原画像4枚・ハッシュ](screenshots/2026-09-09-lab-base01-git-intro/README.md)

[E01]: screenshots/2026-09-09-lab-base01-git-intro/E01-before.png
[E02]: screenshots/2026-09-09-lab-base01-git-intro/E02-staged.png
[E03]: screenshots/2026-09-09-lab-base01-git-intro/E03-identity-error.png
[E04]: screenshots/2026-09-09-lab-base01-git-intro/E04-committed.png
