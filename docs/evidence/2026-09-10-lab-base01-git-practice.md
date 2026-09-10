# lab-base01：Gitブランチ・履歴・除外ルール演習（2026-09-10）

## 結果と範囲

本人がVM内の演習リポジトリで環境名を変更し、作業ブランチへコミットした。
ブランチの切替による本文の切替、履歴の検索、除外ルールの一致・不一致、演習ファイルの
削除まで画面で確認。最後はmain cleanで、変更コミットは作業ブランチに残した。

これは**本人VM内のローカルGit演習**である。環境名の変更は変数ファイル1行だけで、
ステージング環境の構築・Ansibleの再実行・GitHubへのpushの実績ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行して画像提供 |
| 日付 | 2026-09-10 JST（対話の日付）。各画像の撮影時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。OS版は今回再採録していない |
| 実行場所 | `/home/opsadmin/ansible-first-lab`。公開用serverリポジトリとは別 |
| 開始・最終main | 初回コミット `a94c1d3`、未コミットの変更なし |
| 作業ブランチ | `practice/staging-name`（取り込まずに保存） |
| 変更コミット | 短縮SHA `d7b3d4d`。完全SHAはE05/E06の画面に表示（機械可読の読戻しは未採録） |
| コミット表示日時 | `Thu Sep 10 11:06:40 2026 +0900`。VMの時計精度や署名は未検証 |
| 原資料 | [本人提供画像9枚とハッシュ](screenshots/2026-09-10-lab-base01-git-practice/README.md) |

## 実施したことと確認結果

GP番号は本報告書専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 実測結果・証拠 |
| --- | --- | --- | --- |
| GP-01 | 開始状態 | PASS | main clean、a94c1d3、本文はenvironment_name: staging（E01） |
| GP-02 | ブランチ上の変更 | PASS | practice/staging-nameでstaging→staging-testの1行差分、M表示（E02） |
| GP-03 | 変更保存 | PASS | d7b3d4dを作成、1 file changed / 1 insertion / 1 deletion（E03） |
| GP-04 | 切替と保持 | PASS | mainではstaging、作業ブランチではstaging-test。双方clean（E03） |
| GP-05 | ブランチ間比較 | PASS | diff main practice/staging-nameで同じ1行差分、logに2コミット（E04） |
| GP-06 | 取り込まず終了 | PASS | mainへ戻りstaging、main clean。作業ブランチはd7b3d4dに残る（E04） |
| GP-07 | ファイル別履歴 | PASS | log --oneline --all -- env-staging.ymlで2件、showで変更本文確認（E05） |
| GP-08 | 要約と状態維持 | PASS | show --statで1行追加/削除、main clean、本文stagingを維持（E06） |
| GP-09 | 除外ルールと追跡 | PASS | 既存5ルールと、ls-files --error-unmatchで.gitignore出力（E07） |
| GP-10 | 除外一致 | PASS | .retryは.gitignore:5:*.retry、一致終了0、statusに!!（E08） |
| GP-11 | 除外不一致 | PASS | .txtはcheck-ignore出力なし、終了1、statusに??（E08） |
| GP-12 | 後片付け | PASS | 2ファイルをrm、test ! -eの連結後に確認メッセージ、main clean（E09） |

`git diff --cached --check`はE03のAND連結で後続commitが実行されており、成功終了を確認できる。
数値の終了コード自体は未採録。`check-ignore`の終了1は本演習では想定した不一致である。

## 計画からの変更

[元の手順案](../roadmap/lab-base01-git-next-exercises.md)ではlisten_portの変更を予定していたが、
開始時の実ファイルは`environment_name: staging`の1行だった（E01）。実物に合わせて
環境名だけを変更し、ブランチ名も`practice/staging-name`とした。
コンフリクト演習を先に行わず、既存の2コミットを使った履歴検索へ進んだ。

今回の履歴検索は`--all`を付けて作業ブランチも対象にした。mainだけを検索すると、
未マージの変更コミットは含まれない。履歴表示はブランチ切替やファイル変更を行わない。

## 除外ルール演習の対象

既存の除外ルールは`/managed/`、`/managed-vars/`、`/managed-template/`、`/.venv/`、`*.retry`。
今回実測したのは末尾の`*.retry`の一致と不一致のみである。

- `git-ignore-practice-0910.retry`：除外対象。
- `git-ignore-practice-0910.txt`：除外されない未追跡ファイル。
- 既存ファイルを上書きしない空ファイル作成を案内したが、作成コマンドの実行画面・
  ファイルサイズ・内容の独立した読戻しは未採録。E08では両ファイルの存在と状態を確認。
- `.gitignore`が追跡済みであることは確認したが、追跡済みファイルに新しいignoreルールを
  適用して追跡が継続する比較試験はNOT RUN。設定は編集していない。

## SSH接続の切り分け（対話内画像からの補足）

Git演習前に、本人がホスト側PowerShellからの接続を切り分けた。
一方のVMアドレスではタイムアウト、内部ネットワーク側ではTCP/22の到達成功と
`Permission denied (publickey)`を確認。VM内ではsshがactive、22番の待受を確認した。
VM用の既存鍵を`-i`と`IdentitiesOnly=yes`で指定する手順の案内後に、VM内プロンプトと
演習フォルダーでの結果が提供された（E01）。鍵指定付き接続のコマンドと成功直後の画面を
一体では採録していないため、認証方式の独立した検証とはしない。

タイムアウトした経路の原因は未特定。SSH設定・Firewall変更の実施は記録していない。
SSH診断の画像は対話内のみとし、この公開資料には鍵一覧・ネットワーク一覧を添付しない。

## 未実施・限界

- マージ、コンフリクト発生・解消・abort、rebase、push：**NOT RUN**。
- Ansible再実行、実サービスへの反映、ポート変更：**NOT RUN**。
- 履歴検索の`git log -p -2`、マージコミットの探索、本人独力による説明：未採録。
- `/managed/`等のディレクトリルール比較、追跡解除の実験：**NOT RUN**。
- ブランチ作成コマンドの出力は未採録。作成後のブランチ名と状態はE02で確認。
- 連続rawログ、Git bundle、初回コミットの完全SHA、Git署名検証は未採録。
- この結果票を追加するserver側のコミット/CIは、本人VMでの実行主体・対象SHAとは別。

## 復習

`commit`で保存、`diff`で比較、`switch`で切替。`log`で変更を探し、`show`で内容を見る。
`check-ignore -v`は除外理由、`status --ignored`は現在の状態を示す。
これはAIがまとめた復習用説明であり、本人が独力で説明済みという証跡ではない。

- [前段：Git管理開始](2026-09-09-lab-base01-git-intro-practice.md)
- [検証証跡台帳](README.md)
