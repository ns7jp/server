# Ansible による構築・配備手順

このリポジトリの正規の配備手順は **Ansible** に統一されている。旧 [構築・配備手順](deployment.md) はリファレンスとして残しているが、新規ホストへの適用には本文書を使う。

## 1. ディレクトリ

```text
ansible/
├── ansible.cfg
├── requirements.yml
├── inventory/
│   ├── staging.yml
│   ├── production.yml
│   ├── group_vars/
│   │   ├── all/main.yml
│   │   └── monitor/
│   │       ├── main.yml
│   │       └── vault.yml.example
│   └── host_vars/
│       └── monitor-01.yml
├── playbooks/
│   ├── site.yml         # Ubuntu hostを一括構築する完全プレイブック
│   ├── bootstrap.yml    # 新規ホストの OS 初期化のみ
│   ├── foundation.yml   # OS + コンテナランタイムの共通基盤のみ（common + docker）
│   ├── deploy.yml       # アプリと監視設定だけを更新
│   └── verify.yml       # 配備後の健全性検証
└── roles/
    ├── common/      # OS 共通設定（timezone、UFW、SSH、unattended-upgrades）
    ├── docker/      # Docker Engine + Compose plugin + daemon.json
    ├── nginx/       # ホスト側の TLS 準備（Nginx 本体は compose 内）
    ├── monitoring/  # app が配備した Prometheus / Loki / Alertmanager 設定の構文検証
    ├── app/         # アプリ同期、秘密値・環境別設定の生成、`docker compose up -d`
    └── backup/      # systemd timer で日次バックアップ
```

## 2. 前提

- 対象ホストは Ubuntu 22.04 LTS（Jammy）または 24.04 LTS（Noble）
- ローカルから対象ホストへ鍵認証 SSH 可能（`ansible_user` は sudo 権限を持つこと）
- Ansible controller側にPython 3.10+、Git、rsync、tar（`pipx`推奨）

```bash
pipx install ansible-core
pipx inject ansible-core ansible-lint
```

## 3. 初期化

リポジトリ直下から、Ansible 関連の collection を取得する。

```bash
cd server-monitor/ansible
ansible-galaxy collection install -r requirements.yml
```

機密値のテンプレートを編集する。`vault.yml` 自体は暗号化後も `.gitignore` で除外し、リポジトリにはコミットしない。

```bash
cd inventory/group_vars/monitor
umask 077
cp vault.yml.example vault.yml
$EDITOR vault.yml   # 3 つの秘密値を入れる
openssl rand -base64 48 > ../../../.vault_pass
chmod 600 ../../../.vault_pass
ansible-vault encrypt vault.yml --vault-password-file ../../../.vault_pass
```

`.vault_pass` はファイル単位の Vault パスワード。CI に渡す場合は GitHub Secrets に格納し、`ansible-playbook --vault-password-file <path>` で読み込ませる。

Vault 原本と `.vault_pass` の権限は所有者だけに制限する。一方、app role が `/opt/server-monitor/deploy/secrets/*.txt` へレンダリングする Compose secrets は `0644` とする。Compose の file-backed secret は host mode を維持し、Grafana など別 UID の非 root container が読むためである。host 側は親 directory を `0700` にして、他 user の path traversal を防ぐ。

## 4. インベントリ

tracked templateを直接編集せず、実host用は`*.local.yml`へコピーしてGit管理外で保持します。
stagingは`inventory/staging.local.yml.example`、productionは`inventory/production.yml`を元にし、
対象IP、SSH user、FQDNなどを編集します。local inventoryは`ansible/.gitignore`対象です。

| 環境 | inventory ファイル | 既定の差分 |
| --- | --- | --- |
| ラボ / staging | `inventory/staging.local.yml` | `nginx_letsencrypt_enabled: false`、自己署名証明書、UFWでSSH 22をrate limit |
| production | `inventory/production.local.yml` | `nginx_letsencrypt_enabled: true`、本番 FQDN。上流FW / VPNまたはsource指定ruleの設計が別途必要 |

stagingを構築する場合:

```bash
cd ansible
cp inventory/staging.local.yml.example inventory/staging.local.yml
$EDITOR inventory/staging.local.yml
git check-ignore inventory/staging.local.yml .vault_pass \
  inventory/group_vars/monitor/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"
```

productionを構築する場合（上のstaging blockの代わりに実行）:

```bash
cd ansible
cp inventory/production.yml inventory/production.local.yml
$EDITOR inventory/production.local.yml
git check-ignore inventory/production.local.yml .vault_pass \
  inventory/group_vars/monitor/vault.yml
export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"
```

