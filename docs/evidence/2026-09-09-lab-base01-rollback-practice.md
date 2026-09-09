# lab-base01：保存したPlaybookによる切り戻し（2026-09-09）

## 結果と範囲

前段の[check/diff演習](2026-09-09-lab-base01-check-diff-practice.md)で変更した演習用本文を、
退避済みのfirst-before-change.ymlを使って元へ戻した。
check/diffで切り戻しを予測、実際に適用、再度check/diffで変更不要を確認した。

**ホーム内の演習用ファイルの本文を戻した記録**であり、OS全体・アプリ配備・Git commit・
VMチェックポイントのロールバックではない。システム全体の復旧保証には使わない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を案内し、本人が入力・実行・画像提供 |
| 日付 | 2026-09-09 JST（対話の日付）。各操作の開始終了時刻やRTOは未採録 |
| 環境 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前段のAnsible core2.16.3/Python3.12.3を参考とする。今回の再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外の練習フォルダー |
| 使用Playbook | first-before-change.yml。画像でcopyタスクの旧本文指定を確認（[E01]）。全文・ハッシュは未取得 |
| 一次資料 | [原画像2枚・由来・SHA-256](screenshots/2026-09-09-lab-base01-rollback/README.md)。連続rawログは未提供 |

## 試験結果

RB番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果 |
| --- | --- | --- | --- |
| RB-01 | 変更前の指定と現状 | PASS | 退避PlaybookのcontentはManaged by Ansible.、実ファイルはManaged by Ansible version 2.（[E01]） |
| RB-02 | 切り戻し予測 | PASS | `first-before-change.yml --check --diff`でversion2→旧本文の差分、changed1/failed0/終了0（[E01]） |
| RB-03 | 予測時の未適用 | PASS | check/diff直後のcatはversion2を維持（[E01]） |
| RB-04 | 切り戻しの適用 | PASS | 差分とchanged1/failed0/終了0、本文がManaged by Ansible.へ復帰（[E02]上部）。適用コマンド行自体は画面外 |
| RB-05 | 旧指定との一致 | PASS | `first-before-change.yml --check --diff`でok2/changed0/failed0/終了0（[E02]下部） |

実際の切り戻しは、次のコマンドを実行するよう案内した。画像では結果と本文の復帰を確認している。

```bash
ansible-playbook -i localhost, first-before-change.yml --diff
```

その後の確認は、画像内でコマンドも確認できる。

```bash
ansible-playbook -i localhost, first-before-change.yml --check --diff
```

### 戻した本文

```diff
-Managed by Ansible version 2.
+Managed by Ansible.
```

## 最終状態と再実行時の注意

| ファイル | 状態・役割 |
| --- | --- |
| first-before-change.yml | 旧本文を指定。今回の適用・最終checkで使用 |
| managed/message.txt | 旧本文Managed by Ansible.へ切り戻し済み（[E02]） |
| first.yml | 前段ではversion2を指定。今回このファイルを旧版で上書きする操作は案内していない。今回の再読取り画像は未採録 |

first.ymlが前段のままなら、通常実行するとversion2へ再変更される。
最終checkのchanged0はfirst-before-change.ymlの指定に対する結果で、両Playbookと同時に一致した意味ではない。
今回の2つのPlaybookは復習用に保管する方針。削除による後片付けは指示していない。

## 未実施・未採録

- 実行ファイル全文・ハッシュ、Gitによる版管理、最終first.yml再読取り、権限・所有者の今回の再検査は未採録。
- 切り戻し後の通常実行でchanged0を確認する追加試験は **NOT RUN**。最終確認はcheck mode。
- SSH/UFW・OS・リモートホスト・全ロール・アプリ配備の切り戻し、RTO/RPO測定は **NOT RUN**。
- 本人の独力での説明・Playbook作成能力を確認した記録ではない。
- このPRは画像に基づく文書追加。編集環境から本人VMへ接続して再実行したものではない。

- [検証証跡台帳](README.md)
- [前段の変更予測・適用](2026-09-09-lab-base01-check-diff-practice.md)
- [原画像2枚・ハッシュ](screenshots/2026-09-09-lab-base01-rollback/README.md)

[E01]: screenshots/2026-09-09-lab-base01-rollback/E01-preview.png
[E02]: screenshots/2026-09-09-lab-base01-rollback/E02-applied-and-checked.png
