# lab-base01：コンテナ再作成後の保存ログ再読込み（2026-09-08）

## 結果と範囲

前回の[ログ監視演習](2026-09-08-lab-base01-loki-practice.md)でコンテナを削除した後、
保存用ボリュームを残した状態からLokiとGrafanaだけを再作成し、同じ目印・時刻のログ2件を
再表示した。終了時にもコンテナを削除し、ボリュームが残っていることを確認した。

**同じホスト上の名前付きボリュームを再利用したデータ保持の確認であり、バックアップ復元ではない。**
ホスト喪失・ボリューム破損からの復旧、全ログの完全性、全10サービスの受け入れは対象外。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順・画面操作を案内し、本人が実行・画像提供 |
| 日付 | 2026-09-08 JST（対話の日付）。全操作の開始終了時刻は未採録 |
| 環境 | 前段から継続するHyper-V VM lab-base01、Ubuntu Server24.04.4 LTS、メモリ2GiBの演習環境 |
| 開始時HEAD | `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`（[E01]）。終了時HEAD・設定ファイル全量の再採録は未実施 |
| 起動対象 | Loki2.9.0とGrafana11.2.2のみ（[E02]） |
| 資料 | 本人提供の[原画像5枚とハッシュ一覧](screenshots/2026-09-08-lab-base01-persistence/README.md)。連続rawログは未提供 |
| 前後比較 | 前回の[検索成功画像](screenshots/2026-09-08-lab-base01-loki/E06-logs-found.png)と、今回の[E04]を照合 |
| PRの境界 | 今回の記録編集環境からVMを再操作したものではない。文書検査・CIと本人VMの試験を区別 |

## 確認結果

PV番号は本報告書専用の観点ID。

| ID | 観点 | 判定 | 実測結果 |
| --- | --- | --- | --- |
| PV-01 | 再作成前の状態 | PASS | compose psにサービス行なし。alloy_data/grafana_data/loki_data/prometheus_dataの4件が残存（[E01]） |
| PV-02 | コンテナの再作成 | PASS | `up -d --no-deps loki grafana`によりLoki/Grafanaの2件だけUp。3ネットワーク作成（[E02]） |
| PV-03 | 応答準備 | PASS | Grafana database ok、Lokiは準備待ち後ready（[E02]、[E03]） |
| PV-04 | 過去ログの再読込み | PASS | Grafanaで前回と同じ15:57:53.081と16:04:56.004のGET/401・loki-firstログ2件を再表示（[E04]） |
| PV-05 | 終了と保存先の残存 | PASS | downで2コンテナ・3ネットワークRemoved、psにサービス行なし、4ボリューム残存（[E05]） |

対象コンテナを作り直す操作：

```bash
docker compose up -d --no-deps loki grafana
```

Nginx・Alloy・docker-socket-proxy等を起動せず、新しい目印アクセスを生成しない手順で進めた。
既存の保存先から読み出すことを確認するためであり、ログ生成からの経路試験は前段の別記録。
全Dockerコンテナの監査や別プロジェクトからの書込み有無を網羅的に検査したわけではない。

検索には次の式と、日本時間2026-09-08 15:50〜16:10の絶対時間範囲を指定するよう案内した。

```logql
{compose_project="server-monitor-lab", service="nginx"} |= "loki-first"
```

最終画像にはクエリ欄・時間選択欄の設定値全体は写っていないため、これらは案内した条件として記載する。
画像で直接確認できる結果は、2 displayed、目印loki-first、method=GET、service=nginx、status=401と
上記2時刻のログ行。行内Nginx時刻は06:57:53/07:04:56 +0000で、Grafana表示時刻との9時間差は
タイムゾーンの違いであり、転送遅延ではない。

保存済みファイルの全件ハッシュ照合、全ログ件数比較、再起動・長期保持は未実施であり、
今回の2件の再表示から全データの完全性を推定しない。Grafanaの既存ユーザー・設定すべての永続性も未検証。

## つまずきと対応

| 事象 | 対応と確認 | 限界 |
| --- | --- | --- |
| Lokiの準備待ち | 待機後readyを確認（[E02]、[E03]） | 準備所要時間は未測定 |
| LogQLをUbuntuターミナルへ入力 | command not foundを確認し、ブラウザのExplore/Code欄へ入力するよう案内（[E03]） | 検索式はBashコマンドではない。設定ファイル破損とは扱わない |
| Grafanaを開けないという本人申告 | WindowsでSSHトンネルを再開する手順を案内し、本人が開けたと回答。その後ログ画面を提供（[E04]） | トンネルの起動出力・初回のブラウザエラーは未採録。原因がトンネル終了だったと断定しない |

## 最終状態と未実施範囲

- Loki/Grafanaの2コンテナとfrontend/monitoring/host-accessの3ネットワークを撤去（[E05]）。
- `docker compose down`に`-v`を付けず、4ボリュームの存在を前後で確認した。
  同名・同ドライバーの一覧確認であり、内部ファイル全量やvolume inspectの同一性確認ではない。
- Lokiの過去ログ2件の再読込みは今回確認済み。Prometheus/Alloyのデータ再読込みは **NOT RUN**。
- バックアップ取得・別ボリュームへの復元・ホスト障害復旧・データ破損試験・RTO/RPO測定は **NOT RUN**。
- 全10サービス同時稼働、長期稼働、外部通知、自動復旧D-1、Ansible、AWSは **NOT RUN**。
- SSHトンネルのCtrl+C終了は案内済みだが完了申告・画像は未提供。
- この報告書の作成・検証は文書の処理で、本人VMの新たな実行や自力習得の証明を追加するものではない。

- [検証証跡台帳](README.md)
- [前段のログ監視演習](2026-09-08-lab-base01-loki-practice.md)
- [原画像・ハッシュ](screenshots/2026-09-08-lab-base01-persistence/README.md)

[E01]: screenshots/2026-09-08-lab-base01-persistence/E01-before.png
[E02]: screenshots/2026-09-08-lab-base01-persistence/E02-recreated.png
[E03]: screenshots/2026-09-08-lab-base01-persistence/E03-ready-and-input-error.png
[E04]: screenshots/2026-09-08-lab-base01-persistence/E04-stored-logs.png
[E05]: screenshots/2026-09-08-lab-base01-persistence/E05-after.png
