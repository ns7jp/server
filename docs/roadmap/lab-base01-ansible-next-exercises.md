# lab-base01：Ansible演習の次候補（未実施）

> 本書は設計サンプルである。ここに記載したPlaybook・実行手順は**提示のみ**で、
> 本人のVM（`/home/opsadmin/ansible-first-lab`）での実行・画面採録はまだ行っていない。
> 実行して確認できた範囲だけを[検証証跡台帳](../evidence/README.md)へ記録する方針のため、
> 未実施のこの案をそちら側へ混ぜない。

## これまでの実施順（参考）

| # | テーマ | 証跡 |
| --- | --- | --- |
| 1 | 入門（copy/file、changed 2→0→1） | [2026-09-08](../evidence/2026-09-08-lab-base01-ansible-intro-practice.md) |
| 2 | check/diffでの変更予測 | [2026-09-09](../evidence/2026-09-09-lab-base01-check-diff-practice.md) |
| 3 | 切り戻し（旧Playbookでの復帰） | [2026-09-09](../evidence/2026-09-09-lab-base01-rollback-practice.md) |
| 4 | 変数指定（`-e`での上書き） | [2026-09-09](../evidence/2026-09-09-lab-base01-variables-practice.md) |
| 5 | 変数ファイル（`-e @env.yml`） | [2026-09-09](../evidence/2026-09-09-lab-base01-vars-files-practice.md) |
| 6 | テンプレート（Jinja2、`.j2`） | [2026-09-09](../evidence/2026-09-09-lab-base01-template-practice.md) |
| 7 | 入力検証（`assert`での事前拒否） | [2026-09-09](../evidence/2026-09-09-lab-base01-validation-practice.md) |

## 次候補：ハンドラー（`notify` / `handlers`）

これまでの演習はタスクが毎回順番に実行される構成だった。次は「設定ファイルが変わった
ときだけ、後続のアクションを1回だけ起こす」という、Ansibleの中核パターンを扱う。

### 目的

- `notify`で登録したハンドラーが、`changed`が出たタスクの後でのみ実行されることを確認する。
- `changed`が出なかった回（既に同じ内容）はハンドラーが起動しないことを確認する。
- 複数タスクから同名のハンドラーへ`notify`しても、Play末尾で1回しか実行されないことを確認する。

### 提示するPlaybook案（`handlers-demo.yml`）

ホーム内限定で、実サービスの再起動は行わない。ハンドラー発火の有無を
マーカーファイルのタイムスタンプで確認する構成にする。

```yaml
- name: handlers demo
  hosts: localhost
  connection: local
  vars:
    environment_name: staging
    listen_port: 8081
  tasks:
    - name: Render app.conf from template
      ansible.builtin.template:
        src: templates/app.conf.j2
        dest: "{{ ansible_env.HOME }}/ansible-first-lab/managed-template/app.conf"
        mode: "0644"
      notify: Mark config reloaded

    - name: Render second, unrelated file (always same content)
      ansible.builtin.copy:
        content: "static\n"
        dest: "{{ ansible_env.HOME }}/ansible-first-lab/managed-template/static.txt"
        mode: "0644"
      notify: Mark config reloaded

  handlers:
    - name: Mark config reloaded
      ansible.builtin.shell: date > "{{ ansible_env.HOME }}/ansible-first-lab/managed-template/reloaded.marker"
```

### 想定する実行・確認手順（本人VMで実施予定）

1. `reloaded.marker`が存在しない状態から初回実行し、`app.conf`と`static.txt`が
   `changed`、ハンドラーが1回だけ走って`reloaded.marker`が新規作成されることを確認する
   （`--diff`なしの通常実行、ログの`changed=`行とハンドラーのRUNNING行を採録）。
2. 直後に同じ内容で再実行し、両タスクが`changed=0`になり、ハンドラーが
   **起動しない**（出力にハンドラー名の行が出ない、`reloaded.marker`のmtimeが変わらない）
   ことを確認する。
3. `app.conf.j2`側だけ本文を変える（例：`listen_port`を変更）→2タスクのうち
   片方だけ`changed`でも、ハンドラーは1回だけ走ることを確認する
   （`stat`または`ls -l --time-style=full-iso`で前後の`reloaded.marker`のmtimeを比較）。

### 未実施・範囲外（先に明記しておく）

