# lab-base01：Ansibleハンドラー演習（2026-09-11〜14）

## 結果と範囲

本人VMで設定ファイルの変更時だけハンドラーが動くことを確認した。
初回はchanged4、同内容での再実行はchanged0、8082への変更はchanged2、
同じ8082指定での再実行はchanged0。再実行時はマーカーの更新時刻が一致した。
**ホーム内のファイル生成とマーカー更新**の演習であり、実サービスのreload/restartや
ポート待受を実測したものではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 前提〜8082変更の画像提供は2026-09-11、最後の再実行画像提供は2026-09-14 JST（対話日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。Ansible core 2.16.3、Python 3.12.3（E01）。OS版は今回未採録 |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| 入力 | handlers-demo.ymlと既存templates/app.conf.j2。Playbook実ファイル全文・ハッシュは未採録 |
| 出力 | managed-handlers/app.conf、static.txt、reloaded.marker |
| 証拠 | [本人提供画像5枚・ハッシュ](screenshots/2026-09-14-lab-base01-handlers-practice/README.md) |

## 実施内容

既存テンプレートはenvironment_nameとlisten_portを参照する2行（E01）。
案内したPlaybookはlocalhostへのlocal接続で、出力ディレクトリ作成、template、copyの3タスク。
templateとcopyが同名ハンドラーへnotifyし、ハンドラーはfileモジュールのstate: touchで
reloaded.markerを更新する構成とした。実ファイル全文との同一性は未検証で、以下は
表示されたタスク・結果・本文の範囲を記録する。

## 確認結果

HP番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| HP-01 | 開始状態 | PASS | main clean、Ansible版・テンプレート本文、演習用2パスNOT FOUND（E01） |
| HP-02 | 構文確認 | PASS | syntax-checkの後、AND連結で通常実行へ進んだ（E02）。数値の終了コードは未採録 |
| HP-03 | 初回生成 | PASS | 3タスクchanged、RUNNING HANDLERが1回、ok4/changed4/failed0（E02） |
| HP-04 | 初回本文 | PASS | environment=staging、listen_port=8081、static、マーカー作成（E02） |
| HP-05 | 8081再実行 | PASS | ok3/changed0/failed0、終了0、ハンドラー表示なし、前後mtime一致（E03） |
| HP-06 | 8082変更 | PASS | -e listen_port=8082、templateとハンドラーのみchanged、ok4/changed2/failed0、終了0（E04） |
| HP-07 | 変更後の本文・時刻 | PASS | listen_port=8082、staticを確認、マーカーmtimeが更新（E04） |
| HP-08 | 8082再実行 | PASS | ok3/changed0/failed0、終了0、ハンドラー表示なし、前後mtime一致、本文8082（E05） |
| HP-09 | 最終Git状態 | PASS | main、handlers-demo.ymlとmanaged-handlers/が??。追跡済みファイルの変更行なし（E05） |

初回に2つの通知元タスクがchangedとなり、表示されたハンドラー実行は1回だった。
これは案内構成と整合するが、実ファイルのnotify設定全文を独立して採録したわけではない。

## マーカーの観測値

- 初回と8081再実行の前後：2026-09-11 18:54:27.665790865 +0900。
- 8082変更後と最終再実行の前後：2026-09-11 18:58:43.344112531 +0900。

これらはファイルmtimeであり、最後の再実行日時が9月11日だったという意味ではない。
再実行の実行時刻・VM時計精度は別途採録していない。

## 最終状態・未実施

- 設定本文はstaging/8082。通常の既定値8081へ戻す操作は今回未実施。
- Playbookと生成ディレクトリは未追跡のまま残っている。Gitコミット・ignore追加・削除は未実施。
- 実サービス再起動・reload・ポート待受、site.yml/foundation.yml実行は**NOT RUN**。
- flush_handlers、listen、失敗時のハンドラー挙動、loop演習は**NOT RUN**。
- Playbook全文・入力ハッシュ・連続rawログ・実行対象コミットとの紐付けは未採録。
- 生成物の権限や内容全体のハッシュは未採録。画像に表示された本文とmtimeに限定する。
- server側の公開用コミット・文書検査・CIを本人VMでの実行実績と混同しない。

## 手順案との差異と復習

既存のmanaged-templateではなく、未使用を確認したmanaged-handlersを使った。
ハンドラーはshellのdateではなくfileのtouchで更新し、テンプレート自体を編集せず-eでポート値を変更した。
実サービスへの操作は行わず、マーカーで通知の有無を観測した。

変更があれば通知、同じ内容なら通知なし。同じハンドラーへの通知は今回の通常実行では末尾に1回実行された。
この説明はAIによる復習用で、本人独力による説明の採録ではない。

- [手順案](../roadmap/lab-base01-ansible-next-exercises.md)
- [検証証跡台帳](README.md)
