# 2026-09-17 性能 CI 保存結果の分析

**結論: 負荷試験は完走していましたが、HTTP 502 がエラー率に含まれず、失敗した段も PASS と記録されていました。**
並列 4 の段は 18,174 件中 7,115 件、並列 8 の段は 21,526 件中 421 件が HTTP 502 です。
当時の CI 成功を運用上の性能合格へ読み替えません。今回は既存 artifact の読取り・再計算で、負荷試験の新規実行はしていません。

[性能試験の手順](../performance-test.md) / [SLO](../slo.md) / [検証証跡台帳](README.md)

## 1. 実行と分析を分ける

| 項目 | 内容 |
| --- | --- |
| 実行者 | GitHub Actions CI。本人の VM 操作・独立再現ではない |
| 分析者・分析日 | Codex による支援分析、2026-09-17 |
| Run | [35197884893、attempt 1](https://github.com/ns7jp/server/actions/runs/35197884893) / event `pull_request` / 当時の conclusion `success` |
| Job | [105125329682、load-test](https://github.com/ns7jp/server/actions/runs/35197884893/job/105125329682) |
| Run 時間（UTC） | 開始 2026-09-17T08:06:06Z、更新 08:09:02Z |
| API の PR head SHA | `92ff2f270eca9be7775e6112c28b821579a0d9b9` |
| 実際の checkout SHA | `da53d8d7a7ad7eb936d8498f478c406c52a02daf`（PR #260 の合成マージ。job の `git log -1 --format=%H` で確認） |
| 比較上の注意 | 後日の main `2896db6`、今回の文書・コード修正版の実測ではない |
| Runner | GitHub hosted、Ubuntu 24.04.5、image `20260907.300.1`、CPython 3.11.16 |
| Artifact | [10486587103 / perf-test-35197884893-1](https://github.com/ns7jp/server/actions/runs/35197884893/artifacts/10486587103) |
| ZIP | 591,313 bytes、SHA-256 `e2bc4cb94c3a68cf2ab507f387866b378b82a5842089d86afe34ae6ae71aba55`。取得ファイルと API の digest が一致 |
| Artifact の期限 | API の `expires_at`: 2026-10-17T08:08:58Z。数値原本の抜粋を本リポジトリに保持 |

API 項目の抜粋は [source-metadata.json](assets/2026-09-17-performance-ci-analysis/source-metadata.json)、
実行版・環境・終了を示すログ抜粋は [job-excerpt.txt](assets/2026-09-17-performance-ci-analysis/job-excerpt.txt) にあります。

## 2. 測定条件

- 対象は同じ runner の `http://127.0.0.1:8080/healthz`。起動したサービスは `app` と `nginx`。
- closed-loop の並列数 1 → 2 → 4 → 8 → 16、各段 20 秒、リクエストの timeout 10 秒。
- 最初に並列 1 で 5 秒の助走を **1 回だけ** 実施。助走 4,902 件は各段の集計に含めない。各段の助走ではない。
- `--no-compose` を指定し、workflow が先に起動した構成を測定。worker 数の変更は指定なし。設定は既定 2 で、app ログにも worker 起動 2 件がある。
- 各段の開始は UTC 08:07:02 / 08:07:25 / 08:07:48 / 08:08:11 / 08:08:34。段を独立に冷却・初期化した比較ではない。
- p95 / p99 は nearest-rank。HTTP 502 を含む **全応答** の分布であり、成功応答だけの分布ではない。
- 原 artifact にあるのは集計済み JSON。全リクエストの個別レイテンシはないため、成功応答だけの p95 は再計算できない。

## 3. 観測値と再計算

下表の件数・p95・全完了 req/s は原 JSON から読み取りました。成功 req/s と HTTP を含む失敗率は、
同じ JSON の件数・経過秒数から算出した派生値です。表示は丸めています。全桁と式は [analysis.json](assets/2026-09-17-performance-ci-analysis/analysis.json) に残します。

| 並列数 | 全完了件数 | HTTP 200 | HTTP 502 | 全完了 req/s | 成功 req/s | p95 ms（全応答） | HTTP を含む失敗率 | 段の再判定 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 12,703 | 12,703 | 0 | 635.047 | 635.047 | 3.148 | 0% | PASS |
| 2 | 9,875 | 9,875 | 0 | 493.678 | 493.678 | 5.897 | 0% | PASS |
| 4 | 18,174 | 11,059 | 7,115 | 908.368 | 552.748 | 10.037 | 39.1493% | **FAIL** |
| 8 | 21,526 | 21,105 | 421 | 1,075.865 | 1,054.823 | 14.596 | 1.9558% | **FAIL** |
| 16 | 18,926 | 18,926 | 0 | 945.668 | 945.668 | 24.310 | 0% | PASS |

- 通信失敗（タイムアウト・接続例外）は全段 0 件。HTTP ステータスは上表の 200 / 502 のみ。
- 再判定は当時の段の基準 `p95 <= 500ms` と `失敗率 <= 0.01` を使用。HTTP を含めると並列 4 / 8 が未達。
- CI の別の error gate は `失敗率 <= 0.05`。同じ原本へ HTTP を含む計算を適用すれば並列 4 で未達となる。
- これは **当時のデータの再判定**。実際の GitHub conclusion `success`、元 JSON の `PASS` を書き換えたものでも、修正コードの runtime 試験でもない。
- 短い試験の PASS は 28 / 30 日の SLO、全サービス、本人の環境、安定した容量の合格を意味しない。

計算式:

```text
HTTP 失敗件数 = response_requests - success_requests
失敗率 = (HTTP 失敗件数 + 通信失敗件数) / total_requests
成功 req/s = success_requests / elapsed_seconds
```

HTTP 502 を含むレイテンシが低くても、利用者は正常な応答を得ていません。
並列 4 の 908.368 req/s のうち、正常応答は 552.748 req/s です。
**処理量と応答時間だけを見て、エラーを見落とさない**ことが、この記録で確認できた点です。

## 4. 欠陥と切り分け

### 集計漏れはコードと原 JSON で確認できる

実行当時の [`load.py`](https://github.com/ns7jp/server/blob/da53d8d7a7ad7eb936d8498f478c406c52a02daf/scripts/perf/load.py) は、
HTTP 4xx/5xx を応答サンプルとして保存し、成功件数から除外していました。
しかし `error_requests` / `error_rate` の分子は通信例外の `ErrorRecord` だけでした。
その結果、`status_counts` に 502 があっても `error_rate: 0.0` と PASS が出ています。
集計の修正後もこの原本は当時の結果として保持し、修正版での再測定は別記録にします。

### Nginx の upstream 接続失敗は観測済み、根本原因は未確定

[compose-errors-excerpt.txt](assets/2026-09-17-performance-ci-analysis/compose-errors-excerpt.txt) に、
並列 4 の開始後、08:07:50Z から `connect() ... failed (99: Address not available) while connecting to upstream`
が記録されています。HTTP 502 と同じ時間帯に Nginx → app の接続が失敗した証拠です。

送信元ポートや接続資源の不足は候補ですが、当時の `ss`、TIME_WAIT、ポート範囲、CPU・メモリの
時系列がありません。**ポート枯渇・CPU 飽和・worker 不足のいずれも根本原因として確定しません。**
速い 502 応答も req/s と分布に入るため、単純な処理能力不足という結論には進めません。

### 自動算出の飽和点を容量として採用しない

元の計算は、並列 1 → 2 の req/s 低下と p95 上昇を最初の頭打ちとみなし、
`saturation_concurrency: 1` を出しました。しかし並列 4 / 8 で処理量は回復し、HTTP 502 も混在しています。
この 1 回の単純な隣接比較から、同時利用者数やサーバー容量を決めることはできません。
同様に `slo_max_concurrency: 16` は最大の試験段であって、安全な上限の証明ではありません。

## 5. 次の実験と完了条件

| 順序 | 確認すること | 残す証拠 | 現在 |
| --- | --- | --- | --- |
| 1 | HTTP 4xx/5xx と通信失敗を両方数え、失敗する段を検出できるか | HTTP 502 を含む回帰試験、混在時の分母、CLI の非ゼロ終了、workflow の判定 | 修正後の検査結果は当該変更の CI / 作業記録を参照。今回の旧 runtime 結果で代用しない |
| 2 | 同じ小構成で 502 を再現できるか | SHA、image、OS、各段 status_counts、成功 req/s、Nginx error、client/server 資源・socket 状態 | NOT RUN |
| 3 | 接続資源の仮説が観測と一致するか | 許可した検証環境で、同じ時刻の `ss -s`、TIME_WAIT 件数、port range、CPU/メモリ。取得不能ならその理由 | NOT RUN |
| 4 | 原因に対応する変更が改善するか | 同じ環境・負荷で baseline と一つの変更を反復比較。変動幅と悪化も残す | NOT RUN |
| 5 | 本人が結果を説明し、別環境でも測定できるか | 本人の実施・判断・参照資料の記録。AI の分析と区別 | NOT RUN |

worker 数を増やすことを既定の解決策にはしません。接続失敗の原因を観測してから一つの変更を選びます。
32 並列、worker 比較、長時間試験、外部ネットワーク・TLS 経路、監視同居の影響、継続 SLO は未実施です。

### 次回に採る診断値（未実施）

開始前・各段の実行中・終了後を同じ UTC 時刻で対応付けます。エラーは Nginx コンテナの
upstream 接続で起きたため、**host の値だけでなく Nginx の network namespace** を観測します。
各値の取得は読取りのみとし、この段階でカーネル設定や Nginx 設定を書き換えません。

| 観測するもの | 取得候補と範囲 | 判断に使うこと |
| --- | --- | --- |
| TCP 状態数 | host と Nginx 側の `ss -s`、`ss -tan` による ESTABLISHED / SYN-SENT / TIME-WAIT の件数。接続先 app:5000 も区別 | 502 の時刻と接続の蓄積が一致するか |
| socket 集計 | Nginx 側の `/proc/net/sockstat` の `TCP inuse`、`orphan`、`tw`、`alloc`、`mem` | 接続状態の増加と失敗の関連 |
| 自動選択ポートの条件 | Nginx 側の `/proc/sys/net/ipv4/ip_local_port_range`、`ip_local_reserved_ports`、`tcp_tw_reuse` | 使用可能範囲と再利用条件。範囲だけで枯渇を断定しない |
| TCP エラー・待受の累積値 | host / Nginx / app の `/proc/net/snmp`、`/proc/net/netstat`。取得できる場合は `TcpActiveOpens`、`TcpAttemptFails`、`TcpRetransSegs`、`TcpExtListenOverflows`、`TcpExtListenDrops` の開始前後差 | 接続開始失敗、再送、app 側待受のあふれを分ける |
| CPU・メモリ・プロセス | host の `vmstat`、`docker stats --no-stream`、app worker の起動・終了・timeout ログ | CPU 飽和や worker 停止を、接続資源の仮説と分ける |
| 版・設定・HTTP 内訳 | container image digest、Nginx version、実際の upstream / proxy 設定、段別 `status_counts` と成功 req/s | 変更した要素と効果の対応。設定全文に秘密値があれば公開前に除く |

コンテナに `ss` がない場合は、既にある host の `nsenter -t <nginx の実 PID> -n ss ...` を使う方法を検討します。
PID と対象 namespace を確認できない場合や権限がない場合は未取得と記録し、host の値を代用した成功にはしません。
`/proc` のファイルは `docker compose exec -T nginx cat <対象ファイル>` で読めるか確認できます。

ポート範囲と予約ポートはそれぞれ自動ポート選択へ影響します。
[Linux kernel の IP sysctl 定義](https://kernel.org/doc/html/latest/networking/ip-sysctl.html)を参照し、対象環境の実値を記録します。
接続再利用は Nginx の版・upstream 設定・HTTP 設定に依存するため、
[Nginx upstream keepalive の定義](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive)と照合してから別の比較実験を設計します。
この資料を読んだことや上の観測案を用意したことは、原因確定・改善効果の証跡ではありません。

## 6. 保存原本と確認方法

数値原本は取得 ZIP からバイトを変えずに複製しています。

- [original-result.json](assets/2026-09-17-performance-ci-analysis/original-result.json) / [original-summary.md](assets/2026-09-17-performance-ci-analysis/original-summary.md)：当時の PASS と飽和点を保持。現在の分析結論と混同しない。
- [step-c1.json](assets/2026-09-17-performance-ci-analysis/step-c1.json)、[step-c2.json](assets/2026-09-17-performance-ci-analysis/step-c2.json)、[step-c4.json](assets/2026-09-17-performance-ci-analysis/step-c4.json)、[step-c8.json](assets/2026-09-17-performance-ci-analysis/step-c8.json)、[step-c16.json](assets/2026-09-17-performance-ci-analysis/step-c16.json)：分母、status_counts、経過秒数、全応答の分布。
- [original-warmup.json](assets/2026-09-17-performance-ci-analysis/original-warmup.json)：集計に含めなかった助走。
- [SHA256SUMS](assets/2026-09-17-performance-ci-analysis/SHA256SUMS)：保存した各ファイルのハッシュ。

```bash
cd docs/evidence/assets/2026-09-17-performance-ci-analysis
sha256sum -c SHA256SUMS
```

ZIP の digest 一致、各段の件数と status_counts の一致、再計算の分母、サマリーと段別 JSON の p95・req/s の一致を確認しています。
抜粋ログは全文ではありません。生 ZIP と全文ログは解析用に保管し、公開資料には数値原本と必要なログ抜粋だけを含めます。
