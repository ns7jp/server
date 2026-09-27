# lab-base01：block・rescue・always演習（2026-09-14）

## 結果と範囲

本人VMで意図的なタスク失敗からrescueへ進み、alwaysによる後処理まで実行した。
正常条件への切替ではrescueが実行されず、本文normalとマーカー更新を確認。
同じ正常条件での再実行では本文が維持され、後処理のみchangedとなった。
**ホーム内の結果ファイルとマーカーによる制御フロー演習**であり、実サービスの復旧・切り戻しではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。正確な実行・撮影時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。Ansible core 2.16.3、Python 3.12.3（E01）。OS版は未採録 |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 入出力 | block-demo.yml、managed-block/result.txt、managed-block/always.marker |
| 原資料 | [本人提供画像4枚・ハッシュ](../screenshots/2026-09-14-lab-base01-block-practice/README.md) |

## 案内した構成

localhostへlocal接続し、ディレクトリを作成する。blockではsimulate_failureが真なら
failモジュールで意図的に失敗させ、それ以外ではcopyでnormalを記録する。
rescueではrecoveredを記録し、alwaysではfileのstate: touchでマーカーを更新する。
Playbookの実ファイル全文・ハッシュは未採録であり、提示コードとの完全同一性は未検証。

## 確認結果

BP番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| BP-01 | 前提 | PASS | main、既存演習4パス未追跡、今回2パスNOT FOUND、版情報（E01） |
| BP-02 | 構文確認 | PASS | syntax-check後、AND連結で通常実行に進む（E02）。構文確認単独の数値終了コードは未採録 |
| BP-03 | 失敗と対処 | PASS | Planned failure for practice、Record recovery、Record final processingの順に実行（E02） |
| BP-04 | 対処後の状態 | PASS | 本文recovered、マーカー作成。ok3/changed3/failed0/rescued1、終了0（E02） |
| BP-05 | 正常条件 | PASS | -e simulate_failure=false。失敗タスクskipping、正常処理と後処理を実行、rescue実行なし（E03） |
| BP-06 | 正常時の状態 | PASS | 本文normal、マーカー更新。ok3/changed2/failed0/skipped1/rescued0、終了0（E03） |
| BP-07 | 同条件再実行 | PASS | 正常処理はok、後処理だけchanged。本文normal維持、マーカー更新（E04） |
| BP-08 | 最終集計・Git | PASS | ok3/changed1/failed0/skipped1/rescued0、終了0。main、新旧演習6パス未追跡（E04） |

意図的失敗の回は、途中にFAILEDがあってもrescueが成功し、最終failed0・rescued1・終了0となった。
これを「失敗が一度もなかった」と扱わない。recoveredという本文も対処用タスクの実行記録であり、
システムの正常性や実サービス復旧の証明ではない。

## マーカー更新時刻

- 初回：2026-09-14 10:50:12.171784207 +0900（E02）。
- 正常条件への切替後：2026-09-14 10:53:04.362902862 +0900（E03）。
- 同じ正常条件での再実行後：2026-09-14 10:54:52.979608161 +0900（E04）。

各値はファイルmtimeの表示。撮影時刻・VM時計精度を独立に保証するものではない。
always内でtouchする設計のため、同条件でも後処理はchangedとなる。
今回のchanged1は結果ファイルの本文が再変更されたことを意味しない。

## 最終状態・未実施

- result.txtはnormal。最後の実行ではsimulate_failure=falseを指定した。
  案内したPlaybookの既定値はtrueなので、引数なしで再実行する案内はしていない。
- mainにblock-demo.yml、handlers-demo.yml、loop-demo.ymlと各managedディレクトリが未追跡で残る。
  コミット・ignore追加・生成物削除は未実施。追跡済みファイルの変更行は表示されていない。
- 実サービス復旧、バックアップ復元、ポート待受、site.yml実行は**NOT RUN**。
- rescue自体の失敗、到達不能ホスト、構文エラー、強制中断時のalways挙動は**NOT RUN**。
  今回の通常タスク失敗と成功の結果を、あらゆる失敗時のalways保証へ一般化しない。
- 実Playbook全文・入力ハッシュ・実行コミット・連続rawログ・ファイル権限は未採録。
- server側の文書検査とCIは、本人VM内の実行主体・対象とは別。

## 復習

blockは通常処理、rescueは今回のタスク失敗への対処、alwaysは今回の両経路で行った後処理。
終了コードだけでなくrescuedとタスク出力も読む。毎回更新するtouchではchangedが残る。
これはAIによる復習用説明で、本人独力による説明を採録したものではない。

- [前段：loop](2026-09-14-lab-base01-loop-practice.md)
- [検証証跡台帳](../README.md)
