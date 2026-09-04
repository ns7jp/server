# 変更・ロールバック計画兼記録票

> 💡 **初めて読む方へ**: この文書は設定を変更するとき、「失敗したらどう戻すか」を先に決めておく文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#08-変更ロールバック計画兼記録票)を参照してください。

## 1. 位置づけ

一般的な変更区分と PR 運用は [`docs/change-management.md`](../change-management.md)を正本とします。本書はこの構築案件（`SM-DHCP-001`）で「どの値からどの値へ変更し、どの条件で戻したか」を引き渡せる形で記録する案件固有の計画兼結果票です。

この原本の実施欄は初期状態ですべて `NOT RUN` / `NOT SET` です。[Linux版](../build-package/08-change-rollback-plan.md)には実測記録（使い捨てrunner上でのGit-modeロールバック）へのリンクがありますが、本書（DHCP版）には現時点で採録済みの実測記録が**1件もありません**。理由は[要件定義書](00-requirements.md)・[試験仕様書・結果票](06-test-specification.md)と同じで、`dhcp_server` roleは実装済みでローカルでの`ansible-lint --offline`（production profile）とAnsible構文チェックはPASSしていますが、対象ホストへの実適用そのものがまだ行われていないため、変更・ロールバックを実際に試す前提となる初回構築がまだ存在しないからです。

実作業では `docs/evidence/YYYY-MM-DD-change-<ID>.md` のような日付付きファイルへこの原本をコピーし、実際の値と出力を記録します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。原本である本書は直接上書きしません。

## 2. 変更票

| 項目 | 計画・実績 |
| --- | --- |
| Change ID / 関連 Issue | `NOT SET` |
| 対象環境・ホスト | `NOT SET`（想定は`dhcp-01`単体。冗長構成ではないため停止範囲は常に本ホストのみ） |
| 作業者 / 確認者 | `NOT SET` |
| 予定時間 / 実施時間 | `NOT SET` |
| 変更前 commit SHA | `NOT SET` |
| 変更後 commit SHA | `NOT SET` |
| 変更目的 | `NOT SET`（例: 動的プールの拡張、固定IP予約の追加、リース時間の変更など。4節参照） |
| 影響を受ける service / port / data | `NOT SET`（isc-dhcp-server、UDP 67、`/etc/dhcp/dhcpd.conf`、`/var/lib/dhcp/dhcpd.leases`のいずれかを記入） |
| 停止見込み | `NOT SET`（`dhcpd.conf`再配布時の`systemctl restart isc-dhcp-server`分。既存リースの有効性には影響しない） |
| 直前バックアップ ID | `NOT SET` |
| ロールバック判断期限 | `NOT SET` |
| 最終結果 | `NOT RUN` |

## 3. Go / No-Go 条件

次のどれかを満たさなければ実適用を開始しません。

- [ ] 対象ホスト、inventory、変更前後の commit SHA（コードそのものを変更する場合）を相互確認した
- [ ] 秘密値、公開 IP、アカウント ID が diff や採録ログへ出ないことを確認した（本パックは`ansible-vault`を使わないため、Linux版のような暗号化Vaultの取り扱いは不要。詳細は[パラメータシート](03-parameter-sheet.md)）
- [ ] `--check --diff` の差分を読み、意図しない`range`・`host`ブロックの削除や、UDP 67 の公開範囲変更がない
- [ ] `ansible-inventory --graph` と `ansible dhcp -m ping` が成功した
- [ ] 動的プールを変更する場合、新しい範囲が固定IP予約帯（`192.168.50.10`〜`.49`）・インフラ用予約帯（`.2`〜`.9`）と重ならないことを目視確認した。`dhcp_server` roleの`ansible.builtin.assert`は各予約の名前・MAC・IPの書式と一意性のみを検査し、プール範囲と予約帯の重複までは機械的に検査しないため（[詳細設計書](02-detailed-design.md)参照）
- [ ] 固定IP予約を追加する場合、追加するIPが動的プール（`.100`〜`.200`）の外側で、既存予約と重複しないことを確認した
- [ ] 変更対象に対応する単体試験（DUT-01構文検査、DUT-02構文チェック）が成功した
- [ ] 変更前に`dhcpd.conf`と`dhcpd.leases`のバックアップを取得し、取得時刻とバックアップ先を確認した
- [ ] 変更前 commit を別 checkout から再配備できる（役割・テンプレート・playbook自体を変更する場合）
- [ ] ロールバック判断者、判断期限、サービス停止許容時間が決まっている

