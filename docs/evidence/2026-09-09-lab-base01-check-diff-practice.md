# lab-base01：Ansibleの変更予測・適用・再実行（2026-09-09）

## 結果と範囲

本人のUbuntu VMで、前日の[Ansible入門](2026-09-08-lab-base01-ansible-intro-practice.md)の
Playbookを使い、`--check --diff`による変更予測と、通常実行による適用を比較した。
予測時はchanged=1でも実ファイルが旧本文のままであること、実際の適用後は新本文となり、
通常再実行でchanged=0になることを確認した。

**ホーム内の2タスクに限定した演習**で、サーバー全体の構築、全モジュールでのcheck modeの保証ではない。
最後の再実行は`--diff`のみ。案内した最後の`--check --diff`を実行した結果とは記載しない。

## 来歴と対象

| 項目 | 内容 |
| --- | --- |
| 実施日 | 2026-09-09 JST（対話の日付）。画像に各操作の正確な日時は未採録 |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が入力・実行してスクリーンショットを提供 |
| 対象 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前日のcore2.16.3/Python3.12.3を参考とする。今回の版数再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外の練習用フォルダー |
| 管理対象 | `managed`ディレクトリと`managed/message.txt`。Playbookはfirst.yml |
| 退避 | `cp -i first.yml first-before-change.yml`を実行する行を確認（[E02]）。退避ファイル全文・ハッシュは未取得 |
| 証拠 | [原画像3枚と由来・SHA-256](screenshots/2026-09-09-lab-base01-check-diff/README.md)。連続rawログなし |

実行したfirst.ymlの全文・ハッシュ・Git commitは未採録。前段の2タスクと同じ名前の実行結果、
content指定の変更行、実ファイルの前後を確認した範囲に限定する。
今回のPR作成基点mainやCIのSHAをVMのPlaybook実行版として扱わない。

## 確認結果

CD番号は本報告書専用の確認観点。

| ID | 観点 | 判定 | 実測結果 |
| --- | --- | --- | --- |
| CD-01 | 変更前の予測 | PASS | `--check --diff`でok2/changed0/failed0、終了0（[E01]） |
| CD-02 | 指定内容の変更 | PASS | sedでfirst.ymlのcontentをversion 2へ変更しgrepで確認（[E02]） |
| CD-03 | 変更予定の表示 | PASS | `--check --diff`で旧本文から新本文への差分、changed1/failed0/終了0（[E02]） |
| CD-04 | 予測だけでは未適用 | PASS | 直後のcatが旧本文Managed by Ansible.（[E02]） |
| CD-05 | 実際の適用 | PASS | changed1/failed0/終了0、新本文Managed by Ansible version 2.（[E03]上部）。最初の適用コマンド行自体は画面外 |
| CD-06 | 通常再実行 | PASS | `ansible-playbook -i localhost, first.yml --diff`でchanged0/failed0/終了0、新本文維持（[E03]下部） |

### 本文の差分

```diff
-Managed by Ansible.
+Managed by Ansible version 2.
```

予測時のchanged=1は「適用すると変更が必要」という報告で、対象ファイルを書き換えた件数ではない。
今回のfile/copyタスクでは、catによる旧本文の確認と組み合わせて未適用を確かめた。
`--diff`単独はdry-runではなく通常実行である。今回の最後はすでに指定どおりだったため変更がなかった。

## 最終状態・未実施範囲

- 対象ファイル本文はManaged by Ansible version 2.。first.ymlと変更前の退避ファイルを復習用に残す方針。
- ファイル権限や所有者を今回再確認した画像は未提供。本文と実行結果の確認に限定する。
- 適用後の`--check --diff`再確認は案内したが、画像では通常の`--diff`が実行されている。
  **適用後check modeの結果はNOT RUNとして区別**する。
- 退避したPlaybookへの切り戻し、実ファイルを旧本文へ戻す操作は **NOT RUN**。
- 全文・ハッシュ採録、別環境再現、独力での説明、リモートホスト・OS設定・全ロール検証は **NOT RUN**。
- SSH・UFW・Dockerや他VMの設定変更を行う演習ではない。
- check modeはモジュールやタスクにより対応・制約がある。この2タスクの結果から、全Playbookが必ず無変更になるとは一般化しない。
- 本PRは本人提供画像を整理した文書追加。編集環境で本人VMのAnsible操作を再実行したものではない。

- [検証証跡台帳](README.md)
- [前段のAnsible入門](2026-09-08-lab-base01-ansible-intro-practice.md)
- [原画像3枚・ハッシュ](screenshots/2026-09-09-lab-base01-check-diff/README.md)

[E01]: screenshots/2026-09-09-lab-base01-check-diff/E01-baseline.png
[E02]: screenshots/2026-09-09-lab-base01-check-diff/E02-preview.png
[E03]: screenshots/2026-09-09-lab-base01-check-diff/E03-apply-and-repeat.png
