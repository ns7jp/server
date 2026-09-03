# ネットワーク実機検証手順

> 💡 **初めて読む方へ**: この文書は実機のネットワークが設計どおりに動いているかを、1項目ずつ確認する手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#09-ネットワーク実機検証手順)を参照してください。

## 1. 目的と証跡の境界

管理端末から`dhcp-01`、そしてDORA（DISCOVER/OFFER/REQUEST/ACK）を実際に観測するための**クライアント検証VM**までを対象に、IP/CIDR、名前解決、経路、ICMP疎通、待受port、DORAのpacket capture、UFW、クライアント側から見たend-to-end、rogue DHCP非存在を順に確認します。

DNW-01〜09の試験ID定義、必須ID判定、終了判定は[試験仕様書・結果票](06-test-specification.md)を正本とし、本書はその実行手順の詳細だけを扱います。値の正本（セグメント・プール・予約帯・公開ポート）は[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)です。

DHCPのDORA実演にはL2ブロードキャストが必要です。既存の[二セグメント障害ラボ](../../labs/network-troubleshooting/README.md)（Docker上の`172.28.10.0/24` / `172.28.20.0/24`）はDockerの既定bridgeネットワークがコンテナのIPをIPAMで払い出すため、コンテナ内でdhcpdへ実際にDISCOVERを送る構成には別途の作業が要り、素直には成立しません。そのため本パックはこのラボとは独立に、**VM/実機での実演を正本**とします。`dhcp-01`とクライアント検証VMを同一セグメントへ置く具体的な立ち上げ手順は[立ち上げ環境・受け入れ](10-host-bringup-and-acceptance.md)を参照してください。この立ち上げが完了していないと、DNW-06・DNW-08・DNW-09は実施できません。

対象hostの日付付き結果票（[DHCP実ホスト ネットワーク検証結果票テンプレート](../evidence/templates/network-host-validation-dhcp.md)からコピーして作成）が無ければ、引き渡し判定では`NOT RUN`を維持します。本パックはまだ新規に書き起こしている段階で、実ホストへの適用実績そのものが無いため、本書に基づく実施結果は現時点で一件も存在しません。

DNW-09は、[試験仕様書](06-test-specification.md)のDST-06（構築直前の確認）と同じ観点を、構築完了後の実機環境で改めて確認するものです。DST-06は`dhcp-01`にisc-dhcp-serverがまだ入っていない状態での確認、DNW-09は`dhcp-01`が稼働している状態での確認であり、目的は同じでも対象の状態が異なります。片方の結果でもう片方を代替しません。

## 2. 安全条件

- 読み取りコマンドを中心に実施し、UFWルール、route、interfaceを本手順から変更しません。
- クライアント検証VM上での`dhclient`実行（DNW-06、DNW-08、DNW-09）は、専用に用意したクライアント検証VMの、指定したinterfaceに限定します。同一セグメント上の他の機器へリース取得を試みません。
- `tcpdump`はpacket headerだけを最大20 packet、30秒以内で取得します。`-A` / `-X`は使用しません。DHCPオプションには通常認証情報を含みませんが、ホスト名やベンダー識別子などクライアントを特定しうる情報が含まれることがあるため、共有前に内容を確認します。
- SSHを許可するUFWルールを削除・再読込しません。
- 管理端末IP、対象IP、MAC address、hostnameは共有前にマスクします。特に固定IP予約（host reservation）のMAC addressは、実際のクライアント機器を特定しうる情報として扱います。
- rogue DHCP確認（DNW-09）は観測に徹し、応答したサーバーへ追加のリース要求を意図的に繰り返す、停止操作を試みるなど、対象へ影響を与える操作はこの手順の範囲外とします。異常を見つけた場合は記録して報告し、対応は別途[構築手順書](05-build-procedure.md)3.2節の切り分けに従います。

## 3. 事前準備

`dhcp-01`に`iproute2`、`iputils-ping`、`dnsutils`、`ss`（`iproute2`に同梱）、`tcpdump`、`ufw`があることを確認します。クライアント検証VMには加えて`isc-dhcp-client`（`dhclient`）と、可能であれば`nmap`があることを確認します。管理端末の値を実環境に合わせて設定します。

