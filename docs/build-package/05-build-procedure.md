# 構築手順書

## 0. 作業前確認

- 対象: Ubuntu Server 24.04 LTS の検証用 VM 1 台
- 管理端末から公開鍵 SSH と sudo が利用可能
- 対象 IP、作業時間、ロールバック条件を記録済み
- リポジトリの対象 commit SHA を固定済み
- 実値の秘密情報を Issue、PR、端末ログへ貼らない
- [要件定義書](00-requirements.md)と[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go 条件を確認済み

## 1. 管理端末の準備

```bash
git clone https://github.com/ns7jp/server-monitor.git
cd server-monitor
git rev-parse HEAD
python3 -m venv .venv
. .venv/bin/activate
pip install ansible-core ansible-lint
ansible-galaxy collection install -r ansible/requirements.yml
```

## 2. inventory と秘密値

1. `ansible/inventory/staging.local.yml.example`をGit管理外の`staging.local.yml`へコピーし、
   対象IP、SSH user、`git rev-parse HEAD`で確認した40桁commit SHAを設定します。
2. 実hostでは`server_monitor_source_mode: git`を使い、local inventory変更と配備releaseを分離します。
   `directory` modeはclean checkoutを使うCI / local lab向けです。
3. `ansible/inventory/group_vars/monitor/vault.yml.example` を `vault.yml` にコピーします。
4. 3 種類のランダムな秘密値を設定し、`ansible-vault encrypt` で暗号化します。
5. `ansible/.vault_pass` の権限を`600`にし、inventory / VaultとともにGit管理外であることを確認します。

```bash
cp ansible/inventory/staging.local.yml.example ansible/inventory/staging.local.yml
# $EDITOR ansible/inventory/staging.local.yml
git status --short
git check-ignore ansible/inventory/staging.local.yml ansible/.vault_pass \
  ansible/inventory/group_vars/monitor/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/ansible/.vault_pass"
ansible-inventory -i ansible/inventory/staging.local.yml --graph
ansible all -i ansible/inventory/staging.local.yml -m ping
```

## 3. 事前確認と構築

```bash
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

fresh hostの`--check --diff`は、path/account guard、controller側release取得、moduleが示す差分を
確認するbest-effort preflightです。package、rsync、Docker、directory、serviceを実際には作らないため、
後続moduleが前提不足で停止する場合があります。bootstrap成功の証跡にはせず、構文はCI、完全な構築は
[使い捨てhost E2E](../e2e-validation.md)または対象hostへの実適用で確認します。

失敗時は、失敗 task、対象 host、終了 code、直前の変更を保存して作業を中断します。原因を修正してから同じ playbook を再実行します。

## 4. 冪等性確認

```bash
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

`play recap` が `failed=0` かつ `changed=0` であることを記録します。意図した定期更新などで変更が出る場合は、その task と理由を結果票へ残します。

## 5. 構築後確認

```bash
ansible-playbook -i inventory/staging.local.yml playbooks/verify.yml
ssh monitor-01 'systemctl --failed --no-pager'
ssh monitor-01 'docker compose -f /opt/server-monitor/compose.yaml ps'
ssh monitor-01 'ss -lntup'
ssh monitor-01 'ufw status verbose'
```

[試験仕様書](06-test-specification.md)の必須項目を実施し、スクリーンショットだけでなく再現コマンドと主要なテキストログを保存します。

実ホストの IP、route、DNS、待受 address、HTTP、UFW は [ネットワーク実機検証手順](09-network-validation-procedure.md)に従い、Docker 障害ラボとは別の結果票へ記録します。

## 6. 障害・復旧試験

1. D-1 の事前状態を確認します。
2. `scripts/drills/d1-process-down.sh` を実行します。
3. 検知時間、復旧時間、アラート状態、Grafana / Loki の表示を記録します。
4. [`labs/network-troubleshooting/run-drill.sh`](../../labs/network-troubleshooting/run-drill.sh) で二セグメントの通信障害を再現します。

## 7. ロールバック

構成変更が原因の場合は、[変更・ロールバック計画](08-change-rollback-plan.md)に従って変更前 commit の別 checkout から `playbooks/deploy.yml` を適用します。データ破損の場合は[復元ランブック](../roadmap/restore-from-snapshot.md)を使います。復旧後は `verify.yml` と影響範囲の試験を再実行します。

## 8. 作業終了

- 結果票、実行ログ、画面、費用（AWS 使用時）を保存
- 一時的な firewall 許可とテストデータを削除
- 未解決事項を Issue 化
- [引き渡しチェックリスト](07-handover-checklist.md)を確認

