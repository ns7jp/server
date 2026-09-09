# lab-base01：Ansibleテンプレートからの設定生成（2026-09-09）

## 結果と範囲

本人のUbuntu VMで、環境別変数ファイルとJinja2テンプレートを使って演習用app.confを生成した。
初回training/8080、予測では旧本文を維持、実適用でstaging/8081へ変更し、同じ指定の
通常再実行でchanged=0を確認した。

**ホーム内の設定ファイル生成の演習**であり、8080/8081でサービスを起動したり、
実際のstaging環境・複数サーバーを構築したものではない。

## 来歴と対象

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIがPlaybook・テンプレートを提示し、本人が貼り付け・実行・画像提供 |
| 日付 | 2026-09-09 JST（対話の日付）。個別操作の正確な日時は未採録 |
| 環境 | 前段から継続するHyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| ツール版 | 前段のAnsible core2.16.3/Python3.12.3を参考とする。今回の再採録は未実施 |
| 作業場所 | `/home/opsadmin/ansible-first-lab`。serverリポジトリ外 |
| 入力 | template.yml、templates/app.conf.j2、前段のenv-training.yml/env-staging.yml |
| 出力 | managed-template/app.conf。今回の全文・入力ハッシュをVMから取得したものではない |
| 原資料 | [原画像4枚・由来・SHA-256](screenshots/2026-09-09-lab-base01-template/README.md)。連続rawログなし |

## 提示したテンプレートと処理

以下は対話でtemplates/app.conf.j2へ保存するよう提示した内容。実行ファイルのコピーやハッシュ一致の証明ではない。

```jinja2
environment={{ environment_name }}
listen_port={{ listen_port }}
```

template.ymlはlocalhost/connection local/become false/gather_facts falseを指定し、
fileモジュールでmanaged-templateを0750にし、templateモジュールでapp.confを0640で生成する2タスクを案内。
listen_portの既定値は8080、environment_nameは`-e @env-training.yml`等で読み込む構成。
出力先は `/home/opsadmin/ansible-first-lab/managed-template` とした。
入力の全文や生成後のmode/ownerの独立確認は未採録。

## 確認結果

TP番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果・限界 |
| --- | --- | --- | --- |
| TP-01 | 構文確認 | PASS | `template.yml -e @env-training.yml --syntax-check`でplaybook名表示・終了0（[E01]） |
| TP-02 | 初回生成 | PASS | directory/template両タスクchanged、ok2/changed2/failed0/終了0、本文training/8080（[E02]）。起動コマンド行は画面外 |
| TP-03 | 変更予測 | PASS | `-e @env-staging.yml -e listen_port=8081 --check --diff`で2行の差分、changed1/failed0/終了0（[E03]） |
| TP-04 | 予測時の未適用 | PASS | 予測後のcatはtraining/8080のまま（[E03]） |
| TP-05 | 新指定の実適用 | PASS | changed1/failed0/終了0、本文staging/8081（[E04]上部）。適用コマンド行は画面外 |
| TP-06 | 同指定の通常再実行 | PASS | `-e @env-staging.yml -e listen_port=8081`でok2/changed0/failed0/終了0（[E04]下部） |

観測した設定差分：

```diff
-environment=training
-listen_port=8080
+environment=staging
+listen_port=8081
```

変数ファイルとコマンドラインの追加変数を同時に指定している。初回/適用時の本文と予測時の本文を比較し、
予測だけでは出力が変わらないことを確認した。最後はcheck modeではなく通常再実行である。

## 最終状態と未実施範囲

- 最後にcatで確認した本文はstaging/8081。同指定の通常再実行はchanged0だが、その直後のcat再採録はない。
- template.yml、テンプレート、環境別変数ファイル、managed-templateは復習用に保管する方針。
- 本文のポート値を変更しただけで、TCP待受・アプリ起動・設定reloadは **NOT RUN**。
- 入力の全文/ハッシュ、生成後の独立した権限・所有者確認、Gitによる版管理、Playbook不変のバイト照合は未採録。
- training/8080への戻し、未定義変数時の検証、validate、handlers、roles、複数ホスト・リモート構築は **NOT RUN**。
- 本人の独力での説明・テンプレート作成能力を確認したものではない。
- 本PRは本人提供画像に基づく文書追加。編集環境から本人VMのAnsibleを再実行したものではない。

- [検証証跡台帳](README.md)
- [前段の変数ファイル演習](2026-09-09-lab-base01-vars-files-practice.md)
- [原画像4枚・ハッシュ](screenshots/2026-09-09-lab-base01-template/README.md)

[E01]: screenshots/2026-09-09-lab-base01-template/E01-syntax.png
[E02]: screenshots/2026-09-09-lab-base01-template/E02-training.png
[E03]: screenshots/2026-09-09-lab-base01-template/E03-preview.png
[E04]: screenshots/2026-09-09-lab-base01-template/E04-applied-and-repeat.png