確認コマンド例です。出力には秘密値・実IPを含めません。

```bash
BEFORE_SHA='replace-with-the-full-current-commit-sha'
AFTER_SHA='replace-with-the-full-candidate-commit-sha'
git rev-parse HEAD
git diff --stat "$BEFORE_SHA..$AFTER_SHA"
cd ansible
ansible-inventory -i inventory/staging.dhcp.local.yml --graph
ansible dhcp -i inventory/staging.dhcp.local.yml -m ping
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --check --diff
```

`BEFORE_SHA`/`AFTER_SHA`の差分確認は、`ansible/roles/dhcp_server/`や`ansible/playbooks/dhcp.yml`そのものを変更する場合に使います。4.1節のような、host_vars（`ansible/inventory/staging.dhcp.local.yml`、`.gitignore`対象）だけを書き換える一般的な変更では、この2行は該当なしとして構いません。

## 4. 変更手順

1. 変更開始時刻と、直前の`systemctl status isc-dhcp-server`・アクティブなリース件数を記録します。
2. 変更前に`dhcpd.conf`と`dhcpd.leases`をバックアップします（バックアップIDとして採録するタイムスタンプを控えます）。
3. host_vars（`ansible/inventory/staging.dhcp.local.yml`）を書き換える場合は、書き換え前に同ファイルの控えを取ります。role・テンプレート・playbook自体を変更する場合は、変更後commitを別checkoutへ展開します。
4. `--check --diff`で差分を確認してから、`playbooks/dhcp.yml`を適用します。
5. `dhcpd -t -cf /etc/dhcp/dhcpd.conf`（DUT-01相当）と、変更内容に応じた[試験仕様書](06-test-specification.md)の影響範囲（例: プール拡張ならDIT-02・DIT-04、固定予約追加ならDIT-03、リース時間変更ならDIT-05・DIT-08）を再実行します。
6. `systemctl --failed`、`journalctl -u isc-dhcp-server --since`、既存リースの継続を確認し、新規異常がないことを確かめます。
7. 監視時間を終えてから、継続またはロールバックを判定します。

```bash
sudo install -d -m 0750 /var/backups/dhcp
BACKUP_TS="$(date -u +%Y%m%dT%H%M%SZ)"
sudo cp -p /etc/dhcp/dhcpd.conf "/var/backups/dhcp/dhcpd.conf.${BACKUP_TS}"
sudo cp -p /var/lib/dhcp/dhcpd.leases "/var/backups/dhcp/dhcpd.leases.${BACKUP_TS}"
echo "backup id: ${BACKUP_TS}"

cd ansible
cp -p inventory/staging.dhcp.local.yml "inventory/staging.dhcp.local.yml.pre-change.${BACKUP_TS}"
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --check --diff
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a \
  '/usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf'
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a \
  'systemctl --failed --no-pager'
```

`inventory/staging.dhcp.local.yml.pre-change.${BACKUP_TS}`は`.gitignore`対象ディレクトリ内の一時ファイルです。ロールバックが不要になったら6節の手順を参照して確認のうえ削除します。

### 4.1 想定するDHCP固有の変更例

本パックで想定する変更は、いずれも`ansible/roles/dhcp_server/defaults/main.yml`の既定値を直接書き換えるのではなく、host_vars（`ansible/inventory/staging.dhcp.local.yml`）側で上書きする運用を基本とします。既定値そのものを変える場合は、[パラメータシート](03-parameter-sheet.md)・[04-network-ip-plan.md](04-network-ip-plan.md)との整合を取ったうえで別途PRレビューを経ます。

| 変更例 | 変更する Ansible 変数 | 適用前に必ず確認すること |
| --- | --- | --- |
| 動的プールの拡張 | `dhcp_server_range_end`（縮小・両端移動の場合は`dhcp_server_range_start`も） | 新しい範囲が固定IP予約帯（`.10`〜`.49`）・インフラ用予約帯（`.2`〜`.9`）と重ならないこと。将来拡張用の未使用帯（`.201`〜`.254`）へ拡張する場合も、他用途の予定がないか事前に確認すること |
| 固定IP予約の追加 | `dhcp_server_reservations`へ`name`/`mac`/`ip`の組を1件追加 | 追加するIPが動的プール（`.100`〜`.200`）の外側で、既存の予約と重複しないこと。MACアドレスの表記（コロン区切り）はroleの`assert`が書式を検査するが、値そのものが対象機器のMACと一致しているかは目視確認する |
| リース時間の変更 | `dhcp_server_default_lease_time` / `dhcp_server_max_lease_time` | `default_lease_time <= max_lease_time`はroleの`assert`が検査するが、値そのものが運用上妥当か（更新頻度、サービス停止時にクライアントへ与える影響時間）は目視で判断する。T1/T2は明示指定しない設計のため、変更後もクライアント側がRFC 2131の既定比率（目安50%/87.5%）で計算する |

