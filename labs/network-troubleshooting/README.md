# 二セグメント ネットワーク障害ラボ

`client -> proxy -> app` の通信を frontend / backend の二つの Docker network に分け、proxy の backend 接続を意図的に外して障害を再現します。通信経路、名前解決、network membership を順に確認し、接続を戻して復旧を確認します。

## 実行

前提は Linux と Docker Engine / Compose plugin です。

```bash
cd labs/network-troubleshooting
docker compose config --quiet
./run-drill.sh |& tee ../../docs/evidence/network-drill-$(date +%F).log
docker compose down
```

## 観察するポイント

| 段階 | コマンド | 判断 |
| --- | --- | --- |
| 正常 | client から `curl http://proxy/` | proxy 経由で app の本文を取得 |
| 障害 | backend から proxy を切断 | client は 502、proxy は app へ接続不能 |
| 切り分け | `docker network inspect` | backend に proxy が存在しない |
| 経路 | proxy 内で `ip route` | backend subnet の経路が消えている |
| 名前解決 | proxy 内で `getent hosts app` | 接続先解決の成否を確認 |
| 復旧 | proxy を backend へ再接続 | curl が再び成功 |

## 証跡へ残すもの

- 実施日時、commit SHA、Docker / Compose version
- 正常時・障害時・復旧時の curl 結果
- `docker network inspect` と `ip route` の主要出力
- 原因、影響範囲、復旧操作、所要時間
- 実行中に見つかった問題と、修正した Issue / PR

この README とスクリプトの存在だけでは実施実績になりません。実行ログが `docs/evidence/` に追加されて初めて実測済みとして扱います。

