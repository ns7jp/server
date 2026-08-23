# 変更・ロールバック計画兼記録票

## 1. 位置づけ

一般的な変更区分と PR 運用は [`docs/change-management.md`](../change-management.md)を正本とします。本書はこの構築案件で「どの版からどの版へ変更し、どの条件で戻したか」を引き渡せる形で記録する案件固有の計画兼結果票です。

この原本の実施欄は初期状態では `NOT RUN` です。実作業では `docs/evidence/YYYY-MM-DD-change-<ID>.md` へコピーし、実際の値と出力を記録します。

最初の実測記録として、使い捨てUbuntu runner上のGit-mode変更・rollbackを
[2026-08-23の結果票](../evidence/2026-08-23-change-CI-GIT-ROLLBACK.md)へ採録しました。
以下の空欄は次の変更で再利用する原本であり、そのCI実測を`NOT RUN`へ戻すものではありません。
引き渡し対象の永続hostでの変更・rollbackは、現在も`NOT RUN`です。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET` |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前 commit SHA | `NOT SET` |
| 変更後 commit SHA | `NOT SET` |
| 変更目的 | `NOT SET` |
| 影響を受ける service / port / data | `NOT SET` |
| 停止見込み | `NOT SET` |
| 直前バックアップ ID | `NOT SET` |
| ロールバック判断期限 | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go / No-Go 条件

次のどれかを満たさなければ実適用を開始しません。

- [ ] 対象ホスト、inventory、変更前後の commit SHA を相互確認した
- [ ] 秘密値、公開 IP、アカウント ID が diff や採録ログへ出ないことを確認した
- [ ] `--check --diff` の差分を読み、意図しない削除・公開 port 変更がない
- [ ] `ansible-inventory --graph` と `ansible all -m ping` が成功した
- [ ] 変更対象に対応する単体試験が成功した
- [ ] データ変更を伴う場合、直前バックアップの作成時刻とアーカイブ一覧を確認した
- [ ] 変更前 commit を別 checkout から再配備できる
- [ ] ロールバック判断者、判断期限、サービス停止許容時間が決まっている

確認コマンド例です。出力には秘密値を含めません。

```bash
BEFORE_SHA='replace-with-the-full-current-commit-sha'
AFTER_SHA='replace-with-the-full-candidate-commit-sha'
git rev-parse HEAD
git diff --stat "$BEFORE_SHA..$AFTER_SHA"
cd ansible
ansible-inventory -i inventory/staging.local.yml --graph
ansible all -i inventory/staging.local.yml -m ping
ansible-playbook -i inventory/staging.local.yml playbooks/deploy.yml --check --diff
```

## 4. 変更手順

1. 変更開始時刻と監視の事前状態を記録します。
2. データ変更を伴う場合は `sudo systemctl start server-monitor-backup.service` を対象ホストで実行し、終了状態と生成先を記録します。
3. 変更後 commit を checkout した管理端末から `playbooks/deploy.yml` を適用します。
4. `playbooks/verify.yml` と [試験仕様書](06-test-specification.md)の影響範囲を実行します。
5. アラート、`systemctl --failed`、Compose 状態、主要ログに新規異常がないことを確認します。
6. 監視時間を終えてから、継続またはロールバックを判定します。

```bash
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/deploy.yml
ansible-playbook -i inventory/staging.local.yml playbooks/verify.yml
ansible monitor -i inventory/staging.local.yml -b -a \
  'docker compose -f /opt/server-monitor/compose.yaml ps'
ansible monitor -i inventory/staging.local.yml -b -a \
  'systemctl --failed --no-pager'
