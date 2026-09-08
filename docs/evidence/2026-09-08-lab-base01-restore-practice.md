# lab-base01：Lokiバックアップと別ボリュームへの復元（2026-09-08）

## 結果と範囲

本人のHyper-V VMで、停止中のLokiデータを読み取り専用でtarアーカイブへ保存し、
別名のDockerボリュームへ展開する手順を実施した。復元先を使う確認用Lokiの3110番ポートから
過去の目印付きGET/401ログ2件を読み出し、最後に確認用コンテナを撤去した。

**同一VM内の別ボリュームへのバックアップ復元試験**である。
前段の[同じボリュームからの再読込み](2026-09-08-lab-base01-persistence-practice.md)とは区別する。
別ホストへの災害復旧、全データの完全性、RTO/RPOの測定は **NOT RUN**。

## 来歴と対象

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIの手順案内に沿って操作し、結果画像を提供 |
| 日付 | 2026-09-08 JST（対話の日付）。各工程の正確な開始終了時刻は未採録 |
| 環境 | 前段と同じ個人学習用Hyper-V VM lab-base01、Ubuntu24.04.4 LTS、opsadmin |
| 開始時HEAD | `1e5b3335cdf0d8ca7d0726b4411792be9f38c73a`（[E01]）。終了時HEADや全設定ハッシュは未採録 |
| 教材 | [当該SHAのバックアップ・復旧設計](https://github.com/ns7jp/server/blob/1e5b3335cdf0d8ca7d0726b4411792be9f38c73a/docs/backup-restore.md)を参照。今回は手動・Loki単独の試験 |
| 元ボリューム | `server-monitor-lab_loki_data`。開始時に使用中のコンテナなし、read-onlyで約1.0M（[E01]、[E02]） |
| バックアップ | `/home/opsadmin/lab-backups/loki-20260908/loki-data.tgz`、表示サイズ499K。隣にSHA256SUMS（[E03]） |
| 復元先 | `lab-loki-restore-20260908`。別名の復元先として使用、確認時約1.0M（[E04]） |
| 確認用コンテナ | `lab-loki-restore-check`、grafana/loki:2.9.0を使う手順。復元先を/lokiへマウント、Ubuntuの127.0.0.1:3110で確認（[E05]） |
| アーカイブ作業用イメージ | alpine:3.22。取得時のdigestは画像内に記録（[E02]） |
| 証拠 | [原画像7枚と由来・SHA-256](screenshots/2026-09-08-lab-base01-restore/README.md)。連続rawログは未提供 |

画像ハッシュは本PRへのコピー確認用。VM内のバックアップ用SHA256SUMSとは別物である。
バックアップ本体やVM内のSHA256SUMSの中身はこのPRへ取得・公開していない。

## 手順と確認結果

BR番号は本報告書専用の観点IDで、全構成・D-2の受け入れIDではない。

| ID | 観点 | 判定 | 記録 |
| --- | --- | --- | --- |
| BR-01 | 停止と元データの存在 | PASS | Composeサービス行なし、volume使用中コンテナなし、元volume存在、空き9G（[E01]） |
| BR-02 | 読み取り専用で容量確認 | PASS | readonlyマウントでdu約1.0M（[E02]） |
| BR-03 | バックアップ作成 | PASS | 元volumeをreadonlyでtar czf、終了0、アーカイブ499K（[E03]） |
| BR-04 | アーカイブのチェックサム | PASS | SHA256SUMS生成後、sha256sum -cがOK（[E03]）。第三者署名やコピー先検査ではない |
| BR-05 | 別名保存先のデータ確認 | PASS（限定） | 復元先du約1.0M（[E04]）。同画像の終了0は直前の展開コマンドが写っていないため、tarの終了値と画像単独では結び付けられない |
| BR-06 | 復元先でLokiを準備 | PASS | inspectで別名volume→/lokiを確認、3110番ready（[E05]） |
| BR-07 | 復元後のログ検索 | PASS | 3110番のquery_rangeでstatus success、totalEntriesReturned 2、目印付きGET/401ログ2件（[E06]） |
| BR-08 | コンテナ撤去と保管 | PASS | stop/rm後コンテナ行なし、元/復元先volume残存、バックアップの再検査OK（[E07]） |

バックアップ作成は、元ボリュームを`/data`へ読み取り専用でマウントし、
`tar czf /backup/loki-data.tgz -C /data .`を実行。復元は別名ボリュームを`/restore`へ、
バックアップのディレクトリを読み取り専用で`/backup`へマウントし、
`tar xzf /backup/loki-data.tgz -C /restore`を案内した。
元データへの上書きはしない手順で、最終的にも元ボリュームの存在を確認している。
元ボリュームの全ファイルが不変であることをハッシュ比較で証明したわけではない。

復元先の事前不存在確認、volume create、tar展開、確認用docker runの完全な実行行は
画像未採録。本人はそれらの手順に続けて結果を提供したが、画像で直接確認できる範囲を上表に限定する。
Loki起動後は復元先に内部データを書き込む可能性があるため、展開直後と稼働後の全量一致も主張しない。

## ログの照合

確認したクエリはUbuntu内の`http://127.0.0.1:3110/loki/api/v1/query_range`に対する以下の条件（[E06]）。

- query: `{compose_project="server-monitor-lab",service="nginx"} |= "loki-first"`
- start: `2026-09-08T06:50:00Z`
- end: `2026-09-08T07:10:00Z`
- limit: 10

結果はtotalEntriesReturned=2、ログ本文のUTC時刻07:04:56/06:57:53、
`GET /?lab_check=loki-first HTTP/1.1`、401を確認。
前回の[ログ検索画像](screenshots/2026-09-08-lab-base01-loki/E06-logs-found.png)および
[同一ボリューム再読込み](2026-09-08-lab-base01-persistence-practice.md)の2件と照合できる。
Grafanaを復元したのではなく、復元先LokiのAPIを直接照会した結果である。

## 最終状態・未実施範囲

- 復元確認用コンテナは停止・削除済み。元のvolume、復元先volume、アーカイブを保管（[E07]）。
- 最終sha256sum -cのOKは、作成したチェックサムとの一致。バックアップ全データの論理整合性を保証しない。
- 同じVM・同じ仮想ディスク上に元データとバックアップを保存。ホスト/ディスク喪失に耐える保管ではない。
- 元/復元先の全ファイルハッシュ比較・全ログ件数比較・全データの完全性は **NOT RUN**。
- 別ホスト復元、VM喪失・ディスク破損想定、RTO/RPO、定期バックアップ、外部保管は **NOT RUN**。
- Ansible backup role、3-volume復元スクリプト、Grafana/Prometheus/Alloyのバックアップ復元は **NOT RUN**。
- 本演習で全10サービス・外部通知・自動復旧D-1・AWSを検証したとは扱わない。
- 本報告書作成時は画像・リンク・差分の文書検査のみ。AIが本人VMへ接続し再実行したものではない。

- [検証証跡台帳](README.md)
- [前段：保存ログ再読込み](2026-09-08-lab-base01-persistence-practice.md)
- [原画像7枚・ハッシュ](screenshots/2026-09-08-lab-base01-restore/README.md)

[E01]: screenshots/2026-09-08-lab-base01-restore/E01-preconditions.png
[E02]: screenshots/2026-09-08-lab-base01-restore/E02-source-size.png
[E03]: screenshots/2026-09-08-lab-base01-restore/E03-archive.png
[E04]: screenshots/2026-09-08-lab-base01-restore/E04-extracted.png
[E05]: screenshots/2026-09-08-lab-base01-restore/E05-restore-mount-ready.png
[E06]: screenshots/2026-09-08-lab-base01-restore/E06-restored-query.png
[E07]: screenshots/2026-09-08-lab-base01-restore/E07-cleanup.png
