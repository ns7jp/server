# 2026-09-17 upstream 接続再利用の CI 比較

**接続再利用を加えた 1 回目の試験では、5 段すべてで HTTP・通信失敗が 0 件でした。**
ただし同じ workflow の IP 変更後復旧試験は、テスト用 Docker network の設定不備で中断しました。
**負荷試験の合格と workflow 全体の失敗を分けて記録します。** 修正した試験の結果は後続の記録で確認します。

[変更前の再測定](2026-09-17-performance-rerun.md) /
[旧集計の問題](2026-09-17-performance-ci-analysis.md) /
[性能試験の説明](../performance-test.md)

## 実行と条件

| 項目 | 内容 |
| --- | --- |
| 実行・分析 | GitHub Actions による実行、Codex による保存 artifact の分析。本人 VM の実績ではない |
| Run | [35203160709 / attempt 1](https://github.com/ns7jp/server/actions/runs/35203160709)、event `pull_request` |
| Job | [105142512730](https://github.com/ns7jp/server/actions/runs/35203160709/job/105142512730) |
| PR head | `dbd61155cad4a80bfbd2f8943cf9633a1928b327` |
| 実際の checkout | `f9069e8632cdd63de514f19c18dcab4ec6778c45`（PR 合成マージ、job log で確認） |
| Artifact | [10488697888 / perf-test-35203160709-1](https://github.com/ns7jp/server/actions/runs/35203160709/artifacts/10488697888) |
| ZIP の検証 | 875,207 bytes。SHA-256 `7d8024a4323a27b001318e07bbc334a92b5da7c800ae09913a0de6b887791a5e`、API digest と取得 ZIP が一致 |
| 当時の workflow conclusion | **failure**。負荷試験と error gate は success、独立した復旧回帰試験は failure |
| 負荷条件 | app/nginx、同一 runner の loopback `/healthz`、並列 1 / 2 / 4 / 8 / 16、各 20 秒、最初に助走 5 秒を 1 回 |
| 判定条件 | HTTP と通信失敗の両方を数える schema 2。段の失敗率上限 1%、CI 上限 5% を維持 |
| 変更した構成 | worker 2 を維持し `gthread --threads 1 --keep-alive 5`。Nginx の動的解決付き upstream に idle pool 8 / timeout 2 秒、両 location に HTTP/1.1 と Connection ヘッダー除去 |
| 変更しなかった試験条件 | 負荷段、計測時間、失敗率のしきい値、段間待機、カーネル設定 |

この構成変更は **接続を毎回作る負担を減らす仮説** に基づきます。
Gunicorn の sync worker は接続を維持しないため、Nginx と app の両側を一組として変更しました。
同時に複数の設定を変えたため、個別設定の寄与をこの比較から分離しません。
[Gunicorn の説明](https://docs.gunicorn.org/en/stable/design.html?highlight=workers)と
[Nginx の接続再利用・動的解決](https://nginx.org/en/docs/http/ngx_http_upstream_module.html)を参照しています。

## 段ごとの観測

変更前は [run 35201803905](2026-09-17-performance-rerun.md)、変更後は本記録の 1 回です。
runner は別なので、厳密に同一ホストを固定した A/B 試験でも、性能保証でもありません。
req/s は **成功応答** の値、p95 は HTTP エラーを含む全応答の分布です。表示は丸めています。

| 並列数 | 変更前 失敗率 | 変更後 失敗率 | 成功 req/s 前 → 後 | p95 ms 前 → 後 | 変更後 段判定 |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 0% | 0% | 620.864 → 900.104 | 3.510 → 1.192 | PASS |
| 2 | 0% | 0% | 491.230 → 1,338.046 | 5.914 → 1.873 | PASS |
| 4 | 21.0446% | 0% | 623.462 → 1,538.083 | 10.718 → 3.732 | PASS |
| 8 | 0% | 0% | 976.160 → 1,517.924 | 16.725 → 8.342 | PASS |
| 16 | 0% | 0% | 803.789 → 1,474.688 | 29.057 → 18.255 | PASS |

変更後の全完了件数は順に 18,003 / 26,762 / 30,766 / 30,364 / 29,505 件で、すべて HTTP 200。
`http_error_requests` と `transport_error_requests` は各段 0、
`all_steps_verdict: PASS`、実際の CI error gate も success でした。
[元 result.json](assets/2026-09-17-upstream-keepalive-comparison/result.json) と段別 JSON を保存しています。

自動算出は飽和候補 4、目標内だった最大試験段 16 ですが、どちらも本番の容量ではありません。
CPU・測定側・実利用経路の制約、反復時の変動、長期 SLO はこの 1 回では判定しません。

## 接続に関する観測

| 観測 | 変更前 | 変更後 |
| --- | --- | --- |
| Nginx upstream の Address not available | 3,324 行（HTTP 502 件数と一致） | 0 行 |
| Nginx namespace の TCP ActiveOpens（最初 → 最後の採録） | 246 → 74,559 | 4 → 295 |
| TCP PassiveOpens（同上） | 246 → 77,883 | 248 → 139,809 |
| Nginx namespace の sockstat TIME_WAIT 最大採録値 | 40,189 | 14,106 |
| 診断の未取得表示 | 1 箇所（時間制限） | 0 箇所 |

接続開始の増分は変更前 74,313、変更後 291 です。採録窓や要求件数は異なるため、
これをそのまま厳密な削減率とはしません。変更後に要求は多数処理された一方で、
新しい upstream 接続の増加が小さかったことは、接続再利用という仮説と整合します。

TIME_WAIT は namespace 全体で、クライアント側と upstream 側の接続を区別していません。
「upstream のポートを何個使い切った」とは主張しません。変更前後の試験で、
接続失敗・新規接続数・HTTP 結果が同時に変わったことを観測事実とします。

[診断集計](assets/2026-09-17-upstream-keepalive-comparison/diagnostics-summary.json)と
[時刻付き抜粋](assets/2026-09-17-upstream-keepalive-comparison/diagnostics-excerpt.txt)があります。
元 `diagnostics.log` の SHA-256 は `bab9d8344679b23470d4105b6327c1979f6128754970999a818a4e9f3414f7c8` です。
集計値は原ログから計算し、同じ瞬間に全カウンターを採ったものではありません。

## 復旧回帰試験の失敗を残す

[proxy-recovery.log](assets/2026-09-17-upstream-keepalive-comparison/proxy-recovery.log)の実結果は以下です。

| 確認 | 結果 |
| --- | --- |
| Nginx 設定の構文 | PASS |
| app 不在で Nginx 起動、health 502 | PASS |
| app 起動後 health 200 | PASS |
| root の未認証 401 / 認証あり 200 | PASS |
| app の旧 IP を予約して別 IP へ再作成 | **テスト環境の設定で FAIL** |
| IP 変更後の DNS 再解決・HTTP 復帰 | **NOT RUN** |

Docker は、明示した subnet がない network への `--ip` 指定を拒否しました。
これは IP 変更後のアプリ復旧が失敗したという結果ではなく、**その状態を作る前に試験が止まった**ものです。

試験スクリプトは、Docker が選んだ空き subnet を読取り、まだ空の専用 network だけを同じ subnet の
明示設定で作り直すよう修正しています。また、container は create で得た ID を記録してから start し、
起動失敗でも作成済み資源を後片付けできる形にしています。
修正後の実行結果はこの記録に先取りしません。

## 保存物と残る確認

- [source-metadata.json](assets/2026-09-17-upstream-keepalive-comparison/source-metadata.json)：SHA・run・artifact・当時の結論。
- [step-c1.json](assets/2026-09-17-upstream-keepalive-comparison/step-c1.json)、[step-c2.json](assets/2026-09-17-upstream-keepalive-comparison/step-c2.json)、[step-c4.json](assets/2026-09-17-upstream-keepalive-comparison/step-c4.json)、[step-c8.json](assets/2026-09-17-upstream-keepalive-comparison/step-c8.json)、[step-c16.json](assets/2026-09-17-upstream-keepalive-comparison/step-c16.json)：artifact からバイトを変えずに保存した原本。
- [SHA256SUMS](assets/2026-09-17-upstream-keepalive-comparison/SHA256SUMS)：保存物のハッシュ。

次の CI では、**同じ app / Nginx 設定・同じ負荷条件**で再測定し、修正した復旧試験の実行も確認します。
単発の前後比較を反復試験として扱いません。本人環境、独力実行、別ホスト災害復旧、継続運用、実利用者の容量保証は未実施です。
