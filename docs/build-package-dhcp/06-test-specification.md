# 試験仕様書・結果票

> 💡 **初めて読む方へ**: この文書は完成したかどうかを判定する「試験問題と模範解答」です。原本がなぜ常に `NOT RUN` のままなのかは[初心者ガイド](beginner-guide.md#06-試験仕様書結果票)で先に説明しています。

[要件定義書](00-requirements.md)の受け入れ条件を、再実行できるコマンドと期待結果へ展開した原本です。試験ID体系（DUT / DIT / DST / DNW）の正本は本書とし、他の文書（特に[ネットワーク実機検証手順](09-network-validation-procedure.md)）は本書のIDを参照するだけに留めます。

> ## この文書の読み方（先に読んでください）
>
> **下の表がすべて `NOT RUN` なのは、まだ何も試していないからではありません。**
> [Linux版試験仕様書・結果票](../build-package/06-test-specification.md)と同じく、これは
> 対象ホストが決まっていない段階の**空白の原本**です。`dhcp-01`に相当する検証用ホストを
> 用意するたびに複製して記入し、原本自体は後から上書きしません。
>
> Linux版・AD版には既に実測済みの証跡（[検証証跡台帳](../evidence/README.md)参照）への
> リンクがありますが、本書（DHCP版）には**現時点で1件もありません**。理由は次のとおりです。
>
> - 新規role `ansible/roles/dhcp_server/` と専用playbook `ansible/playbooks/dhcp.yml` は
>   すでに実装済みで、ローカルでの`ansible-lint --offline`（production profile）と
>   `ansible-playbook ... --syntax-check`は通過を確認しています。
> - しかし対象ホストへの実適用そのものが行われていないため、DORA
>   （DISCOVER/OFFER/REQUEST/ACKの4-way handshake）の実演、固定予約、プール枯渇、
>   リース永続化、監視統合などの構築・結合試験、およびセキュリティ試験・ネットワーク
>   実機検証は**1件も実行していません**。
>
> したがって DUT / DIT / DST / DNW のいずれのIDについても、結果欄は `NOT RUN` が唯一の
> 正しい値です。これは「Linux版より試験項目が緩い」ことを意味せず、単に「この構築案件が
> まだ実施段階に入っていない」ことを示しています。本パックはWindows版・AD版のような
> フェーズ1/フェーズ2の分割を採用していないため（[要件定義書](00-requirements.md)参照）、
> [Windows版試験仕様書・結果票](../build-package-windows/06-test-specification.md)にあるような
> 「一部IDは前提未実装によりBLOCKEDが前提」という区分もありません。全31 IDが等しく、
> 対象ホストの用意ができ次第そのまま実行できる状態にあります。
>
> ### この原本を埋めるには
>
> `dhcp-01`に相当する検証用ホストを1台用意し（[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)
> 参照）、[構築手順書](05-build-procedure.md)に沿って構築したうえで、本書の表と同じ試験IDに
> 対応する結果を記入します。記入した結果はこの原本を直接上書きせず、日付付きの証跡ファイル
> （例: `docs/evidence/YYYY-MM-DD-dhcp-build-validation.md`）へコピーして保存します。命名・
> 記録ルールは[検証証跡台帳](../evidence/README.md)に合わせます。実際にその日付のevidence
> ファイルが存在するようになるのは、対象ホストで試験を実施した後です。現時点ではまだ
> 1件も存在しないため、本書は空白の原本のまま置いています。
>
> ネットワーク実機検証（DNW-01〜09）の記入様式は
> [DHCP版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-dhcp.md)
> を使います。手順の詳細は[ネットワーク実機検証手順](09-network-validation-procedure.md)を
> 正本とします。

## 記録情報

| 項目 | 値 |
| --- | --- |
| 実施日時 | `NOT RUN` |
| 実施者 | `NOT RUN` |
| 環境 | `NOT RUN` |
| commit SHA | `NOT RUN` |
| OS / tool versions | `NOT RUN` |
| isc-dhcp-server バージョン | `NOT SET` |
| `dhcp_server_interface`（実機値） | `NOT SET` |

結果は `PASS / FAIL / BLOCKED / NOT RUN` のいずれかを記入します。初期値の `NOT RUN` は成功実績ではありません。

| 判定 | 意味 |
| --- | --- |
| `PASS` | 期待結果を実出力で確認し証跡への参照がある |
| `FAIL` | 実行したが一致しない |
| `BLOCKED` | 前提不足で実行できず理由と解除条件がある |
| `NOT RUN` | 未実行、成功実績として数えない |

設計値と実績値は必ず分けて記録し、未実施の実績値は `NOT SET` / `NOT RUN` / `NOT READY` のいずれかを使います。安易に `PASS` へ書き換えないでください。

## 単体・構成試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| DUT-01 | dhcpd.conf構文検査 | `sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf` | 構文エラーなし（exit 0） | NOT RUN | — |
| DUT-02 | Ansible構文チェック | `ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --syntax-check` | exit 0 | NOT RUN | — |
| DUT-03 | ansible-lint | `ansible-lint --offline`（`ansible/`配下） | production profileで0 failure | NOT RUN | — |
| DUT-04 | systemdユニット有効化 | `systemctl is-enabled isc-dhcp-server` | `enabled` | NOT RUN | — |
| DUT-05 | 成果物リンク | `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links` | README/docsの相対リンクがすべてリポジトリ内で解決 | NOT RUN | — |

DUT-01（構文検査）はisc-dhcp-serverがインストールされたホストでしか実行できませんが、DUT-02・
DUT-03・DUT-05はこのリポジトリのcheckout環境だけで対象ホストの有無に関係なく今すぐ実施できます。
実ホストが無いことを理由に放置せず、先に実施して構いません。

## 構築・結合試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| DIT-01 | 新規構築・冪等性 | `dhcp.yml`適用（1回目・2回目） | 1回目`failed=0`、2回目`changed=0` | NOT RUN | — |
| DIT-02 | DORA実測 | クライアントVMで`sudo dhclient -v <interface>` | `192.168.50.100`〜`.200`の範囲でIPを取得し、tcpdumpでDISCOVER/OFFER/REQUEST/ACKの4パケットを観測 | NOT RUN | — |
| DIT-03 | 固定予約 | 登録済みMACアドレスのクライアントで`dhclient`実行 | 常に同一の予約IPを取得 | NOT RUN | — |
| DIT-04 | プール枯渇 | プール内の全アドレスを払い出した状態で新規クライアントが要求 | 新規クライアントはDHCPNAKまたは無応答（新規リースが払い出されない） | NOT RUN | — |
| DIT-05 | リース更新 | 検証用に短いリース時間（例: `dhcp_server_default_lease_time: 120`等）を一時適用し、T1到達時のunicast DHCPREQUEST（RENEW）とT2到達時のbroadcast DHCPREQUEST（REBIND）をtcpdumpで観測 | T1到達時はリース元サーバーへの2パケット（DHCPREQUEST→DHCPACK）のunicast RENEWで、新たなDISCOVER/OFFERを介さずリース期限が延長される。REBINDまで進んだ場合はDHCPREQUESTがbroadcastで送出される | NOT RUN | — |
| DIT-06 | サービス再起動後のリース永続化 | `sudo systemctl restart isc-dhcp-server`後に`/var/lib/dhcp/dhcpd.leases`を確認 | 既存のリース内容が保持されている | NOT RUN | — |
| DIT-07 | リース解放 | クライアントで`sudo dhclient -r <interface>` | DHCPRELEASE送出後、同一IPが即座に他クライアントへ払い出し可能になる | NOT RUN | — |
| DIT-08 | オプション配布 | クライアントで`ip route`、`resolvectl status`（または`cat /etc/resolv.conf`） | gateway・DNS・ドメイン名が設計値と一致 | NOT RUN | — |
| DIT-09 | サービス停止復旧 | `sudo systemctl stop isc-dhcp-server`後の検知・復旧 | 検知・自動復旧または手動復旧・正常化までの時間（RTO）を記録 | NOT RUN | — |
| DIT-10 | 監視統合 | `app_node_exporter_targets`へ`dhcp-01`を追加し`site.yml`再適用後、Prometheusで確認 | `up{host="dhcp-01"}=1` | NOT RUN | — |
| DIT-11 | バックアップ・復元 | `dhcpd.conf`とリースDBのバックアップ取得後、復元してDORAを再実施 | 復元後に新規リースが正常に払い出される | NOT RUN | — |

DIT-02・DIT-03・DIT-07・DIT-08・DIT-09は、クライアント役のVMをもう1台用意しないと実施できません。
[立ち上げ環境の選択肢](10-host-bringup-and-acceptance.md)で`dhcp-01`とクライアントVMを同一セグメントに
置く構成を先に組んでください。

## セキュリティ試験

| ID | 試験 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| DST-01 | UFW | `sudo ufw status verbose` | UDP 67は`192.168.50.0/24`のみ許可、他ネットワークへの許可がない | NOT RUN | — |
| DST-02 | ファイル権限 | `stat -c '%U:%G %a' /etc/dhcp/dhcpd.conf` | `root:root`、`644`以下 | NOT RUN | — |
| DST-03 | AppArmor | `sudo aa-status \| grep dhcpd` | `usr.sbin.dhcpd`がenforceモード | NOT RUN | — |
| DST-04 | SSH hardening | `sudo sshd -T \| grep -E 'permitrootlogin\|passwordauthentication'` | `permitrootlogin no`、`passwordauthentication no` | NOT RUN | — |
| DST-05 | 監査ログ | `journalctl -u isc-dhcp-server --since today` | リース割当・解放イベントが記録されている | NOT RUN | — |
| DST-06 | rogue DHCP確認 | 構築直前に`sudo nmap --script broadcast-dhcp-discover`相当の確認、またはクライアントで応答元DHCPサーバーのIPを確認 | 応答するDHCPサーバーが1台もない（`dhcp-01`にisc-dhcp-serverをまだ導入していない状態） | NOT RUN | — |

DST-06はNFR-08の受け入れ確認でもあります。構築直前（`dhcp.yml`適用前、isc-dhcp-serverが
まだ`dhcp-01`に存在しない時点）に実施する試験のため、期待結果は「応答するDHCPサーバーが
1台もないこと」です。構築後にまとめて実施しようとすると同一セグメントの状態がすでに変わって
しまい、意味を持ちません。実施タイミングを他のDST/DITと混同しないでください。

## ネットワーク実機検証

base Linux版の[NW-01〜09](../build-package/09-network-validation-procedure.md)に対応するDHCP版のIDです。
詳しい手順は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とし、本書はID・操作・
期待結果の一覧だけを保持します。

| ID | 確認対象 | 操作 | 期待結果 | 結果 | 証跡 |
| --- | --- | --- | --- | --- | --- |
| DNW-01 | interface / IP / CIDR | `ip -br addr` | 設計値と一致 | NOT RUN | — |
| DNW-02 | route / gateway | `ip route` | 想定gateway/device/sourceと一致 | NOT RUN | — |
| DNW-03 | DNS名前解決（`dhcp-01`自身） | `dig`、`getent hosts`、`resolvectl` | 想定recordとresolverが設計どおり | NOT RUN | — |
| DNW-04 | ICMP疎通 | `ping` | 方針どおりの疎通または遮断 | NOT RUN | — |
| DNW-05 | 待受port（UDP 67、TCP 22、TCP 9100） | `ss -lntup` / `ss -lunp` | 設計どおりの待受のみ | NOT RUN | — |
| DNW-06 | DORAのpacket capture | `tcpdump -nn -i <interface> udp port 67 or port 68` | DISCOVER/OFFER/REQUEST/ACKの4パケットを観測 | NOT RUN | — |
| DNW-07 | UFWとkernel rule | `sudo ufw status verbose`、`nft` / `iptables` | UDP 67は`192.168.50.0/24`限定、他は非公開 | NOT RUN | — |
| DNW-08 | クライアント側から見たend-to-end | クライアントVMで`sudo dhclient -v <interface>` | 設計どおりのプール範囲でリースを取得し、gateway・DNS・ドメイン名も一致 | NOT RUN | — |
| DNW-09 | rogue DHCP非存在の実機確認 | `sudo nmap --script broadcast-dhcp-discover`相当、または応答元DHCPサーバーIPの確認 | 応答するDHCPサーバーが`dhcp-01`のみ | NOT RUN | — |

DNW-01〜09の記入は、原本のこの表に直接書き込まず、
[DHCP版ネットワーク結果票テンプレート](../evidence/templates/network-host-validation-dhcp.md)を
`docs/evidence/YYYY-MM-DD-network-host-validation-dhcp.md`へコピーして使います。DNW-09は
DST-06のネットワーク版で、同じ観点（同一セグメントに応答するDHCPサーバーが何台あるか）を
異なるタイミングで確認するものです。DST-06は構築直前（isc-dhcp-server未導入）の確認で期待結果は
「1台もない」、DNW-09は構築後の実機環境での確認で期待結果は「`dhcp-01`の1台のみ」です。
期待結果自体は異なるため、片方の結果でもう片方を代替しません。

## 終了判定

- 必須ID: DUT-01〜05、DIT-01〜11、DST-01〜06、DNW-01〜09（合計31 ID）
- `FAIL`または`BLOCKED`が1件でもあれば構築完了としません。
- 必須IDに`NOT RUN`が残る場合も構築完了としません。
- 結果はこの原本を直接上書きせず、`docs/evidence/YYYY-MM-DD-dhcp-build-validation.md`のような
  日付付きevidenceへコピーして保存します。命名・記録ルールは[検証証跡台帳](../evidence/README.md)に
  合わせます。実際の日付は現時点では存在しないため、原本はすべて`NOT RUN`のまま作成しています。

構築案件全体の完了は、上記31 IDがすべて`PASS`し、[作業結果・引き渡し報告書](11-work-result-report.md)へ
計画対実績・差異・残存リスクが記録された状態を指します。資料（本書を含む設計・手順書一式）が揃った
ことと、構築案件が完了したことは別の状態です。現時点の結果は[検証証跡台帳](../evidence/README.md)を
参照してください。