```

## 5. ロールバック開始条件

次のいずれかが発生し、判断期限までに安全に解消できない場合は変更を継続せず戻します。

- `verify.yml` が失敗する
- `/healthz`、Prometheus、Grafana、Loki のいずれかが規定時間内に ready にならない
- UI / metrics の認証が回避できる、または管理 UI が loopback 以外へ公開される
- 新しい重大アラート、データ欠損、継続的な error log が発生する
- Ansible 適用が途中で失敗し、実ホストの状態を確定できない
- 実測した復旧見込みが許容停止時間を超える

## 6. コード・設定のロールバック

作業中の checkout を `git reset --hard` で戻しません。変更前 commit を別の一時 checkout に展開し、対象版が明確な状態で再配備します。
接続先inventoryはrollback worktree内のGit管理外fileへcopyし、秘密値は既存の暗号化Vaultを
absolute pathで参照します。sourceは`git` modeと旧40桁SHAをCLIで上書きし、local inventory変更を
releaseへ混ぜません。旧SHAがremote repositoryに存在し、その版が`git` modeをサポートすることを
Go条件で確認します。

```bash
set -euo pipefail
ROLLBACK_SHA='replace-with-the-full-last-known-good-commit-sha'
ACTIVE_INVENTORY='/absolute/path/to/ansible/inventory/staging.local.yml'
ACTIVE_VAULT='/absolute/path/to/ansible/inventory/group_vars/monitor/vault.yml'
VAULT_PASSWORD_FILE='/absolute/path/to/ansible/.vault_pass'
REPO_ROOT="$(git rev-parse --show-toplevel)"
ROLLBACK_WORKTREE="$(dirname "$REPO_ROOT")/server-monitor-rollback"
[[ "$ROLLBACK_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git -C "$REPO_ROOT" rev-parse --verify "${ROLLBACK_SHA}^{commit}")" = "$ROLLBACK_SHA"
test -f "$ACTIVE_INVENTORY"
test -f "$ACTIVE_VAULT"
test -f "$VAULT_PASSWORD_FILE"
test ! -e "$ROLLBACK_WORKTREE"
test ! -L "$ROLLBACK_WORKTREE"
git -C "$REPO_ROOT" worktree add --detach "$ROLLBACK_WORKTREE" "$ROLLBACK_SHA"
install -m 600 "$ACTIVE_INVENTORY" \
  "$ROLLBACK_WORKTREE/ansible/inventory/rollback.local.yml"
cd "$ROLLBACK_WORKTREE/ansible"
ansible-playbook -i inventory/rollback.local.yml \
  --vault-password-file "$VAULT_PASSWORD_FILE" -e "@$ACTIVE_VAULT" \
  -e server_monitor_source_mode=git -e "server_monitor_git_version=$ROLLBACK_SHA" \
  playbooks/deploy.yml --check --diff
ansible-playbook -i inventory/rollback.local.yml \
  --vault-password-file "$VAULT_PASSWORD_FILE" -e "@$ACTIVE_VAULT" \
  -e server_monitor_source_mode=git -e "server_monitor_git_version=$ROLLBACK_SHA" \
  playbooks/deploy.yml
ansible-playbook -i inventory/rollback.local.yml \
  --vault-password-file "$VAULT_PASSWORD_FILE" -e "@$ACTIVE_VAULT" \
  playbooks/verify.yml
ansible monitor -i inventory/rollback.local.yml -b -a \
  'cat /opt/server-monitor/.server-monitor-deploy-revision'
```

最後のrevision markerが`ROLLBACK_SHA`と一致することを記録します。ロールバック後も、認証、
待受 address、監視 targets、ログ取り込みを再試験します。不要になった一時 checkoutの削除は、
証跡を保存し対象pathを確認した後に別作業として行います。

## 7. データのロールバック

設定を戻すだけではデータ破損を解消できない場合に限り、[バックアップ・復旧手順](../backup-restore.md)と[スナップショット復元ランブック](../roadmap/restore-from-snapshot.md)を使用します。

- 破損した volume を直ちに削除せず、調査用に識別・隔離します。
- 復元元アーカイブの日時、checksum、RPO を記録します。
- 別 volume へ復元して内容を確認してから切り替えます。
- 秘密値はバックアップアーカイブではなく、承認された秘密管理先から復元します。
- D-2 実測証跡がない間は、ホスト障害からの復元を「検証済み」と記載しません。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認 | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 配備後試験 | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック（必要時） | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の commit SHA と稼働状態が一致する
- [ ] 必須 smoke test と影響範囲の再試験が `PASS`
- [ ] 変更前後の時刻、実出力、判断理由を evidence へ保存した
- [ ] 残存リスク、暫定対応、恒久対応の Issue を記録した
- [ ] 一時的な FW 許可、試験データ、保守モードを解除した
