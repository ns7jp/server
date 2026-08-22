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
│   ├── site.yml         # 0 台から構築する完全プレイブック
│   ├── bootstrap.yml    # 新規ホストの OS 初期化のみ
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
- ローカル側に Python 3.10+ と `pipx` 推奨

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
cp vault.yml.example vault.yml
$EDITOR vault.yml   # 3 つの秘密値を入れる
openssl rand -base64 32   # 例。値の生成に使う
echo 'change-me' > ../../../.vault_pass
chmod 600 ../../../.vault_pass
ansible-vault encrypt vault.yml --vault-password-file ../../../.vault_pass
```

`.vault_pass` はファイル単位の Vault パスワード。CI に渡す場合は GitHub Secrets に格納し、`ansible-playbook --vault-password-file <path>` で読み込ませる。

Vault 原本と `.vault_pass` の権限は所有者だけに制限する。一方、app role が `/opt/server-monitor/deploy/secrets/*.txt` へレンダリングする Compose secrets は `0644` とする。Compose の file-backed secret は host mode を維持し、Grafana など別 UID の非 root container が読むためである。host 側は親 directory を `0700` にして、他 user の path traversal を防ぐ。

## 4. インベントリ

`inventory/staging.yml` の `ansible_host` を実 IP に書き換える。本番は `inventory/production.yml` を編集し、ホスト名・SSO 連携・Let's Encrypt 有効化を行う。

| 環境 | inventory ファイル | 既定の差分 |
| --- | --- | --- |
| ラボ / staging | `inventory/staging.yml` | `nginx_letsencrypt_enabled: false`、自己署名証明書、UFW で 22 のみ |
| production | `inventory/production.yml` | `nginx_letsencrypt_enabled: true`、本番 FQDN、UFW で 22/443 |

## 5. 0 台から構築

```bash
cd ansible
ansible-playbook -i inventory/staging.yml playbooks/site.yml --check --diff
ansible-playbook -i inventory/staging.yml playbooks/site.yml
```

`--check --diff` で差分を見てから実適用する。実行が成功すれば `site.yml` の末尾で `verify.yml` が呼ばれ、`/healthz`、Prometheus `/-/ready`、Loki `/ready`、Grafana `/api/health`、`/metrics` の認証可否を順に確認する。

## 6. 冪等性の確認

2 回連続で同じ playbook を流し、2 回目の `changed=0` を確認する。

```bash
ansible-playbook -i inventory/staging.yml playbooks/site.yml
ansible-playbook -i inventory/staging.yml playbooks/site.yml | tail -5
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
ansible-playbook -i inventory/staging.yml playbooks/deploy.yml
```

実装手順は次のとおり。

1. `deploy/` 配下を rsync で同期（既存の `secrets/*.txt` は除外）
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
| `molecule (common/docker/nginx/monitoring)` | `molecule list` で各 scenario を読み込み、`converge.yml` / `verify.yml` の `--syntax-check` を実行 |

通常の PR CI はシナリオの妥当性のみを検証する。実コンテナでの収束 / 冪等性確認は
上記のローカル実行に加え、`.github/workflows/ansible-integration.yml` を手動実行
して確認できる。結果は `docs/evidence/` に記録してから実績として扱う。

## 10. 既存 docker-compose 環境からの移行

1. 既存ホストの `deploy/secrets/*.txt` の値を控える
2. それらを `inventory/group_vars/monitor/vault.yml` に転記し、`ansible-vault encrypt` で暗号化
3. ステージング相当のホストで `site.yml` を `--check --diff` モード実行し、差分が想定どおりか確認
4. ステージングで実適用、`verify.yml` を流す
5. 本番に対して同じ手順を実施し、以後は手動変更を禁止

`docs/deployment.md` の手順で構築されたホストでも、`server_monitor_install_dir`（既定 `/opt/server-monitor`）を合わせれば本プレイブックでそのまま管理対象にできる。
