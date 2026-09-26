# lab-base01：生成済み設定のずれを検出・修正（2026-09-14）

## 結果と範囲

本人VMのclone先で、生成済みapp.confのポート9999と指定値8091の差分をcheck/diffで検出した。
予測後の実ファイルは9999のままで、通常実行によって8091へ復帰し、開始時のSHA-256に戻った。
修正後の同条件再実行はchanged0・終了0。**演習用設定ファイルの修正**であり、実サービスの復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付） |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01）。OS/Ansible版は今回未取得 |
| 実行場所 | /home/opsadmin/ansible-reproduce-lab（E01）。同じVM内のclone先 |
| 保存版 | practice/save-ansible-exercises、短縮SHA38559f2。完全SHA表示はE01/E03 |
| 対象 | role-validated-demo.ymlとpractice_config_validated、managed-role-validated/app.conf |
| 修正直前のVM表示日時 | 2026-09-14T14:44:37+09:00（E03）。時計精度は未検証 |
| 証拠 | [本人提供画像4枚・ハッシュ](../screenshots/2026-09-14-lab-base01-drift-practice/README.md) |

## 確認結果

DR番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| DR-01 | 開始状態 | PASS | VM・pwd・HEAD38559f2、Git変更なし、本文staging/8091とSHA-256（E01） |
| DR-02 | 差分予測 | PASS | --check --diffでstaging/8091指定。差分は9999削除・8091追加（E02） |
| DR-03 | 予測時の実ファイル | PASS | ok3/changed1/failed0、終了0。予測後の本文はstaging/9999、変更後のSHA-256を表示（E02） |
| DR-04 | 修正 | PASS | --checkなし、--diff付き通常実行。templateのみchanged、ok3/changed1/failed0、終了0（E03） |
| DR-05 | 本文復帰 | PASS | staging/8091、SHA-256がE01開始値と一致。HEAD38559f2、Git変更なし（E03） |
| DR-06 | 修正後再実行 | PASS | 同じstaging/8091指定で全3タスクok、changed0/failed0、終了0（E04） |
| DR-07 | 最終状態 | PASS | 本文とSHA-256を維持、Git変更行なし、clone先のプロンプト（E04） |

E02のchanged1は予測、E03のchanged1は実修正。両者を同じ実行結果として扱わない。
assertが確認するのは指定した入力8091で、生成ファイル内の9999を不正値として拒否したわけではない。
9999はポートの許可範囲内でも今回の期待値8091とは異なるため、templateの差分として検出された。

## 手動変更とハッシュの採録範囲

生成ファイルだけをsedで8091から9999へ変更する手順を案内したが、その入力操作と直後の
cat/ハッシュ/Git状態は画像未提供。手動変更操作の実行自体は独立採録していない。
E02のbefore差分が9999で、check後のcatも9999であることは確認できる。
check前の9999状態のSHA-256は未採録のため、check前後のハッシュ一致を確認済みとは記載しない。

E01の正常時、E03の修正後、E04の再実行後に表示されたapp.confのSHA-256は一致する。
原本値は画像を参照する。機械可読なrawログ・ファイルそのものは未取得。
画像用SHA256SUMS.txtはVM内app.confのハッシュではない。

## 最終状態・未実施

- 最終本文はstaging/8091、作業場所はclone先。コミット追加・push・削除は今回案内していない。
- 生成物は前段で追加したGit除外対象。Git変更なしは生成済み設定の正しさを保証しない。
  ただし今回、9999の状態でのgit statusは未採録である。
- 修正後HEADはE03で確認、最終再実行後のHEAD読戻しは未採録。
- 別マシン・新規OS、実サービスreload/restart、ポート待受の検証は**NOT RUN**。
- 入力全ファイルのハッシュ・全設定・権限・mtime・依存関係固定、連続rawログは未採録。
- server側の公開用コミット・CIと本人VMの38559f2での実行を区別する。

## 復習

予測で差分を読み、通常実行で修正し、再実行で変更なしを確認する。
入力値が妥当なことと、生成済み設定が期待値どおりであることは別の確認である。
この説明はAIによる復習用で、本人独力による説明の採録ではない。

- [前段：cloneからの再現](2026-09-14-lab-base01-reproduce-practice.md)
- [検証証跡台帳](../README.md)
