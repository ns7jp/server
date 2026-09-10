# lab-base01：Git演習の次候補（未実施）

> 本書は手順案の保管文書。2026-09-10に本人VMでブランチ・履歴・ignoreの一部を実施した。
> 実物に合わせた変更点・実測範囲は[結果票](../evidence/2026-09-10-lab-base01-git-practice.md)を正本とする。
> 以下の案をすべて実行したという意味ではない。未実施項目は引き続きNOT RUN。

## 2026-09-10時点の実施範囲

| テーマ | 状態 |
| --- | --- |
| ブランチ・diff | 環境名staging→staging-testに変更して実施。取り込まず作業ブランチを残す6bを選択 |
| コンフリクト | VM内の練習ブランチで発生・解消・abortを実施。[追補結果票](../evidence/2026-09-10-lab-base01-git-merge-practice.md) |
| 履歴探索 | 2コミットでファイル別log --all、show、show --stat、前後状態を確認。log -p -2は未採録 |
| ignore境界 | *.retryの一致/不一致と削除を確認。ディレクトリ比較・追跡継続の比較試験はNOT RUN |

以降は実施前の設計サンプルを保持する。開始条件のlisten_portは実ファイルにはなく、
初回commit後にbranch操作が未実施という記述も前段時点の情報である。

注意：後掲のコンフリクト案の手順1〜3は、mainの変更後に分岐するためそのままでは競合を再現しない。
今回実施したのは追補結果票のとおり、共通mainから2本を分岐して各々で同じ行を変更する手順である。
後掲の原案をそのまま再実行せず、実測済みの分岐条件を参照する。

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

## 次候補（コンフリクトの次）：`git log`で履歴を探す

コンフリクト解消後は、作った履歴を「眺める」のではなく、質問に応じて絞り込む練習へ進む。
この演習では新しいcommitを作らず、前段までに作った履歴を読み取り専用で利用する。

### 目的

- `--oneline`は履歴の索引、`-p`は各commitの変更内容を見る指定だと区別する。
- `git log -- <file>`で、リポジトリ全体ではなく特定ファイルに関係する履歴だけを探す。
- commit IDを控え、`git show <commit>`で後から同じ変更を再確認できることを確かめる。
- 表示コマンドは作業ツリーや履歴を変更しないことを、実行前後の`git status`で確認する。

### 想定する実行・確認手順（本人VMで実施予定）

1. `git status --short --branch`を実行し、未commitの変更がない状態から開始する。変更があれば
   勝手に破棄せず、この演習を中断して内容を確認する。
2. `git log --oneline --decorate --graph --all`を実行し、main、作業ブランチ、マージcommitの
   位置を確認する。画面に収まらない場合は`q`でpagerを終了する。
3. `git log -p -2`で直近2件のcommit本文と差分を読み、`--oneline`との情報量の違いを確認する。
4. `git log --oneline -- env-staging.yml`を実行し、同ファイルを変更したcommitだけに絞られる
   ことを確認する。`--`はrevision名とファイルパスの境界であり、省略しない。
5. (4)で得たcommit IDを1件選び、`git show --stat <commit>`で変更対象の要約、
   `git show -- env-staging.yml <commit>`ではなく
   `git show <commit> -- env-staging.yml`でそのファイルの差分を確認する。
6. `git status --short --branch`を再実行し、開始時と同じであることを確認する。

### 採録する最小証跡

- 実行前後の`git status --short --branch`。
- `--oneline --decorate --graph --all`でブランチの位置が分かる出力。
- `git log --oneline -- env-staging.yml`と、そこから選んだcommitに対する`git show --stat`。
- 「どの質問にどの表示を使うか」を本人の言葉で1行ずつ記録する。

### 未実施・範囲外（先に明記しておく）

- `git bisect`による不具合commitの探索、`git blame`による行単位の履歴確認は扱わない。
- `reflog`、削除したbranchの復旧、履歴の書き換えは扱わない。
- pagerや`format.pretty`など、個人のGit表示設定は変更しない。

## 次候補（履歴探索の次）：`.gitignore`の境界を確認する

