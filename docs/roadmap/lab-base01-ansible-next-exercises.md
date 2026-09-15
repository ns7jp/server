# lab-base01：Ansible演習の次候補（未実施）

> 本書は設計サンプルである。ここに記載したPlaybook・実行手順は**提示のみ**で、
> 本人のVM（`/home/opsadmin/ansible-first-lab`）での実行・画面採録はまだ行っていない。
> 実行して確認できた範囲だけを[検証証跡台帳](../evidence/README.md)へ記録する方針のため、
> 未実施のこの案をそちら側へ混ぜない。

## 元ログ照合の追補（2026-09-15）

[元ログ結果票](../evidence/2026-09-15-lab-base01-original-log-check.md)で展開済み一覧と元ログ5件の一致を確認した。別媒体保存ではない。

## ハンドラー演習の実施追補（2026-09-14）

冒頭の未実施表記と後掲コードは設計時点の原案である。
[本人VMの実測結果](../evidence/2026-09-14-lab-base01-handlers-practice.md)では、
新規managed-handlers、fileのtouchハンドラー、-eによる8082変更を用いた。
初回・8081再実行・8082変更・8082再実行を確認。loopは引き続きNOT RUN。
原案そのものの全文を実行・検証したとは扱わない。

## loop演習の実施追補（2026-09-14）

[本人VMのloop結果票](../evidence/2026-09-14-lab-base01-loop-practice.md)に初回・再実行・部分変更・再実行を記録。
前の追補にあるloop NOT RUNはその時点の記録であり、本追補で実施範囲を更新する。
ディレクトリ作成と変数対応を補った構成で、changed2→0→1→0を確認。後掲原案そのものの検証ではない。

## block・rescue・alwaysの実施追補（2026-09-14）

[本人VMの結果票](../evidence/2026-09-14-lab-base01-block-practice.md)に意図的失敗・正常条件・正常再実行を記録。
ホーム内の結果ファイルとマーカーで制御フローを確認。実サービス復旧やrescue自体の失敗はNOT RUN。
後掲の「未設計」候補表は設計時点の記述で、本追補を最新の実施範囲とする。

## Vault演習の実施追補（2026-09-14）

[本人VMのVault結果票](../evidence/2026-09-14-lab-base01-vault-practice.md)にダミー値の暗号化、
パスワード付き読み込み、未指定時の拒否を記録。password-fileや実際の認証情報の配備はNOT RUN。
後掲の候補表は設計時点の記述であり、本追補を今回の実施範囲とする。

## role演習の実施追補（2026-09-14）

[本人VMのrole結果票](../evidence/2026-09-14-lab-base01-role-practice.md)に初回・再実行・変数上書き・再実行を記録。
最初の別環境実行を除外し、VM側のchanged2→0→1→0を採録。実サービスや既存site.ymlへの組込みはNOT RUN。
後掲候補表は設計時点の記述であり、本追補を今回の実施範囲とする。

## role入力検証の実施追補（2026-09-14）

[本人VMの入力検証結果票](../evidence/2026-09-14-lab-base01-role-validation-practice.md)に
8091の受入、70000の拒否、対象ファイルの前後ハッシュ一致、正常再実行を記録。
既存roleとは別に検証付きroleを作成。境界値・形式違い・不正環境名はNOT RUN。

## 入力境界値・形式検証の追補（2026-09-14）

[本人VMの境界値結果票](../evidence/2026-09-14-lab-base01-boundary-practice.md)で
check modeの1/65535受入、0/65536/abc/80.5拒否を確認。前段の境界値NOT RUNは当時の記録である。
通常実行の書き込み、不正環境名や追加形式の検証は引き続きNOT RUN。

## 環境名入力検証の追補（2026-09-14）

[本人VMの環境名結果票](../evidence/2026-09-14-lab-base01-env-validation-practice.md)に
通常実行でのstagng拒否、対象ファイルの前後ハッシュ一致、正常再実行を記録。
前段の不正環境名NOT RUNは当時の記録。空文字・大文字小文字等の追加比較は未実施。

## 設定ずれ検出・修正の追補（2026-09-14）

[本人VMの設定ずれ結果票](../evidence/2026-09-14-lab-base01-drift-practice.md)で
clone先の9999→8091差分予測、通常実行の修正、修正後の変更なしを確認。
手動変更操作そのものは未採録。実サービス復旧の証跡とは扱わない。

## 実行ログ保存の追補（2026-09-14）

