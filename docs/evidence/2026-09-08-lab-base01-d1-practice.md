# lab-base01：D-1アプリ自動再起動・HTTP復帰の実測（2026-09-08）

## 結果と境界

本人のHyper-V VM上のapp/nginx最小構成で、アプリ異常終了後の再起動回数0→1、
PID11749→12186、HTTP復帰のスクリプト計測2秒を確認した。
計測直後はhealth startingだったが、後続確認でhealthyとHTTP200を確認した。
最後に2コンテナと3ネットワークを撤去した。

**このVMの1回の実行で、アプリ自動再起動とHTTP応答復帰を確認した記録**である。
2秒は秒単位のスクリプト計測で、Dockerのhealthy判定までの時間、アラート検知時間、
全機能の復旧時間、本番のRTO保証ではない。外部通知・別ホスト復旧は **NOT RUN**。

## 来歴・構成

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を案内し、本人が操作・結果画像を提供 |
| 対象 | 前段から継続するHyper-V VM lab-base01、Ubuntu Server24.04.4 LTS、opsadmin |
| 開始時HEAD | `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`（[E01]）。終了時のHEAD・dirty状態・スクリプトハッシュ再採録は未実施 |
| 教材 | [当該SHAのD-1スクリプト](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/scripts/drills/d1-process-down.sh) |
| 起動対象 | app/nginxの2サービス。監視・通知の全構成は今回起動しない |
| 再起動設定 | appのrestart policyはunless-stopped。running=true、count0を事前確認（[E01]） |
| 原資料 | [原画像4枚・由来・SHA-256](screenshots/2026-09-08-lab-base01-d1/README.md)。連続rawログは未提供 |
| AIの担当 | 手順案内、画像読取り、文書作成・文書検査。本人VMへの接続・試験代行ではない |

## 実施経路

事前にappがhealthy、nginxがUp、`http://127.0.0.1:8080/healthz`が200であることを確認した（[E01]）。
sudoの認証待ちを計測に混ぜないため`sudo -v`を先に行い、以下を実行するよう案内した。

```bash
bash scripts/drills/d1-process-down.sh --service app --project-dir /home/opsadmin/server --timeout 60
```

起動コマンド・sudo認証・kill操作の行そのものは最終サマリー画像に写っていない。
コマンドは「案内した手順」、後述の数値は「提供画像で確認した結果」と区別する。
教材スクリプトはDockerから対象コンテナのホスト側PIDを取得してSIGKILLを送り、
HTTP応答復帰をポーリングする実装。試験中に手動start/restartを行わないよう案内した。
手動介入がなかったことを連続操作ログで独立監査した記録ではない。

## 試験結果

D1番号はこの報告書の確認観点で、過去のD-1結果と合算しない。

| ID | 観点 | 判定 | 画像・結果 |
| --- | --- | --- | --- |
| D1-01 | 正常時の応答と設定 | PASS | app healthy、nginx Up、HTTP200、running=true、PID11749、unless-stopped、count0（[E01]） |
| D1-02 | スクリプトの復帰判定 | PASS（計測範囲限定） | recover_seconds2、verdict PASS、終了コード0（[E02]） |
| D1-03 | 再起動の確認 | PASS | サマリーcount0→1、inspect count1/running=true/PID12186（[E02]） |
| D1-04 | healthyへの復帰 | PASS | 計測直後のstartingから、後続確認でhealthyとHTTP200（[E02]、[E03]） |
| D1-05 | 終了・撤去 | PASS | downで2コンテナ・3ネットワークRemoved、psにサービス行なし（[E04]） |

### 計測値

| 項目 | 画像に表示された値 |
| --- | --- |
| kill_at | 2026-09-08T09:16:56Z（JST18:16:56） |
| recover_at | 2026-09-08T09:16:58Z（JST18:16:58） |
| recover_seconds | 2 |
| rto_target_seconds | 300（スクリプト内の目標値） |
| restart_count | 0 → 1 |
| verdict / 終了コード | PASS / 0 |

案内した待機上限は`--timeout 60`。表示された300はスクリプト内の固定目標値であり、
待機上限を300秒で実行した証拠ではない。スクリプト起動行が未採録のため、実際の引数全体は未確認。
タイムスタンプとRESULT_JSONは画像内のスクリプト出力であり、独立した時計による計測ではない。

教材スクリプトは`date +%s`とHTTPポーリングを使用する。curl -fの成功を復帰判定とし、
再起動回数の増加をPASS条件に組み込んでいないため、今回はサマリーだけに依存せず
実際のcount増加・PID変化と後続のHTTP200/healthyを併せて確認した。
停止中のHTTP失敗を連続採録したものではなく、サブ秒精度・healthy到達時間も測定していない。

## 終了状態と未実施事項

- app/nginxとmonitoring/frontend/host-accessの3ネットワークを撤去（[E04]）。
- downに`-v`を付けない終了手順。既存volumeの削除は指示していないが、終了後一覧の再確認は未採録。
- この記録で再起動回数の増加とPID変化が観測できた。SIGKILL操作の生ログやDocker eventsの連続記録は未提供。
- Prometheus/Grafanaでの停止検知、Alertmanager/Slack通知、ログ収集との同時検証は **NOT RUN**。
- 2秒をアラート通知・全機能・healthy到達までの復旧時間として扱わない。
- 反復試験、負荷時・長期稼働、別ホスト・VM喪失からの復旧、D-2、AWS、Ansible適用は **NOT RUN**。
- 本人の独力での再実施・自分の言葉での説明を確認した記録ではない。
- 今回のPR作成環境では画像・リンク・差分の検査のみ。新たなVM試験やCIの実測を追加したものではない。

- [検証証跡台帳](README.md)
- [前段のバックアップ復元](2026-09-08-lab-base01-restore-practice.md)
- [原画像4枚・ハッシュ](screenshots/2026-09-08-lab-base01-d1/README.md)

[E01]: screenshots/2026-09-08-lab-base01-d1/E01-before.png
[E02]: screenshots/2026-09-08-lab-base01-d1/E02-summary.png
[E03]: screenshots/2026-09-08-lab-base01-d1/E03-healthy.png
[E04]: screenshots/2026-09-08-lab-base01-d1/E04-cleanup.png
