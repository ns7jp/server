# lab-base01：Ansible入門・再実行と手動変更の修正（2026-09-08）

## 結果と範囲

本人のUbuntu VMで、専用フォルダーとファイルを作る2タスクのPlaybookを実行した。
初回changed=2、同じ状態での再実行changed=0、手動で本文を変えた後の再実行changed=1を確認。
いずれもfailed=0、終了コード0で、最後に本文が指定内容へ戻った。

**ホームディレクトリ内のファイル管理に限定したAnsible入門演習**である。
`foundation.yml` / `site.yml`、OS・SSH・UFW設定、リモートサーバー構築の実績ではない。
この結果を全ロールの冪等性やサーバー全体の自動構築完了へ読み替えない。

## 来歴・環境

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIがPlaybookと手順を提示し、本人が貼り付け・実行・画像提供 |
| 日付 | 2026-09-08 JST（対話の日付）。厳密な開始終了時刻は未採録 |
| 対象 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| 導入方法 | Ubuntuのansible-coreパッケージをaptで導入する手順を案内。導入後のバージョンを確認 |
| 実測版 | ansible/ansible-playbook core2.16.3、Python3.12.3、Jinja3.1.2、libyaml=True（[E01]） |
| 実行場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外の練習フォルダー |
| 対象ホスト・権限 | 案内したPlaybookはlocalhost、connection local、become false、gather_facts false |
| 実行ファイルの版 | `first.yml`の全文やハッシュはVMから未取得。下記は対話で提示した内容であり、実行ファイルとバイト一致を証明したものではない |
| 原資料 | [本人提供画像4枚・由来・SHA-256](screenshots/2026-09-08-lab-base01-ansible-intro/README.md)。連続rawログは未提供 |

## 提示したPlaybook

本人からコピー貼り付けで作成したいという要望があり、nanoでの入力に代えて
引用付きhere-documentで以下をfirst.ymlへ保存する手順を案内した。
これは実行ファイルのダウンロードではなく、案内内容の再掲である。

```yaml
---
- name: First Ansible practice
  hosts: localhost
  connection: local
  gather_facts: false
  become: false

  tasks:
    - name: Create practice directory
      ansible.builtin.file:
        path: /home/opsadmin/ansible-first-lab/managed
        state: directory
        mode: "0750"

    - name: Create practice file
      ansible.builtin.copy:
        dest: /home/opsadmin/ansible-first-lab/managed/message.txt
        content: "Managed by Ansible.\n"
        mode: "0640"
```

## 試験結果

AI番号は本報告書専用の確認観点ID。

| ID | 観点 | 判定 | 実測結果 |
| --- | --- | --- | --- |
| AI-01 | 導入確認 | PASS | ansible/ansible-playbookの版数表示（[E01]） |
| AI-02 | 構文検査 | PASS | `ansible-playbook -i localhost, first.yml --syntax-check`がplaybook名を表示、終了0（[E02]） |
| AI-03 | 初回適用 | PASS | 2タスクともchanged、ok2/changed2/unreachable0/failed0、終了0（[E02]） |
| AI-04 | 実体の確認 | PASS | managedは750、message.txtは640、所有者opsadmin、本文Managed by Ansible.（[E02]） |
| AI-05 | 同じ状態で再適用 | PASS | 2タスクともok、ok2/changed0/unreachable0/failed0、終了0（[E03]） |
| AI-06 | 手動変更の確認 | PASS | printfで本文をChanged manually.へ変更し、catで確認（[E04]） |
| AI-07 | 再適用で修正 | PASS | directoryはok、fileはchanged、ok2/changed1/failed0、終了0、本文がManaged by Ansible.へ復旧（[E04]） |

2回目のchanged=0は、この2タスクの対象が指定した状態にあったため変更不要だったことを示す。
手動変更後はファイルだけを変更し、フォルダーに不要な変更を加えなかった。
Ansibleが常時監視して自動修復する構成ではなく、本人がPlaybookを再実行した時に修正された。

## 最終状態と未実施範囲

- `first.yml`と`managed/message.txt`は復習用に残す方針。最終本文はManaged by Ansible.（[E04]）。
- ファイル削除の後片付けは指示していない。サーバーの常駐サービスを追加した演習ではない。
- 実行したfirst.yml全文・SHA-256・Gitによる版管理は未採録。
- 手動変更修正後の追加再実行changed=0、check/diffモード、異常時の終了、削除からの再生成は **NOT RUN**。
- AnsibleによるリモートSSH接続、sudoを使うOS設定、複数ホスト、roles、handlers、Vault、
  `foundation.yml` / `site.yml`適用、監視全体の自動構築は **NOT RUN**。
- 本人が自分の言葉で説明できるか、独力でPlaybookを書けるかは未確認。貼り付け実行の成功と区別する。
- 本PRは画像に基づく記録追加。編集環境で本人VMのAnsible試験を再実行したものではない。

- [検証証跡台帳](README.md)
- [前段のD-1自動復旧](2026-09-08-lab-base01-d1-practice.md)
- [原画像4枚・ハッシュ](screenshots/2026-09-08-lab-base01-ansible-intro/README.md)

[E01]: screenshots/2026-09-08-lab-base01-ansible-intro/E01-versions.png
[E02]: screenshots/2026-09-08-lab-base01-ansible-intro/E02-first-run.png
[E03]: screenshots/2026-09-08-lab-base01-ansible-intro/E03-second-run.png
[E04]: screenshots/2026-09-08-lab-base01-ansible-intro/E04-drift-repair.png
