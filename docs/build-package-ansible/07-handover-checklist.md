# 引き渡しチェックリスト

> 💡 **初めて読む方へ**: この文書は作業を依頼者へ引き渡す前の最終確認リストです。試験が全部`PASS`していても、鍵の受け渡し方法を伝え忘れるような漏れを防ぐために使います。

## 引き渡し判定

| 項目 | 判定 |
| --- | --- |
| 案件ID | `SM-ANS-001` |
| 引き渡し対象ホスト | `NOT SET` |
| 判定 | `NOT READY` |
| 判定理由 | 引き渡し対象ホストが未指定で、[試験仕様書](06-test-specification.md)のフェーズ1必須項目が`NOT RUN` |

## 成果物チェック

- [ ] `ansible/playbooks/foundation.yml`が対象ホストへ適用済みで、[試験仕様書](06-test-specification.md)のフェーズ1必須IDがすべて`PASS`
- [ ] `ansible/inventory/foundation.local.yml`（実値）がGit追跡外であることを`git check-ignore`で確認済み
- [ ] `03-parameter-sheet.md`の実機記入欄が実測値で埋まっている
- [ ] `09-network-validation-procedure.md`のAFNW-01〜05の結果票がある
- [ ] `11-work-result-report.md`に計画対実績、差異、残存リスクが記入されている

## 鍵・秘密値の受け渡し

本パックは`ansible-vault`を使いません（[00-requirements.md](00-requirements.md#5-制約と対象外)）。受け渡すべき機密は次の1点だけです。

- [ ] 管理者アカウント（`server_monitor_admin_user`）のSSH**秘密鍵**を、Git管理外の安全な経路（パスワードマネージャー共有、対面でのUSB渡しなど）で引き渡し先へ渡した
- [ ] 公開鍵は`ansible/inventory/foundation.local.yml`（Git追跡外）に記載済みで、リポジトリのどこにも秘密鍵の実値が含まれていないことを確認した（`git log -p -- ansible/inventory/`で秘密鍵らしき文字列が無いか確認）
- [ ] 旧管理者アカウントや検証用の一時鍵が残っていないことを確認した

## 運用・保守

- [ ] 対象ホストで`ansible-playbook ... playbooks/foundation.yml --check --diff`を再実行し、意図しない構成ドリフト（手動変更）が無いことを確認する運用を引き渡し先へ説明した
- [ ] このホストを次にどの案件（監視、AD、Windows、Zabbixなど）で使うか、または使わないかを引き渡し先と確認した
- [ ] RHEL系（フェーズ2）が未着手であることと、その理由（実機VM未用意）を伝えた
- [ ] [変更・ロールバック計画](08-change-rollback-plan.md)の場所を共有した

## セキュリティ

- [ ] `sshd -T`でpassword認証・root直接ログインが無効であることを引き渡し前に再確認した
- [ ] firewallの許可範囲がSSHのみであることを引き渡し前に再確認した
- [ ] `docker`グループがアプリ用アカウントへ付与されていないことを再確認した

## 未解決事項

| 項目 | 内容 | 解消条件 |
| --- | --- | --- |
| RHEL系実機構築 | AlmaLinux/Rocky 9への`foundation.yml`適用が未実施 | フェーズ2用VMの用意、[05-build-procedure.md 手順9](05-build-procedure.md#9-フェーズ2-almalinuxrocky-9への適用未着手)の実施 |
| `foundation.yml`合成後のCI検証 | 現在のCIは各roleのMolecule scenarioを個別に検証しており、`common`+`docker`を組み合わせた`foundation.yml`自体の実コンテナ収束・冪等性は自動検証していない | `.github/workflows/ansible-integration.yml`への追加を検討 |
| ansible-lint / 完全な--syntax-check | この検証環境では`galaxy.ansible.com`が遮断されており未実施 | GitHub Actions（`.github/workflows/ansible-check.yml`）での実行結果を確認する |

これらは引き渡しを妨げる欠陥ではなく、[00-requirements.md](00-requirements.md#5-制約と対象外)に明記した対象外・未実装事項です。引き渡し先が誤って「全機能実装済み」と解釈しないよう、この表をそのまま共有します。