```yaml
# ansible/inventory/staging.dhcp.local.yml（host_vars抜粋、編集例）
all:
  children:
    dhcp:
      hosts:
        dhcp-01:
          # 例1: 動的プールを .100〜.200 から .100〜.220 へ拡張
          dhcp_server_range_end: 192.168.50.220
          # 例2: プリンター1台を固定IP予約帯へ追加
          dhcp_server_reservations:
            - name: printer-01
              mac: "08:00:27:aa:bb:cc"
              ip: 192.168.50.20
          # 例3: リース時間を短縮（12時間→6時間、24時間→12時間）
          dhcp_server_default_lease_time: 21600
          dhcp_server_max_lease_time: 43200
```

3つの変更例は独立して適用できますが、同時に複数を変更する場合はGo/No-Go条件（3節）をそれぞれの変更ごとに満たしているかを個別に確認してください。1つの変更票にまとめて記録しても構いませんが、判定は変更内容ごとに分けて残します。

## 5. ロールバック開始条件

次のいずれかが発生し、判断期限までに安全に解消できない場合は変更を継続せず戻します。

- `dhcpd -t -cf /etc/dhcp/dhcpd.conf`（DUT-01相当）が失敗する
- `dhcp.yml`の適用が途中で失敗し、対象ホストの`dhcpd.conf`の状態を確定できない
- 変更後、DORA実測（DIT-02相当）でクライアントが新しい範囲内のIPを取得できない、またはOFFERが得られない
- 固定IP予約を追加したにもかかわらず、登録済みMACのクライアントが期待した予約IPを取得しない（DIT-03相当）
- 変更後、動的プールと固定IP予約帯・インフラ用予約帯が重複していることが判明した
- UDP 67 の待受・UFW許可範囲が意図せず変化した（DST-01相当）
- 既存クライアントのリースが変更直後に失われる、または再起動後にリース内容が保持されない（DIT-06相当）
- 新しい重大アラート、`journalctl -u isc-dhcp-server`の継続的なerror logが発生する
- 実測した復旧見込みが許容停止時間を超える

## 6. コード・設定のロールバック

`dhcp_server` roleは、`ansible.builtin.template`の`validate`パラメータで`dhcpd -t -cf %s`を実行し、構文エラーのある設定は反映前に拒否します。そのためロールバックの主経路は、Windows/AD版のようなVMスナップショット優先ではなく、[Linux版パック](../build-package/08-change-rollback-plan.md)と同じく**設定を戻して`dhcp.yml`を再適用する**ことです。dhcpd.confを直接手で書き換えて戻すことは、緊急時の代替手段（6.2節）に限ります。

### 6.1 Ansible変数を戻して再適用する（優先）

4.1節のようなhost_vars（`ansible/inventory/staging.dhcp.local.yml`）の書き換えだけで完結する変更は、4節で取った控えファイルを戻すだけです。

```bash
set -euo pipefail
cd ansible
BACKUP_TS='replace-with-the-backup-timestamp-recorded-in-step-4'
PRE_CHANGE_INVENTORY="inventory/staging.dhcp.local.yml.pre-change.${BACKUP_TS}"
test -f "$PRE_CHANGE_INVENTORY"
cp -p inventory/staging.dhcp.local.yml \
  "inventory/staging.dhcp.local.yml.rollback-failed.$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$PRE_CHANGE_INVENTORY" inventory/staging.dhcp.local.yml
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --check --diff
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a \
  '/usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf'
ansible dhcp -i inventory/staging.dhcp.local.yml -b -a \
  'systemctl is-active isc-dhcp-server'
```