[本人VMのログ結果票](../evidence/2026-09-14-lab-base01-log-capture-practice.md)に
正常再実行のtee保存、終了コード分離、読戻し・ハッシュ一致・権限確認を記録。
失敗時のパイプ挙動と別媒体バックアップは未検証。

## 失敗時ログ保存の追補（2026-09-14）

[本人VMの失敗ログ結果票](../evidence/2026-09-14-lab-base01-failure-log-practice.md)に
不正ポート拒否の終了2とtee終了0、読戻し・ハッシュ一致・権限を記録。
前段の失敗時未検証は当時の記録。保存処理自体の失敗は引き続きNOT RUN。

## ログ転送の追補（2026-09-14）

[本人のログ転送結果票](../evidence/2026-09-14-lab-base01-log-transfer-practice.md)に
VMからホストWindowsへ2ログをscpし、サイズ・SHA-256が一致した結果を記録。
別媒体・別拠点バックアップや復元試験は未実施。

## Windows側ログ確認の追補（2026-09-14）

[Windows側ログ結果票](../evidence/2026-09-14-lab-base01-windows-log-review-practice.md)に
転送済み2ログのCOMMAND・集計・終了コード抽出を記録。全文レビューやAnsible再実行ではない。

## ログ復元の追補（2026-09-14）

[ログ復元結果票](../evidence/2026-09-14-lab-base01-log-restore-practice.md)に
WindowsからVMの別フォルダーへ2ログを戻し、ハッシュ・サイズ・抽出内容を確認した結果を記録。
同じホストPC内の練習であり、別媒体・ホスト故障からの復旧は未実施。

## 変更版既定値の実行追補（2026-09-15）

[8085検証結果票](../evidence/2026-09-15-lab-base01-default-8085-practice.md)に
dac8a0fでのtraining/8085新規生成と通常再実行のchanged0を記録。実サービスや他入力値は今回未検証。

## タグ版切り戻しの追補（2026-09-15）

[タグ版切り戻し結果票](../evidence/2026-09-15-lab-base01-tag-rollback-practice.md)に
ソース切替と生成物の再適用の違い、8085→8080と再実行changed0を記録。実サービス復旧ではない。

## ログ付き変更管理の追補（2026-09-15）

[変更・切り戻し一連結果票](../evidence/2026-09-15-lab-base01-change-cycle-practice.md)に
5段階のログ出力と8080への復帰を記録。実サービス変更や途中失敗時の自動切り戻しは未検証。

## 5段階ログ照合の追補（2026-09-15）

[ログ照合結果票](../evidence/2026-09-15-lab-base01-cycle-review-practice.md)に
保存済み5ログのコマンド説明・集計・終了コード確認を記録。全文レビューや新しい実行結果ではない。

## ログアーカイブの追補（2026-09-15）

[ログアーカイブ結果票](../evidence/2026-09-15-lab-base01-log-archive-practice.md)に
5ログとSHA一覧のtar.gz保存、別フォルダー展開と5件OKを記録。別媒体保存や破損試験は未実施。

## ハッシュ不一致検出の追補（2026-09-15）

[不一致検出結果票](../evidence/2026-09-15-lab-base01-checksum-mismatch-practice.md)に
試験コピー1件のみFAILED、元ログ・検証済みコピーは一致した結果を記録。欠落・一覧破損は未検証。

## 不一致ログ復元の追補（2026-09-15）

[1件復元結果票](../evidence/2026-09-15-lab-base01-checksum-restore-practice.md)に
finalだけのFAILEDから選択復元で5件OKへ戻した結果を記録。元のSHA一覧を使用した。

## ログ欠落検出の追補（2026-09-15）

[欠落検出結果票](../evidence/2026-09-15-lab-base01-missing-log-practice.md)に
別名退避で元名の欠落を検出し、名前を戻して5件OKへ復帰した結果を記録。実削除や媒体故障ではない。

## ログ検証スクリプトの追補（2026-09-15）

[Python検証結果票](../evidence/2026-09-15-lab-base01-log-checker-practice.md)に
既存5ログと正常・不一致・欠落・directoryエラー4ケースを記録。汎用入力や権限不足は未検証。

## 不正一覧検証の追補（2026-09-15）

[不正一覧結果票](../evidence/2026-09-15-lab-base01-manifest-validation-practice.md)に
実ソース読戻しと4ケースの拒否・ハッシュ維持を記録。権限不足や特殊ファイル等は未検証。

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