```bash
TARGET_HOST=dhcp-01
TARGET_IP='192.168.50.5'
TARGET_FQDN='dhcp-01.lab.example.test'
MANAGEMENT_IP='192.0.2.30'
CLIENT_VM=<クライアント検証VMへのSSH先>
CLIENT_IF=<クライアント検証VM側でip -br linkにより確認したinterface名>
DHCP_IF=<dhcp-01側の払い出し対象セグメント側interface名。dhcp_server_interface変数と同じ値>

date --iso-8601=seconds
git rev-parse HEAD
ssh "$TARGET_HOST" 'uname -a; command -v ip ping dig getent ss ufw tcpdump dhcpd'
ssh "$CLIENT_VM" 'uname -a; command -v ip dhclient tcpdump'
ssh "$CLIENT_VM" 'command -v nmap || echo "nmap not installed (DNW-09 fallback手順を使用)"'
```

`192.0.2.30`は[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)と同じ、管理端末IPの記入例です。実行前に`TARGET_FQDN`、`MANAGEMENT_IP`、`CLIENT_VM`、`CLIENT_IF`、`DHCP_IF`を実環境の値へ置き換えます。`DHCP_IF`は[構築手順書](05-build-procedure.md)2節で`dhcp_server_interface`変数へ設定した値と必ず一致させます。

`dhcp-01`自身のFQDNは[パラメータシート](03-parameter-sheet.md)のとおり「環境ごとに決定」で、現時点では`NOT SET`です。上記の`dhcp-01.lab.example.test`は記入例であり、実環境で対応するDNS record（正引き）を作っていない場合は、DNW-03の判定を`NOT APPLICABLE`とし、理由を結果票へ書きます。`option domain-name-servers`として払い出す`192.168.50.1`は、あくまでクライアント向けの値であり、`dhcp-01`自身の名前解決を担うDNSサーバーがそのセグメントに存在することを意味しません。

コマンドの欠落は`FAIL`ではなく`BLOCKED`として前提パッケージを整備してから再実行します。クライアント検証VMの用意そのものができていない場合は、[立ち上げ環境・受け入れ](10-host-bringup-and-acceptance.md)を先に完了させ、DNW-06・DNW-08・DNW-09は`BLOCKED`のまま先送りします。

結果の記入先は[DHCP実ホスト ネットワーク検証結果票テンプレート](../evidence/templates/network-host-validation-dhcp.md)です。

## 4. DNW-01: interface、IP、CIDR

```bash
ssh "$TARGET_HOST" 'ip -br link; ip -br addr'
```

確認点:

- `DHCP_IF`が`UP`
- `DHCP_IF`のIPアドレスが`192.168.50.5/24`（動的払い出しプールの対象外として除外している固定IP）と一致
- `dhcp-01`は払い出し対象セグメントとSSH管理を同一interfaceで兼用する単一NIC構成が前提のため、意図しない追加のグローバルアドレスや、想定外のセグメントに属するアドレスが無いこと
- loopback `127.0.0.1/8`が存在
- ここで確認したinterface名が、[構築手順書](05-build-procedure.md)2節で`dhcp_server_interface`変数へ設定した値（`DHCP_IF`）と一致していること。両者が食い違っていると、role適用は成功していてもDHCPは想定と別のinterfaceで待受してしまいます

## 5. DNW-02: routeとgateway

```bash
ssh "$TARGET_HOST" 'ip route show table main'
ssh "$TARGET_HOST" "ip route get $MANAGEMENT_IP"
ssh "$TARGET_HOST" 'ip route get 192.168.50.1'
```

確認点:

- default routeの`gateway`が`192.168.50.1`（[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)のとおり）、`dev`が`DHCP_IF`
- `dhcp-01`は単一NIC構成のため、管理端末（`MANAGEMENT_IP`）宛の応答も同じ`DHCP_IF`・同じdefault gateway経由で戻る設計です。`ip route get $MANAGEMENT_IP`の出力でも`dev`と`src`が`DHCP_IF`・`192.168.50.5`になっていることを確認します
- `ip route get 192.168.50.1`の`src`が`192.168.50.5`

外向き通信を許可しない閉域環境では、`1.1.1.1`（クライアントへ配布するDNSフォールバック値、`dhcp-01`自身の到達性確認としては必須ではない）への到達成功は要求しません。ここではあくまでroute選択の出力を確認し、閉域という設計理由を記録します。

