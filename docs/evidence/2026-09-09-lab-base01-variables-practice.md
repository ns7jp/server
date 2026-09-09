# lab-base01：Ansibleの変数指定と再実行（2026-09-09）

## 結果と範囲

本人のUbuntu VMで、変数を持つ2タスクのPlaybookを使い、初回にenvironment=trainingを生成し、
実行時の`-e environment_name=staging`でenvironment=stagingへ変更した。
同じ指定で再実行しchanged=0とstaging本文の維持を確認した。

**ホーム内の演習用ファイルの内容を変数で切り替えた記録**であり、
実際のステージング環境・別サーバーを構築した実績ではない。
SSH・UFW・OS設定・全ロールの自動構築や冪等性は対象外。

## 来歴と環境

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIがPlaybookと手順を提示し、本人がコピー・実行・画像提供 |
| 日付 | 2026-09-09 JST（対話の日付）。各コマンドの正確な開始終了時刻は未採録 |
| 対象 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前段のAnsible core2.16.3/Python3.12.3を参考とする。今回の再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`、serverリポジトリ外 |
| Playbook | variables.yml。全文・ハッシュ・Gitの版はVMから未取得。下記は案内した内容の再掲 |
| 出力 | managed-vars/environment.txt。最終本文environment=staging（[E03]） |
| 原資料 | [無加工の原画像3枚・SHA-256](screenshots/2026-09-09-lab-base01-variables/README.md)。連続rawログは未提供 |

## 提示したPlaybook

この内容をvariables.ymlへ保存するhere-documentを案内した。実行ファイルとのバイト一致を証明したものではない。

```yaml
---
- name: Practice Ansible variables
  hosts: localhost
  connection: local
  gather_facts: false
  become: false

  vars:
    environment_name: training
    output_dir: /home/opsadmin/ansible-first-lab/managed-vars

  tasks:
    - name: Create output directory
      ansible.builtin.file:
        path: "{{ output_dir }}"
        state: directory
        mode: "0750"

    - name: Write environment setting
      ansible.builtin.copy:
        dest: "{{ output_dir }}/environment.txt"
        content: "environment={{ environment_name }}\n"
        mode: "0640"
```

## 確認結果

VR番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果と限界 |
| --- | --- | --- | --- |
| VR-01 | 初回の既定値適用 | PASS | `variables.yml`を実行、ok2/changed2/failed0/終了0、本文training（[E01]） |
| VR-02 | 変更予測後の旧本文 | 部分確認 | [E02]上部にchanged1/failed0/終了0とtraining本文。予測コマンド・予測差分は画面外のためcheck mode実行の全証跡とはしない |
| VR-03 | 実行時の変数指定 | PASS | `-e environment_name=staging --diff`を確認、directoryはok・fileはchanged、changed1/failed0/終了0（[E02]） |
| VR-04 | 指定後の実体 | PASS | 差分training→stagingと、catのenvironment=staging（[E02]） |
| VR-05 | 同じ指定で再適用 | PASS | `-e environment_name=staging`の通常再実行でok2/changed0/failed0/終了0、本文stagingを維持（[E03]） |

適用コマンドと再実行は次のとおり。画像でコマンドを確認できる。

```bash
ansible-playbook -i localhost, variables.yml -e environment_name=staging --diff
ansible-playbook -i localhost, variables.yml -e environment_name=staging
```

前段のcheck/diff演習を踏まえ、最初に同じ変数指定の`--check --diff`で予測する手順を案内した。
画像に見える予測後の本文と、その後の適用コマンド・差分を区別して記録する。
Playbookを書き換えず実行時に値を切り替える目的の演習だが、操作間のファイルハッシュは未採録。

## 最終状態・未実施範囲

- 最終出力はenvironment=staging。variables.ymlとmanaged-varsは復習用に残す方針。
- 提示Playbookの既定値はtraining。`-e`を省いて通常実行するとtrainingへ戻す指定になるが、
  staging適用後に実際に省略して戻す試験は **NOT RUN**。
- 今回の構文チェック結果、Playbook全文・ハッシュ、出力の権限/所有者の再確認は未採録。
- 予測時のコマンド・差分全体が写っていないため、VR-02は部分確認とする。
- 変数ファイル・inventory/group_vars・複数環境・リモート接続・Vault・rolesによる切替は **NOT RUN**。
- サーバー全体の自動構築、独力での説明・Playbook記述能力を確認した実績ではない。
- 本PRは本人提供画像を整理した文書追加。編集環境で本人VMのAnsibleを再実行したものではない。

- [検証証跡台帳](README.md)
- [前段の切り戻し](2026-09-09-lab-base01-rollback-practice.md)
- [原画像3枚・ハッシュ](screenshots/2026-09-09-lab-base01-variables/README.md)

[E01]: screenshots/2026-09-09-lab-base01-variables/E01-training.png
[E02]: screenshots/2026-09-09-lab-base01-variables/E02-staging.png
[E03]: screenshots/2026-09-09-lab-base01-variables/E03-repeat.png
