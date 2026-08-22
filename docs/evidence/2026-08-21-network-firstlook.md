# ネットワーク切り分けの一次メモ — 2026-08-21

[ns7jp/ns7jp の証跡採録チェックリスト（優先6）](https://github.com/ns7jp/ns7jp/blob/main/docs/evidence-capture-checklist.md)。既存ラボ（`app` + `nginx`）を対象に、`ss` / `docker port` / `docker inspect` で待ち受けポートを確認しようとしたところ、想定外の状態に遭遇し、その原因を切り分けた記録。

> **2026-08-21 追記のまとめ**: 当初は「ホストの `127.0.0.1:8080`（公開ポート）経由で `ss` / 名前解決 / 経路 / パケットを観察する」つもりだったが、`frontend` ネットワークの `internal: true` によりホストへのポート公開自体が無効化されていることが分かった（下記「原因」参照）。その代わり、コンテナ IP を直接指定する方法・`docker compose exec` でコンテナ内部に入る方法で、当初の 4 項目（`ss` / 名前解決 / `traceroute` / `tcpdump`）すべてを実質的に観察できた（「追記」「追記2」「追記3」参照）。想定していた経路（ホストの公開ポート経由）とは異なる方法だが、既存ラボの経路・名前解決・パケットを実際に確認するという目的自体は達成できたと考えている。

## 基本情報

| 項目               | 内容                                                                                                        |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| 実施日時             | 2026-08-21                                                                                                |
| 対象 commit        | 不明                                                                                                        |
| 環境               | ローカル Linux（WSL2 Ubuntu、`usr722@DESKTOP-19F10FT`）                                                          |
| Docker / Compose | Docker version 29.1.3, build 29.1.3-0ubuntu3~24.04.2 / Docker Compose version 2.40.3+ds1-0ubuntu1~24.04.1 |
| 対象コンテナ           | `server-monitor-lab-nginx-1`（`frontend` ネットワークにのみ接続）                                                      |

## やろうとしたこと

`docs/evidence-capture-checklist.md` の優先6に沿って、`ss -tlnp` で nginx の待ち受けポート（`127.0.0.1:8080`）を確認しようとした。

## 症状: 待ち受けポートが見えない

```text
$ ss -tlnp
State   Recv-Q  Send-Q  Local Address:Port      Peer Address:Port  Process
LISTEN  0       1000    10.255.255.254:53       0.0.0.0:*
LISTEN  0       4096    127.0.0.54:53           0.0.0.0:*
LISTEN  0       4096    127.0.0.1:46233         0.0.0.0:*
LISTEN  0       4096    127.0.0.53%lo:53        0.0.0.0:*
```

`127.0.0.1:8080` が一覧に無い（見えるのは WSL2 の DNS スタブリゾルバのみ）。

## 切り分け

### 1. コンテナは動いているか（`docker compose ps`）

```text
server-monitor-lab-nginx-1   nginx:1.27-alpine   ...   nginx   3 days ago   Up 10 minutes
    80/tcp, 8080/tcp
```

`Up` にはなっている。ただし `PORTS` 列にホスト側のマッピング（`127.0.0.1:8080->8080/tcp` のような表記）が出ていない。

### 2. Docker 自身は公開していると思っているか（`docker port`）

```text
$ docker port server-monitor-lab-nginx-1
（出力なし）
```

Docker 側も「公開している」とは認識していない。

### 3. compose の設定自体は正しいか（`docker compose config`）

```text
nginx:
  ...
  ports:
    - mode: ingress
      host_ip: 127.0.0.1
      target: 8080
      published: "8080"
      protocol: tcp
```

設定は正しく `127.0.0.1:8080 -> 8080/tcp` を要求している。`MONITOR_PORT` のズレなどではない。

### 4. コンテナを作り直せば直るか（`--force-recreate`）

```text
$ docker compose up -d --force-recreate nginx
[+] Running 2/2
 ✔ Container server-monitor-lab-app-1    Healthy
 ✔ Container server-monitor-lab-nginx-1  Started

$ docker port server-monitor-lab-nginx-1
（出力なし）
```

再作成しても変わらず。古いコンテナ設定が残っていた、という単純な話ではなかった。

### 5. nginx はエラーで落ちていないか（`docker logs`）

```text
2026/08/21 07:36:59 [notice] 1#1: using the "epoll" event method
2026/08/21 07:36:59 [notice] 1#1: nginx/1.27.5
2026/08/21 07:36:59 [notice] 1#1: OS: Linux 6.18.33.2-microsoft-standard-WSL2
2026/08/21 07:36:59 [notice] 1#1: start worker processes
2026/08/21 07:36:59 [notice] 1#1: start worker process 21
2026/08/21 07:36:59 [notice] 1#1: start worker process 22
2026/08/21 07:36:59 [notice] 1#1: start worker process 23
2026/08/21 07:36:59 [notice] 1#1: start worker process 24
```

エラーなし。worker も4つ正常に起動している。nginx 自体は健全。

### 6. Docker デーモンが実際に何をバインドしたか（`docker inspect`）

```text
$ docker inspect server-monitor-lab-nginx-1 --format '{{json .NetworkSettings.Ports}}'
{"80/tcp":null,"8080/tcp":null}

$ docker inspect server-monitor-lab-nginx-1 --format '{{json .HostConfig.PortBindings}}'
{"8080/tcp":[{"HostIp":"127.0.0.1","HostPort":"8080"}]}
```

**ここで矛盾が見える。** `HostConfig.PortBindings`（要求された設定）には `127.0.0.1:8080` が確かに入っているのに、`NetworkSettings.Ports`（実際に反映された結果）は両方とも `null`。要求は正しく渡っているのに、実際のポートフォワーディングが確立されていない。

## 原因

`compose.yaml` で nginx が接続している `frontend` ネットワークの定義:

```yaml
networks:
  frontend:
    internal: true
```

`internal: true` は「このネットワークを外部への経路から遮断する」設定だが、この遮断は**ホストへのポート公開（DNAT によるポートフォワーディング）も含めて無効化する**。`ports:` の設定自体は Docker に受理され `HostConfig.PortBindings` には記録されるが、実際にホストと疎通させるフォワーディングルールは `internal: true` のネットワークでは作られない。nginx コンテナ自体はエラーなく起動しているため、この症状はログや `docker compose ps` の `Up` 表示だけを見ていては気づけない。

## 学び

- 「コンテナが `Up` になっている」ことと「設定したポートが実際にホストへ公開されている」ことは別物で、`docker compose ps` の `PORTS` 列だけでは判断しきれない場合がある。`docker port` と `docker inspect` の `NetworkSettings.Ports` を見て初めて「要求はされたが未反映」という状態に気づけた。
- `internal: true` の副作用（ポート公開が効かなくなること）は、ネットワーク定義を見ただけでは直感的に分からない。ドキュメント上は「外部への経路を切る」としか書かれていないことが多いが、実際にはホスト publish もその「外部」に含まれる。
- 切り分けの順番として、まずアプリ側（nginx のログ）を疑ったが、実際は一段下（Docker のネットワーク設定）に原因があった。「コンテナは動いている」で切り分けを止めず、Docker デーモンが実際に何を反映しているかまで見て初めて原因に辿り着いた。

## 追記: `docker compose exec` 経由での名前解決の実測

`docker compose exec` は Docker ソケット経由でコンテナに直接入るため、`internal: true` によるホストへのポート公開の制約を受けない。この方法で、当初「未実施」としていた名前解決の確認を後日改めて実施した。

```text
$ docker compose exec nginx sh -c "getent hosts app; cat /etc/resolv.conf"
172.18.0.3      app     app
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 127.0.0.11
search flets-east.jp iptvf.jp
options ndots:0

# Based on host file: '/etc/resolv.conf' (internal resolver)
# ExtServers: [host(10.255.255.254)]
# Overrides: []
# Option ndots from: internal
```

`getent hosts app` は `172.18.0.3`（`app` コンテナの実際の IP）へ正しく解決された。`/etc/resolv.conf` の `nameserver 127.0.0.11` は、`deploy/nginx/local.conf` のコメントに書かれていた設計理由（`resolver 127.0.0.11 valid=10s` を使い、起動時の一度きりの名前解決ではなくリクエストごとに Docker の埋め込み DNS で再解決する）と一致することを実機で確認できた。

なお `ExtServers: [host(10.255.255.254)]` は、コンテナ内の DNS 問い合わせも最終的にはホスト（WSL2）側の DNS 設定を経由することを示している。`10.255.255.254` は WSL2 の DNS トンネリング機能が使う内部プロキシアドレスで、別途 `dig +trace github.com` を試した際にこのアドレスへの問い合わせがタイムアウトする事象も確認した（`dig @8.8.8.8 github.com` は正常に応答したため、外部への疎通自体は生きており、WSL2 側の DNS トンネリングだけが不調だったと判断している。本題ではないため深追いはしていない）。

## 追記2: ホストからコンテナ IP への直接 `traceroute`

`internal: true` が塞いでいたのは「ホストで公開したポート（`127.0.0.1:8080`）経由のアクセス」であって、「ホストからブリッジ上のコンテナ IP への直接到達性」ではないのではと考え、`docker compose exec nginx hostname -i` で得た nginx コンテナの実 IP に対して、ホスト（WSL2）から直接 `traceroute` を実行した。

```text
$ traceroute 172.18.0.4
traceroute to 172.18.0.4 (172.18.0.4), 30 hops max, 60 byte packets
 1  172.18.0.4 (172.18.0.4)  331.417 ms  0.217 ms  0.083 ms
```

1 ホップで到達した。つまり、ホストからコンテナ IP への直接ルーティングは `internal: true` の影響を受けておらず、通っていることが分かった。

これにより、原因の理解がより正確になった。`internal: true` が無効化するのは**ホストで公開したポート経由のアクセス（DNAT によるポートフォワーディング）**であり、**ホストからブリッジ上のコンテナ IP への直接到達性**は妨げていない。ホストはそのブリッジネットワークに直結しているため、Docker が管理する NAT/フォワーディングのルールを介さずに到達できる、という理解である（この理解が Docker の一般的な仕様として正しいかは未検証。今回の実機での観察に基づく推定）。

## 追記3: 実際のパケットの観察（`tcpdump`）

「追記2」で、ホストからコンテナ IP への直接到達性は `internal: true` の影響を受けないと分かったため、ホスト側の公開ポート（`127.0.0.1:8080`）の代わりにコンテナ IP を直接指定して `tcpdump` を試した。

```text
$ docker network inspect server-monitor-lab_frontend --format 'br-{{slice .Id 0 12}}'
br-2d8e012d4377

$ sudo tcpdump -i br-2d8e012d4377 -n port 8080 -w /tmp/lab-capture.pcap &
[1] 9370
tcpdump: listening on br-2d8e012d4377, link-type EN10MB (Ethernet), snapshot length 262144 bytes

$ curl -s http://127.0.0.1:8080/healthz   # 公開ポート経由（想定どおり応答なし・パケットも記録されず）
$ curl -s http://172.18.0.4:8080/healthz  # コンテナ IP を直接指定

$ sudo kill %1
$ tcpdump -r /tmp/lab-capture.pcap -n
18:41:51.821134 IP 172.18.0.2.37720 > 172.18.0.4.8080: Flags [.], ack 1, win 63, ...
18:41:51.821549 IP 172.18.0.2.37720 > 172.18.0.4.8080: Flags [P.], seq 1:101, ack 1, win 63, ..., length 100: HTTP: GET /healthz HTTP/1.1
18:41:51.821625 IP 172.18.0.4.8080 > 172.18.0.2.37720: Flags [.], ack 101, win 64, ..., length 0
18:41:51.825267 IP 172.18.0.4.8080 > 172.18.0.2.37720: Flags [P.], seq 1:618, ack 101, win 64, ..., length 617: HTTP: HTTP/1.1 200 OK
18:41:51.825358 IP 172.18.0.2.37720 > 172.18.0.4.8080: Flags [.], ack 618, win 63, ...
18:41:51.825443 IP 172.18.0.4.8080 > 172.18.0.2.37720: Flags [F.], seq 618, ack 101, win 64, ...
18:41:51.825937 IP 172.18.0.2.37720 > 172.18.0.4.8080: Flags [F.], seq 101, ack 619, win 63, ...
18:41:51.826038 IP 172.18.0.4.8080 > 172.18.0.2.37720: Flags [.], ack 102, win 64, ...
（同じパターンが 18:42:21・18:42:51 にも記録されている。約 30 秒間隔）
tcpdump: pcap_loop: truncated dump file; tried to read 16 header bytes, only got 15
```

TCP の 3-way handshake → `HTTP: GET /healthz HTTP/1.1` → `HTTP: HTTP/1.1 200 OK`（617 バイト）→ FIN/ACK による正常終了、という一連のやり取りを平文 HTTP のまま観察できた（このラボは TLS 未設定のため、想定どおり暗号化されていない）。

**同じパターンが 30 秒間隔で複数回記録されている点について**: 送信元 `172.18.0.2` は自分が打った `curl` の結果というより、`compose.yaml` で `frontend` ネットワークにも参加している `blackbox`（blackbox-exporter、監視スタック全体が既に起動していたため常時稼働中）が `/healthz` を定期プローブしている通信だと考えている（未確認。ソース側のプロセスを特定する追加確認はしていない）。手動の `curl` によるものかプローブによるものか、この記録だけでは完全には区別できていない。

末尾の `tcpdump: pcap_loop: truncated dump file` は、キャプチャファイルを読んだ際に出た警告で、`kill` した直後の書き込み未完了によるものと考えられる。実際に読めた内容自体には影響していない。

## 今回の証跡としての範囲

- 当初想定していた「ホスト（WSL2）の `127.0.0.1:8080`（公開ポート）経由」での観察は、`internal: true` によるポート公開の無効化により実施できなかった。
- 代わりに、名前解決は `docker compose exec`（「追記」）、経路（`traceroute`）と実際のパケット（`tcpdump`）はコンテナ IP を直接指定する方法（「追記2」「追記3」）で、それぞれ実施できた。
- `docs/evidence-capture-checklist.md` 優先6が意図していた「既存ラボの経路と名前解決を dig / traceroute / ss / tcpdump で実際に調べる」という目的自体は、当初想定と異なる経路（コンテナ IP 直接指定・`docker compose exec`）を通じて実質的に達成できたと考えている。

## 次にやること（検討）

- `172.18.0.2` からの定期プローブが `blackbox` によるものかどうかは未確認。確認するなら `docker compose logs blackbox` や blackbox の設定ファイルを見ると特定できる可能性がある。
- `frontend` の `internal: true` によりホスト公開ポート経由の検証ができないという制約自体は解消していない。ローカル検証用途に限り `internal: true` を外す・検証用の別ネットワークを足す、という compose.yaml 側の変更を検討する余地はあるが、本番相当の構成を崩すことになるため、変更するかどうかは要判断。

> **AI 支援について**: この調査は本人が実機（WSL2）で実際にコマンドを実行し、Claude Code とのやり取りの中で次に確認すべきコマンドを提案してもらいながら進めた。`internal: true` が原因であるという結論は AI の提案によるものであり、本人が Docker のネットワーク仕様を独力で調べて辿り着いたものではない。この記録はその過程を正直に残したもの。

## 2026-08-22 follow-up — 制約の解消と再検証

上記は2026-08-21時点の観察として残し、翌日に構成を修正しました。`frontend` / `monitoring`の
`internal: true`は内部通信用segmentとして維持し、hostへ公開する`nginx` / Prometheus /
Alertmanager / Grafana / Lokiだけを、非internalの`host-access` bridgeにも接続しています。
公開portはすべて`127.0.0.1` bindのままで、app / exporter / collectorは`host-access`へ接続していません。

[Full-stack E2E run 32563104045](https://github.com/ns7jp/server-monitor/actions/runs/32563104045)で、
次を再検証してすべてPASSになりました。詳細は
[2026-08-22 Full-stack E2E証跡](2026-08-22-full-stack-e2e.md)に記録しています。

- `docker compose ps`で管理5 portsが`127.0.0.1`へ公開される
- `ss -lntp`で同5 portsにwildcard bindがない
- host loopbackから`/healthz`へ到達できる
- 別Docker namespaceからhost:8080へ直接到達できない
- 別namespaceからSSH tunnelを通す場合だけ`/healthz`へ到達できる
- loopback上のTCP/8080 headerを`tcpdump`で採録できる
- UFWはactive / incoming deny / SSH limitで、管理portのALLOW ruleはない

この構成で「内部service間の分離」と「host loopbackからの運用アクセス」を両立しました。
なお、これはephemeral runner内の境界検証であり、独立した管理端末・組織DNS・cloud firewallを
含むproduction相当のnetwork検証ではありません。