## 6. DNW-03: DNS名前解決（`dhcp-01`自身）

管理端末と`dhcp-01`自身の両方から確認します。

```bash
dig +time=2 +tries=1 "$TARGET_FQDN" A
getent ahostsv4 "$TARGET_FQDN"
ssh "$TARGET_HOST" "dig +time=2 +tries=1 $TARGET_FQDN A"
ssh "$TARGET_HOST" "getent ahostsv4 $TARGET_FQDN"
ssh "$TARGET_HOST" 'resolvectl status || cat /etc/resolv.conf'
```

確認点:

- `dig`の`status`、answer、問い合わせ先DNS
- `getent`の結果と`dig`の結果が一致
- `resolvectl status`（またはフォールバックの`/etc/resolv.conf`）で、`dhcp-01`自身が問い合わせに使うresolverが設計どおりであること

3節で述べたとおり、本パックの基準構成（VirtualBoxのHost-Only/Internalネットワーク、[立ち上げ環境・受け入れ](10-host-bringup-and-acceptance.md)）には、`dhcp-01`自身のFQDNを正引きできる権威DNSサーバーが前提として含まれていません。`dig`が`NXDOMAIN`または無応答になる場合、それ自体はDHCP機能（FR-02〜FR-08）の欠陥ではなく、この検証環境にDNSインフラが無いことの表れです。その場合はDNW-03を`NOT APPLICABLE`と判定し、理由（DNSインフラ未構築、または`/etc/hosts`等の代替手段で管理端末からの名前解決を代替している旨）を結果票に記録します。組織の既存DNSへ`dhcp-01`のAレコードを登録済みの環境では、通常どおり`PASS` / `FAIL`で判定します。

## 7. DNW-04: ICMP疎通

```bash
ping -c 4 -W 2 "$TARGET_IP"
ssh "$TARGET_HOST" 'ping -c 4 -W 2 127.0.0.1'
ssh "$TARGET_HOST" 'ping -c 4 -W 2 192.168.50.1'
```

ICMPをFW方針で遮断する環境では、ping失敗だけでサービス障害と判定しません。packet lossと方針を記録し、待受port・DORAの試験（DNW-05〜08）へ進みます。

## 8. DNW-05: 待受port（UDP 67、TCP 22、TCP 9100）

```bash
ssh "$TARGET_HOST" 'sudo ss -lunp | grep -E ":67\b"'
ssh "$TARGET_HOST" 'sudo ss -lntup'
ssh "$TARGET_HOST" "sudo ss -lntp 'sport = :9100'"
```

確認点:

- `dhcpd`プロセスがUDP 67をbindしている。bind interfaceは[詳細設計書](02-detailed-design.md)のとおり`/etc/default/isc-dhcp-server`の`INTERFACESv4`で`DHCP_IF`を明示する設計のため、待受interfaceが空欄（全interface待受）になっていないこと
- TCP 22（SSH）のlistenerが存在する。repository既定ではUFWにより全送信元へ`LIMIT`（総当たり抑止）で、CIDR制限そのものはproduction受入で追加する運用（送信元制限の確認はDNW-07で行う）
- TCP 9100（`prometheus-node-exporter`パッケージによるnode_exporter）のlistenerが存在する。node_exporterはbindそのものは既定どおり全interfaceに対して行い、アクセス制御はUFW側（中央Prometheus host`monitor-01`のIPのみ許可）に委ねる設計です（[詳細設計書](02-detailed-design.md)アクセス制御節）。bind自体の絞り込みが無いことは、この設計上`FAIL`ではありません
- 67/udp、22/tcp、9100/tcp以外に、想定しない`0.0.0.0` / `[::]`のlistenerが無いこと

`ss`の process情報にはPIDとuserが含まれます。共有用evidenceでは必要な行だけ残します。

## 9. DNW-06: DORAのpacket capture

[構築手順書](05-build-procedure.md)5節の「DORA実機確認」では、クライアント検証VM側（`CLIENT_IF`）でpacket captureを行う簡易確認をすでに実施しています。本項目（DNW-06）は、`dhcp-01`側（`DHCP_IF`）でcaptureし、**サーバー自身が受信・送信するDORAの4パケット**を確認する、独立した観点の正式な確認です。クライアント側の観測とサーバー側の観測が両方揃って初めて、経路上のどこにも欠落が無いことを言えます。

