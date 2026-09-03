# 要件定義書

> 💡 **初めて読む方へ**: この文書は「何を作るか」「完成の合格基準」を先に決める文書です。`NFR`（非機能要件）や`AFIT-xx`のような略語につまずいたら、先に[案件パック 初心者ガイド](beginner-guide.md#3-12文書カード)を確認してください。文書番号（00〜11）と役割はLinux版と共通です。

## 1. 文書の位置づけ

既存のLinux版構築案件パック（案件ID`SM-LAB-001`、正本は[../build-package/README.md](../build-package/README.md)）は、`server-monitor`という監視アプリをUbuntuホスト1台へ構築する案件です。そこでAnsibleは「決めた設計を再現よく実行する道具」として使われています。

本パック（案件ID`SM-ANS-001`）は視点を変え、**その道具（Ansibleのroleとplaybook）自体を1つの構築案件の成果物とみなします**。対象は新規作成した`ansible/roles/common` / `ansible/roles/docker`の組み合わせと、それを実行する`ansible/playbooks/foundation.yml`です。`common` / `docker`両roleはLinux版パックの`site.yml`でもすでに使われている既存roleであり、本パックで新しいroleを作るわけではありません。本パックが新規に行うのは、**その2つのroleを「監視アプリに依存しない、独立した基盤構築の単位」として切り出し、設計・試験・引き渡しの一式を整えること**です。

本書に「済(自動)」「済(手動)」「未実装」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。本パック全体を通じて実装状態は次の3区分のみを使い、混同しません。

| 区分 | 意味 |
| --- | --- |
| 済(自動) | 今すぐ実行可能なコードとして用意したもの。`ansible/playbooks/foundation.yml`とその依存role・inventory・group_varsがこれに当たる |
| 済(手動) | コード化されていないが、本パックの手順書（コマンド）で今すぐ実施できるもの（対象VMの用意、SSH鍵の配布、inventoryの編集） |
| 未実装 | 本パックは設計のみを示し、実行実績がまだ無いもの（AlmaLinux/Rocky 9実機ホストでの構築、`foundation.yml`合成後の実コンテナ収束・冪等性確認をCIの`ansible-integration.yml`へ追加すること） |

「済(自動)」を、実ホストで実行して`PASS`したことと混同しないでください。コードが存在し、この検証環境内でYAML構文を確認済みであることを意味します。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | `SM-ANS-001` |
| 利用者 | これから監視・AD・Windows・Zabbixなどの構築案件に着手するインフラエンジニア（本人を想定） |
| 対象環境 | Ubuntu Server 24.04 LTS（フェーズ1・基準）、AlmaLinux/Rocky 9（フェーズ2・設計のみ） |
| 対象ホスト | 新規VM 1台（論理ホスト名`ans-01`。フェーズ2は`ans-el9-01`） |
| 構築方式 | `ansible/playbooks/foundation.yml`（`common` role → `docker` role の順で適用） |
| 提供機能 | OSハードニング（timezone、パッケージ、firewall、SSH、自動更新、SELinux）、Docker Engine + Compose plugin導入、案件ごとに変数を上書きできる設計 |
| 引き渡し単位 | 構成コード（`ansible/playbooks/foundation.yml`、`ansible/inventory/group_vars/foundation/`、`ansible/inventory/foundation.local.yml.example`）、設計書、パラメータシート、構築手順、試験結果、作業結果報告 |
| 完了判定 | フェーズ1必須試験がすべて`PASS`し、計画対実績・差異・未解決事項・残存リスクが作業結果報告に記載済み |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 |
| --- | --- | --- |
| FR-01 | 運用者が`foundation.yml`を新規Ubuntuホストへ適用し、timezone・パッケージ・firewall・SSH・自動更新のOSハードニングが完了すること | AFIT-01 |
| FR-02 | 同じ`foundation.yml`をAlmaLinux/Rocky 9ホストへ適用しても、role内部のOSファミリー分岐により意味的に同等な結果が得られること | AFIT-06 |
| FR-03 | Docker Engine + Compose pluginが導入され、`docker compose version`が実行できること | AFIT-03 |
| FR-04 | 管理者アカウントが鍵認証でSSHログインでき、password認証とrootログインは拒否されること | AFST-01、AFST-02 |
| FR-05 | 対象ホスト・案件ごとに`server_monitor_user`等の既定値を`group_vars`の優先順位で上書きできること（例: `foundation` groupは`monitor`ではなく`svc-baseline`を使う） | AFUT-04、02-detailed-design.mdの変数設計 |
| FR-06 | 管理端末から対象ホストへの名前解決・経路・SSH到達性・firewall許可範囲を確認できること | AFNW-01〜05 |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 再現性 | 未構築の`ans-01`へ`foundation.yml`を適用し、`failed=0`で終了すること | AFIT-01 |
| NFR-02 | 冪等性 | 2回目の適用が`changed=0`になること | AFIT-02 |
| NFR-03 | 移植性 | Debian系・RHEL系の双方に対応するコードであること（OS差分は`vars/<family>.yml`へ分離） | AFUT-04（Molecule `default` / `el9`） |
| NFR-04 | 最小公開 | 対象ホストで着信を許可するのはSSHのみとし、追加の公開ポートを作らないこと | AFST-03 |
| NFR-05 | 認証 | root SSHログインとpassword認証を拒否し、鍵認証のみを許可すること | AFST-01、AFST-02 |
| NFR-06 | 最小権限 | 汎用アプリ用アカウントへ`docker`グループ（root相当）を付与しないこと | AFST-04 |
| NFR-07 | 安全装置 | 未対応OS、危険な`server_monitor_install_dir`、`root`グループ指定などをホスト変更前に`assert`で拒否すること | 02-detailed-design.mdの冪等性設計、AFUT-01 |
| NFR-08 | 保守性 | role内のtasksは変数だけを読み、OSごとの差分はvars/tasksファイルへ分離すること（tasksへのif分岐の直書きを避ける） | 02-detailed-design.md |
| NFR-09 | テスト容易性 | Moleculeの`default`（Ubuntu）と`el9`（Rocky）シナリオでCIから検証できること | AFUT-04 |
| NFR-10 | 追跡性 | 実行日時、環境、commit SHA、実行コマンド、実出力、判定を証跡として保存すること | 全必須試験 |

## 5. 制約と対象外

- 監視アプリ・Docker Composeワークロードの配備は対象外です（[Linux版詳細設計書](../build-package/02-detailed-design.md)の領域であり、変更しません）。
- `ansible-vault`による秘密値管理は対象外です。`common` / `docker`両roleはVaultを必要とする機密値を扱いません。
- 高可用性、複数ホストへの同時適用、production SLA、24時間有人監視は対象外です。
- AlmaLinux/Rocky 9実機ホストでの構築は対象外です。Moleculeによるコンテナ検証は実施済みですが、`apply`の実行実績が無い限り本案件の構築実績には含めません（フェーズ2として区分）。
- 中央監視基盤（Prometheus等）へのホスト登録は対象外です。本パックは個々の下地ホストを作るところまでを扱います。
- `foundation.yml`（`common` + `docker`の組み合わせ）自体の実コンテナ収束・冪等性のCI自動検証は対象外です。現状のCIは各role単体のMolecule scenarioの構文検証のみを行います（[00-requirements.mdの区分表](#1-文書の位置づけ)の「未実装」参照）。

## 6. 前提条件

- `ans-01`用の新規VM（Ubuntu Server 24.04 LTS）が用意されていること。フェーズ2着手時は`ans-el9-01`用のAlmaLinux/Rocky 9 VMも用意すること。
- 管理端末に管理者用のSSH鍵ペアが用意されており、公開鍵をinventoryへ設定できること。
- Ansible controller側にPython 3.10+、`pipx install ansible-core`、`ansible-lint`が使えること。
- 対象IP、SSHユーザー、管理者ユーザー名（`server_monitor_admin_user`）が作業前に決まっていること。
- 対象commit SHAと、直前の正常なcommit SHAを変更記録へ残せること。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きのevidenceへコピーして保存します。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。
