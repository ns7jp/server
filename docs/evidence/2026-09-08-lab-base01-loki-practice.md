# lab-base01：6サービスのログ収集・Loki検索（2026-09-08）

## 結果と範囲

本人のHyper-V VMでLoki・Alloy・docker-socket-proxyを起動し、app・nginx・Grafanaを追加した。
目印 `loki-first` を含むNginxへのHTTPアクセスを作り、Grafana ExploreのLoki検索で
同じ目印を含むGET/401のログ2件を表示した。最後に6コンテナ・4ネットワークを撤去した。

**メモリ2GiBのVMで6サービスに絞ったログ監視の部分演習**であり、
全10サービスの同時稼働・全ログ経路・通知・自動復旧の受け入れではない。
前段の[5サービスの数値監視](2026-09-08-lab-base01-monitoring-practice.md)とは起動対象が異なる。

## 実行環境・証拠

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順・画面操作を案内し、本人が操作してスクリーンショットを提供 |
| 日付 | 2026-09-08 JST（対話の日付）。画像のGrafana表示時刻とログ内UTC時刻は区別する |
| VM | `lab-base01`、Ubuntu Server24.04.4 LTS。今回のfree表示は合計1.9GiB、6サービス時available約1.1GiB、Swap使用0（[E02]） |
| 構成 | app、nginx、Grafana、Loki、Alloy、docker-socket-proxy。Prometheus・node-exporter・Alertmanager・blackboxは今回未起動 |
| イメージ表示 | nginx1.27-alpine、Grafana11.2.2、Loki2.9.0、Alloyv1.16.1、proxy v0.5.0のdigest指定を画面で確認（[E01]、[E02]） |
| 教材版の境界 | 前段で採録したclone SHAは `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`。今回もSHA採録を案内したが結果未提供のため、実行版が同一と厳密には確認できない |
| 参照教材 | [当該SHAの学習ガイド](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/docs/beginner-learning-guide.md)・[Alloy構成](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/deploy/alloy/config.alloy) |
| 原資料 | [原画像7枚・ハッシュ一覧](screenshots/2026-09-08-lab-base01-loki/README.md)。rawログ全文・連続操作録画は未提供 |
| PRの境界 | 今回の編集環境からVMへ接続して試験したものではない。PR/CIの版や文書検査を本人VMの実測と同一視しない |

AD・WSUS VMを停止しないという本人の制約を維持し、VMのメモリ増設を前提にしない構成とした。
観測時のメモリ余裕は長期・高負荷時の安定性保証ではない。

## 起動と目印の生成

案内した起動範囲は以下。画像では起動後の一覧を確認する。

```bash
docker compose up -d loki docker-socket-proxy alloy
docker compose up -d app nginx
docker compose up -d --no-deps grafana
```

Grafanaを`--no-deps`で追加し、Prometheus等の数値監視サービスを追加起動しない。
Lokiの `http://127.0.0.1:3100/ready` は最初 `Ingester not ready: waiting for 15s after being ready`、
待機後の確認で `ready` となった（[E02]、[E03]）。実際の待ち時間の測定値は未採録。

Nginxへ次の目印付きGETを送り、HTTP401を確認した（[E03]）。
認証なしの要求のため401は期待どおりで、ログ生成の目的を満たす。

```bash
curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8080/?lab_check=loki-first'
```

## 確認結果

LP番号はこの報告書専用の観点IDであり、全構成の必須試験IDではない。

| ID | 観点 | 判定 | 結果と資料 |
| --- | --- | --- | --- |
| LP-01 | 収集基盤の起動 | PASS | Loki・Alloy・proxyの3件がUp（[E01]） |
| LP-02 | 6サービス構成 | PASS | 6件がUp、app healthy。利用可能メモリ約1.1GiB・Swap0（[E02]） |
| LP-03 | Loki準備状態 | PASS | 初回の準備待ちから、再確認でready（[E02]、[E03]） |
| LP-04 | 目印付きアクセス | PASS | `/?lab_check=loki-first`が401（[E03]） |
| LP-05 | Grafanaで検索 | PASS | 下記LogQLの入力と、同じ目印を含むログ2件・GET/401を表示（[E06]） |
| LP-06 | 終了・撤去 | PASS | 6コンテナと4ネットワークRemoved、compose psにサービス行なし（[E07]） |

使用した検索式：

```logql
{compose_project="server-monitor-lab", service="nginx"} |= "loki-first"
```

検索結果の共通ラベルはservice=nginx、method=GET、status=401、job=containers。
画面上の結果は2026-09-08 15:57:53.081と16:04:56.004の2件で、行内のNginx時刻は
06:57:53 +0000と07:04:56 +0000（[E06]）。画面と行内の時差を送信遅延と解釈しない。
この範囲で、Nginxのログが収集・保存されGrafanaで検索できることを確認した。
Alloy/proxyの内部通信を個別にパケット採録したり、全サービスのログ欠落を検査したわけではない。

## つまずきと対応

ExploreでNo dataが表示された時点では、上部の青い表示に検索式が見えていたが、
Builderの入力は未設定（[E04]）。Codeへの切替後にも実際の入力欄は空だった（[E05]）。
「Enter a Loki query」の欄へ検索式を入れて実行する操作を案内し、最終的に
入力済み式と検索結果を確認した（[E06]）。目印の再生成・時間範囲の確認も案内したため、
初回No dataの全原因を入力欄だけに確定しない。収集障害や構成コードの欠陥を発見したとは扱わない。

## 終了状態と未実施範囲

- `docker compose down`でgrafana/nginx/alloy/proxy/loki/appの6件と、
  frontend/docker-api/monitoring/host-accessの4ネットワークを撤去（[E07]）。
- `-v`を付けない終了手順なので名前付きボリュームを削除する操作ではない。
  終了後のvolume一覧・保存ログの再読込み・バックアップ復元は **NOT RUN**。
- 最終画像のプロンプトにはvenv表示がないが、deactivateコマンドそのものは未採録。
- WindowsのSSHトンネル再開・ログインを案内しGrafana画面を確認したが、
  トンネル起動の実行画像とCtrl+Cでの終了確認は未提供。
- .env・秘密値の再生成や削除は案内していない。終了後のハッシュ・存在再確認は未採録。
- ホストのauth.log/syslogの検索、全コンテナのログ網羅性、読み取り専用proxyのPOST拒否の再試験、
  通知、D-1、数値監視との全10サービス同時稼働、長期稼働、性能、再起動後の再現性は **NOT RUN**。
- Ansible・AWS・組織環境・第三者への引き渡し・独力での説明完了を示す記録ではない。
- PR作成時のPNG・ハッシュ・リンク・差分検査は文書検査。VM試験を再実行したものではない。

- [検証証跡台帳](README.md)
- [前段の数値監視](2026-09-08-lab-base01-monitoring-practice.md)
- [原画像7枚・SHA-256](screenshots/2026-09-08-lab-base01-loki/README.md)

[E01]: screenshots/2026-09-08-lab-base01-loki/E01-collectors-start.png
[E02]: screenshots/2026-09-08-lab-base01-loki/E02-six-services.png
[E03]: screenshots/2026-09-08-lab-base01-loki/E03-ready-and-request.png
[E04]: screenshots/2026-09-08-lab-base01-loki/E04-explore-builder-empty.png
[E05]: screenshots/2026-09-08-lab-base01-loki/E05-explore-code-empty.png
[E06]: screenshots/2026-09-08-lab-base01-loki/E06-logs-found.png
[E07]: screenshots/2026-09-08-lab-base01-loki/E07-cleanup.png