端末A（`dhcp-01`への1つ目のSSHセッション。先にcaptureを開始します）:

```bash
ssh -t "$TARGET_HOST" \
  "sudo timeout 30 tcpdump -nn -i $DHCP_IF -c 20 'udp port 67 or port 68'"
```

端末B（クライアント検証VMへのSSHセッション。captureが動いている間に実行します）:

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
```

確認点:

- 端末Aの`tcpdump`出力に、`DHCPDISCOVER`（送信元`0.0.0.0.68` → 宛先`255.255.255.255.67`）、`DHCPOFFER`（`192.168.50.5.67` → `255.255.255.255.68`またはクライアントの割当予定IP宛）、`DHCPREQUEST`、`DHCPACK`の4パケットが順に観測される
- 取得したIPアドレスが動的払い出しプール`192.168.50.100`〜`.200`の範囲内（固定予約MACの場合は該当する予約IP）
- captureが30秒以内に完了し、`-c 20`の上限内に収まる（収まらない場合はブロードキャストの多い環境である可能性があり、`-c`の値を見直します）

確認後、クライアント検証VM側のテストリースを明示的に解放します（後始末、DNW-08・DNW-09の前提もクリアにします）。

```bash
ssh "$CLIENT_VM" "sudo dhclient -r $CLIENT_IF"
```

DISCOVERへの応答（OFFER）が観測できない場合は、13節の切り分け表に従い、サービス状態・bind interface・UFWの順で確認します。

## 10. DNW-07: UFWとkernel rule

```bash
ssh "$TARGET_HOST" 'sudo ufw status verbose'
ssh "$TARGET_HOST" 'sudo ufw status numbered'
ssh "$TARGET_HOST" 'sudo nft list ruleset || sudo iptables -S'
```

確認点:

- `Status: active`
- default incomingが`deny`
- 67/udpの許可送信元が`192.168.50.0/24`のみで、他ネットワークへの許可が無い（NFR-03、DST-01のネットワーク版）
- 9100/tcpの許可送信元が中央Prometheus host（`monitor-01`）のIPのみ
- 22/tcpは repository既定で全送信元へ`LIMIT`。production受入では上流FW/VPNまたはsource指定UFW ruleにより、許可元が承認済みの管理元CIDRだけであること
- 上記以外の外部向けallowルールが無い
- クラウド環境で構築する場合は、security group / NACLとUFWの両方を別途採録します（本パックの基準構成はVM/実機であり、クラウドは対象外です。[要件定義書](00-requirements.md)6章参照）

## 11. DNW-08: クライアント側から見たend-to-end

クライアント検証VMから実際に`dhclient`を実行し、DHCPオプション（gateway・DNS・ドメイン名）まで含めて設計値どおり反映されることを確認します（FR-07、DIT-08のネットワーク版）。

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
ssh "$CLIENT_VM" 'ip -br addr'
ssh "$CLIENT_VM" 'ip route'
ssh "$CLIENT_VM" 'resolvectl status || cat /etc/resolv.conf'
```

確認点:

- `dhclient -v`ログに`DHCPDISCOVER` → `DHCPOFFER` → `DHCPREQUEST` → `DHCPACK`の順で出力される
- 取得したIPアドレスが動的払い出しプール`192.168.50.100`〜`.200`の範囲内。固定IP予約（`dhcp_server_reservations`）を登録済みのMACアドレスで実行した場合は、常に同一の予約IP（`192.168.50.10`〜`.49`の範囲）が払い出される
- `ip route`のdefault gatewayが`192.168.50.1`
- DNSサーバーが`192.168.50.1`と`1.1.1.1`（閉域網でフォールバックを配布しない設計にしている場合は`192.168.50.1`のみ）
- ドメイン名が`lab.example.test`

確認後、テストリースを解放します。

```bash
ssh "$CLIENT_VM" "sudo dhclient -r $CLIENT_IF"
```

リースが取得できない場合は、DNW-05（listener）・DNW-06（packet到達）・DNW-07（UFW）の結果と突き合わせ、13節の切り分け順で原因を分離します。

## 12. DNW-09: rogue DHCP非存在の実機確認

