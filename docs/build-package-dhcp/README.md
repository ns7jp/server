# DHCPサーバー構築案件パック

**一言でいうと**: 検証用LANセグメント`192.168.50.0/24`向けに、新規サーバー`dhcp-01`でDHCPv4の払い出しを構築し、引き渡すまでの書類一式です。

初めての方は、先に[案件パック 初心者ガイド](beginner-guide.md)を読むと全体像がつかめます。

このディレクトリは、案件ID`SM-DHCP-001`の成果物を工程順にまとめたものです。Ubuntu Server 24.04 LTSの検証用VM 1台（新規・論理ホスト名`dhcp-01`）に**isc-dhcp-server**を構築し、検証用LANセグメント`192.168.50.0/24`へDHCPv4のリースを払い出せるようにします。既存の監視基盤（[Linux版パック](../build-package/README.md)、案件ID`SM-LAB-001`）、[Windows版パック](../build-package-windows/README.md)（`SM-WIN-001`）、[AD版パック](../build-package-ad/README.md)（`SM-AD-001`）、[Zabbix版パック](../build-package-zabbix/README.md)（`SM-ZBX-001`）とは独立した新規構築案件です。

案件は「何を作るか決める → 設計する → 作る → 試験する → 報告して渡す」の順に進みます。工程ごとに書類が分かれるため、文書は00から11までの12個あります。番号は作られた順で、読む順とは一致しません。初めて読むときは、下の「最短レビュー順」に従ってください。

「Linux監視基盤・Windows/AD統合・Zabbix監視」に加えて、**ネットワークの基盤サービス（DHCP）を要件定義から引き渡しまで設計・構築できる**ことを示すのが、このパックをポートフォリオへ追加した狙いです。本文書にある「設計値」と、実機で取得した「実績値」は分けて管理します。

| 案件 ID | 対象 | 現在の引き渡し判定 |
| --- | --- | --- |
| `SM-DHCP-001` | Ubuntu Server 24.04 LTS の検証用 VM 1 台（新規・論理ホスト名 `dhcp-01`）へ isc-dhcp-server を構築し、検証用LANセグメント `192.168.50.0/24` 向けにDHCPv4のリース払い出し（動的プール・固定予約）を提供する | **`NOT READY`** — 引き渡し対象ホストが未指定で、必須試験（`DUT`/`DIT`/`DST`/`DNW`）が `NOT RUN` |

表中の `NOT READY` は、必須の試験が終わっておらず、引き渡せる状態ではないことを表します。

```mermaid
flowchart LR
    R["要件ID 00"] --> D["基本・詳細設計 01-04"]
    D --> B["構築 05 / dhcp_server role + dhcp.yml適用"]
    B --> T["試験 06 / 09 / DUT・DIT・DST・DNW"]
    T --> E["日付付き実測証跡 docs/evidence"]
    E --> W["作業結果報告 11"]
    W --> H["引き渡し判定 07"]
```

次の3つは、それぞれ別の状態です。ひとまとめにしないでください。

- 文書が「作成済み」であること
- `dhcp_server` roleが`ansible-lint --offline`（production profile）とAnsible構文チェックを通過していること
- 特定の引き渡し対象ホスト（`dhcp-01`）で受け入れが完了したこと

最終判定は[作業結果・引き渡し報告書](11-work-result-report.md)と[引き渡しチェックリスト](07-handover-checklist.md)を使います。

### 初めての方はまずこちら

`NFR`（非機能要件。速さ・止まりにくさ・安全性など、機能以外の要求）、`Gate`（次の工程へ
進んでよいかを判断する関門）、`DORA`、`DIT-xx`のような言葉が初見の場合は、12文書を読み始める前に
[案件パック 初心者ガイド](beginner-guide.md)で、案件パックとは何か、各文書の役割、
読む順とかかる時間の目安を確認してください。

## 既存パックとの関係

本パックは[Linux版パック](../build-package/README.md)、[Windows版パック](../build-package-windows/README.md)、[AD版パック](../build-package-ad/README.md)、[Zabbix版パック](../build-package-zabbix/README.md)と同じ構成・文体・厳格さを踏襲しますが、次の2点が特徴です。

1. **単一フェーズで完結する構成であること**: Windows版・AD版パックは「フェーズ1（ホスト単体構築）」「フェーズ2（中央監視統合）」に分かれます。`dhcp-01`はLinuxホストのため、既存の中央Prometheus（`monitor-01`）の`app_node_exporter_targets`へそのまま1行追加でき、Windows/AD版のような「中央監視基盤への統合待ち`BLOCKED`」という区分が本パックには**ありません**。そのため本パックは、[Linux版パック](../build-package/README.md)と同じ単一フェーズの工程ゲート（G0〜G5）で完結します。
2. **既に実装済みのAnsible roleがあり、その適用結果だけがまだ無いこと**: 新規role `ansible/roles/dhcp_server/` と専用playbook `ansible/playbooks/dhcp.yml` は実装済みで、`ansible-lint --offline`（production profile）とAnsible構文チェックはローカルで通過を確認しています。一方で、対象ホストへの実適用とDORA（DHCPの4-way handshake）の実演はまだ行っていません。「roleは実装済みで静的チェックはPASS、実ホスト適用は`NOT RUN`」という中間状態であることは、[00-requirements.md](00-requirements.md)と[01-basic-design.md](01-basic-design.md)に明記しています。これは、Zabbixパックが「Ansible role化は未実装」と書いているのとは対照的な状態です。

