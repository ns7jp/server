# 二セグメント ネットワーク障害ラボ 証跡 — 2026-08-19

[labs/network-troubleshooting/README.md](../../labs/network-troubleshooting/README.md) の自動ドリル（`run-drill.sh`）を実際に実行した記録。

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実施日時 | 2026-08-19 17:18 JST（08:18 UTC） |
| 対象 commit | `bcf1135` |
| 環境 | ローカル Linux（WSL2 Ubuntu 24.04） |
| Docker / Compose | Docker 29.1.3 ／ Docker Compose 2.40.3+ds1 |
| 実行コマンド | `./run-drill.sh \|& tee ../../docs/evidence/network-drill-2026-08-19.log` |

## 結果: PASS

```text
PASS: network fault was reproduced, isolated, and recovered
```

6 段階すべてが想定どおりに完了した。

## 実行結果の詳細

| 段階 | 操作 | 結果 |
| --- | --- | --- |
| [1/6] | ラボ起動（`client` / `proxy` / `app` の3コンテナ） | Started |
| [2/6] | 正常時: `client` → `proxy` → `app` | `server-monitor network lab: ok` |
| [3/6] | 障害注入: `proxy` を `backend` ネットワークから切断 | 実行 |
| [4/6] | 障害確認: `client` から `curl http://proxy/` | `curl: (22) The requested URL returned error: 502`。**PASS: request failed as expected** |
| [5/6] | 切り分け | 下記参照 |
| [6/6] | 復旧: `proxy` を `backend` へ再接続し再確認 | `server-monitor network lab: ok`（正常時と同じ結果に復帰） |

### [5/6] 切り分けの詳細

**`docker network inspect` の `backend` ネットワーク所属コンテナ**（`proxy` が居ないことを確認）:

```json
{"9ed768873c4ccee34e9d3541a63cb54093485a70a03e2ff5c96aac105d391738":{"Name":"server-monitor-network-lab-app-1","EndpointID":"b03f715d205e41180f5ef10b08677d85986173404a1b80ab5d75af551e624f7f","MacAddress":"9e:de:41:ac:4e:aa","IPv4Address":"172.28.20.20/24","IPv6Address":""}}
```

`backend` サブネット（`172.28.20.0/24`）には `app` のみが残っており、`proxy` は切り離されている。

**`proxy` 内の `ip route`**（`backend` サブネットへの経路が消えていることを確認）:

```text
default via 172.28.10.1 dev eth1
172.28.10.0/24 dev eth1 scope link  src 172.28.10.10
```

`frontend`（`172.28.10.0/24`）への経路のみが残り、`backend`（`172.28.20.0/24`）への経路は完全に消えている。

**`proxy` 内の `getent hosts app`**（名前解決の成否）:

出力なし（`|| true` により空でも drill 自体は継続する仕様）。`backend` ネットワークから切断された時点で、Docker の埋め込み DNS からも `app` の名前解決ができなくなることを確認した。ルーティングだけでなく名前解決も同時に失われる、という点が実際に確認できた。

## 原因・影響範囲・復旧操作

| 項目 | 内容 |
| --- | --- |
| 原因（注入した障害） | `docker network disconnect server-monitor-lab-backend <proxy>` による、`proxy` の `backend` ネットワークからの切断 |
| 影響範囲 | `client` → `proxy` → `app` の経路が完全に遮断。`proxy` は `502` を返す（`app` 自体は健全なまま） |
| 復旧操作 | `docker network connect --ip 172.28.20.10 server-monitor-lab-backend <proxy>` で再接続 |
| 復旧確認 | 再接続後、`client` からの `curl` が再び成功することを確認 |
| 所要時間 | スクリプト全体で 10 秒台（`docker compose down` 後のコンテナ・ネットワーク削除を含む） |

## 実行前に見つけて修正した問題（2 件）

このドリルを初めて実行するにあたり、事前レビューで実機の欠陥を2件発見し、実行前に修正した。

1. **`nginx.conf` の静的名前解決によるクラッシュループのリスク**（未発生・予防的に修正）
   `proxy` と `app` の間に `depends_on` が無く起動順序が保証されないため、[D-1 演習で見つけた不具合](../drills/logs/2026-08-19-D-1.md)（[PR #61](https://github.com/ns7jp/server-monitor/pull/61)）と同じパターンで `proxy` が起動失敗しうる状態だった。同じ `resolver` + 変数によるパターンで修正（[PR #63](https://github.com/ns7jp/server-monitor/pull/63)）。
2. **`run-drill.sh` に実行ビットが付与されていなかった**（実機で発生・修正）
   `./run-drill.sh` を実行すると `Permission denied` になった。`chmod +x` で修正。

いずれも今回のドリル実行では発生しなかった（1件目は予防、2件目は事前に修正済みで再実行時には発生していない）が、**この README とスクリプトが存在するだけでは、実際には一度も動かせない状態だった**ことを示している。

## 関連

- [検証証跡台帳](README.md)
- [ラボ README](../../labs/network-troubleshooting/README.md)
- [予防的修正 PR #63](https://github.com/ns7jp/server-monitor/pull/63)
- [D-1 演習記録 2026-08-19](../drills/logs/2026-08-19-D-1.md)（同じ nginx 不具合パターンの初出）
