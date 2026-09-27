# lab-base01：変更予測・適用・切り戻しの一連演習（2026-09-15）

## 結果と範囲

本人VMでtraining/8080から8085への変更予測・適用・再実行を行い、旧版8080へ切り戻して
再実行の変更なしを確認した。各段階の画面にAnsible/RUN/TEE終了0とログ保存先が表示され、
最後に5ログの存在とサイズを確認した。**演習用設定ファイルの変更管理**であり、実サービスの変更・復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付） |
| 環境 | プロンプトopsadmin@lab-base01。OS/Ansible版は今回未採録 |
| 作業場所 | /home/opsadmin/ansible-tagged-restore |
| 旧版 | practice/save-ansible-exercises、短縮SHA38559f2 |
| 変更版 | practice/from-tag、短縮SHAdac8a0f |
| 対象 | role-validated-demo.yml、managed-role-validated/app.conf |
| ログ保存先 | /home/opsadmin/ansible-practice-logsのchange-*.log |
| 原資料 | [本人提供画像6枚・ハッシュ](../screenshots/2026-09-15-lab-base01-change-cycle-practice/README.md) |

## 確認結果

CC番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 段階 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| CC-01 | 開始 | PASS | 旧版clean、両ブランチのSHA、本文training/8080・ハッシュ表示（E01） |
| CC-02 | 予測 | PASS | 変更版へswitch、check/diffで8080→8085、changed1/failed0、実ファイル8080と開始ハッシュ維持（E02） |
| CC-03 | 適用 | PASS | --diff付き通常実行、changed1/failed0、本文training/8085へ変更（E03） |
| CC-04 | 適用後確認 | PASS | 通常再実行changed0/failed0、本文8085と前後ハッシュ一致（E04） |
| CC-05 | 切り戻し | PASS | 旧版へswitch、defaults8080、通常実行changed1/failed0、本文8080・開始時ハッシュへ復帰（E05） |
| CC-06 | 最終確認 | PASS | 旧版38559f2、通常再実行changed0/failed0、本文8080とハッシュ維持、Git変更なし（E06） |
| CC-07 | 終了コード | PASS | E02〜E06の全段階でANSIBLE_EXIT=0、RUN_EXIT=0、TEE_EXIT=0 |
| CC-08 | ログ一覧 | PASS | preview/apply/repeat/rollback/finalの5ファイルとサイズを表示（E06） |

予測のchanged1は実書き込みではなく、その後の適用changed1とは区別する。
旧版と変更版を実行した順序は38559f2→dac8a0f→38559f2である。
今回の対象ファイルの最終本文・ハッシュは開始状態と一致したが、全システムの不変性検査ではない。

## 日時とログ

画面で読めるVM日時は適用前10:40:13・後10:40:16、適用後再実行前10:41:17・後10:41:20、
切り戻し後10:43:37、最終確認10:44:41（すべて2026-09-15、+09:00）。時計精度や所要時間保証は未検証。
予測開始日時と切り戻し前情報は画像上部が切れており、当該表示は未採録。

| ログ段階 | 表示サイズ |
| --- | --- |
| preview | 1565 bytes |
| apply | 1429 bytes |
| repeat | 1113 bytes |
| rollback | 1724 bytes |
| final | 1119 bytes |

ログ名の原本は各LOG_FILE行とE06一覧を参照する。
今回はログ本文の独立した読戻し、ログ自体のSHA-256・権限検査、Windows転送は未実施。
画面出力と一覧に基づく記録であり、ログ実体を取得・公開したものではない。

## コマンドとコードの境界

各段階で実行前後の情報とAnsible出力をteeへ渡し、Ansibleの終了コードをグループのexitへ
引き継ぎ、PIPESTATUSからRUN/TEEの値を別々に出す手順を案内した。
COMMAND行は手順が出力した説明で、自動シェルトレースではない。全入力コードの画面採録ではない。
RUN/TEE終了コードとLOG_FILEは保存後の画面出力であり、ログ本文に収録されたという意味ではない。
今回は全段階成功のみで、途中失敗時の中止・自動切り戻しを試験していない。

## 未実施・限界

- 実サービス起動・reload/restart、ポート待受、利用者からの疎通確認は**NOT RUN**。
- 変更失敗時の自動復旧、複数ホスト、新規OSでの試験は**NOT RUN**。
- 全入力ハッシュ・権限・mtime、全ディレクトリの前後比較は未採録。
- 最終HEADの表示は最終実行前。実行後のHEAD読戻しは今回未採録で、Git状態は変更なしを確認。
- ログはVM内に保存。ログ実体の取得・別媒体バックアップは未実施。
- 画像用SHA256SUMS.txtはapp.confやログのハッシュとは別。
- server側の公開用文書コミット・CIと本人VMの実行主体・対象を区別する。

- [前段：タグ版への切り戻し](2026-09-15-lab-base01-tag-rollback-practice.md)
- [検証証跡台帳](../README.md)