DHCPデーモンには、Ubuntuの`isc-dhcp-server`パッケージを使う`isc-dhcp-server`を採用しています。ISC（開発元）は2022年にisc-dhcpをEOL（開発終了）とし、後継として`isc-kea-dhcp4-server`（Kea DHCP、JSON設定）を推奨していますが、本パックはあえて`isc-dhcp-server`を選んでいます。理由は[00-requirements.md](00-requirements.md)の1章と[01-basic-design.md](01-basic-design.md)の2章に記載し、Keaへの移行は「発展的な設計・将来構想」として次のステップに明記しています。

## 最短レビュー順

1. [要件定義書](00-requirements.md) — 何を作り、何を作らないか。どうなれば合格かを決める（要件 ID と受け入れ条件を定義）
2. [基本設計書](01-basic-design.md) — 全体の構成と、非機能（NFR）の設計方針
3. [パラメータシート](03-parameter-sheet.md) — 実際に入力する設定値の一覧（OS・ネットワーク・DHCPスコープ・Ansible変数）
4. [構築手順書](05-build-procedure.md) — `dhcp-01`をAnsibleで組み立てる手順
5. [試験仕様書・結果票](06-test-specification.md) — 何を確かめれば合格かと、実測結果を書き込む用紙（`DUT`/`DIT`/`DST`/`DNW`）
6. [ネットワーク実機検証手順](09-network-validation-procedure.md) — `dhcp-01`と検証用LANセグメントの間で通信・DORAを確認する手順（名前が引けるか、経路は正しいか、待ち受けているか、DORAのpacket captureはどうか）
7. [作業結果・引き渡し報告書](11-work-result-report.md) — 計画対実績（予定と実際の比較）、試験の集計、差異、残存リスク（残ったままの危険）、完了判定
8. [検証証跡台帳](../evidence/README.md) — 実測済み・未実測の境界（どこまで実機で確かめ、どこからが未確認か）

## 成果物一覧

| 工程 | 成果物 | 状態 |
| --- | --- | --- |
| 要件定義 | [00-requirements.md](00-requirements.md) | 作成済み |
| 基本設計 | [01-basic-design.md](01-basic-design.md) | 作成済み |
| 詳細設計 | [02-detailed-design.md](02-detailed-design.md) | 作成済み |
| パラメータ設計 | [03-parameter-sheet.md](03-parameter-sheet.md) | 作成済み |
| ネットワーク設計 | [04-network-ip-plan.md](04-network-ip-plan.md) | 作成済み |
| 構築 | [05-build-procedure.md](05-build-procedure.md) | 手順作成済み。`dhcp_server` roleは`ansible-lint --offline`（production profile）とAnsible構文チェックをローカルで通過済み（DUT-02, DUT-03）。実機結果は証跡台帳で管理 |
| 試験 | [06-test-specification.md](06-test-specification.md) | 仕様作成済み・未実施欄は `NOT RUN` |
| 引き渡し | [07-handover-checklist.md](07-handover-checklist.md) | 作成済み |
| 変更・ロールバック | [08-change-rollback-plan.md](08-change-rollback-plan.md) | 計画・記録様式作成済み。実施結果は `NOT RUN` |
| ネットワーク実機検証 | [09-network-validation-procedure.md](09-network-validation-procedure.md) | 手順作成済み。実施結果は `NOT RUN` |
| 立ち上げ・受け入れ | [10-host-bringup-and-acceptance.md](10-host-bringup-and-acceptance.md) | 最短手順を作成済み |
| 作業結果報告 | [11-work-result-report.md](11-work-result-report.md) | 原本作成済み。対象ホストごとの実績は日付付き evidence へ複製して記録 |
| ネットワーク結果票 | [DHCP版実機検証テンプレート](../evidence/templates/network-host-validation-dhcp.md) | テンプレート作成済み |
| 一次切り分け記録 | [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md) | テンプレート作成済み（既存パックと共用） |

## 工程ゲート

表中の `NOT SET` は、値や承認がまだ決まっていないことを表します。

| Gate | 完了条件 | 現在の状態 |
| --- | --- | --- |
| G0 要件確定 | 要件 ID、対象、対象外、受け入れ条件が合意済み | 文書作成済み。実案件での承認は `NOT SET` |
| G1 設計確定 | 基本・詳細・パラメータ・ネットワーク設計のレビュー完了 | 文書作成済み。実案件での承認は `NOT SET` |
| G2 構築完了 | `dhcp.yml`の初回適用が成功し、2回目適用で`changed=0`になること | roleは`ansible-lint --offline`・Ansible構文チェックともPASS。対象ホストでの適用は `NOT RUN` |
| G3 試験完了 | 対象ホストの必須31 ID（`DUT-01〜05`、`DIT-01〜11`、`DST-01〜06`、`DNW-01〜09`）がすべて `PASS` | `NOT READY` |
| G4 作業完了 | 作業結果報告書に実績、障害、差異、残存リスクを記録 | 原本のみ。実案件報告は `NOT SET` |
| G5 引き渡し | 受領者、日時、未解決事項を記録 | `NOT READY` |