`ansible/roles/dhcp_server/`のtasks・templates・defaultsや`ansible/playbooks/dhcp.yml`そのものを変更した場合は、host_vars を戻すだけでは不十分です。この場合は変更前commitを別checkoutに展開してから再配備します。作業中のcheckoutを`git reset --hard`で戻しません。

```bash
set -euo pipefail
ROLLBACK_SHA='replace-with-the-full-last-known-good-commit-sha'
ACTIVE_INVENTORY='/absolute/path/to/ansible/inventory/staging.dhcp.local.yml'
REPO_ROOT="$(git rev-parse --show-toplevel)"
ROLLBACK_WORKTREE="$(dirname "$REPO_ROOT")/server-monitor-dhcp-rollback"
[[ "$ROLLBACK_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git -C "$REPO_ROOT" rev-parse --verify "${ROLLBACK_SHA}^{commit}")" = "$ROLLBACK_SHA"
test -f "$ACTIVE_INVENTORY"
test ! -e "$ROLLBACK_WORKTREE"
test ! -L "$ROLLBACK_WORKTREE"
git -C "$REPO_ROOT" worktree add --detach "$ROLLBACK_WORKTREE" "$ROLLBACK_SHA"
install -m 600 "$ACTIVE_INVENTORY" \
  "$ROLLBACK_WORKTREE/ansible/inventory/rollback.dhcp.local.yml"
cd "$ROLLBACK_WORKTREE/ansible"
ansible-playbook -i inventory/rollback.dhcp.local.yml \
  playbooks/dhcp.yml --check --diff
ansible-playbook -i inventory/rollback.dhcp.local.yml \
  playbooks/dhcp.yml
ansible dhcp -i inventory/rollback.dhcp.local.yml -b -a \
  '/usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf'
ansible dhcp -i inventory/rollback.dhcp.local.yml -b -a \
  'systemctl is-active isc-dhcp-server'
```

本パックは秘密値を扱わないため（[パラメータシート](03-parameter-sheet.md)参照）、Linux版のような`ansible-vault`のVaultファイル・パスワードファイルの受け渡しは不要です。この点がLinux版の同種手順との主な違いです。

両方の経路とも、適用後に`/usr/sbin/dhcpd -t -cf /etc/dhcp/dhcpd.conf`が成功し、`isc-dhcp-server`が`active`であることを確認してから完了とします。不要になった一時checkout・控えファイルの削除は、証跡を保存し対象pathを確認した後に別作業として行います。

### 6.2 `dhcpd.conf`をバックアップから直接復元する（緊急時の代替手段）

Ansible経由の再適用が判断期限までに間に合わない場合、または管理端末から対象ホストへAnsible実行そのものが到達できない場合に限り、対象ホストへ直接SSHして4節で取ったバックアップから`dhcpd.conf`のみを復元します。**必ず`dhcpd -t`で構文を確認してからサービスを再起動してください。**先に再起動してしまうと、構文エラーのある設定のままサービスが停止した状態になりかねません。

```bash
set -euo pipefail
BACKUP_TS='replace-with-the-backup-timestamp-recorded-in-step-4'
BACKUP_DIR='/var/backups/dhcp'
sudo test -f "${BACKUP_DIR}/dhcpd.conf.${BACKUP_TS}"
sudo cp -p /etc/dhcp/dhcpd.conf \
  "/etc/dhcp/dhcpd.conf.rollback-failed.$(date -u +%Y%m%dT%H%M%SZ)"
sudo cp -p "${BACKUP_DIR}/dhcpd.conf.${BACKUP_TS}" /etc/dhcp/dhcpd.conf
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
sudo systemctl restart isc-dhcp-server
systemctl is-active isc-dhcp-server
sudo journalctl -u isc-dhcp-server --since "5 minutes ago" --no-pager
```

`dhcpd -t`が失敗した場合は、絶対に`systemctl restart`を実行せず、直前に退避した`dhcpd.conf.rollback-failed.<timestamp>`と復元元のバックアップの両方を保存したうえで調査します。この経路は`dhcpd.conf`のみを対象とし、`dhcpd.leases`（リースDB）には触れません。リースDB自体の復元が必要な場合は7節に従います。この手順を実施した対象ホストのAnsible側host_vars（`staging.dhcp.local.yml`）も、後日忘れずに同じ値へ揃えてください。揃えないまま次回`dhcp.yml`を適用すると、手動復元した内容がAnsible側の値で再び上書きされます。

## 7. データ（リースDB）のロールバック