[試験仕様書](06-test-specification.md)のDST-06は、`dhcp-01`にisc-dhcp-serverをまだ導入していない構築直前の状態で「応答するDHCPサーバーが1台も無いこと」を確認する試験です。DNW-09はこれとは別に、`dhcp-01`が稼働している構築完了後の状態で「応答するDHCPサーバーが`dhcp-01`（`192.168.50.5`）1台だけであること」を実機で確認します。

```bash
ssh "$CLIENT_VM" "sudo nmap --script broadcast-dhcp-discover -e $CLIENT_IF"
```

`nmap`が利用できない環境では、`dhclient`の詳細ログで代替します。

```bash
ssh "$CLIENT_VM" "sudo dhclient -v $CLIENT_IF"
ssh "$CLIENT_VM" "sudo dhclient -r $CLIENT_IF"
```

確認点:

- 応答したDHCPサーバーのIPアドレスが`192.168.50.5`のみ
- `nmap`の`broadcast-dhcp-discover`出力（または`dhclient -v`ログの`DHCPOFFER`行）に、`192.168.50.5`以外のサーバーIPが現れない

`192.168.50.5`以外のサーバーが応答した場合は、rogue DHCPサーバーが存在する状態です。その値と応答内容（`DHCPOFFER`のオプション等）を記録し、[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ切り分けを残したうえで、rogueサーバーを停止するかセグメントを分離してから再確認します。安全が確認できるまでDNW-09を`PASS`にしません。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| `dhcp-01`のFQDNを解決できない | DNS未構築、または record不整合 | `dig`、`getent`、`resolvectl status` | この検証環境にDNSインフラがそもそも無い（`NOT APPLICABLE`）か、DNS応答なし・NXDOMAINかを分離 |
| `dhcp-01`へICMP/経路が届かない | route / gateway不整合、またはFW方針による遮断 | `ip route get`、`ping` | FW方針による意図的な遮断か、経路設定の不整合かを分離してから待受portの確認へ進む |
| DISCOVERへの応答（OFFER）が来ない | サービス停止、bind interface不一致、UFW拒否のいずれか | `systemctl status isc-dhcp-server`、`sudo ss -lunp`、`sudo ufw status verbose` | サービス障害・`INTERFACESv4`の設定不一致・UFW拒否のどれかを切り分ける |
| 予約MACのクライアントに違うIPが払い出される | `dhcp_server_reservations`の設定ミス、またはMACアドレス表記の不一致 | `dhcpd.conf`の該当`host`句、クライアント側`ip -br link`のMACアドレス | 設定ファイル側の誤りか、登録したMACアドレス自体の誤記かを分離 |
| 想定外の複数DHCPサーバーが応答する（rogue疑い） | 意図しないDHCPサーバーの稼働、または別セグメントとの混在 | `nmap --script broadcast-dhcp-discover`、応答元IPの特定 | rogueサーバーの停止、またはセグメント分離の要否を判断する |
| node_exporterへのconnection refused | serviceまたはUFWスコープの不一致 | `systemctl status prometheus-node-exporter`、`sudo ufw status verbose` | service停止か、送信元スコープ（`monitor-01`のIP）の設定不一致かを分離 |
| tcpdumpに何も映らない（timeout） | 上流FW、L2スイッチ設定、またはVMネットワークの構成不備 | `tcpdump`、UFW、[立ち上げ環境・受け入れ](10-host-bringup-and-acceptance.md)の設定 | packetがそもそも到達していないのか、到達しているがサーバー側で破棄されているのかを分離 |

切り分け時は[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全IDを`PASS / FAIL / BLOCKED / NOT RUN / NOT APPLICABLE`のいずれかで判定した
- [ ] raw logと結果票の日時、commit SHAが一致し、対象環境（`dhcp-01`とクライアント検証VMの双方）を明記した
- [ ] packet capture、IP、MACアドレス、hostname情報を共有前に確認・マスクした
- [ ] クライアント検証VM側の一時的なテストリースを`dhclient -r`で解放した（DNW-06、DNW-08、DNW-09で取得した分をすべて含む）
- [ ] 一時的な`tcpdump` / `nmap`のプロセスが残っていない
- [ ] DNW-09でrogue DHCPを検出した場合は、[構築手順書](05-build-procedure.md)3.2節の切り分けに従い、rogueサーバーの停止またはセグメント分離が完了するまで結果を`PASS`にしていない
- [ ] 問題があれば一次記録とIssueを相互リンクした