`.gitignore`を「何となく秘密や一時ファイルを隠すもの」と覚えず、どのルールがどのパスに
一致したかを`git check-ignore`で説明できる状態を目指す。既存の追跡対象を壊さないよう、
演習専用の空ファイルだけを作成し、終了時に削除する。

### 目的

- ignore対象と追跡対象は別概念であり、既に追跡済みのファイルには通常のignoreルールが
  適用されないことを確認する。
- `git check-ignore -v`の「ルール記載ファイル・行番号・パターン・対象パス」を読み取る。
- 似た名前でも、ディレクトリ位置や拡張子により一致・不一致が変わることを確認する。
- 秘密値らしいファイルを作れば安全になるのではなく、commit前の確認が必要だと理解する。

### 事前確認

1. `git status --short --branch`がcleanであることを確認する。
2. `git check-ignore -v managed/example '*.retry' 2>/dev/null || true`のような架空パスだけの確認ではなく、
   `sed -n '1,200p' .gitignore`で実在するルールを先に読む。
3. 以降で使う候補パスは、`.gitignore`に実際に存在するパターンから選ぶ。記載がなければ
   ルールを推測で追加せず、この演習を`BLOCKED`として記録する。

### 想定する実行・確認手順（本人VMで実施予定）

1. `.gitignore`の既存ルールに一致する、内容が空の演習用ファイルを2件作る。前段で案内した
   内容が維持されていれば、`mkdir -p managed && touch managed/ignore-check.txt practice.retry`を使う。
   実際の認証情報や秘密値は入力しない。
2. それぞれに`git check-ignore -v -- <path>`を実行し、出力されたパターンと行番号が
   `.gitignore`の記載に一致することを確認する。
3. 名前は似ているがルールに一致しない空ファイルを1件作り、
   `git check-ignore -v -- <path>`が終了コード1・出力なしになることを確認する。
4. `git status --short --ignored`で、ignore対象は`!!`、ignoreされない未追跡ファイルは`??`と
   表示されることを確認する。終了コードを確認する場合は各コマンドの直後に`echo "$?"`を使う。
5. `git ls-files --error-unmatch .gitignore`で`.gitignore`自体が追跡済みであることを確認し、
   ignoreルールを追加しても追跡済みファイルが自動的に追跡解除されるわけではないと整理する。
6. 作成した演習用ファイルだけを`rm -- <path...>`で削除する。最後に
   `git status --short --branch`が開始時と同じであることを確認する。

### 安全上の注意

- `git add -f`、`git rm --cached`、`.gitignore`の編集はこの確認演習では行わない。
- `git clean`は演習用以外の未追跡ファイルも消す可能性があるため使わない。
- `git check-ignore`の出力なしは即座に「安全」を意味しない。むしろ追跡候補になり得るため、
  `git status`で確認し、秘密値を含む場合はcommitせず削除する。
- `2>/dev/null || true`で結果を隠さない。想定した不一致だけ終了コード1として記録する。

## さらに次の候補（要判断）

| 候補 | 着手条件 | 確認したいこと |
| --- | --- | --- |
| remote・push | 公開先、可視性、使用する認証方式を本人が決める | `remote -v`・初回push・upstreamの関係 |
| `git blame` | 履歴探索まで本人VMで採録済み | 行の最終変更commitを調べ、責任追及ではなく変更理由の入口として使う |
| `git bisect` | テストで良否を判定できる題材を別途用意する | 二分探索で原因commitを絞る流れ |

本書の実行・採録が済んだ段階で、結果は新規の
`docs/evidence/YYYY-MM-DD-lab-base01-git-branch-practice.md`（ブランチ/diff）、
`docs/evidence/YYYY-MM-DD-lab-base01-git-conflict-practice.md`（コンフリクト解消）、
`docs/evidence/YYYY-MM-DD-lab-base01-git-history-practice.md`（履歴探索）、または
`docs/evidence/YYYY-MM-DD-lab-base01-git-ignore-practice.md`（ignore境界）へ記録し、
本書側は該当セクションを「実施済み」へ更新するか、[README](README.md)の表から外す。
