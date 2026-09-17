# 演習ログ

演習を実施した後、下記テンプレートに沿って結果をここへ追加する。
未実施の結果や見込み値を実績として保存しない。

- D-1: [2026-08-19 ローカル実測（RTO 13秒）](2026-08-19-D-1.md)
- D-1: [2026-08-22 Full-stack E2E（RTO 1秒）](../../evidence/2026-08-22-full-stack-e2e.md)
- D-2: 未実施
- D-6 / D-7 / D-8 / D-9: 未実施（スクリプトとテンプレートのみ）

| 演習 | テンプレート | 対応する演習スクリプト |
| --- | --- | --- |
| D-1 プロセスダウン | [TEMPLATE-D-1-process-down.md](TEMPLATE-D-1-process-down.md) | [`d1-process-down.sh`](../../../scripts/drills/d1-process-down.sh) |
| D-2 ホスト障害復旧 | [TEMPLATE-D-2-host-failure.md](TEMPLATE-D-2-host-failure.md) | — |
| D-6 ディスク逼迫 | [TEMPLATE-D-6-disk-full.md](TEMPLATE-D-6-disk-full.md) | [`d6-disk-full.sh`](../../../scripts/drills/d6-disk-full.sh) |
| D-7 メモリ圧迫 | [TEMPLATE-D-7-memory-pressure.md](TEMPLATE-D-7-memory-pressure.md) | [`d7-memory-pressure.sh`](../../../scripts/drills/d7-memory-pressure.sh) |
| D-8 遅延 | [TEMPLATE-D-8-latency-spike.md](TEMPLATE-D-8-latency-spike.md) | [`d8-latency-spike.sh`](../../../scripts/drills/d8-latency-spike.sh) |
| D-9 通知経路断 | [TEMPLATE-D-9-alertmanager-down.md](TEMPLATE-D-9-alertmanager-down.md) | [`d9-alertmanager-down.sh`](../../../scripts/drills/d9-alertmanager-down.sh) |

D-3〜D-5 は AWS 環境を前提としたロードマップ上の番号で、スクリプトもテンプレートも無い
（[../README.md](../README.md) の一覧を参照）。
