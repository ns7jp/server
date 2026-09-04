# 要件定義書

> 💡 **初めて読む方へ**: この文書は「何を作るか」「完成の合格基準」を先に決める文書です。`NFR`（非機能要件）や`DIT-xx`のような略語につまずいたら、先に[案件パック 初心者ガイド](beginner-guide.md#00-要件定義書)を確認してください。

## 1. 文書の位置づけ

本パックは、検証用LANセグメント(`192.168.50.0/24`)向けに新規のDHCPv4サーバー(論理ホスト名`dhcp-01`)を構築し、運用担当者へ引き渡す案件(案件ID`SM-DHCP-001`)として扱います。既存の監視基盤([Linux版パック](../build-package/README.md)、案件ID`SM-LAB-001`)、[Windows版パック](../build-package-windows/README.md)(`SM-WIN-001`)、[AD版パック](../build-package-ad/README.md)(`SM-AD-001`)、[Zabbix版パック](../build-package-zabbix/README.md)(`SM-ZBX-001`)とは独立した新規構築案件です。本書は要求と受け入れ条件を定義し、設計値の正本は後続資料、実行結果の正本は[検証証跡台帳](../evidence/README.md)に分離します。

本書に「作成済み」「role実装済み」と書いてあっても、実ホストでの構築・試験完了を意味しません。受け入れ可否は[試験仕様書・結果票](06-test-specification.md)の結果で判定します。新規role `ansible/roles/dhcp_server/` と専用playbook `ansible/playbooks/dhcp.yml` はすでに実装済みで、ローカルでの`ansible-lint --offline`(production profile)とAnsible構文チェックは通過を確認していますが、対象ホストへの実適用とDORA(DISCOVER/OFFER/REQUEST/ACKの4-way handshake)の実演は`NOT RUN`です。この「roleは実装済みで静的チェックはPASS、実ホスト適用は`NOT RUN`」という中間状態は、[Windows版パック](../build-package-windows/00-requirements.md)・[AD版パック](../build-package-ad/00-requirements.md)が抱える「Windows対応roleそのものが未実装」という制約とも、[Zabbixパック](../build-package-zabbix/00-requirements.md)の「Ansible role化は未実装」という状態とも異なります。

構築は、Windows版・AD版パックのような「フェーズ1(ホスト単体構築)」「フェーズ2(中央監視統合)」の2段階分割を採用しません。`dhcp-01`はLinuxホストのため、既存の中央Prometheus(`monitor-01`)の`app_node_exporter_targets`へそのまま1行追加でき、監視統合のために新たなネットワーク到達性やAnsible roleを別途用意する必要がないためです。したがって本パックは、[Linux版パック](../build-package/00-requirements.md)と同じ単一フェーズの工程ゲート(G0〜G5)で完結します。

### DHCPデーモンの選定について(技術選定トレードオフ)

DHCPデーモンには、Ubuntuのapt packageとして提供される**isc-dhcp-server**(パッケージ名・サービス名とも`isc-dhcp-server`)を採用します。ここで正直に明記しておくべき事実として、開発元のISCは2022年にisc-dhcpを**EOL(開発終了)**とし、後継として**Kea DHCP**(`isc-kea-dhcp4-server`、JSON形式の設定)を推奨しています。それでも本パックがisc-dhcp-serverを選ぶ理由は次のとおりです。

1. 設定ファイル(`dhcpd.conf`)がブロック構文で、JSON中心のKeaより初心者にとって読み書きしやすいこと。
2. 国内の入門書・資格教材(LPIC等)や既存の小規模DHCP運用で、今なお広く使われている実務知識であること。
3. Ubuntu 24.04(noble)のuniverseリポジトリに`isc-dhcp-server`パッケージが存在する前提で設計していますが、この前提は[構築手順書](05-build-procedure.md)で`apt-cache policy isc-dhcp-server`により必ず実機確認します。パッケージが存在しない場合はKea DHCPへの切替が必要になります。
4. Keaへの移行は対象外ではなく、[発展的な設計・将来構想](01-basic-design.md)として次のステップに明記します。

この選定トレードオフの説明は、[Zabbixパック](../build-package-zabbix/01-basic-design.md)が「なぜ既存Prometheusと統合しないか」を説明しているのと同じ位置づけの、正直な設計判断として書いています。isc-dhcp-serverがEOLであるという事実そのものは、隠さずに[基本設計書](01-basic-design.md)にも明記します。

## 2. 案件概要

| 項目 | 内容 |
| --- | --- |
| 案件ID | `SM-DHCP-001` |
| 利用者 | DHCPサーバーを構築・運用する担当者 |
| 対象環境 | Ubuntu Server 24.04 LTS、検証用VM 1台、論理ホスト名`dhcp-01` |
| 構築対象 | isc-dhcp-serverによる、検証用LANセグメント(`192.168.50.0/24`)向けのDHCPv4サーバー新規構築 |
| 構築方式 | 新規Ansible role `dhcp_server`(`ansible/roles/dhcp_server/`) + 専用playbook `ansible/playbooks/dhcp.yml`。既存の`common` roleでOS基盤を整えたうえで適用する |
| 提供機能 | DHCPv4動的リース払い出し(DORA)、固定IP予約(host reservation)、gateway・DNS・ドメイン名オプションの配布、リースの永続化・更新(RENEW/REBIND)・明示的解放(DHCPRELEASE)、プール枯渇時の安全な失敗、サービス停止の検知と復旧、UFW/AppArmorによるセキュリティ、中央Prometheusへの監視統合、`dhcpd.conf`とリースDBのバックアップ・復元 |
| 引き渡し単位 | 設計書、パラメータシート、構築手順、試験結果、作業結果報告 |
| 完了判定 | 必須試験(`DUT`/`DIT`/`DST`/`DNW`、合計31 ID)がすべて`PASS`し、計画対実績・差異・未解決事項・残存リスクが作業結果報告と受領記録に記載済み |

## 3. 機能要件

| ID | 要件 | 受け入れ確認 | 実装・設計先 |
| --- | --- | --- | --- |
| FR-01 | 運用者がSSH経由で`dhcp-01`を管理できること | DIT-01 | [構築手順書](05-build-procedure.md) |
| FR-02 | isc-dhcp-serverが`192.168.50.0/24`向けに新規リースを払い出せること(DISCOVER→OFFER→REQUEST→ACKの4-way handshake、通称DORA) | DIT-02 | [構築手順書](05-build-procedure.md) |
| FR-03 | 事前登録したMACアドレスへ、常に同一の固定IP(host reservation)を払い出せること | DIT-03 | [詳細設計書](02-detailed-design.md) |
| FR-04 | 動的プール枯渇時に新規クライアントへリースを払い出さず、安全に失敗すること(DHCPNAKまたは無応答) | DIT-04 | [詳細設計書](02-detailed-design.md) |
| FR-05 | クライアントがリース満了前に更新(RENEW/REBIND)でき、サービス再起動後もリースDBの内容が保持されること | DIT-05、DIT-06 | [構築手順書](05-build-procedure.md) |
| FR-06 | クライアントがDHCPRELEASEで明示的にリースを解放でき、解放されたIPがプール内で再割当て可能な状態（`binding state free;`）に遷移すること | DIT-07 | [構築手順書](05-build-procedure.md) |
| FR-07 | 払い出しにgateway・DNS・ドメイン名のオプションが含まれ、クライアント側で設計値どおりに反映されること | DIT-08 | [パラメータシート](03-parameter-sheet.md) |
| FR-08 | isc-dhcp-serverサービスの停止を検知し、復旧と正常性確認までの時間を記録できること | DIT-09 | [構築手順書](05-build-procedure.md) |
| FR-09 | 中央Prometheus(`monitor-01`)が`dhcp-01`のnode_exporterをscrapeできること | DIT-10 | `ansible/roles/app/defaults/main.yml`(`app_node_exporter_targets`) |
| FR-10 | 管理端末から`dhcp-01`までの名前解決、経路、待受、UFWを確認できること | DNW-01〜09 | [ネットワーク実機検証手順](09-network-validation-procedure.md) |

## 4. 非機能要件

| ID | 分類 | 要件 | 受け入れ確認 |
| --- | --- | --- | --- |
| NFR-01 | 再現性 | 未構築の対象VMへ`dhcp.yml`を適用し、エラーなく完了すること | DIT-01 |
| NFR-02 | 冪等性 | `dhcp.yml`の2回目適用が`changed=0`になること | DIT-01(2回目) |
| NFR-03 | セキュリティ | UFWでUDP 67の待受を払い出し対象セグメント側interface（`dhcp_server_interface`）限定にし、それ以外のネットワークへ非公開とすること | DST-01 |
| NFR-04 | セキュリティ | `/etc/dhcp/dhcpd.conf`の所有者・権限が`root:root`かつ`0644`以下であること | DST-02 |
| NFR-05 | セキュリティ | AppArmorプロファイル`usr.sbin.dhcpd`がenforceモードで有効であること | DST-03 |
| NFR-06 | セキュリティ | SSHはcommon roleの既定強化(root禁止、パスワード認証禁止)を継承すること | DST-04 |
| NFR-07 | 監査性 | リースの割当・解放イベントがsyslog/journalへ記録されること | DST-05 |
| NFR-08 | セキュリティ | 構築直前に、同一セグメントに想定外のDHCPサーバー(rogue DHCP)が存在しないことを確認した記録があること | DST-06 |
| NFR-09 | 復旧性 | `dhcpd.conf`とリースDBのバックアップ・復元手順があり、RTOを記録すること | DIT-11 |
| NFR-10 | 保守性 | プール拡張・固定IP追加などの変更時、Go/No-Go条件とロールバック手順を記録すること | [変更・ロールバック計画](08-change-rollback-plan.md) |
| NFR-11 | 追跡性 | 実行日時、環境、コマンド、実出力、判定を証跡に残すこと | 全必須試験 |
| NFR-12 | 完了管理 | 計画対実績、試験集計、差異、残存リスクを1件の報告へまとめること | [作業結果・引き渡し報告書](11-work-result-report.md) |
| NFR-13 | 監視統合 | node_exporterを中央Prometheusへ登録し、`up=1`を確認すること | DIT-10 |

## 5. 制約と対象外

- 単一DHCPサーバー(`dhcp-01`1台)の検証用構成であり、ISC failoverプロトコルによる冗長化・複数DHCPサーバー構成は対象外です。将来構想として[基本設計書](01-basic-design.md)に記す発展構成としてのみ言及します。
- DHCPv6、IPv6ステートレス自動設定(SLAAC)併用は対象外です([基本設計書](01-basic-design.md)の発展構想でのみ言及)。
- DHCPリレー(`dhcrelay`)を使った複数セグメントへの配信は対象外です。単一セグメント内でのDHCPサーバー直接配置が本パックの基準構成であり、複数セグメントへの中継は[基本設計書](01-basic-design.md)の発展構想でのみ言及します。
- Dynamic DNS(DDNS)連携、DHCP snooping/Dynamic ARP Inspectionなどスイッチ側の対策は対象外です。`dhcpd.conf`では`ddns-update-style none;`を明記し、スイッチ側の対策は運用者の別管轄と位置づけます。
- Kea DHCPへの移行は対象外です([基本設計書](01-basic-design.md)の発展構想でのみ言及)。
- 24時間有人監視、複数拠点、実組織の個人情報、商用SLAは対象外です。
- クラウド(AWS等)でのDHCP構築は、[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)に示す選択肢の一つに過ぎず、`apply`/`destroy`相当の実行証跡がない限り本案件の構築実績には含めません。

## 6. 前提条件

- 管理端末からSSH公開鍵認証で対象VMへ接続でき、sudo権限を持つこと。
- 対象VMに、払い出し対象セグメント(`192.168.50.0/24`)へ実際に接続されたNICが最低1枚あること(interface名は環境依存のため、`ip -br link`で実機確認してから`dhcp_server_interface`変数に設定する)。
- 対象IP、作業時間帯、ロールバック条件が作業前に確定していること。
- リポジトリの対象commit SHAを固定できること。
- 構築直前に、同一セグメントに他のDHCPサーバーが存在しないことを確認できること(NFR-08)。

## 7. 要件トレーサビリティと判定

詳細な操作・期待結果は[試験仕様書・結果票](06-test-specification.md)を正本とします。結果はその原本へ直接記入せず、日付付きのevidenceへコピーして保存します。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し、証跡への参照がある |
| `FAIL` | 実行したが期待結果と一致しない |
| `BLOCKED` | 前提不足で実行できず、理由と解除条件がある |
| `NOT RUN` | 未実行。成功実績として数えない |

必須IDは`DUT-01〜05`、`DIT-01〜11`、`DST-01〜06`、`DNW-01〜09`の合計31 IDです。`FAIL`または`BLOCKED`が1件でもあれば構築完了とはしません。必須IDに`NOT RUN`が残る場合も同様に構築完了とはしません。設計値と実績値は必ず分けて記録し、未実施の実績値は`NOT SET`/`NOT RUN`/`NOT READY`のいずれかを使います。安易に`PASS`へ書き換えないでください。

現時点の結果は[検証証跡台帳](../evidence/README.md)を参照してください。資料が揃ったことと、構築案件が完了したことは別の状態です。
