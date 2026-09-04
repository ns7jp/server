# Ansible自動化基盤 構築・試験結果票 — 2026-09-04

[試験仕様書・結果票](../build-package-ansible/06-test-specification.md)の原本をコピーし、Hyper-V上に構築した`ans-01`(Ubuntu 24.04.4 LTS)へ`ansible/playbooks/foundation.yml`を適用した結果を記入したものです。原本は`NOT RUN`のまま保持し、実施結果はこの日付付きファイルへ記録します。

> **この証跡が示す範囲**: 本人のホストPC(Windows、Hyper-V)上の仮想スイッチに接続したVM 1台（Ubuntu 24.04、Hyper-V Quick Create経由）へ、WSL2(Ubuntu-24.04)をAnsible controllerとして`foundation.yml`（`common` + `docker` role）を適用した記録です。実行者はAI支援セッションで手順を受け取り、コマンドと出力をスクリーンショットで確認しました。フェーズ2（AlmaLinux/Rocky 9実機）、CI（GitHub Actions）でのMolecule実行、恒久稼働・再起動後確認は対象外です。

## 基本情報

| 項目 | 値 |
| --- | --- |
| 全体状態 | **フェーズ1必須ID（AFUT-01〜05、AFIT-01〜05、AFIT-07、AFST-01〜05）が全件`PASS`**。任意項目のAFNW-06（rate limit）とフェーズ2（AFIT-06/AFST-06）は未実施のまま残る |
| 実施日時（JST） | 2026-09-04 |
| 実施者 | ns7jp |
| 対象環境 / host | `ans-01`（`192.168.11.95/24`、DHCP割当）、Hyper-V VM（Quick Create、Ubuntu 24.04.4 LTS gallery image） |
| 管理端末 / controller | ホストPC（`DESKTOP-19F10FT`、Windows、Hyper-V）上のWSL2 `Ubuntu-24.04`。`ansible`本体は事前にapt導入済み（`/usr/bin/ansible-playbook`）で、`pipx install ansible-core`は空振りだった（pipxが空のまま）。`ansible-galaxy collection install -r requirements.yml`は「既に導入済み」と応答。Molecule（AFUT-04用）は`pipx install molecule` + `pipx inject molecule ansible-core 'molecule-plugins[docker]' docker`で導入 |
| 初期ログインユーザー | `usr722`（Quick Create時に設定、password認証で初回接続） |
| 作成した管理者アカウント | `ansible-admin`（`server_monitor_admin_user`、鍵認証のみ） |
| commit SHA | `44cf16a`（WSL側で`git pull origin main`を実行した時点のmain HEAD） |
| OS / kernel | Ubuntu 24.04.4 LTS |

秘密値（VMのSSH秘密鍵、`usr722`のログインpassword）は記載していません。

