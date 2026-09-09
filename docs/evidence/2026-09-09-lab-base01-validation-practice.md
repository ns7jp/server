# lab-base01：Ansibleで不正な設定値を変更前に拒否（2026-09-09）

## 結果と範囲

本人のUbuntu VMで、テンプレート生成前に入力値をassertで検証するPlaybookを使用した。
正しいstaging/8081では検証・後続タスクが成功。不正なポート70000では上限65535の検証に失敗し、
後続のディレクトリ・ファイル生成タスクへ進まなかった。出力ファイルの前後SHA-256が一致し、
本文はstaging/8081を維持した。

**ホーム内の演習用ファイル生成を守る入力検証**であり、実際のポート待受・ネットワーク制御ではない。
意図した拒否のため、Ansibleのfailed=1・終了コード2は異常系試験の期待結果として扱う。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順・Playbookを提示し、本人が操作して画像提供 |
| 日付 | 2026-09-09 JST（対話の日付）。各操作の正確な開始終了時刻は未採録 |
| 対象 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前段のcore2.16.3/Python3.12.3を参考とする。今回の再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外 |
| 入力 | template-validated.yml、templates/app.conf.j2、env-staging.yml。今回の全文・ハッシュは未取得 |
| 保護対象 | managed-template/app.conf。前段のstaging/8081が存在する状態で実施 |
| 原資料 | [原画像2枚・由来・SHA-256](screenshots/2026-09-09-lab-base01-validation/README.md)。連続rawログは未提供 |

## 提示した検証条件

以下をpre_tasksに置き、既存のfile/templateタスクより前で確認するPlaybookを案内した。
これは案内内容の再掲で、VMから取得した実行ファイルのコピーではない。

```yaml
pre_tasks:
  - name: Validate input values
    ansible.builtin.assert:
      that:
        - environment_name in ['training', 'staging']
        - (listen_port | string) is match('^[0-9]+$')
        - (listen_port | int) >= 1
        - (listen_port | int) <= 65535
      fail_msg: "Invalid environment or port number."
      success_msg: "Input values are valid."
```

## 確認結果

IV番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果 |
| --- | --- | --- | --- |
| IV-01 | 正しい値の許可 | PASS | staging/8081でInput values are valid.、ok3/changed0/failed0/終了0（[E01]） |
| IV-02 | 正常時の既存本文 | PASS | environment=staging、listen_port=8081（[E01]） |
| IV-03 | 範囲外の値を拒否 | PASS（期待した失敗） | staging/70000で上限65535のassertがevaluated_to=false、Invalid environment or port number.、failed1/終了2（[E02]） |
| IV-04 | 後続処理前に停止 | PASS | Validate input valuesで失敗し、その後のfile/templateタスクは表示されず、ok0/changed0（[E02]） |
| IV-05 | 出力ファイルの不変 | PASS | 拒否前後のsha256sumが一致し、catでstaging/8081維持（[E02]） |

画像内で確認した不正値の実行コマンド：

```bash
ansible-playbook -i localhost, template-validated.yml -e @env-staging.yml -e listen_port=70000
```

check modeではなく通常実行で拒否した。changed=0の報告だけに依存せず、
対象app.confのSHA-256と本文を前後比較した。画像のSHA-256一覧と、画像内のapp.confハッシュは別物である。

## 最終状態と未実施範囲

- app.confはstaging/8081のまま。書込みが起きていないため復旧のための書戻しは不要。
- template-validated.yml、テンプレート、変数ファイルは復習用に残す方針。削除は案内していない。
- 70000の上限拒否と8081の許可を確認。0・負数・文字列・境界1/65535・不正環境名・未定義変数の試験は **NOT RUN**。
- 不正値拒否後に正しい値を再実行する追加試験、check modeでの拒否、全タスクの副作用監査は **NOT RUN**。
- SHA-256比較はapp.confの内容についての確認。権限・所有者・更新日時等のメタデータの不変は未検証。
- VM内Playbook全文・ハッシュ・版数の再採録、実サービスの起動・リロード・接続・OS設定は未実施または未採録。
- 入力検証によるファイル生成前の拒否であり、templateモジュールのvalidate機能の試験ではない。
- 全入力の安全性、独力の説明・Playbook作成能力を確認した実績ではない。
- 本PRは本人の画像を整理した文書追加。編集環境で本人VMのAnsibleを再実行したものではない。

- [検証証跡台帳](README.md)
- [前段のテンプレート演習](2026-09-09-lab-base01-template-practice.md)
- [原画像2枚・ハッシュ](screenshots/2026-09-09-lab-base01-validation/README.md)

[E01]: screenshots/2026-09-09-lab-base01-validation/E01-valid.png
[E02]: screenshots/2026-09-09-lab-base01-validation/E02-invalid.png
