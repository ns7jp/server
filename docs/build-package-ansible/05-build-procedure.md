# 構築手順書

> 💡 **初めて読む方へ**: この手順は上から順にコマンドを実行していく実務形式です。各ステップの「なぜ」を読み飛ばさないでください。特に手順3（適用前確認）と手順6（冪等性確認）は、Ansibleの設計を理解するうえで最も重要な部分です。

対象は`ans-01`（Ubuntu Server 24.04 LTS、フェーズ1）です。フェーズ2（`ans-el9-01`、AlmaLinux/Rocky 9）の手順は手順9にまとめています。

## 0. 作業前確認

- [ ] 対象VMが起動しており、管理端末からSSH到達性があること（`ssh <user>@<IP>`が成功する）
- [ ] 対象VMのOSがUbuntu Server 24.04 LTS（または22.04 LTS）であること
- [ ] スナップショットまたは再作成手順があり、失敗時に戻せること
- [ ] 管理者用のSSH鍵ペアを用意済みで、公開鍵の文字列を控えていること
- [ ] 対象commit SHAを控えていること（`git rev-parse HEAD`）

## 1. Ansible controllerを準備する

```bash
pipx install ansible-core
pipx inject ansible-core ansible-lint
cd server/ansible
ansible-galaxy collection install -r requirements.yml
```

`common` / `docker`両roleは`community.general`と`ansible.posix`のモジュールを使います（`requirements.yml`参照）。controller側にcollectionが無いと、`--syntax-check`の時点でモジュール解決に失敗します。

> **この検証環境での制約**: AI支援セッションの作業環境は`galaxy.ansible.com`へのネットワークアクセスがポリシーで遮断されており、`ansible-galaxy collection install`を実行できませんでした。代わりに`pip install ansible`（`ansible-core`ではなくcollection同梱のフル版）を使うことで、`galaxy.ansible.com`に頼らず`community.general`等を取得でき、`ansible-lint --offline`（0 failure、production profile）と`--syntax-check`の両方をその環境で確認できました。ただしこれはCI本来の実行環境とは異なるため、GitHub Actions（`.github/workflows/ansible-check.yml`）側の実行結果も別途確認してください。この境界は[試験仕様書](06-test-specification.md)のAFUT-01/02に記録しています。
>
> **実VMでの実行**: 2026-09-04に、Windows上のHyper-V VM（Ubuntu 24.04.4 LTS）とWSL2上のAnsible controller（`pipx install ansible-core`）を使い、本手順を通しで実施しました。結果は[構築・試験結果票](../evidence/2026-09-04-ansible-foundation-build.md)を参照してください。Hyper-V Quick Createのgallery imageは`/etc/netplan/`設定が無い状態で起動したため、手動でnetplan設定を追加する手順が必要でした（案件パックの欠陥ではなくVMイメージ側の初期状態です）。

## 2. inventoryを準備する

```bash
cd server/ansible
cp inventory/foundation.local.yml.example inventory/foundation.local.yml
$EDITOR inventory/foundation.local.yml
# 対象IP、SSH user、server_monitor_admin_user、
# server_monitor_admin_authorized_keys（管理者の公開鍵）を実値へ置換する
git check-ignore inventory/foundation.local.yml
```

`foundation.local.yml`は`ansible/.gitignore`の`inventory/*.local.yml`により追跡対象外です。最後の`git check-ignore`は、除外設定が効いていることをコミット前に確認するためのコマンドで、対象ファイル名が1行表示されれば正しく無視されています。

## 3. 適用前確認（`--check --diff`）

```bash
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --check --diff
```

**このコマンドは何を確認していて、何を確認していないか**を区別してください。

| 確認できること | 確認できないこと |
| --- | --- |
| 変数が解決できるか（未定義変数エラーが出ないか） | fresh hostでのパッケージ導入が実際に成功するか |
| `assert`ガード（未対応OS、危険なinstall_dirなど）が正しく発火するか | Dockerサービスの起動、handlerの実行 |
| 各moduleが「今の状態と望む状態の差分」をどう予測するか | 予測どおりに本適用が成功する保証 |

