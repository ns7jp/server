# ネットワーク切り分けの一次メモ — 2026-08-21

[ns7jp/ns7jp の証跡採録チェックリスト（優先6）](https://github.com/ns7jp/ns7jp/blob/main/docs/evidence-capture-checklist.md)。既存ラボ（`app` + `nginx`）を対象に、`ss` / `docker port` / `docker inspect` で待ち受けポートを確認しようとしたところ、想定外の状態に遭遇し、その原因を切り分けた記録。

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

## 今回の証跡としての範囲

- ホスト（WSL2）から `127.0.0.1:8080` 経由での `ss` / `dig` / `traceroute` / `tcpdump` の実行は、上記の理由により意味のある結果が得られないと判断し、今回は実施していない。
- 実施できたのは「症状の確認」から「原因の特定（`internal: true` によるポート公開の無効化）」までで、`docs/evidence-capture-checklist.md` 優先6が本来意図していた「クライアント視点での経路・名前解決の観察」そのものは未実施。

## 次にやること（検討）

- `frontend` を `internal: true` のままにする方針を維持するなら、ホスト側からの検証はあきらめ、`docker compose exec` で同じネットワーク上の別コンテナから内部的に確認する形に切り替える。
- あるいは、ローカル検証用途に限り `internal: true` を外す・検証用の別ネットワークを足す、という compose.yaml 側の変更を検討する（本番相当の構成を崩すことになるため、変更するかどうかは要判断）。

> **AI 支援について**: この調査は本人が実機（WSL2）で実際にコマンドを実行し、Claude Code とのやり取りの中で次に確認すべきコマンドを提案してもらいながら進めた。`internal: true` が原因であるという結論は AI の提案によるものであり、本人が Docker のネットワーク仕様を独力で調べて辿り着いたものではない。この記録はその過程を正直に残したもの。