設定を戻すだけでは解消できない、リースDB（`/var/lib/dhcp/dhcpd.leases`）自体の破損・不整合が疑われる場合に限り、この節の手順を使います。これはNFR-09・DIT-11（バックアップ・復元、RTOの記録）に対応する手順で、[構築手順書](05-build-procedure.md)の7節はこの節を正本として参照しています。

- 破損が疑われる`dhcpd.leases`を直ちに削除せず、調査用に`/var/backups/dhcp/`へ日付付きで退避してから復元作業に入ります。
- 復元元バックアップの取得時刻（4節で記録したバックアップID）を確認します。
- `isc-dhcp-server`パッケージは、`dhcpd.leases`が存在しない状態でも初回起動時に空のリースDBを自動生成します。これは動作としては成立しますが、既存クライアントの割当履歴を失うため、履歴を保持したい場合は自動生成に任せず、必ずバックアップから復元してください。
- 復元手順は次のとおりです。`systemctl stop`で対象サービスを止めてから`dhcpd.leases`を戻し、`dhcpd -t`で`dhcpd.conf`の構文を確認したうえで`systemctl start`し、クライアントVMからDORAを再実施して新規リースが正常に払い出されることを確認します（DIT-11）。

```bash
set -euo pipefail
BACKUP_TS='replace-with-the-backup-timestamp-recorded-in-step-4'
BACKUP_DIR='/var/backups/dhcp'
sudo test -f "${BACKUP_DIR}/dhcpd.leases.${BACKUP_TS}"
sudo systemctl stop isc-dhcp-server
sudo cp -p /var/lib/dhcp/dhcpd.leases \
  "/var/backups/dhcp/dhcpd.leases.suspect.$(date -u +%Y%m%dT%H%M%SZ)"
sudo cp -p "${BACKUP_DIR}/dhcpd.leases.${BACKUP_TS}" /var/lib/dhcp/dhcpd.leases
sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
sudo systemctl start isc-dhcp-server
systemctl is-active isc-dhcp-server
```

- バックアップ取得完了時刻から、復元後にクライアントVMで新規リースの正常払い出しを確認できた時刻までをRTOとして8節へ記録します。
- 単一サーバー構成のため、復元中は`dhcp-01`が完全にDHCPペイロードへ応答できない時間が生じます。この停止時間を許容できるかどうかは、変更票（2節）の「停止見込み」欄で事前に合意しておきます。
- D-2 実測証跡がない間は、この手順を「検証済み」とは記載しません。DIT-11の実測が完了するまで、本節の手順は設計どおりに動く見込みであって、実機で確認された事実ではありません。

## 8. 実施結果

| 時刻 | 操作 / 判断 | コマンドまたは証跡 | 結果 |
| --- | --- | --- | --- |
| `NOT RUN` | 変更前確認・バックアップ取得 | — | NOT RUN |
| `NOT RUN` | 変更適用 | — | NOT RUN |
| `NOT RUN` | 配備後試験（DUT-01・影響範囲のDIT） | — | NOT RUN |
| `NOT RUN` | 継続 / ロールバック判断 | — | NOT RUN |
| `NOT RUN` | ロールバック（必要時） | — | NOT RUN |
| `NOT RUN` | RTO（データのロールバックを実施した場合のみ） | — | NOT RUN |

## 9. 終了条件

- [ ] 変更後またはロールバック後の`dhcpd.conf`の内容・commit SHA（コードを変更した場合）と、稼働状態（`systemctl is-active isc-dhcp-server`）が一致する
- [ ] `dhcpd -t -cf /etc/dhcp/dhcpd.conf`（DUT-01相当）と、影響範囲の再試験が `PASS`
- [ ] 変更後、動的プール・固定IP予約帯・インフラ用予約帯が重複していないことを再確認した
- [ ] 変更前後の時刻、実出力、判断理由を evidence（`docs/evidence/YYYY-MM-DD-change-<ID>.md`）へ保存した
- [ ] 残存リスク、暫定対応、恒久対応の Issue を記録した
- [ ] 一時的な控えファイル（`*.pre-change.*`、`*.rollback-failed.*`）、`/var/backups/dhcp/`配下の調査用退避ファイルの要否を判断し、不要なものは削除した
- [ ] 手動でdhcpd.confを復元した場合（6.2節）、Ansible側host_vars（`staging.dhcp.local.yml`）を同じ値へ揃えた
