# ネットワーク設計・IPアドレス表

> 💡 **初めて読む方へ**: この文書はどのIP・ポートに、誰が、どこから接続できるかを決めた文書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#04-ネットワーク設計ipアドレス表)を参照してください。

本書は、新規の監視サーバーホスト`zbx-01`のネットワーク設計とIPアドレス表を定義します。監視対象ホスト`monitor-01`(既存、変更なし)側の設計は[Linux版ネットワーク設計・IPアドレス表](../build-package/04-network-ip-plan.md)を正本とし、本書は`zbx-01`の追加分と、`monitor-01`・`zbx-01`間のtrapper通信のみを扱います。[詳細設計書](02-detailed-design.md)の「アクセス制御」表は本書の要約であり、値の正本は本書です。

## 1. 本体構成

| Zone | CIDR / interface(例示) | 主な通信 | 制御 |
| --- | --- | --- | --- |
| 管理端末 | `192.0.2.20/24` | SSH 22/tcp、Frontendへのtunnel(`127.0.0.1:${ZABBIX_WEB_PORT:-8081}`へのローカル転送) | production受入では上流FW / VPNまたはsource指定UFW ruleで管理元CIDR限定(base packと同方針)。既定はUFW `LIMIT`で全送信元 |
| `zbx-01`(Ubuntu Server 24.04 LTS、新規) | `192.0.2.11/24`、`zbx.example.test` | SSH、trapper受信(10051/tcp)、更新、通知 | UFW default deny incoming。SSHは`LIMIT`、10051のみ`monitor-01`のIPを送信元に指定して明示許可 |
| `monitor-01`(既存、変更なし) | `192.0.2.10/24`([Linux版09文書](../build-package/09-network-validation-procedure.md)と同じ値)、`monitor.example.test` | Agent2からのtrapper送信(→`zbx-01`:10051)、UserParameter経由の`127.0.0.1:8080/healthz`アクセス | 既存Linux版パックのUFW設計のまま変更しない。10050(passive listener)は既定未使用 |
| Compose network(`zabbix-internal`、`internal: true`) | Docker管理 | postgres / zabbix-server / zabbix-web間の通信 | 外部egress不可。`internal: true`のnetworkだけに接続したserviceのpublished portはhostへ転送されない |
| Compose network(`zabbix-host-access`、`driver: bridge`) | Docker管理 | zabbix-server・zabbix-webのpublished portをhostへ転送するためだけの経路 | postgresは参加させない。公開対象だけをこのbridgeにも接続する、既存`compose.yaml`の`host-access`パターンを踏襲 |
| loopback(`zbx-01`) | `127.0.0.1/8` | Zabbix Frontend | SSH tunnel経由のみ |

## 2. Frontendとtrapperで設計思想が異なる理由(本書の中心)

`zbx-01`が外部から使われるportは2つだけですが、守り方の設計思想はまったく異なります。

**Frontend**(`${ZABBIX_WEB_PORT:-8081}/tcp`)は、運用者がブラウザで操作する管理UIです。[Linux版](../build-package/04-network-ip-plan.md)・[Windows版](../build-package-windows/04-network-ip-plan.md)・[AD版](../build-package-ad/04-network-ip-plan.md)と同じ「管理UIは外部公開しない」方針のまま、bind address自体を`127.0.0.1`に固定します。運用者はSSH tunnelでloopbackへ転送してから使うため、UFWにallowルールを追加する必要はありません。bind addressそのものが唯一の防御線であり、「そもそもネットワークの外から到達できない」設計です。

**trapper**(`10051/tcp`)は、`monitor-01`のZabbix Agent2がactive checkでpushしてくる値を受け取る受け口です。push元の`monitor-01`は`zbx-01`とは別ホストのため、bindを`127.0.0.1`に固定するとAgent2からの接続そのものが成立しません。trapperは「監視系ポートのうち唯一、他ホストからの着信を受ける必要があるport」であり、bind addressだけで守る設計は使えません。そこでbindはゆるく(interface address全体で)受けたうえで、UFWの送信元CIDR指定で`monitor-01`のIPだけを許可し、それ以外の送信元は拒否します。