- 実サービスの`systemd` unitに対する`service`モジュールでの`restart`/`reload`は扱わない
  （ホーム内ファイルのマーカーで代替する、入門・テンプレート演習と同じ境界）。
- `listen: <topic>`によるハンドラーのグループ化は扱わない。
- `meta: flush_handlers`でのPlay中途実行は扱わない。
- エラー発生時に`notify`済みハンドラーが実行されない挙動（`rescue`との組み合わせ）は別演習とする。

## 次候補（handlersの次）：`loop`

ハンドラー演習が「1回だけ起こす」を扱うのに対し、今度は「同型のタスクを対象の数だけ
繰り返す」パターンを扱う。個別に`file`/`template`タスクを並べていたこれまでのPlaybookを、
1つの`loop`付きタスクへ書き換えられることを確認する。

### 目的

- `loop`で複数の宛先ファイルを1タスクから生成できることを確認する。
- `loop`の各回の`changed`/`ok`が個別に判定され、`register`した結果（`results`）に
  ループ回数分の要素が入ることを確認する。
- 一部の宛先だけ既存内容と一致する場合に、その回だけ`changed=false`になることを確認する
  （全体が1つの`changed`に丸められないことの確認）。

### 提示するPlaybook案（`loop-demo.yml`）

これまでと同じくホーム内限定。3つの環境向け設定ファイルを1タスクでまとめて生成する。

```yaml
- name: loop demo
  hosts: localhost
  connection: local
  vars:
    envs:
      - name: training
        port: 8080
      - name: staging
        port: 8081
      - name: production
        port: 8082
  tasks:
    - name: Render per-environment app.conf
      ansible.builtin.template:
        src: templates/app.conf.j2
        dest: "{{ ansible_env.HOME }}/ansible-first-lab/managed-loop/{{ item.name }}/app.conf"
        mode: "0644"
      loop: "{{ envs }}"
      loop_control:
        label: "{{ item.name }}"
      register: render_result
```

`templates/app.conf.j2`はこれまでの演習で使ったもの（`environment_name`/`listen_port`を
参照する構成）をそのまま流用する想定。`vars_files`側の`environment_name`/`listen_port`と
`loop`側の`item.name`/`item.port`の対応づけをテンプレート内で揃える必要がある点を、
実行前に案内する。

### 想定する実行・確認手順（本人VMで実施予定）

1. 初回実行で3ディレクトリ・3ファイルが新規生成され、`changed=1`（タスク単位）だが
   `render_result.results`には3要素、いずれも`changed: true`であることを`-v`出力または
   `debug`タスクで確認する。
2. 同じ内容で再実行し、タスク全体は`changed=0`、`results`の3要素すべてが
   `changed: false`であることを確認する。
3. `envs`変数の`production`のポートだけ変更して再実行し、`results`の該当要素のみ
   `changed: true`、他2件は`changed: false`であることを確認する
   （`loop_control.label`で該当要素をログ上で識別する）。

### 未実施・範囲外（先に明記しておく）

- `loop`と`with_items`等の旧構文の比較は扱わない（`loop`のみを対象とする）。
- ネストした`loop`（`subelements`、`loop`の入れ子）は扱わない。
- 生成した3ファイルに対する実サービスの起動・ポート待受は扱わない
  （テンプレート演習・入門演習と同じ境界）。
- 失敗時の`loop`継続・中断（`ignore_errors`との組み合わせ）は別演習とする。

## さらに次の候補（優先度順・未設計）

| 候補 | 確認したいこと |
| --- | --- |
| `block` / `rescue` / `always` | 失敗時の代替処理と、常に走る後始末タスクの切り分け（切り戻し演習の応用） |
| `ansible-vault` | 平文で置いていた変数ファイルの暗号化・復号、`--ask-vault-pass`と`vault-password-file`の違い |
| roleへの切り出し | これまでの単一Playbookタスクをrole（`tasks/`・`templates/`・`defaults/`）へ再編し、`site.yml`側roleとの差を確認 |

本書の実行・採録が済んだ段階で、結果は新規の
`docs/evidence/YYYY-MM-DD-lab-base01-handlers-practice.md`（handlers）または
`docs/evidence/YYYY-MM-DD-lab-base01-loop-practice.md`（loop）へ記録し、
本書側は該当セクションを「実施済み」へ更新するか、[README](README.md)の表から外す。
