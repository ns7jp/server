# lab-base01：Git演習の次候補（未実施）

> 本書は設計サンプルである。ここに記載したコマンド・実行手順は**提示のみ**で、
> 本人VM（`/home/opsadmin/ansible-first-lab`）での実行・画面採録はまだ行っていない。
> 実行して確認できた範囲だけを[検証証跡台帳](../evidence/README.md)へ記録する方針のため、
> 未実施のこの案をそちら側へ混ぜない。

## これまでの実施（参考）

| # | テーマ | 証跡 |
| --- | --- | --- |
| 1 | Git管理の開始（`git init`・初回commit、identity未設定の検出） | [2026-09-09](../evidence/2026-09-09-lab-base01-git-intro-practice.md) |

初回commit `a94c1d3`の時点で、ローカル`main`に9ファイルがある状態から次を扱う。
remote設定・push・ブランチ操作はまだ一度も行っていない（前段記録の「未実施範囲」どおり）。

## 次候補：ブランチを切って変更し、`diff`で比較してから戻す

Ansible側の「切り戻し」演習（別Playbookでの復帰）と対になる、Gitのネイティブな機能
（`branch`・`diff`・`checkout`/`switch`）で同じ目的を達成できることを確認する。

### 目的

- `main`から作業ブランチを切り、そのブランチでだけ変更・commitできることを確認する。
- `git diff`でブランチ間・commit間の差分が行単位で見えることを確認する。
- `main`へ戻すと、作業ブランチの変更が見えなくなること（削除ではなく退避）を確認する。
- 最後に作業ブランチをmainへ取り込む（`merge`）か、取り込まずに残すかの違いを確認する。

### 想定する実行・確認手順（本人VMで実施予定）

1. `git switch -c practice/listen-port`で作業ブランチを作成し、`git branch --show-current`で
   ブランチ名が切り替わったことを確認する。
2. `env-staging.yml`の`listen_port`を`8081`から別の値へ変更し、`git diff`で変更前後の差分
   （`-8081`/`+新しい値`の行）を確認したうえでcommitする。
3. `git diff main practice/listen-port`で、2つのブランチ間の差分が(2)の変更と一致することを
   確認する。
4. `git switch main`で戻り、`env-staging.yml`の内容が`8081`のまま（作業ブランチの変更が
   見えない）ことを`cat`で確認する。ここでAnsibleのPlaybookを**実行しない**
   （ファイル内容の確認にとどめ、Ansible演習とGit演習の対象を混同しない）。
5. `git switch practice/listen-port`で作業ブランチへ戻れること、変更が保持されていることを
   再確認する。
6. 選択式で次のいずれかを行い、結果を`git log --oneline --graph --all`で確認する。
   - 6a. `git switch main && git merge practice/listen-port`で取り込み、mainに変更が反映される。
   - 6b. 取り込まずに`practice/listen-port`を残し、mainは変更前のままであることを確認する
     （どちらを選んだか記録に明記する）。

### 未実施・範囲外（先に明記しておく）

- remoteの設定・`git push`・GitHubへの公開は扱わない（前段記録の境界を維持する）。
- コンフリクトを起こす演習（mainと作業ブランチで同じ行を別々に変更する）は別演習とする。
- `git rebase`・`git cherry-pick`・`git stash`は扱わない。
- 変更後のPlaybook実行（Ansible側の検証）はこのGit演習の範囲外。ファイル内容の確認のみ。
- commitの著者情報・署名の検証は前段から継続して未採録。

## 次候補（ブランチ/diffの次）：コンフリクトの発生と解消

前段のブランチ演習は「同じ行を変更していない」ため、`merge`は必ず成功する。次は、
main側と作業ブランチ側で**同じ行**を別々に変更し、`merge`が止まる・マーカーが挿入される・
手動で解消するという、実務で最初につまずく手順を扱う。

### 目的

- 同じ行への別々の変更で`git merge`が`CONFLICT`となり、自動マージが止まることを確認する。
- コンフリクト中の`git status`が該当ファイルを「both modified」等で示すことを確認する。
- ファイル内の`<<<<<<<`/`=======`/`>>>>>>>`マーカーの位置と、mainの内容・作業ブランチの
  内容がそれぞれどちらに対応するかを確認する。
- マーカーを手動で編集し、`git add`→`git commit`でマージが完了することを確認する。
- `git merge --abort`で、コンフリクト前の状態へ戻せることも別途確認する。

### 想定する実行・確認手順（本人VMで実施予定）

1. `main`で`env-staging.yml`の`listen_port`を`8081`から`8090`へ変更しcommitする
   （前段のブランチ演習とは別に、mainを直接進める）。
2. `main`から新しい作業ブランチ`practice/conflict-port`を切り、同じ行の`listen_port`を
   `8099`へ変更しcommitする。
3. `git switch main && git merge practice/conflict-port`を実行し、`CONFLICT (content)`が
   出て自動マージが止まることを確認する。
4. `git status`で該当ファイルが未マージ状態として表示されることを確認する。
5. `env-staging.yml`を開き、`<<<<<<< HEAD`（mainの`8090`）と
   `>>>>>>> practice/conflict-port`（作業ブランチの`8099`）のマーカーを確認したうえで、
   マーカーを削除してどちらか一方（または別の値）を残す。
6. `git add env-staging.yml && git commit`（マージコミットとして完了）し、
   `git log --oneline --graph`で2つの親を持つマージコミットができていることを確認する。
7. 別途、同じ手順を再現してから今度は`git merge --abort`を使い、mainが
   コンフリクト前の`8090`のまま、作業ブランチも変更されずに残ることを確認する
   （6と7は同じブランチの再利用ではなく、別のブランチで再現する）。

### 未実施・範囲外（先に明記しておく）

- 3-way以上の複数ブランチが絡むコンフリクトは扱わない（2ブランチ間のみ）。
- `git rebase`中のコンフリクト（`merge`とマーカーの意味は同じだが操作系が異なる）は
  別演習とする。
- マージ後のPlaybook実行・Ansible側の反映確認はこのGit演習の範囲外。
- コンフリクトマーカーを含んだファイルを誤ってcommitしてしまうケース
  （マーカー未解消のままadd）は、今回の手順では発生させない（案内で明示的に避ける）。

## さらに次の候補（優先度順・未設計）

| 候補 | 確認したいこと |
| --- | --- |
| `git log`での履歴探索 | `--oneline`・`-p`・特定ファイルの履歴（`git log -- <file>`）の違い |
| `.gitignore`の境界確認 | `git check-ignore -v`で、前段で案内したパターンがどのパスに効くかを個別に確認 |
| remote・push（要判断） | GitHub等への公開が前提になるため、公開先・可視性を本人が決めてから着手 |

本書の実行・採録が済んだ段階で、結果は新規の
`docs/evidence/YYYY-MM-DD-lab-base01-git-branch-practice.md`（ブランチ/diff）または
`docs/evidence/YYYY-MM-DD-lab-base01-git-conflict-practice.md`（コンフリクト解消）へ記録し、
本書側は該当セクションを「実施済み」へ更新するか、[README](README.md)の表から外す。