| Port | Service | Bind / 許可範囲 | 理由 |
| --- | --- | --- | --- |
| 22/tcp | SSH | UFW `LIMIT`。production受入では管理元CIDR限定(base packと同方針) | 構築・運用 |
| `${ZABBIX_WEB_PORT:-8081}/tcp` | Zabbix Frontend(Nginx同梱、コンテナ内部は8080/tcp) | `127.0.0.1`のみ。運用者はSSH tunnel経由 | 既存パックと同じ「管理UIは外部公開しない」方針 |
| 10051/tcp | Zabbix Server trapper(active check受信) | `monitor-01`のIPのみ許可(UFW source指定)。loopback限定にはできない — 他ホストから着信する唯一の監視系ポート | `monitor-01`のAgent2がactive checkで`zbx-01`へpushするために必須 |
| 5432/tcp | PostgreSQL | 外部非公開。Docker internal network(`zabbix-internal`)のみ | DBは他ホストから直接繋がせない |
| 10050/tcp(`monitor-01`側) | Zabbix Agent2 listener(passive check用、既定は未使用) | 既定では未使用(active checkのみ運用)。将来passive checkを使う場合のみ、`zbx-01`のIP限定で許可 | active checkを主方式とし、pull型のpassiveは任意拡張として設計のみ示す |

これはbase packの04文書にすでに書かれている「SSHはUFW `LIMIT`で全送信元に開けるが、管理元CIDR限定は別途source指定ルールで行う」という誠実な書き方と同じ考え方です。**bind addressだけで守れないもの(他ホストから着信する必要があるport)はfirewallの送信元制限で守り、bind addressだけで守れるもの(自ホスト内だけで完結する管理UI)はbind自体をloopbackに閉じる**、という2つの防御線を混同しないことが本書の要点です。

`ZABBIX_SERVER_BIND_ADDRESS`(`.env.example`)の既定値は`127.0.0.1`です。これはCI/localで安全側に倒した既定値であり、そのままでは`monitor-01`からの着信を受け付けられません。実ホストへ適用する際は、`monitor-01`からの着信を受けられるinterface address(例: `192.0.2.11`)へ明示的に上書きします。「既定はloopback、環境ごとに明示上書きする」という既存repoのパターンをtrapperにも適用したものであり、bindを緩めた分の防御はUFWの送信元CIDR制限(`monitor-01`のIPのみ許可)が担います。bind addressを緩めることと、送信元を制限しないことは別問題であり、どちらか一方だけでtrapperを守ったことにはなりません。

## 3. 実環境で確認する項目

実行順、期待結果、採録方法は[ネットワーク実機検証手順](09-network-validation-procedure.md)(`ZNW-01`〜`09`)を正本とします。本節はその概要であり、「管理端末→`zbx-01`」「`monitor-01`→`zbx-01`:10051(trapper)」の2方向で確認します。

管理端末→`zbx-01`:

- `ip -br addr`で`zbx-01`のinterfaceとCIDRを確認
- `ip route`でdefault gatewayと経路を確認
- `ss -lntup`でFrontendが`127.0.0.1`のみにbindしていることを確認
- `getent hosts` / `dig`で`zbx.example.test`の名前解決を確認
- SSH tunnel経由で`curl -v`によりFrontendのHTTP statusを確認。tunnelを介さず`${ZABBIX_WEB_PORT:-8081}/tcp`へ直接接続できないことも確認

`monitor-01`→`zbx-01`:10051(trapper):

- `ss -lntup`でtrapperがloopback限定ではなく(意図どおり)interface全体でlistenしていることを確認
- `ufw status verbose`で10051/tcpの許可送信元が`monitor-01`のIPのみであることを確認
- `monitor-01`から`zabbix_agent2 -t agent.ping`または`nc -zv`で`zbx-01`のtrapperへの到達を確認
- 必要時だけ`tcpdump -nn -i any port 10051`でpacketを確認
- Zabbix Frontend上で`monitor-01`のitemのlast dataが直近interval以内に更新されることを確認(ZIT-03相当)

repository既定のUFWはSSH 22/tcpを`LIMIT`で開けますが、送信元CIDRは絞りません。管理元CIDR限定が受入条件の環境では、上流security group / VPNの制限を採録するか、source指定UFW ruleを案件変数として設計・実装してから引き渡します。10051も同様に、bindだけでなくUFWのsource指定ルールが実際に効いていることを確認しないと、trapperを事実上無制限公開したままになるため注意します。

独立した引き渡し対象host/管理端末の結果は、[結果票テンプレート](../evidence/templates/network-host-validation.md)(Linux版と共用)から日付付きevidenceを作成するまで`NOT RUN`です。`zbx-01`向けと`monitor-01`向け(またはtrapper方向)で、それぞれ複製して記入します。