### 配備するsourceを固定する

`directory` modeは、Ansible controller上のcleanなGit checkoutから指定SHAの
`git archive`を一時展開し、Git追跡fileだけを同期します。未commit・未追跡のfileがある場合は
操作ミスを避けるため適用前に停止し、ignoredのTerraform credential/stateやcacheはarchiveへ
入りません。Git submoduleはarchiveからcontentが欠落するため、gitlinkを検出した時点で明示的に
停止します。archiveは`tar.umask=0022`でgroup書き込みを許さないmodeに正規化し、同期時は
checksumでも内容を照合して、配備先に残った旧managed fileを削除します。host側で生成する`.env`、
`.artifacts`、secret、TLS鍵、Alertmanager設定などだけを明示的に保持します。配備後のSHAは
Compose reconciliationと通知済みhandlerまで成功した後、SHAを
`/opt/server-monitor/.server-monitor-deploy-revision`に改行付きで記録します。

実host用のignored local inventoryでは`git` modeを使い、branch名や`main`ではなく
40桁commit SHAを指定します。これによりcontrollerのinventory変更をtarget releaseへ混入させません。
Ansible controllerの一時directoryへそのSHAをfetchし、取得結果が指定値と一致することをassertして
`git archive`を作ります。その後はdirectory modeと同じtracked-release syncを使うため、対象hostが
非emptyでも配備でき、targetに`.git`やignored credential/stateを残しません。`.env`、`.artifacts`、
secret、TLS鍵、Alertmanager設定、revision markerだけをroot-relative ruleで保持します。
保持した`deploy/secrets/*.txt`は、現在の`app_secrets`と有効なSlack overlayだけをallowlistとして
再照合し、設定から外れたsecretを残しません。

```yaml
server_monitor_source_mode: git
server_monitor_git_version: "replace-with-40-character-commit-sha"
```

`server_monitor_install_dir`は`/opt`または`/srv`配下の専用directoryだけを受け付けます。
`/`などの危険な値、配下のTLS・deploy・secret pathの上書き、symlinkによるtree外へのredirectは
各roleのdirectory作成やfile生成より前に拒否します。`app_secrets`のnameは重複しない安全な
`.txt` basenameだけを許可し、Slack用filenameは専用設定に予約します。

## 5. Ubuntu hostを一括構築

```bash
cd ansible
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
```

`--check --diff`は変数・path/account guard、controller側release取得、各moduleが示す差分を
確認するbest-effort preflightです。fresh hostではrsyncやDockerを実際には導入せず、後続moduleが
前提binary不足で停止する場合もあるため、bootstrap成功の証跡にはしません。Compose操作、handler、
endpointのruntime verifyもcheck mode中は明示的にskipします。構文はCIのsyntax-check、完全な
構築は使い捨てhost E2Eで確認します。実適用が成功した場合だけ、
`site.yml`末尾の`verify.yml`が`/healthz`、Prometheus `/-/ready`、Loki `/ready`、
Grafana `/api/health`、`/metrics`の認証可否を順に確認します。

2026-08-22のhost全体E2Eは、Dockerが事前導入された使い捨てUbuntu 24.04 runnerで
実施しました。Docker roleの設定収束は確認済みですが、Docker未導入の最小OSからのpackage導入は
まだ実測していません。対象環境と結果の境界は[日付付き証跡](evidence/2026-08-22-full-stack-e2e.md)を参照してください。

## 6. 冪等性の確認

2 回連続で同じ playbook を流し、2 回目の `changed=0` を確認する。

```bash
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml
ansible-playbook -i inventory/staging.local.yml playbooks/site.yml | tail -5
# play recap で changed=0 / failed=0 が出ること
```

