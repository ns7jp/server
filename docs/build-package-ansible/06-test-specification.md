# 試験仕様書・結果票

> 💡 **初めて読む方へ**: この文書は「合格の基準」を先に決める試験問題と、実測結果を書き込む結果票を兼ねています。この原本は常に`NOT RUN`のまま保存し、実施結果は日付付きのevidenceへコピーして記録します。試験IDの読み方は[初心者ガイド](beginner-guide.md#4-現場用語ブリッジ)を参照してください。

## この文書の読み方

- 試験IDの接頭辞`AF`は「Ansible Foundation」の略で、他パック（`ZUT`＝Zabbix、`AUT`＝AD）と区別するために付けています。
- `UT`＝単体・構成試験、`IT`＝構築・結合試験、`ST`＝セキュリティ試験、`NW`＝ネットワーク実機検証（[09-network-validation-procedure.md](09-network-validation-procedure.md)に別途詳細）。
- 結果欄は`PASS` / `FAIL` / `BLOCKED` / `NOT RUN`のいずれかのみを使います。実行していない項目を`PASS`とは書きません。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日 | `NOT SET` |
| 実施者 | `NOT SET` |
| 対象ホスト | `NOT SET`（論理ホスト名は`ans-01`） |
| 適用commit SHA | `NOT SET` |
| Ansible / ansible-lint version | `NOT SET` |

## 単体・構成試験（AFUT）

| ID | 項目 | 手順 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AFUT-01 | YAML構文 | `python3 -c "import yaml; yaml.safe_load(open(f))"`を新規3ファイルへ実行 | 例外が発生しない | `PASS`（このセッションで確認済み） | 本PRの作業ログ |
| AFUT-02 | ansible-lint | `ansible-lint --offline`（`ansible/`直下） | 新規ファイルがproduction profileで検出されない | `NOT RUN`（この検証環境では`galaxy.ansible.com`が遮断されておりcollection未取得のため未実行。CIで実行） | — |
| AFUT-03 | 全playbookの構文チェック | `ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --syntax-check` | エラー無く終了する | `NOT RUN`（同上の理由） | — |
| AFUT-04 | Molecule scenario検出 | `cd ansible/roles/common && molecule list`、`docker`roleも同様 | `default`と`el9`の両scenarioが検出される | `NOT RUN` | — |
| AFUT-05 | 成果物リンク | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` | 本パックのMarkdown内リンクがすべてリポジトリ内で解決する | `NOT RUN` | — |

## 構築・結合試験（AFIT）

| ID | 項目 | 手順 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AFIT-01 | 新規構築（Ubuntu） | `ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml` | play recapで`failed=0` | `NOT RUN` | — |
| AFIT-02 | 冪等性 | 上記コマンドを2回目実行 | play recapで`changed=0, failed=0` | `NOT RUN` | — |
| AFIT-03 | Docker動作確認 | `docker version && docker compose version && systemctl is-active docker` | いずれも正常応答、`active` | `NOT RUN` | — |
| AFIT-04 | 時刻同期 | `systemctl is-active chrony`（Ubuntu）/ `chronyd`（RHEL系） | `active` | `NOT RUN` | — |
| AFIT-05 | 自動更新設定 | Ubuntu: `unattended-upgrade --dry-run -d`／RHEL系: `dnf automatic --timer status`相当の確認 | 有効化されている | `NOT RUN` | — |
| AFIT-06 | RHEL系（フェーズ2）構築 | [05-build-procedure.md 手順9](05-build-procedure.md#9-フェーズ2-almalinuxrocky-9への適用) | `failed=0`、AFIT-01〜05相当がRHEL系でも成立 | `BLOCKED`（フェーズ2着手待ち。実VM未用意） | — |
| AFIT-07 | 実ホストnetwork | [09-network-validation-procedure.md](09-network-validation-procedure.md)のAFNW-01〜05を実行 | 名前解決/経路/待受/SSH到達性/firewallが設計どおり | `NOT RUN` | [結果票テンプレート](../evidence/templates/network-host-validation.md) |

## セキュリティ試験（AFST）

| ID | 項目 | 手順 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| AFST-01 | password認証禁止 | `sudo sshd -T \| grep -i passwordauthentication` | `no` | `NOT RUN` | — |
| AFST-02 | rootログイン禁止 | `sudo sshd -T \| grep -i permitrootlogin` | `no`または`prohibit-password` | `NOT RUN` | — |
| AFST-03 | 最小公開 | `ss -lntup`（対象ホスト） | `22/tcp`以外の着信listenが無い | `NOT RUN` | — |
| AFST-04 | dockerグループ非付与 | `id svc-baseline` | `docker`グループが含まれない | `NOT RUN` | — |
| AFST-05 | install dir権限 | `stat -c '%U:%G %a' /opt/ansible-foundation` | `svc-baseline:svc-baseline 750` | `NOT RUN` | — |
| AFST-06 | SELinux enforcing（RHEL系・フェーズ2） | `getenforce` | `Enforcing` | `BLOCKED`（AFIT-06と同じ理由） | — |
| AFST-07 | 未対応OSでの安全停止 | 未対応distributionのコンテナへ`common` roleを適用（Molecule等） | 最初の`assert`で停止し、パッケージが1つも入らない | `NOT RUN` | — |

## 終了判定

フェーズ1必須ID（AFUT-01〜05、AFIT-01〜05、AFIT-07、AFST-01〜05）がすべて`PASS`し、[作業結果・引き渡し報告書](11-work-result-report.md)へ記録された時点で、フェーズ1の試験完了とします。フェーズ2必須ID（AFIT-06、AFST-06）は、AlmaLinux/Rocky 9実機ホストを用意してから着手します。

現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。