## 検証環境

基準環境は Ubuntu Server 24.04 LTS の単一ホスト（`dhcp-01`、静的IP`192.168.50.5/24`）です。構築コードは新規role `ansible/roles/dhcp_server/`（`defaults/main.yml`、`meta/main.yml`、`tasks/main.yml`、`handlers/main.yml`、`templates/dhcpd.conf.j2`、`templates/isc-dhcp-server.j2`）と、専用playbook `ansible/playbooks/dhcp.yml`（`hosts: dhcp`グループに対して`common` role → `dhcp_server` roleの順で適用する2 play構成）です。既存の`site.yml`とは独立しています。

ローカルで`ansible-lint --offline`（production profile）を実行し0 failureを確認済み、`ansible-playbook -i inventory/staging.yml playbooks/dhcp.yml --syntax-check`も成功済みです（DUT-02, DUT-03）。CI（`.github/workflows/ansible-check.yml`）にも同等の構文チェックを追加済みですが、molecule対象role一覧（common/docker/nginx/monitoring）には含めていません（`app`/`backup`/`storage`と同様、molecule scenarioは用意していません）。**実ホストへの適用、DORA（DISCOVER/OFFER/REQUEST/ACK）の実演は`NOT RUN`**です。

新規inventory例は`ansible/inventory/staging.dhcp.local.yml.example`です。コピーして`staging.dhcp.local.yml`として使います（`.gitignore`対象）。`dhcp_server_interface`は既定値が空文字で、払い出し対象セグメント`192.168.50.0/24`へ実際に接続されたNIC名を`ip -br link`で実機確認したうえでinventoryに明示指定する必要があります。

DHCPのDORA実演にはL2ブロードキャストが必要で、既存の[二セグメント障害ラボ](../../labs/network-troubleshooting/README.md)（Docker上の`172.28.10.0/24` / `172.28.20.0/24`）が使うDockerの既定bridgeネットワークでは素直に成立しません（Dockerがコンテナのdhcpdへ実際にDISCOVERを送る構成にはひと手間要るため）。そのため本パックは、Dockerラボではなく**VM/実機での実演を正本**とします。VirtualBoxのHost-OnlyネットワークまたはInternalネットワークで`dhcp-01`とクライアント役VMを同一セグメントに置く立ち上げ手順は[10-host-bringup-and-acceptance.md](10-host-bringup-and-acceptance.md)にまとめています。Dockerベースの払い出しラボは「発展的な設計・将来構想」として言及するにとどめ、未実装です。

ネットワーク実機検証は、本パック専用の[結果票テンプレート](../evidence/templates/network-host-validation-dhcp.md)を使い、「管理端末→`dhcp-01`」「クライアントVM→`dhcp-01`（DORA）」の2方向を確認します。日付付きの結果票（例: `docs/evidence/YYYY-MM-DD-dhcp-build-validation.md`）が保存されるまで`NOT RUN`です。

## 完了の定義

次をすべて満たした時点で「構築・試験完了」とします。

- `dhcp-01`で`ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml`が`failed=0`で終了する（NFR-01 / DIT-01）
- 2回目の適用が`changed=0`になる（NFR-02 / DIT-01の2回目）
- クライアントVMで`dhclient`実行時に、DISCOVER/OFFER/REQUEST/ACKの4パケット（DORA）をtcpdumpで観測し、`192.168.50.100`〜`.200`の範囲でIPを取得する（DIT-02）
- [試験仕様書](06-test-specification.md)の必須31 ID（`DUT-01〜05`、`DIT-01〜11`、`DST-01〜06`、`DNW-01〜09`）がすべて`PASS`
- UFWでUDP 67の待受を払い出し対象interface（`dhcp_server_interface`）限定にし、`dhcpd.conf`の権限・AppArmorのenforceモード・SSH hardeningを確認する（DST-01〜04）
- 構築直前に、同一セグメントに想定外のDHCPサーバー（rogue DHCP）が存在しないことを確認した記録が残る（NFR-08 / DST-06 / DNW-09）
- `dhcpd.conf`とリースDBのバックアップ・復元手順を実施し、復元後に新規リースが正常に払い出されることとRTOを記録する（NFR-09 / DIT-11）
- 中央Prometheus（`monitor-01`）の`app_node_exporter_targets`へ`dhcp-01`を追加し、`up{host="dhcp-01"}=1`を確認する（NFR-13 / DIT-10）
- 未解決事項、ロールバック方法が引き渡し記録に残る
- 管理端末→`dhcp-01`、クライアントVM→`dhcp-01`の両方向で名前解決、経路、待受、DORA、UFWを確認し、実行出力を保存する
- [作業結果・引き渡し報告書](11-work-result-report.md)の計画対実績、試験集計、差異、残存リスク、受領判定を記入する