冪等性が崩れた場合は Molecule の `idempotence` ステップでも検出される（[ローカル検証](#9-ローカル検証molecule) 参照）。

手元に専用VMがない場合は [Full-stack Ansible E2E](e2e-validation.md)をActionsから
実行できる。使い捨てUbuntu 24.04 runnerへ同じ`site.yml`を2回適用し、2回目の
`changed=0`を文字列ではなくworkflowの終了条件として検査する。runtime、network、
障害復旧、restoreのraw logも同じartifactへ保存する。

## 7. アプリと監視設定だけを更新

OS の再設定を含まないため、運用中のホストへの差分適用は短時間で完了する。

```bash
ansible-playbook -i inventory/staging.local.yml playbooks/deploy.yml
```

実装手順は次のとおり。

1. controllerでGit追跡fileだけのrelease archiveを作り、旧managed driftを削除しつつtargetへ同期（host生成fileだけ保持）
2. Vault から秘密値を取り出して `deploy/secrets/*.txt` を再生成
3. 環境別 Alertmanager 設定を追跡対象外の `alertmanager.ansible.yml` に生成
4. `compose.yaml` と `compose.ansible.yaml` を重ねて `docker compose up -d --build --pull missing` で適用
5. `verify.yml` を別途実行して健全性を確認

## 8. バックアップ

`backup` ロールが `server-monitor-backup.timer`（systemd）を導入し、既定で **毎日 03:30（ホストの timezone。標準構成では Asia/Tokyo）** に Prometheus / Grafana / Loki の Docker volume をスナップショットする。保持期間は 14 日。

```bash
systemctl list-timers server-monitor-backup.timer
journalctl -u server-monitor-backup.service --since today
ls -lah /var/backups/server-monitor
```

`backup_enabled: false` で無効化できる。リテンションとスケジュールは `inventory/group_vars/monitor/main.yml` で変更する。
backup先は`/var/backups`または`/srv/backups`配下の専用・非symlink directory、retentionは
1〜3650日、project/volume/service名は保守的な文字集合に制限します。retention削除は
`YYYYMMDDTHHMMSSZ`形式の完了snapshotだけを対象にし、一時directoryや別用途directoryを削除しません。

## 9. ローカル検証（Molecule）

各ロールに Molecule シナリオを同梱している。フルライフサイクル
（create → converge → idempotence → verify → destroy）は Docker-in-Docker
+ systemd を要するためローカル実行を前提とする。

```bash
pip install 'ansible' 'molecule' 'molecule-plugins[docker]' 'docker'
docker pull geerlingguy/docker-ubuntu2204-ansible:latest
cd ansible/roles/common
molecule test
```

`common` 以外も同様に `roles/docker`、`roles/nginx`、`roles/monitoring` から
`molecule test` を実行できる。冪等性が崩れたタスクは Molecule の
`idempotence` ステップで検出される。

GitHub Actions（`.github/workflows/ansible-check.yml`）では次を検証する：

| ジョブ | 内容 |
| --- | --- |
| `lint` | `ansible-lint --offline` と全 playbook の `--syntax-check` |
| `molecule (common/docker/nginx/monitoring)` | `molecule list`でscenarioを読み込み、存在する`prepare.yml`と`converge.yml` / `verify.yml`を`--syntax-check` |

通常の PR CI はシナリオの妥当性のみを検証する。実コンテナでの収束 / 冪等性確認は
上記のローカル実行に加え、`.github/workflows/ansible-integration.yml` を手動実行
して確認できる。結果は `docs/evidence/` に記録してから実績として扱う。

## 10. common + docker だけを構築する（`foundation.yml`）

監視アプリを含む一式（`site.yml`）ではなく、OS ハードニングとコンテナランタイムの
共通基盤だけを新規ホストへ構築したい場合は `foundation.yml` を使う。`bootstrap.yml`
（`common` role のみ）に `docker` role を加えたものであり、以後どの構築案件（監視、AD、
Windows、Zabbix など）にも使い回せる下地を作ることを目的にしている。設計の考え方は
[Ansible自動化基盤構築案件パック](build-package-ansible/README.md)にまとめている。

```bash
cd ansible
cp inventory/foundation.local.yml.example inventory/foundation.local.yml
$EDITOR inventory/foundation.local.yml  # 対象IP、SSH user、管理者の公開鍵へ置換
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --check --diff
ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml
```

`foundation` group には `inventory/group_vars/foundation/main.yml` が適用され、
`server_monitor_user` などの既定値が `monitor`（監視アプリ用）ではなく
`svc-baseline`（案件非依存の汎用名）へ上書きされる。Vault は使わない。
`common` / `docker` 両 role は機密値を必要としないため、この2 roleだけを
適用する構成では `ansible-vault` の初期化そのものが不要になる。

## 11. 既存 docker-compose 環境からの移行

1. 既存ホストの `deploy/secrets/*.txt` の値を控える
2. それらを `inventory/group_vars/monitor/vault.yml` に転記し、`ansible-vault encrypt` で暗号化
3. ステージング相当のホストで `site.yml` を `--check --diff` モード実行し、差分が想定どおりか確認
4. ステージングで実適用、`verify.yml` を流す
5. 本番に対して同じ手順を実施し、以後は手動変更を禁止

`docs/deployment.md` の手順で構築されたホストでも、`server_monitor_install_dir`（既定 `/opt/server-monitor`）を合わせれば本プレイブックでそのまま管理対象にできる。
