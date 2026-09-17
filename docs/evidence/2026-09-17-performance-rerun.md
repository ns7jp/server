# 2026-09-17 集計修正後の性能 CI 再試験

**HTTP エラーを数える修正後も 502 が再現し、CI は正しく失敗しました。** 並列 4 で 15,795 件中 3,324 件（21.0446%）が HTTP 502 です。これは集計修正の実構成での再試験であり、502 を解消した結果ではありません。

[旧結果の再分析](2026-09-17-performance-ci-analysis.md) / [性能試験の手順](../performance-test.md) / [証跡台帳](README.md)

## 実行版と原資料

| 項目 | 内容 |
| --- | --- |
| 実行者・環境 | GitHub Actions の使い捨て Ubuntu runner。本人 VM の操作・独力再現ではない |
| Run / Job | [35201803905、attempt 1](https://github.com/ns7jp/server/actions/runs/35201803905) / [load-test 105138075738](https://github.com/ns7jp/server/actions/runs/35201803905/job/105138075738)。event `pull_request`、conclusion `failure` |
| 時刻（UTC） | run 開始 08:49:51、更新 08:52:50。測定は並列 1 が 08:50:47、2 が 08:51:10、4 が 08:51:33、8 が 08:51:56、16 が 08:52:19 |
| PR head SHA | `a8bf1ee23d7770c94f205f9a35f46ce441ceaf02` |
| 実際の checkout SHA | `6df5b50ddbf418c276ef1db0aaeedafbd7eebcb7`（合成マージ。job の `git log -1 --format=%H` で確認） |
| 対象 | `app` / `nginx`、同じ runner の `http://127.0.0.1:8080/healthz`。closed-loop、各段 20 秒、最初に並列 1 の助走 5 秒を 1 回 |
| Artifact | [10488187600 / perf-test-35201803905-1](https://github.com/ns7jp/server/actions/runs/35201803905/artifacts/10488187600)、527,371 bytes。期限 2026-10-17T08:52:45Z |
| ZIP SHA-256 | `10837ae8944e4ed5b3ba869083ee3de558f597299fa2e826d59eb4cb6192edcc`。取得 ZIP と API digest が一致 |

[source-metadata.json](assets/2026-09-17-performance-rerun/source-metadata.json) と [job-excerpt.txt](assets/2026-09-17-performance-rerun/job-excerpt.txt) に実行版・原資料・CI 失敗の確認箇所を保存しました。この結果を、後続のコード版や本番環境の合否へ流用しません。

## 測定結果

件数と速度は保存 JSON の値です。p95 は HTTP 502 を含む**全応答**の分布で、成功応答だけの値ではありません。

| 並列数 | 全完了件数 | HTTP 200 | HTTP 502 | 成功 req/s | p95 ms（全応答） | HTTP を含む失敗率 | 段の判定 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 12,419 | 12,419 | 0 | 620.864 | 3.510 | 0.0000% | PASS |
| 2 | 9,826 | 9,826 | 0 | 491.230 | 5.914 | 0.0000% | PASS |
| 4 | 15,795 | 12,471 | 3,324 | 623.462 | 10.718 | 21.0446% | FAIL |
| 8 | 19,529 | 19,529 | 0 | 976.160 | 16.725 | 0.0000% | PASS |
| 16 | 16,082 | 16,082 | 0 | 803.789 | 29.057 | 0.0000% | PASS |

通信例外は全段 0 件です。並列 4 は段の失敗率基準 1% と CI gate の 5% を超えました。job ログにも `HTTP-inclusive error_rate=0.2104463437796771 > 0.05` と終了 1 が残っています。

原本のトップレベル `verdict: PASS` は後方互換の「少なくとも一段が合格」という意味です。**全段の判定は `all_steps_verdict: FAIL`、CI も `failure`** です。`saturation_concurrency: 1` は候補値、`slo_max_concurrency: 16` は試験した段の結果であり、安定した処理能力や同時利用者数の上限とは扱いません。

## 診断で確認できたこと

- 並列 4 の測定中、08:51:40〜08:51:50 UTC に Nginx から app:5000 への `connect() ... failed (99: Address not available)` が 3,324 行ありました。[原文の先頭・末尾抜粋](assets/2026-09-17-performance-rerun/compose-errors-excerpt.txt)を保存しています。
- host と Nginx の network namespace の診断値を分けて採りました。TIME_WAIT の蓄積と 502 の時間帯が重なりますが、集計は入方向・出方向の接続が混在し、複数コマンドを順に取得しています。**upstream 向けポートの占有数や枯渇率は確定できません。**
- Nginx 側で採録した `ip_local_port_range` は 32768〜60999、`tcp_tw_reuse` は 2 でした。範囲と TIME_WAIT 総数の単純比較から、根本原因を断定しません。CPU・メモリは瞬時値であり、継続的な飽和の有無を単独で証明しません。
- SAMPLE 1 の namespace 取得に `UNAVAILABLE ... exit=124` が 1 件あります。残りの記録で補完して「全観測成功」としません。

[診断の原文抜粋](assets/2026-09-17-performance-rerun/diagnostics-excerpt.txt)と[15時点の派生集計](assets/2026-09-17-performance-rerun/diagnostics-summary.json)を保存しました。派生集計の `nginx_state06` は方向未分離の TCP TIME_WAIT 件数、`tw_total` は累積カウンターで、現在のポート占有数ではありません。原資料のハッシュ・抜粋範囲は[来歴](assets/2026-09-17-performance-rerun/excerpt-provenance.json)を参照します。

## 続けて確かめること

接続再利用の設定変更を一つの比較実験として扱い、同じ負荷条件で HTTP 内訳・成功 req/s・接続状態を記録します。**この結果票には、その変更後の測定をまだ含めていません。** 測定後も別 runner 間の値の差だけで因果を断定せず、対象 SHA と変更点を分けて評価します。本人環境の再現、第三者確認、長時間・外部経路・本番 SLO は未実施です。

## 保存した数値原本

[result.json](assets/2026-09-17-performance-rerun/original-result.json)、[summary.md](assets/2026-09-17-performance-rerun/original-summary.md)、[助走](assets/2026-09-17-performance-rerun/original-warmup.json)、段別の [1](assets/2026-09-17-performance-rerun/step-c1.json) / [2](assets/2026-09-17-performance-rerun/step-c2.json) / [4](assets/2026-09-17-performance-rerun/step-c4.json) / [8](assets/2026-09-17-performance-rerun/step-c8.json) / [16](assets/2026-09-17-performance-rerun/step-c16.json) は ZIP 内の原本とバイト単位で一致します。改行や既存の PASS 表示も書き換えていません。

[SHA256SUMS](assets/2026-09-17-performance-rerun/SHA256SUMS) で保存ファイルを確認できます。

```bash
cd docs/evidence/assets/2026-09-17-performance-rerun
sha256sum -c SHA256SUMS
```
