# lab-base01：タグ起点のブランチ変更とタグ維持（2026-09-14）

## 結果と範囲

本人VMのbundle復元先でpractice-validated-v1からpractice/from-tagを作成し、
検証付きroleの既定ポートを8080から8085へ変更してコミットdac8a0fを作成した。
ブランチが進んでもタグの参照先は38559f2のままで、差分1行と作業変更なしを確認した。
**Git履歴の操作演習**であり、8085でのAnsible実行やサービス動作は未検証。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 実行場所 | /home/opsadmin/ansible-tagged-restore。プロンプトopsadmin@lab-base01 |
| 起点 | practice-validated-v1、短縮SHA38559f2 |
| 新規ブランチ | practice/from-tag |
| 変更コミット | 短縮SHAdac8a0f。完全SHAはE03のrev-parse出力を参照 |
| 対象ファイル | roles/practice_config_validated/defaults/main.yml |
| 原資料 | [本人提供画像3枚・ハッシュ](../screenshots/2026-09-14-lab-base01-from-tag-practice/README.md) |

## 確認結果

FT番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| FT-01 | 開始状態 | PASS | Git変更なし、HEADとタグcommit解決結果一致、from-tagの一覧出力なし（E01） |
| FT-02 | ブランチ作成 | PASS | タグ指定のswitch -c成功、from-tag clean、既定値training/8080（E01） |
| FT-03 | 差分 | PASS | sedで8085へ変更、diffは1行のみ、diff check exit=0（E02） |
| FT-04 | identityエラー | PASS（想定外分岐） | add・空白検査後、Author identity unknownでcommit停止（E02） |
| FT-05 | 設定 | PASS | --localでuser.name/user.email設定、読戻しでns7jpとnoreplyメールを確認（E03） |
| FT-06 | 保存 | PASS | 空白検査後にcommit成功、dac8a0f、1 insertion/1 deletion（E03） |
| FT-07 | タグ維持 | PASS | HEADは新SHA、タグcommit解決は旧38559f2、差分8080→8085（E03） |
| FT-08 | 最終状態 | PASS | statusはpractice/from-tag行のみ。未コミット変更なし（E03） |

## identity設定の扱い

復元先でcommitがidentity未設定により停止したため、このリポジトリだけにuser.nameと
user.emailを設定した。設定値の読戻しは採録したが、作成コミットのauthor表示や署名検証は未実施。
Gitの作成者情報設定はGitHub認証とは別であり、本人性の独立した検証とはしない。
clone/bundleの履歴復元とリポジトリローカル設定は別のものである。

## 最終状態・限界

- practice/from-tagに変更を保存。タグを強制移動・削除する操作は行っていない。
- タグが指すcommitの維持を確認したが、タグオブジェクト自体の前後SHA比較は今回未採録。
- 通常roleの既定値変更や生成物への反映は行っていない。
- 8085でのAnsible実行、入力検証や実ポート待受は**NOT RUN**。
- ブランチのマージ・push・bundle再作成・Windows同期は**NOT RUN**。
- commitの数値終了コードは未採録。成功メッセージとHEAD・差分・statusから確認した。
- OS/Git版、全入力ハッシュ、rawログ、Git bundle実体は今回未取得。
- server側の公開文書コミット・CIと本人VMのdac8a0fを区別する。

## 復習

タグを起点にブランチを作り、変更を保存するとブランチの先端だけが進む。
今回のタグは元の版を指したままだった。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：タグ切替と復帰](2026-09-14-lab-base01-tag-switch-practice.md)
- [検証証跡台帳](../README.md)
