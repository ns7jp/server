# ネットワーク実機検証手順

## 1. 目的と証跡の境界

管理端末から Ubuntu VM、VM の loopback、Docker service までを対象に、IP/CIDR、名前解決、経路、待受 port、HTTP、packet、firewall を順に確認します。

[`labs/network-troubleshooting`](../../labs/network-troubleshooting/README.md) は二セグメント障害の再現用です。
[2026-08-22 Full-stack E2E](../evidence/2026-08-22-full-stack-e2e.md)ではephemeral runner内の
`IT-12 / ST-01 / ST-04`をPASSとして採録しました。本手順は、独立した管理端末と引き渡し対象VMの
NIC / DNS / UFWを確認する別試験です。その対象hostの日付付き結果票がなければ、引き渡し判定では
`NOT RUN`を維持します。

## 2. 安全条件

- 読み取りコマンドを中心に実施し、FW ルール、route、interface を本手順から変更しません。
- `tcpdump` は packet header だけを最大 20 packet、15 秒で取得します。`-A` / `-X` は認証情報や本文を採録しうるため使用しません。
- SSH を許可する UFW ルールを削除・再読込しません。
- 管理端末 IP、公開 IP、MAC address は共有前にマスクします。
- `curl` に実パスワード、token、cookie を直接書かず、認証試験は別の保護されたログで実施します。

## 3. 事前準備

Ubuntu VM に `iproute2`、`iputils-ping`、`dnsutils`、`curl`、`tcpdump`、`ufw` があることを確認します。管理端末の値を実環境に合わせて設定します。

```bash
TARGET_HOST=monitor-01
TARGET_IP='192.0.2.10'
TARGET_FQDN='monitor.example.test'
MANAGEMENT_IP='192.0.2.20'
CAPTURE_INTERFACE=lo
TARGET_PORT=8080
TARGET_URL=http://127.0.0.1:8080/healthz

date --iso-8601=seconds
git rev-parse HEAD
ssh "$TARGET_HOST" 'uname -a; command -v ip ping dig ss curl tcpdump ufw'
```

`192.0.2.0/24` と `.example.test` は記入例です。実行前に `TARGET_IP`、`TARGET_FQDN`、`MANAGEMENT_IP` を実環境の値へ置き換えます。外部 NIC を capture する場合は `CAPTURE_INTERFACE` も `ens3` などの実在名へ変えます。

FQDN を付与しない環境では `TARGET_FQDN` を `NOT APPLICABLE` とし、理由を結果票へ書きます。コマンドの欠落は `FAIL` ではなく `BLOCKED` として前提パッケージを整備してから再実行します。

結果の記入先は [ネットワーク実機検証テンプレート](../evidence/templates/network-host-validation.md)です。

## 4. NW-01: interface、IP、CIDR

```bash
ssh "$TARGET_HOST" 'ip -br link; ip -br addr'
```

確認点:

- 想定 interface が `UP`
- 対象 IP と prefix length が IP アドレス表と一致
- 意図しない global address がない
- loopback `127.0.0.1/8` が存在

## 5. NW-02: route と default gateway

```bash
ssh "$TARGET_HOST" 'ip route show table main'
ssh "$TARGET_HOST" 'ip route get 1.1.1.1'
ssh "$TARGET_HOST" "ip route get $MANAGEMENT_IP"
```

確認点:

- default route の gateway と device が設計値に一致
- 対象 subnet は想定 interface へ向く
- `ip route get` の source address が意図した NIC の address

外向き通信を許可しない閉域環境では `1.1.1.1` への到達成功を要求しません。ここでは route 選択の出力だけを確認し、閉域という設計理由を記録します。

## 6. NW-03: DNS 名前解決

管理端末と対象 VM の両方から確認します。

```bash
dig +time=2 +tries=1 "$TARGET_FQDN" A
getent ahostsv4 "$TARGET_FQDN"
ssh "$TARGET_HOST" "dig +time=2 +tries=1 $TARGET_FQDN A"
ssh "$TARGET_HOST" "getent ahostsv4 $TARGET_FQDN"
ssh "$TARGET_HOST" 'resolvectl status || cat /etc/resolv.conf'
```

確認点:

- `dig` の `status`、answer、問い合わせ先 DNS
- `getent` の結果と `dig` の結果が一致
- split DNS を使う場合、管理端末と VM で想定どおりの address が返る

## 7. NW-04: ICMP 疎通

```bash
ping -c 4 -W 2 "$TARGET_IP"
ssh "$TARGET_HOST" 'ping -c 4 -W 2 127.0.0.1'
```

ICMP を FW 方針で遮断する環境では、ping 失敗だけでサービス障害と判定しません。packet loss と方針を記録し、TCP / HTTP の試験へ進みます。

## 8. NW-05: 待受 port

```bash
ssh "$TARGET_HOST" 'sudo ss -lntup'
ssh "$TARGET_HOST" "sudo ss -lntp 'sport = :$TARGET_PORT'"
```

