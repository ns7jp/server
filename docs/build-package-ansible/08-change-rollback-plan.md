# 変更・ロールバック計画兼記録票

> 💡 **初めて読む方へ**: この文書は「完成後に設定を変更するとき、失敗したらどう戻すか」を先に決めておく文書です。問題が起きてから戻し方を考えるのでは遅い、という考え方に基づきます。

## 1. 変更の分類

| 分類 | 例 | 影響範囲 | 承認 |
| --- | --- | --- | --- |
| role内部の変更 | `common` / `docker`のtasks・defaultsの修正 | 本パックだけでなく、`site.yml`（Linux版パック）など同じroleを使う全案件 | 必須。他パックへの影響を確認する |
| `foundation.yml` / `group_vars/foundation`の変更 | 新しい変数上書き、role追加 | 本パックのみ | 推奨 |
| inventory値の変更 | 対象IP、SSHユーザーの変更 | 対象ホストのみ | 任意（作業記録は残す） |

`common` / `docker`両roleは他の案件パックと共有されているため、本パックのためだけの変更でroleそのものを書き換えると、[Linux版パック](../build-package/README.md)（`SM-LAB-001`）の挙動にも影響します。role内部を変更する場合は、変更後に`ansible-lint`とMoleculeの両方を再実行し、影響範囲をこの文書に記録してください。

## 2. Go / No-Go条件

変更を対象ホストへ適用する前に、次をすべて満たすことを確認します。

- [ ] 変更内容が[詳細設計書](02-detailed-design.md)の設計方針（責務分離、ガード、変数優先順位、冪等性）と矛盾しない
- [ ] `ansible-lint --offline`が通過する（この検証環境ではCIでの実行結果で代替する）
- [ ] 変更対象のroleにMoleculeシナリオがあれば、ローカルで`molecule test`を実行し`idempotence`まで成功する
- [ ] 変更前の対象ホストの状態（`ansible-playbook ... --check --diff`の出力）を保存済み
- [ ] ロールバック手順（本書3節）を確認済み

いずれか1つでも満たさない場合は`No-Go`とし、対象ホストへは適用しません。

## 3. ロールバック手順

### 3.1 コード変更のロールバック

```bash
git log --oneline -- ansible/roles/common ansible/roles/docker ansible/playbooks/foundation.yml
git revert <問題のcommit SHA>
```

Ansibleのコードそのものはコンテナや外部サービスへの副作用が無いため、直前の正常commitへ`git revert`すれば、次回の適用から新しい設定は使われなくなります。

### 3.2 対象ホストのロールバック

`common` / `docker`両roleは「望む状態」を宣言的に適用するため、**直前のcommitへ戻したplaybookをもう一度適用する**ことが基本のロールバック手段です。

```bash
git checkout <直前の正常commit SHA> -- ansible/
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --check --diff
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml
```

検証専用の使い捨てVMの場合は、VMの再作成（スナップショット復元またはゼロからの再構築）のほうが早く確実です。

## 4. 変更記録

| 日付 | 変更内容 | 対象role/ファイル | Go/No-Go判定 | 実施結果 | ロールバック要否 |
| --- | --- | --- | --- | --- | --- |
| `NOT SET` | — | — | — | — | — |

この表は変更のたびに追記します。原本には記入例を残さず、実際の変更が発生した時点で行を追加してください。
