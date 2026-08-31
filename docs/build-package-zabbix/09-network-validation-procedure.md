# ネットワーク実機検証手順

> 💡 **初めて読む方へ**: この文書は実機のネットワークが設計どおりに動いているかを、1項目ずつ確認する手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#09-ネットワーク実機検証手順)を参照してください。

## 1. 目的と証跡の境界

新規の Zabbix サーバーホスト `zbx-01`（Ubuntu Server 24.04 LTS、`compose.zabbix.yaml` による Zabbix 7.0 LTS 構築）を対象に、IP/CIDR、名前解決、経路、待受 port、HTTP、trapper 疎通、packet、firewall を順に確認します。監視対象ホスト `monitor-01` は既存の[`docs/build-package/`](../build-package/README.md)（案件ID `SM-LAB-001`）で構築済みであり、その基本的な NIC / DNS / UFW は[Linux版のネットワーク実機検証手順](../build-package/09-network-validation-procedure.md)で確認する対象です。本書はそれを重複して検証せず、`monitor-01` を「新しく追加される trapper 送信元」として扱います。

本書の確認は 2 方向で構成します。

- **方向1（管理端末→zbx-01）**: 運用者が Zabbix Frontend・zbx-01 自体へ到達できることを確認します。基本設計は Linux 版と同じ「管理 UI は loopback 限定、SSH tunnel 経由」です。
- **方向2（monitor-01→zbx-01:10051）**: Zabbix Agent2 の active check が `ServerActive=192.0.2.11:10051` へ push できることを確認します。trapper (10051/tcp) は他ホストからの着信を受ける、本パック唯一の監視系 port です。この設計思想の違いは[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします。

`ZNW-01`〜`ZNW-09` の試験ID定義、必須ID判定は[試験仕様書・結果票](06-test-specification.md)（`ZIT-09`、関連要件は`FR-07`/`NFR-06`）を正本とし、本書はその実行手順の詳細だけを扱います。二方向の障害を注入・体験できるラボは本パックには無いため、本手順は独立した管理端末・zbx-01・monitor-01 実機による検証です。対象hostの日付付き結果票がなければ、引き渡し判定では`NOT RUN`を維持します。

結果は zbx-01・monitor-01 ともに Ubuntu であるため、[ネットワーク実機検証テンプレート](../evidence/templates/network-host-validation.md)（Linux版と共用）へ記入します。テンプレートのID欄は`NW-01`〜`09`表記ですが、本書では`ZNW-01`〜`09`として読み替え、対象host欄に`zbx-01`と`monitor-01`の両方を記録します。

## 2. 安全条件

- 読み取りコマンドを中心に実施し、UFW ルール、`DOCKER-USER` iptables chain のルール、route、interface を本手順から変更しません。ZNW-09 で trapper の送信元制限を確認する際も、許可ルール自体は変更せず、許可されていない送信元（管理端末）からの接続試行によって確認します。
- `tcpdump` は packet header だけを最大 20 packet、15 秒で取得します。`-A` / `-X` は認証情報や Frontend の session cookie、本文を採録しうるため使用しません。
- SSH を許可する UFW ルール、trapper (10051/tcp) を monitor-01 の IP だけへ許可する `DOCKER-USER` iptables chain のルールを削除・再読込しません。
- 管理端末 IP、zbx-01 / monitor-01 の公開 IP、MAC address は共有前にマスクします。
- `curl` に Frontend の実パスワードや認証 cookie を直接書かず、`zabbix_sender` の試験 item には実際の監視値ではなく無害なダミー値だけを使います。ZST-02（既定パスワード変更試験）は本書の対象外です。

## 3. 事前準備

zbx-01 に `iproute2`、`iputils-ping`、`dnsutils`、`curl`、`tcpdump`、`ufw`、`iptables`、`netcat-openbsd` があることを確認します。monitor-01 は[Linux版の事前準備](../build-package/09-network-validation-procedure.md#3-事前準備)に加え、本パックの[構築手順書](05-build-procedure.md)で Zabbix Agent2 導入(`ServerActive=192.0.2.11:10051`)まで完了していることを前提とします。管理端末の値を実環境に合わせて設定します。

```bash
ZBX_HOST=zbx-01
ZBX_IP='192.0.2.11'
ZBX_FQDN='zbx.example.test'
MONITOR_HOST=monitor-01
MONITOR_IP='192.0.2.10'
MANAGEMENT_IP='192.0.2.20'
WEB_PORT="${ZABBIX_WEB_PORT:-8081}"
TRAPPER_PORT=10051
CAPTURE_INTERFACE=ens3   # zbx-01の外部NIC名に置き換える（monitor-01からの着信はloopbackを通らない）

date --iso-8601=seconds
git rev-parse HEAD
ssh "$ZBX_HOST" 'uname -a; command -v ip ping dig ss curl tcpdump ufw iptables nc; docker compose -f compose.zabbix.yaml ps'
ssh "$MONITOR_HOST" 'uname -a; command -v ip ping dig ss curl nc; systemctl is-active zabbix-agent2'
```

`192.0.2.0/24` と `.example.test` は[パラメータシート](03-parameter-sheet.md)の記入例です。実行前に `ZBX_IP`、`ZBX_FQDN`、`MANAGEMENT_IP` を実環境の値へ置き換えます。`docker compose ps` の全サービスが `running`(`ZIT-01`)であること、`zabbix-agent2` が `active`であることを確認できない場合は、`FAIL`ではなく`BLOCKED`として前提（構築手順書05）を先に完了させます。

結果の記入先は[ネットワーク実機検証テンプレート](../evidence/templates/network-host-validation.md)です。

## 4. ZNW-01: interface、IP、CIDR

```bash
ssh "$ZBX_HOST" 'ip -br link; ip -br addr'
ssh "$MONITOR_HOST" 'ip -br link; ip -br addr'
```

確認点:

- zbx-01 の対象 IP/prefix が `192.0.2.11/24` と一致
- monitor-01 の対象 IP/prefix が `192.0.2.10/24`（[base packの実績値](../build-package/03-parameter-sheet.md)と同一）と一致
- 想定 interface が両ホストとも `UP`、意図しない global address がない
- loopback `127.0.0.1/8` が両ホストに存在

## 5. ZNW-02: route と default gateway

```bash
ssh "$ZBX_HOST" 'ip route show table main'
ssh "$ZBX_HOST" "ip route get $MANAGEMENT_IP"
ssh "$MONITOR_HOST" "ip route get $ZBX_IP"
```

確認点:

- zbx-01 の default route と、管理端末宛の経路が設計値に一致
- **monitor-01 から zbx-01 宛（trapper送信経路）**の `ip route get` が想定 interface・source address を返す
- 閉域環境で外向き通信を許可しない場合は、経路選択の出力だけを確認し、外部到達性は要求しません

## 6. ZNW-03: DNS 名前解決

```bash
dig +time=2 +tries=1 "$ZBX_FQDN" A
ssh "$ZBX_HOST" "dig +time=2 +tries=1 $ZBX_FQDN A"
ssh "$MONITOR_HOST" "dig +time=2 +tries=1 $ZBX_FQDN A; getent ahostsv4 $ZBX_FQDN"
```

確認点:

- `dig` の `status`、answer が `zbx.example.test` → `192.0.2.11` を返す
- 管理端末・zbx-01・monitor-01 の結果が一致

Agent2 の `ServerActive`（[監視設計](02-detailed-design.md#ログ監視設計)参照）は IP直接指定であり、trapper接続自体は名前解決に依存しません。ここでは運用者の SSH/Frontend アクセスと将来の FQDN 移行に備え、名前解決が設計どおり機能することだけを確認します。FQDN を付与しない環境では `NOT APPLICABLE` とし、理由を結果票へ書きます。

## 7. ZNW-04: ICMP 疎通

```bash
ping -c 4 -W 2 "$ZBX_IP"
ssh "$MONITOR_HOST" "ping -c 4 -W 2 $ZBX_IP"
```

ICMP を UFW 方針で遮断する環境では、ping 失敗だけでサービス障害と判定しません。packet loss と方針を記録し、TCP / trapper 試験（ZNW-06）へ進みます。

## 8. ZNW-05: 待受 port

```bash
ssh "$ZBX_HOST" 'sudo ss -lntup'
ssh "$ZBX_HOST" "sudo ss -lntp 'sport = :$WEB_PORT'"
ssh "$ZBX_HOST" "sudo ss -lntp 'sport = :$TRAPPER_PORT'"
ssh "$MONITOR_HOST" 'sudo ss -lntup'
```

確認点:

- zbx-01: Frontend (`$WEB_PORT`) は `127.0.0.1` にだけ bind
- zbx-01: trapper (`10051`) は `0.0.0.0` を含め広く bind されている — これは設計どおりです。他ホストから着信する唯一の監視系portのため、送信元制限は bind ではなく ZNW-08 の `DOCKER-USER` iptables chain のルールで行います(UFWでは行えません)
- zbx-01: `5432`(PostgreSQL) が host の listen 一覧に現れない（`zabbix-internal`、`internal: true` の Docker network内のみで完結するため）
- monitor-01: Agent2 の passive check listener (`10050`) は Agent2 の仕様上 bind され続けます(Agent1 の `StartAgents=0` に相当する無効化パラメータが Agent2 に無いため)。これは想定どおりで、`Server` 未設定による protocol 層拒否と、monitor-01 の既存 UFW(`10050/tcp` の allow ルールを追加しない)によるネットワーク層拒否の 2 段構えで守ります。外部からの到達不可は ZNW-08 で別途確認します

`ss` の process 情報には PID や user が含まれます。共有用 evidence では必要な行だけ残します。

## 9. ZNW-06: TCP / HTTP / trapper 到達性

方向1(Frontend)と方向2(trapper)を分けて確認します。

```bash
# (1) zbx-01自身のloopbackからFrontendを確認
ssh "$ZBX_HOST" "curl --fail --silent --show-error --max-time 5 -D - http://127.0.0.1:$WEB_PORT/"

# (2) 管理端末からFrontendへ直接アクセス（loopback限定のため失敗が正しい設計）
curl --verbose --max-time 5 "http://$ZBX_IP:$WEB_PORT/"

# (3) monitor-01からzbx-01のtrapper portへのTCP到達性（active checkの送信経路）
ssh "$MONITOR_HOST" "nc -zv -w 5 $ZBX_IP $TRAPPER_PORT"

# (4) 管理端末からzbx-01のtrapper portへの直接アクセス（monitor-01以外は拒否が正しい設計）
nc -zv -w 5 "$ZBX_IP" "$TRAPPER_PORT"
```

期待結果:

- (1) は 200
- (2) は接続失敗（運用者は SSH tunnel 経由で利用し、Frontend を直接公開しない）
- (3) は `succeeded`(open) — monitor-01 は許可された送信元
- (4) は接続拒否または timeout — 管理端末は trapper の許可送信元に含まれない

(2)(4) の失敗は本設計では `PASS` です。`curl --verbose` の出力に認証 header を含めないでください。

## 10. ZNW-07: packet capture

zbx-01 で trapper port 宛の packet を待ち受け、15 秒以内に monitor-01 から接続します。ループバックではなく monitor-01 からの実際の着信を捕捉するため、`CAPTURE_INTERFACE` は zbx-01 の外部 NIC 名を使用します。

端末A（zbx-01）:

```bash
ssh -t "$ZBX_HOST" \
  "sudo timeout 15 tcpdump -nn -i $CAPTURE_INTERFACE -c 20 \"tcp port $TRAPPER_PORT and host $MONITOR_IP\""
```

端末B（monitor-01、上記15秒の間に実行）:

```bash
ssh "$MONITOR_HOST" "nc -zv -w 3 $ZBX_IP $TRAPPER_PORT"
```

SYN のみ見えて応答がなければ zbx-01 側の listener / `DOCKER-USER` chain を、monitor-01 からの発信自体が zbx-01 に届かなければ上流 FW / security group / route を調べます。

## 11. ZNW-08: UFW と DOCKER-USER chain

UFW と `DOCKER-USER` iptables chain は守備範囲が異なるため、分けて確認します。**UFWはDockerが`ports:`で公開したportを経由しないため、trapper(10051/tcp)の送信元制限はUFWのコマンドでは確認できません**([`docs/security.md`](../security.md)、[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)参照)。

```bash
# UFW: SSH(22/tcp)などDockerが公開していないportの既定deny incoming運用を確認
ssh "$ZBX_HOST" 'sudo ufw status verbose'

# DOCKER-USER chain: trapper(10051/tcp)の送信元制限はここで確認する
ssh "$ZBX_HOST" 'sudo iptables -L DOCKER-USER -n --line-numbers'
```

確認点:

- UFW: `Status: active`、default incoming が deny
- UFW: `22/tcp` は repository既定でUFW `LIMIT`。production受入では管理元CIDR限定であること（[Linux版09](../build-package/09-network-validation-procedure.md)と同方針）
- UFW: `$WEB_PORT`・`10051/tcp`・`5432/tcp`への外部向けallow ruleが無い(UFWはこれらのportの送信元制限を担わない設計のため、そもそもruleを追加していない)
- `DOCKER-USER` chain: `10051/tcp`宛で、**monitor-01 の IP（`$MONITOR_IP`）へのACCEPT rule**が、**送信元を問わないDROP rule**より上の行にある(先に評価される)ことを確認
- `DOCKER-USER` chain にmonitor-01のIP以外からのACCEPT ruleが無い
- cloud VM の場合は security group / NACL も別途採録(こちらもUFWとは独立した防御層)

Frontend が「bind addressだけで守る」設計であるのに対し、trapperは「ゆるくbindし`DOCKER-USER`chainのiptables source制限で絞る」設計です。この違いを結果票の備考に明記し、両者を混同しないようにします。

## 12. ZNW-09: end-to-end(2方向)

**方向1: 管理端末 → zbx-01 Frontend（SSH tunnel経由）**

端末A:

```bash
ssh -N -L 18081:127.0.0.1:$WEB_PORT "$ZBX_HOST"
```

端末B:

```bash
curl --fail --silent --show-error --max-time 5 -D - \
  http://127.0.0.1:18081/
```

期待結果は HTTP 200 です。確認後は端末A で `Ctrl-C` を押し、tunnel が残っていないことを確認します。

**方向2: monitor-01 → zbx-01:10051（trapperプロトコルの実疎通）**

```bash
ssh "$MONITOR_HOST" \
  "command -v zabbix_sender >/dev/null 2>&1 && \
   zabbix_sender -z $ZBX_IP -p $TRAPPER_PORT -s monitor-01 -k znw09.connectivity-check -o 1 || \
   nc -zv -w 5 $ZBX_IP $TRAPPER_PORT"
```

`zabbix_sender` が導入済みの場合は、Zabbix Server から JSON レスポンス（`processed`/`failed`件数を含む）が返ればプロトコルレベルの疎通は `PASS` です。この時点で host `monitor-01` が Frontend 上に未登録なら `failed: 1` が返りますが、それは host 登録（`ZIT-03`の範囲）が未実施なだけであり、trapper のネットワーク疎通そのものとは区別します。`zabbix_sender` が無い環境では `nc` によるTCP到達性確認で代替し、その旨を結果票へ記録します。

管理端末から同じ port へ試みた場合（ZNW-06(4)で `PASS` と確認済みの拒否）を、あらためて `NOT RUN` のまま重複記録しないでください。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| FQDN を解決できない | DNS server / record 不整合 | `dig`、`getent` | DNS 応答なし、NXDOMAIN、双方の値の差異を分離 |
| zbx-01 へ IP到達しない | route / gateway 不整合 | `ip route get`、`ping` | ICMP 方針を確認後、TCP へ進む |
| Frontend に管理端末から直接繋がる（想定外） | `ZABBIX_WEB_PORT`のbind address誤設定(`.env`が`0.0.0.0`等へ上書きされている)。UFWの設定はこの経路に無関係 | `ss -lntup`、`docker compose -f compose.zabbix.yaml config` | `$WEB_PORT` の bind、`compose.zabbix.yaml` の port mapping を確認 |
| monitor-01 から trapper が connection refused | zbx-01 の `DOCKER-USER` chain が monitor-01 の IP を許可していない、または `zabbix-server` コンテナ停止 | `iptables -L DOCKER-USER -n --line-numbers`、`ss -lntup`、`docker compose -f compose.zabbix.yaml ps` | `DOCKER-USER` chain の rule かコンテナ状態かを分離(UFWは無関係) |
| monitor-01 から trapper が timeout | 上流 FW / security group / route 不整合 | `tcpdump`、`ip route`、security group | packet 到着前後で担当境界を分離 |
| trapper へ TCP接続はできるが `zabbix_sender` が `failed` を返す | Frontend で Host `monitor-01` が未登録、または Template 未リンク | Frontend の Host一覧、[構築手順書](05-build-procedure.md)のHost登録手順 | ネットワーク疎通(本書)と Host 登録(`ZIT-03`)を切り分け、後者は本書の対象外と明記 |
| HTTP 502（Frontendの内部エラー） | web コンテナから DB / server コンテナへ到達不可 | `docker compose logs`、`zabbix-internal` network の状態 | コンテナ健全性、DB接続文字列、network membership を確認 |

切り分け時は [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全ID(`ZNW-01`〜`09`)を `PASS / FAIL / BLOCKED / NOT RUN` のいずれかで判定した
- [ ] raw log と結果票の日時、commit SHA、環境（zbx-01・monitor-01双方）が一致する
- [ ] packet capture、IP、MAC、hostname、account 情報を共有前にマスクした
- [ ] 一時的な SSH tunnel、`nc` / `zabbix_sender` の接続確認プロセスが終了している
- [ ] trapper の `DOCKER-USER` chain のルール、Zabbix Server / Agent2 の設定を本手順から変更していないことを確認した
- [ ] ZNW-09の`zabbix_sender`結果で `failed` が出た場合、trapperのネットワーク疎通(本書)とHost登録(`ZIT-03`)の境界を結果票に明記した
- [ ] 問題があれば一次記録と Issue を相互リンクした