詳しくは[詳細設計書「check modeの限界」](02-detailed-design.md#check-modeの限界)を参照してください。ここで`UNREACHABLE`や`assert`失敗が出た場合は、本適用へ進まずinventoryを見直します。

## 4. 本適用

```bash
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml
```

play recapで`failed=0`になることを確認します。`unreachable`が出た場合はSSH到達性・`ansible_user`・鍵の指定を見直してください。

## 5. 適用結果を確認する

対象ホストへSSHし、次のコマンドで結果を確認します（`sudo`が必要なものを含みます）。

```bash
# OS共通
timedatectl                              # timezoneがAsia/Tokyoであること
sudo systemctl is-active chrony || sudo systemctl is-active chronyd
id svc-baseline                          # dockerグループが含まれていないこと
ls -ld /opt/ansible-foundation           # 所有者・パーミッションの確認

# SSH
sudo sshd -T | grep -i passwordauthentication   # no であること
sudo sshd -T | grep -i permitrootlogin          # no または prohibit-password であること

# firewall（Ubuntu）
sudo ufw status verbose                  # 22/tcp（LIMIT）以外に許可が無いこと

# firewall（RHEL系）
sudo firewall-cmd --list-all             # servicesにsshのみ、rich ruleでrate limit

# Docker
docker version
docker compose version
sudo systemctl is-active docker
```

## 6. 冪等性の確認

2回連続で同じplaybookを流し、2回目の`changed=0`を確認します。

```bash
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml | tail -5
# play recap で changed=0 / failed=0 が出ること
```

`changed=0`にならない場合は、[詳細設計書「冪等性の実装パターン」](02-detailed-design.md#冪等性の実装パターン)を参照し、どのタスクが毎回差分を出しているかを`-vv`付きで特定してください。

## 7. ローカルでのMolecule検証（開発者向け・任意）

対象ホストを使わずに、role単体の収束・冪等性をコンテナで検証する場合は次を実行します。

```bash
pip install 'ansible' 'molecule' 'molecule-plugins[docker]' 'docker'
cd ansible/roles/common
molecule test          # default（Ubuntu）scenario
molecule test -s el9   # el9（Rocky）scenario
cd ../docker
molecule test
molecule test -s el9
```

`molecule test`は`create → converge → idempotence → verify → destroy`を通しで実行します。`idempotence`ステップで失敗した場合は、対象ホストへ本適用する前に修正できます。

## 8. 後片付け

検証専用ホストの場合は、証跡を保存したのちに破棄して構いません。永続ホストとして引き渡す場合は、[10-host-bringup-and-acceptance.md](10-host-bringup-and-acceptance.md)へ進みます。

## 9. フェーズ2: AlmaLinux/Rocky 9への適用

手順自体は手順2〜6と同一です。`inventory/foundation.local.yml.example`の`ans-el9-01`をコメントアウトから外し、SSHユーザーを対象OSの既定ユーザー（例: `rocky`）へ変更します。

```bash
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --limit ans-el9-01 --check --diff
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --limit ans-el9-01
```

2026-09-04にAlmaLinux 9.7実機（`ans-el9-01`）へ適用し、構築・冪等性・SELinux enforcingを実測`PASS`しました（[結果票](../evidence/2026-09-04-ansible-foundation-el9-build.md)）。実行して初めて、`container_manage_cgroup` SELinux booleanが`docker` role適用前（`container-selinux`未導入時点）だと設定できない欠陥が見つかり、修正済みです（[欠陥台帳](../evidence/defects-found.md)#31）。

ただしこの実測に使ったVMは以前の用途からの再利用環境（Zabbixサーバー等が既に稼働）だったため、「まっさらな新規ホストへの構築」「最小公開（SSHのみ）」の証跡としては、専用の新規VMでの再実施が必要です。role自体の動作・冪等性・OS横断対応の実証としては完了しています。
