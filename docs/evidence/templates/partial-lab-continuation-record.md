# 小構成の再起動・運用・別 VM 復元・引き渡し結果票

[実行手順](../../partial-lab-continuation.md)に沿って、Git 除外済みの `.artifacts/continuation/` へコピーして記入します。
この原本と、まだ実行していない欄は `NOT RUN` のまま保持します。本文の期待値は実測結果ではありません。

## 対象と実行主体

| 項目 | 記録 |
| --- | --- |
| 全体状態 | NOT RUN |
| 実施日時・実施者 | NOT RUN |
| VM / OS / メモリ / 空きディスク | NOT RUN |
| 管理端末・SSH / コンソール確認 | NOT RUN |
| Git SHA / dirty 状態 / イメージ ID | NOT RUN |
| 対象サービス | 予定：app/nginx の2サービス |
| 停止時刻・戻れない場合の手順 | NOT RUN |
| 自分が選択・実行した操作 | NOT RUN |
| AI の支援内容・参照資料 | NOT RUN |
| 証拠ファイル・取得時刻 | NOT RUN |

## 再起動・24 時間の間欠点検

| 観点 | 再起動前 | 再接続直後 / +0 | +1h | +6h | +24h以降 |
| --- | --- | --- | --- | --- | --- |
| 実時刻・証拠ファイル | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| machine-id / boot ID | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| SHA・設定ハッシュ・image ID | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Docker / app / nginx 状態 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| HTTPコードと status=ok の本文 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| 未認証401・認証ありの応答 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| メモリ・ディスク・OOM・新規error | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| 判定・理由 | NOT RUN | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

実経過時間：NOT RUN。PC スリープ・観測欠測・手動復旧の時刻と理由：NOT RUN。
4時点の点検を、連続可用性・72時間・全構成の受け入れへ読み替えません。

## 別 VM 復元

| 観点 | 結果・証拠 |
| --- | --- |
| 元 VM / 新 VM の区別、同じ物理PCか | NOT RUN |
| 新規OSから準備した範囲 | NOT RUN |
| コピー前後の archive / 設定 SHA-256 | NOT RUN |
| 新 VM の未使用ボリューム、展開終了コード | NOT RUN |
| 実際の mount・Loki image ID・ready本文 | NOT RUN |
| query / 時間範囲 / 件数 / 元ログとの本文一致 | NOT RUN |
| 開始・終了時刻と計測対象 | NOT RUN |
| コンテナ撤去・archiveとvolumeの保管先 | NOT RUN |
| 判定・限界 | NOT RUN |

全ログ完全性、RPO、別物理ホストの災害復旧：NOT RUN。

## 自分の説明

- 通信経路を自分の言葉で説明：NOT RUN
- 状態・HTTPコード・本文の違いを説明：NOT RUN
- 失敗の症状→調査理由→原因→修正→確認：NOT RUN
- volume再利用・archive復元・別VM復元の違い：NOT RUN
- 参照した資料、AIに教わった点、自力で説明できなかった点：NOT RUN

## 実際の確認者による引き渡し

| 項目 | 記録 |
| --- | --- |
| 確認者・実施日（公開時は同意のある表記のみ） | NOT RUN |
| 渡した手順の版・対象・資格情報の受渡方法 | NOT RUN |
| 確認者が実行した起動・HTTP本文確認 | NOT RUN |
| 計画停止・再開と証拠 | NOT RUN |
| 迷った点・本人の補足・修正した手順 | NOT RUN |
| 確認者の結果・残存課題 | NOT RUN |

確認者不在なら `BLOCKED`。本人や AI を第三者の代わりにしません。

## 終了時の報告

- やったこと：NOT RUN
- 確認できたことと証拠：NOT RUN
- 未実施・失敗・保留と再開位置：NOT RUN
- 起動中のサービス、保持したデータ、終了した接続：NOT RUN
- 公開候補に含めるファイルと除外した個人情報：NOT RUN