## 単体・構成試験（AFUT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AFUT-01 | YAML構文 | PASS | `python3 -c "import yaml; yaml.safe_load(open(f))"`を`foundation.yml`・`inventory/group_vars/foundation/main.yml`・`inventory/foundation.local.yml.example`へ実行、例外なし（実施: AI支援セッションの作業環境、2026-09-03） |
| AFUT-02 | ansible-lint | PASS | `pip install ansible`（`ansible-core`ではなくcollection同梱のフル版）で`community.general`等を取得し、`ansible-lint --offline`を実行。`Passed: 0 failure(s), 0 warning(s) in 69 files processed of 76 encountered. Profile 'production' was required, and it passed.`（実施: AI支援セッションの作業環境、`galaxy.ansible.com`がネットワークポリシーで遮断されているため`pip`経由でcollectionを取得。CI本来の`ansible-lint`実行とは別環境） |
| AFUT-03 | 全playbookの構文チェック | PASS | 上記と同じ環境で`ansible-playbook -i inventory/foundation-test.yml playbooks/foundation.yml --syntax-check`が`playbook: playbooks/foundation.yml`のみで正常終了。WSL側での実適用が成功したことでも間接的に再確認済み |
| AFUT-04 | Molecule scenario検出 | PASS | WSL側に`pipx install molecule` + `pipx inject molecule ansible-core 'molecule-plugins[docker]' docker`を導入（WSLはDockerが別途稼働中を確認済み）。`common`・`docker`両roleで`molecule list`を実行し、`default`と`el9`の両scenarioが検出された（`server-monitor-common`/`-el9`、`server-monitor-docker`/`-el9`） |
| AFUT-05 | 成果物リンク | PASS | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` → `1 passed, 52 deselected`（実施: AI支援セッションの作業環境、2026-09-03） |

## 構築・結合試験（AFIT）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| — | 適用前確認（`--check --diff`） | 想定どおりの失敗 | `TASK [common : Ensure chrony is enabled and running]`で`fatal: Could not find the requested service chrony: host`。play recap `ok=11 changed=2 unreachable=0 failed=1 skipped=2`。check modeではchronyパッケージが実導入されないため後続moduleが前提を欠く、[詳細設計書](../build-package-ansible/02-detailed-design.md#check-modeの限界)に記載済みの制約どおりの挙動 |
| AFIT-01 | 新規構築（Ubuntu） | PASS | `ansible-playbook -i inventory/foundation.local.yml playbooks/foundation.yml --ask-become-pass`。play recap `ok=55 changed=5 unreachable=0 failed=0 skipped=14 rescued=0 ignored=0` |
| AFIT-02 | 冪等性 | PASS | 直後の再実行で`ok=54 changed=0 failed=0 skipped=14`。後述の欠陥修正（`common_admin_sudo_nopasswd: true`追加）後にも再実行し、`changed=1`（sudoersのみ）→再々実行で`changed=0`を再確認。2回、独立して冪等性を実測 |
| AFIT-03 | Docker動作確認 | PASS | `ansible-admin`で`sudo docker version`（Client/Server共に`29.8.0`、containerd `v2.3.4`、runc `v1.5.1`）、`docker compose version`（`v5.5.1`）、`systemctl is-active docker`（`active`） |
| AFIT-04 | 時刻同期 | PASS | `sudo ss -lntup`で`chronyd`（pid 3050）がNTPポート（`127.0.0.1:323`、`[::1]:323`）で待ち受けていることを確認 |
| AFIT-05 | 自動更新設定 | PASS | `dpkg -l unattended-upgrades` → `ii unattended-upgrades 2.9.1+nmu4ubuntu1`。`/etc/apt/apt.conf.d/20auto-upgrades` → `APT::Periodic::Update-Package-Lists "1";` / `APT::Periodic::Unattended-Upgrade "1";` |
| AFIT-06 | RHEL系（フェーズ2）構築 | BLOCKED | 実VM未用意のため未着手（既存の状態を維持） |
| AFIT-07 | 実ホストnetwork | PASS | 下表AFNW参照。AFNW-01〜05すべてPASS（AFNW-06は任意項目でNOT RUN） |

## セキュリティ試験（AFST）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AFST-01 | password認証禁止 | PASS | `sudo sshd -T \| grep -i passwordauthentication` → `passwordauthentication no` |
| AFST-02 | rootログイン禁止 | PASS | `sudo sshd -T \| grep -i permitrootlogin` → `permitrootlogin no` |
| AFST-03 | 最小公開 | PASS | `sudo ss -lntup`で外部（`0.0.0.0`/`[::]`）にLISTENしているのは`22/tcp`（IPv4/v6）のみ。他はloopback限定のDNSスタブ、またはUDPのDHCPクライアント |
| AFST-04 | dockerグループ非付与 | PASS | `id svc-baseline` → `uid=999(svc-baseline) gid=988(svc-baseline) groups=988(svc-baseline)`。`docker`グループなし |
| AFST-05 | install dir権限 | PASS | `stat -c "%U:%G %a %n" /opt/ansible-foundation` → `svc-baseline:svc-baseline 750 /opt/ansible-foundation` |
| AFST-06 | SELinux enforcing（RHEL系・フェーズ2） | BLOCKED | AFIT-06と同じ理由 |
| AFST-07 | 未対応OSでの安全停止 | NOT RUN | 今回は未対応OSでの実行を試みていない |

## ネットワーク実機検証（AFNW、09-network-validation-procedure.md対応）

| ID | 確認対象 | 結果 | 実出力（要点）/ 備考 |
| --- | --- | --- | --- |
| AFNW-01 | IP・interface確認 | PASS | `ip -br addr` → `eth0 UP 192.168.11.95/24 ...`（DHCPで取得。当初`eth0`が`DOWN`のままだった原因は後述の欠陥参照） |
| AFNW-02 | 経路確認 | PASS | `ip route` → `default via 192.168.11.1 dev eth0 proto dhcp src 192.168.11.95 metric 100`。同一サブネット（`192.168.11.0/24`）と`docker0`（`172.17.0.0/16`、linkdown）の経路も設計どおり |
| AFNW-03 | 待受確認 | PASS | 上記AFST-03と同じ`ss -lntup`結果 |
| AFNW-04 | SSH到達性 | PASS | `usr722`（password）・`ansible-admin`（鍵、`ssh -i ~/.ssh/ans01-admin`）双方で到達性を繰り返し確認 |
| AFNW-05 | firewall許可範囲 | PASS | `sudo ufw status verbose` → `Status: active`、`Default: deny (incoming), allow (outgoing), deny (routed)`、`22/tcp` / `22/tcp (v6)`のみ`LIMIT IN Anywhere` |
| AFNW-06 | rate limit発火確認（任意） | NOT RUN | 対象ホストへの負荷を伴うため未実施 |

## 見つかった欠陥

実行して初めて見つかった実装上の欠陥が1件あります。詳細は[欠陥台帳](defects-found.md)（#30）を参照してください。

`common` roleが作る管理者アカウント（`ansible-admin`）は、SSH公開鍵は登録するがパスワードを一切設定しない。一方`common_admin_sudo_nopasswd`の既定値は`false`（sudoにpasswordを要求）のため、既定のままだと**そのアカウントのsudoが恒久的に成功しない**。`ansible-lint`・`--syntax-check`・sudoersの`visudo -cf`検証はいずれも構文レベルの検査であり、この意味論的な欠陥は捕まえない。実機で`ansible-admin`のsudoを試して初めて発覚した。

対応として、`ansible/inventory/group_vars/foundation/main.yml`の既定値に`common_admin_sudo_nopasswd: true`を追加した（本PRに含む）。鍵認証をこのgroupの唯一の認証要素と位置づける設計判断で、[02-detailed-design.md](../build-package-ansible/02-detailed-design.md)の設計方針と整合する。

## 見つかった構築上のつまずき（欠陥ではないが記録する事実）

- Hyper-V Quick Createの Ubuntu 24.04.4 LTS gallery imageは、`/etc/netplan/`に設定ファイルが1つも無い状態で起動した（`networkctl status eth0`が`Network File: n/a`、`unmanaged`）。DHCPv4が要求されず`eth0`が`UP`でもIPv4が付かなかった。手動で`dhcp4: true`のnetplan設定を追加して解決した。このリポジトリのroleやplaybookの欠陥ではなく、VMイメージ側の初期状態に起因する
- WindowsターミナルのQuickEdit Mode（クイック編集モード）により、ウィンドウ内をクリックすると出力表示が一時停止する。Ansible自体は裏で正常に動作していたが、一見「フリーズした」ように見え、原因切り分けに時間を要した

## 未実施・今後の課題

フェーズ1必須ID（AFUT-01〜05、AFIT-01〜05、AFIT-07、AFST-01〜05）は全件`PASS`した。残るのは次の任意・フェーズ2項目のみ。

- AFNW-06（rate limit発火確認、任意項目。対象ホストへの負荷を伴うため見送り）
- AFST-07（未対応OSでの安全停止、任意の追加確認）
- フェーズ2（AlmaLinux/Rocky 9実機、AFIT-06・AFST-06）
- CI（GitHub Actions）上での`ansible-lint`・`--syntax-check`の実行結果確認（この証跡はpipのcollection取得によるローカル代替。CI本来の実行結果とは別）
- 再起動後の設定保持確認（[10-host-bringup-and-acceptance.md](../build-package-ansible/10-host-bringup-and-acceptance.md)の範囲）