確認点:

- 8080、3000、9090、9093、3100 は `127.0.0.1` にだけ bind
- 外部向けは承認された SSH 22/tcp だけ
- 想定しない `0.0.0.0` / `[::]` の listener がない

`ss` の process 情報には PID や user が含まれます。共有用 evidence では必要な行だけ残します。

## 9. NW-06: TCP / HTTP

loopback bind を確認するため、対象 VM 内から health endpoint を取得します。その後、管理端末から直接 8080/tcp へ接続できないことも確認します。

```bash
ssh "$TARGET_HOST" "curl --fail --silent --show-error --max-time 5 -D - $TARGET_URL"
curl --verbose --max-time 5 "http://$TARGET_IP:$TARGET_PORT/healthz"
ssh "$TARGET_HOST" 'curl --fail --silent --show-error --max-time 5 http://127.0.0.1:9090/-/ready'
ssh "$TARGET_HOST" 'curl --fail --silent --show-error --max-time 5 http://127.0.0.1:3000/api/health'
ssh "$TARGET_HOST" 'curl --fail --silent --show-error --max-time 5 http://127.0.0.1:3100/ready'
```

期待結果:

- VM 内の health / readiness は 200
- 管理端末から VM の 8080/tcp への直接接続は失敗
- 運用者は SSH tunnel 経由で利用し、不要な port を公開しない

直接接続の失敗は本設計では `PASS` です。`curl --verbose` の出力に認証 header を含めないでください。

## 10. NW-07: packet capture

端末 A で header だけを待ち受け、15 秒以内に端末 B の health check を実行します。

端末 A:

```bash
ssh -t "$TARGET_HOST" \
  "sudo timeout 15 tcpdump -nn -i $CAPTURE_INTERFACE -c 20 'tcp port $TARGET_PORT'"
```

端末 B:

```bash
ssh "$TARGET_HOST" "curl --fail --silent --show-error --max-time 5 $TARGET_URL"
```

標準手順は `CAPTURE_INTERFACE=lo` で loopback の health check を採ります。管理端末から届く packet を調べる場合は外部 NIC 名へ変え、端末 B から `curl http://$TARGET_IP:$TARGET_PORT/healthz` を実行します。SYN のみ見えて応答がなければ listener / host FW を、VM に packet 自体が届かなければ上流 FW / security group / route を調べます。

## 11. NW-08: UFW と kernel rule

```bash
ssh "$TARGET_HOST" 'sudo ufw status verbose'
ssh "$TARGET_HOST" 'sudo ufw status numbered'
ssh "$TARGET_HOST" 'sudo nft list ruleset || sudo iptables -S'
```

確認点:

- `Status: active`
- default incoming が deny
- SSH 22/tcp の許可元が承認済みの管理 CIDR
- 8080、3000、9090、9093、3100 の外部向け allow がない
- cloud VM の場合は security group / NACL と UFW の両方を別途採録

## 12. NW-09: SSH tunnel 経由の end-to-end

管理 port を外部公開せず、運用者が想定経路で利用できることを確認します。端末 A の tunnel を開いたまま、端末 B から health endpoint を取得します。

端末 A:

```bash
ssh -N -L 18080:127.0.0.1:8080 "$TARGET_HOST"
```

端末 B:

```bash
curl --fail --silent --show-error --max-time 5 -D - \
  http://127.0.0.1:18080/healthz
```

期待結果は HTTP 200 です。確認後は端末 A で `Ctrl-C` を押し、tunnel が残っていないことを確認します。

## 13. 障害時の切り分け順

| 症状 | 最初の仮説 | 確認 | 次の判断 |
| --- | --- | --- | --- |
| FQDN を解決できない | DNS server / record 不整合 | `dig`、`getent`、`resolvectl status` | DNS 応答なし、NXDOMAIN、NSS 差異を分離 |
| IP へ届かない | route / gateway 不整合 | `ip route get`、`ping` | ICMP 方針を確認後、TCP へ進む |
| connection refused | listener 不在 | `ss -lntup`、Compose 状態 | service 停止または bind address を確認 |
| timeout | FW / upstream route | `tcpdump`、UFW、security group | packet 到着前後で担当境界を分離 |
| HTTP 502 | proxy から app へ到達不可 | proxy log、Docker network、`getent hosts` | app 健全性、名前解決、network membership |

切り分け時は [トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)に、仮説、反証条件、実行コマンド、実出力、学びをその場で記録します。

## 14. 終了処理

- [ ] 全 ID を `PASS / FAIL / BLOCKED / NOT RUN` のいずれかで判定した
- [ ] raw log と結果票の日時、commit SHA、環境が一致する
- [ ] packet capture、IP、MAC、hostname、account 情報を共有前に確認した
- [ ] 一時的な SSH tunnel と capture process が終了している
- [ ] 問題があれば一次記録と Issue を相互リンクした
