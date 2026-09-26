# lab-base01：タグ版の再適用による切り戻し（2026-09-15）

## 結果と範囲

変更コミットdac8a0fの生成結果training/8085から、タグpractice-validated-v1の38559f2へ
ソースを切り替え、Ansible通常実行でtraining/8080へ戻した。Git切替だけでは生成物が変わらず、
再適用でchanged1、再実行でchanged0になることを確認した。
**ホーム内の設定ファイルの切り戻し**であり、サービス再起動・通信・サーバー全体の復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付） |
| 環境 | プロンプトopsadmin@lab-base01。OS/Ansible版は今回未採録 |
| 作業場所 | /home/opsadmin/ansible-tagged-restore |
| 開始版 | practice/from-tag、短縮SHAdac8a0f |
| 切り戻し版 | practice-validated-v1、短縮SHA38559f2 |
| 最終ブランチ | practice/save-ansible-exercises |
| 再適用直前のVM日時 | 2026-09-15T10:27:12+09:00（E03）。時計精度は未検証 |
| 原資料 | [本人提供画像4枚・ハッシュ](../screenshots/2026-09-15-lab-base01-tag-rollback-practice/README.md) |

## 確認結果

RB番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| RB-01 | 開始状態 | PASS | from-tag clean、HEADdac8a0f、タグ38559f2、本文training/8085・ハッシュ表示（E01） |
| RB-02 | ソース切替 | PASS | switch --detachで38559f2。defaultsはtraining/8080へ戻る（E02） |
| RB-03 | 生成物の維持 | PASS | Git切替後も本文training/8085、SHA-256がE01と一致。HEAD (no branch)、変更なし（E02） |
| RB-04 | 再適用 | PASS | --diff付き通常実行、8085削除/8080追加、ok3/changed1/failed0、終了0（E03） |
| RB-05 | 切り戻し結果 | PASS | 本文training/8080と新しいSHA-256、Git変更なし（E03） |
| RB-06 | 同条件再実行 | PASS | 通常実行、全3タスクok、changed0/failed0、終了0、前後ハッシュ一致（E04） |
| RB-07 | 終了状態 | PASS | 旧版ブランチへ復帰、HEAD38559f2、変更なし、本文training/8080（E04） |

Gitが管理するroleソースと、除外対象の生成済みapp.confは別である。
タグへ切り替えても生成物は8085を維持し、Ansibleの再適用によって8080へ変わった。
再適用と再実行は-eなしで行われ、旧版の既定値を用いた構成と整合する。

## ハッシュと履歴の扱い

開始時とGit切替後の8085のハッシュが一致し、8080再適用後と再実行前後のハッシュも一致した。
これらは異なる本文のハッシュである。値の原本は画像を参照する。
画像用SHA256SUMS.txtは対象app.confのハッシュとは別で、実ファイルをこの公開作業では取得していない。
新しいGitコミットの作成・revert・タグの移動は案内していない。
practice/from-tagを削除する操作は行っていないが、最終時の全ブランチ一覧は未採録。

## 未実施・限界

- 実サービスのreload/restart、ポート待受・接続、サーバー全体の復旧は**NOT RUN**。
- 権限・mtime・全ファイルの前後比較、入力全ハッシュ、連続rawログは未採録。
- 異なるホストや新規OS、全Playbook、不正値での再実行は今回対象外。
- ブランチpush・bundle更新・Windowsコピー同期は未実施。
- originの追跡表示は前段bundle cloneに由来し、GitHub同期済みの証拠ではない。
- server側の公開文書コミット・CIと本人VMでの切り戻しを区別する。

## 復習

ソースを旧版へ戻す操作と、その設定を対象ファイルへ反映する操作は別である。
再適用後は本文と再実行の変更なしを確認する。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：変更した既定値8085の実行](2026-09-15-lab-base01-default-8085-practice.md)
- [検証証跡台帳](../README.md)
