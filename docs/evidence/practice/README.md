# 練習ログ（2026-09-09〜15）

手元の Hyper-V 上の Ubuntu VM `lab-base01` で行った、Ansible と Git の細かな練習の記録です。AI の手順案内を受けながら本人が操作し、結果を画面で確認しています。

採用ご担当者さまには、まず[検証証跡台帳の「主要な記録」](../README.md#主要な記録)をご覧ください。このページは、個別の操作をさらに確かめたい場合の索引です。各記録の本文・判定は移動前（`docs/evidence/` 直下）から変えていません。原画像は引き続き [`../screenshots/`](../screenshots/) にあります。

## 2026-09-15：ログ検証ツールのREADME作成と同期

[READMEの保存・clone先への取り込み](2026-09-15-lab-base01-checker-readme-practice.md)を原画像4枚で記録。
54行追加の0e1a684を作成し、Fast-forward・追跡4件・終了0・変更なしを確認した。

## 2026-09-15：cloneしたツールで保存ログを検証

[保存ログ5件への適用結果](2026-09-15-lab-base01-checker-real-logs-practice.md)を原画像1枚付きで記録。
5件すべてOK、終了0、実行前後HEAD一致・Git変更なし。指定manifestとのハッシュ整合性の確認である。

## 2026-09-15：ログ検証ツールのclone再現

[保存版88ece6dを別フォルダーで9テスト再現](2026-09-15-lab-base01-checker-reproduce-practice.md)した記録を原画像2枚付きで追加。
clone終了0、追跡3件、9件成功・試験終了0、HEAD維持・変更なし。同じVM内の検証である。

## 2026-09-15：ログ検証ソース・9テストの保存

[3ファイルの初回コミット88ece6dと再検証](2026-09-15-lab-base01-checker-save-practice.md)を原画像5枚付きで記録。
9テスト成功・終了0、保存後もHEAD一致・変更なしを確認。VM内ローカル保存でpushや別媒体バックアップは未実施。

## 2026-09-15：ログ検証の権限不足試験

[非rootでのPermission deniedと権限復帰](2026-09-15-lab-base01-checker-permission-practice.md)を原画像2枚付きで記録。
ERROR/終了2、600復帰後OK/終了0、両テストPASS・スクリプト不変表示を確認。他権限環境は未検証。

## 2026-09-15：不正ハッシュ一覧の拒否

[空一覧・形式不正・重複・親パスの4ケース](2026-09-15-lab-base01-manifest-validation-practice.md)を原画像3枚付きで記録。
全件ERROR/終了2、ランナー4/4 PASS・終了0、実スクリプト本文とハッシュ維持を確認。
全入力や全OSの安全性保証ではない。

## 2026-09-15：Pythonログ検証の4分類

[正常・不一致・欠落・読取りエラーの判別](2026-09-15-lab-base01-log-checker-practice.md)を原画像4枚付きで記録。
既存5ログOK、専用4ケースPASS・ランナー終了0を確認。権限不足や不正一覧等はNOT RUN。

## 2026-09-15：ログ欠落の検出と復帰

[finalログの別名退避・欠落検出・名前復帰](2026-09-15-lab-base01-missing-log-practice.md)を原画像3枚付きで記録。
FAILED open or read・終了1から、元名へ戻して5件OK・終了0へ復帰。初期正常検査は画像未採録。

## 2026-09-15：不一致ログ1件の復元

[finalログの選択復元と5件OKへの復帰](2026-09-15-lab-base01-checksum-restore-practice.md)を原画像2枚付きで記録。
復元前終了1から、アーカイブ内1件の上書き復元後は終了0。同じVM内の試験用ファイル復元である。

## 2026-09-15：ハッシュ不一致の検出

[試験用ログ1件の変更検出](2026-09-15-lab-base01-checksum-mismatch-practice.md)を原画像3枚付きで記録。
正常5件OK・終了0から、追記したfinalだけFAILED・終了1へ変化。元ログと検証済みコピーは各5件OK。
変更者特定や署名による真正性検証ではない。

## 2026-09-15：元ログとのハッシュ照合

[元ログ5件の照合](2026-09-15-lab-base01-original-log-check.md)で全件OK・終了0を確認。前段の展開検証を補う原画像1枚付き記録。

## 2026-09-15：変更ログのアーカイブ・展開検証

[5ログとハッシュ一覧の保存・展開](2026-09-15-lab-base01-log-archive-practice.md)を原画像3枚付きで記録。
作成・一覧・展開検証の終了0、展開後5件OKと計6ファイルを確認。同じVM内の検証で、別媒体保存ではない。

## 2026-09-15：変更作業5段階のログ照合

[5ログのCOMMAND・集計・終了コード抽出](2026-09-15-lab-base01-cycle-review-practice.md)を原画像1枚付きで記録。
changed1→1→0→1→0、全件failed0・終了0を照合。保存済みログの読み取りで、新規Ansible実行ではない。

## 2026-09-15：ログ付き変更・切り戻し一連演習

[予測・適用・再実行・切り戻し・最終確認](2026-09-15-lab-base01-change-cycle-practice.md)を原画像6枚付きで記録。
8080→8085→8080、開始時ハッシュ復帰、全段階終了0、5ログの存在を確認。
対象は演習用ファイルであり、実サービス復旧やログ本文の独立読戻しは未実施。

## 2026-09-15：タグ版を再適用して切り戻し

[タグ切替・8080再適用・変更なしの再実行](2026-09-15-lab-base01-tag-rollback-practice.md)を原画像4枚付きで記録。
Git切替だけでは生成物8085が残り、通常実行で8080へ変更。旧版ブランチ38559f2へ復帰した。
演習用ファイルの切り戻しで、実サービス復旧はNOT RUN。

## 2026-09-15：変更した既定値8085の実行確認

[dac8a0fでのtraining/8085生成と再実行](2026-09-15-lab-base01-default-8085-practice.md)を原画像3枚付きで記録。
changed2→0、終了0、本文・SHA-256・HEAD維持を確認。初回入力行は未採録、再実行の-eなしを確認。
実サービスの8085待受はNOT RUN。

## 2026-09-14：タグ起点のブランチ変更

[8080→8085のコミットとタグ維持](2026-09-14-lab-base01-from-tag-practice.md)を原画像3枚付きで記録。
identity未設定をローカル設定で解消し、dac8a0fを保存。タグ参照先38559f2とGit変更なしを確認。
Ansible再実行・push・bundle更新はNOT RUN。

## 2026-09-14：タグ指定の切替と復帰

[タグからdetached HEADへ切替・元ブランチへ復帰](2026-09-14-lab-base01-tag-switch-practice.md)を原画像2枚付きで記録。
HEAD38559f2とタグ名の一致、変更なしを確認。同じコミット間の切替で、新しいAnsible試験ではない。

## 2026-09-14：タグ付きbundle復元

[ブランチと注釈付きタグの保存・復元](2026-09-14-lab-base01-tagged-bundle-practice.md)を原画像3枚付きで記録。
作成・verify・clone終了0、タグSHA・注釈・参照先38559f2の維持を確認。
同じVM内のGit復元で、復元先Ansible実行・Windows転送はNOT RUN。

## 2026-09-14：lab-base01の注釈付きタグ

[practice-validated-v1の作成と参照先確認](2026-09-14-lab-base01-tag-practice.md)を原画像2枚付きで記録。
作成終了0、種類tag、参照先38559f2、検証範囲の注釈、作業変更なしを確認。
VM内の版識別であり、タグpushや新しいAnsible実行はNOT RUN。

## 2026-09-14：Windows Git整合性検査

[fsck --fullとbundle verify](2026-09-14-lab-base01-git-integrity-practice.md)を原画像1枚付きで記録。
31オブジェクト検査、双方終了0、最終Git変更なしを確認。Playbook動作検証とは区別する。

## 2026-09-14：Windows上でのbundle復元

[転送済みbundleからのソース・履歴復元](2026-09-14-lab-base01-windows-bundle-practice.md)を原画像2枚付きで記録。
clone終了0、HEAD38559f2、履歴2件、追跡ファイル20件と変更なしを確認。
Windows上でのAnsible実行やホスト故障からの復旧はNOT RUN。

## 2026-09-14：bundleのWindows転送

[practice.bundleのscp転送と一致確認](2026-09-14-lab-base01-bundle-transfer-practice.md)を原画像2枚付きで記録。
終了0、5138バイト、SHA-256一致を確認。同じホストPC内への複製である。
Windowsコピーからの復元や別媒体バックアップはNOT RUN。bundle実体は公開対象外。

## 2026-09-14：lab-base01のGit bundle復元

[bundle作成・verify・復元・新規生成・再実行](2026-09-14-lab-base01-bundle-practice.md)を原画像5枚付きで記録。
38559f2の指定ブランチ履歴、生成物不在、changed2→0、本文・ハッシュ維持を確認。
同じVM内の復元練習であり、別媒体・新規OS・ホスト故障からの復旧ではない。

## 2026-09-14：WindowsからVMへのログ復元

[2ログの復元・ハッシュ一致・内容読取り](2026-09-14-lab-base01-log-restore-practice.md)を原画像3枚付きで記録。
各scp終了0、失敗1321バイト・正常1395バイト、SHA-256と終了コードの読取りを確認。
同じホストPC内のファイル復元練習で、ホスト故障や別媒体からの復旧試験ではない。

## 2026-09-14：Windows側でのログ確認

[コピー済みログから条件・集計・終了コードを抽出](2026-09-14-lab-base01-windows-log-review-practice.md)した記録を原画像1枚付きで追加。
正常8091/終了0と失敗70000/終了2を照合。Ansible再実行ではなく、保存済みログの読み取りである。

## 2026-09-14：lab-base01からWindowsへのログ転送

[2ログのscp転送・サイズとSHA-256一致](2026-09-14-lab-base01-log-transfer-practice.md)を原画像2枚付きで記録。
scp終了0、失敗1321バイト・正常1395バイトを確認。同じホストPC内への複製であり、別媒体バックアップではない。
公開資料にはログ実体・秘密鍵本文・パスフレーズを含めない。

## 2026-09-14：lab-base01の失敗ログ保存

[Ansible終了2・tee終了0と読戻し](2026-09-14-lab-base01-failure-log-practice.md)を原画像3枚付きで記録。
70000拒否後も本文・ハッシュ・HEADを維持。ログはハッシュ一致、mode600・1321バイト。
保存処理自体の失敗や別媒体バックアップはNOT RUN。公開資料は画像証跡で、ログ実体ではない。

## 2026-09-14：lab-base01の実行ログ保存

[正常再実行のログ保存・読戻し・権限確認](2026-09-14-lab-base01-log-capture-practice.md)を原画像3枚付きで記録。
ANSIBLE/RUN/TEE終了0、ログハッシュ一致、mode600・1395バイトを確認。
ログ実体はVM内に保存。公開資料は画像証跡で、rawログ転送や別媒体バックアップは未実施。

## 2026-09-14：lab-base01の設定ずれ検出・修正

[9999→8091の予測・修正・再実行](2026-09-14-lab-base01-drift-practice.md)を原画像4枚付きで記録。
予測後は9999のまま、通常実行で8091と開始時ハッシュへ復帰、再実行changed0を確認。
対象はclone先の演習用ファイル。実サービス復旧はNOT RUN。手動変更操作の画面は未採録。

## 2026-09-14：lab-base01のローカルclone再現

[同じVM内の別フォルダーで新規生成・再実行](2026-09-14-lab-base01-reproduce-practice.md)した記録を原画像4枚付きで追加。
38559f2、出力未生成、changed2→0、終了0、staging/8091とSHA-256維持を確認。
新規OS・別マシンでの再現や別媒体バックアップではない。

## 2026-09-14：lab-base01の保存版role正常再実行

[38559f2でのstaging/8091再実行](2026-09-14-lab-base01-saved-rerun-practice.md)を原画像2枚付きで記録。
VM表示日時・コミット・入力引数・changed0/終了0・前後ハッシュとGit状態を対応付けた。
対象は検証付きroleの正常再実行のみ。他Playbook・不正入力の保存版再検証はNOT RUN。

## 2026-09-14：lab-base01の演習ソースGit保存

[12ファイル・191行の選別とコミット38559f2](2026-09-14-lab-base01-save-ansible-practice.md)を原画像10枚付きで記録。
生成物・Vault演習ファイルを除外し、差分レビュー・空白検査・コミット後cleanを確認。
VM内ローカル保存であり、push・バックアップ・保存コミットでの再実行はNOT RUN。

## 2026-09-14：lab-base01の環境名入力検証

[stagng拒否・ハッシュ一致・正常再実行](2026-09-14-lab-base01-env-validation-practice.md)を原画像2枚付きで記録。
通常実行の最初のassertで入力ミスを拒否し、対象ファイルのSHA-256とstaging/8091の維持を確認。
追加の環境名パターンや実サービス検証はNOT RUN。

## 2026-09-14：lab-base01の入力境界値・形式検証

[1/65535受入・0/65536/abc/80.5拒否](2026-09-14-lab-base01-boundary-practice.md)を原画像6枚付きで記録。
check modeで終了0/2、対象ファイルのSHA-256とstaging/8091の維持を確認。
許可値での実書き込みではない。不正環境名・追加形式・型別試験はNOT RUN。

## 2026-09-14：lab-base01のrole入力検証

[8091受入・70000拒否・ハッシュ一致・正常再実行](2026-09-14-lab-base01-role-validation-practice.md)を原画像4枚付きで記録。
最初のassertで拒否し、対象ファイルの前後SHA-256とstaging/8091の維持を確認。
境界値・数字以外・不正環境名はNOT RUN。ソースと生成物は未追跡のまま保持。

## 2026-09-14：lab-base01のAnsible role

[roleの初回・再実行・既定値上書き](2026-09-14-lab-base01-role-practice.md)をVM側原画像5枚付きで記録。
changed2→0→1→0、最終staging/8091、defaultsのtraining/8080を確認。
最初の別環境実行とは区別する。実サービスはNOT RUN。ソース・生成物はVM内で未追跡のまま保持。

## 2026-09-14：lab-base01のAnsible Vault

[ダミー変数の暗号化・読み込み・パスワードなし拒否](2026-09-14-lab-base01-vault-practice.md)を原画像4枚付きで記録。
暗号化終了0、パスワード付き一致確認終了0、未指定時の復号拒否終了1を区別する。
実認証情報は未使用。Vaultパスワードと暗号文ファイル本体は公開対象外。

## 2026-09-14：lab-base01のblock・rescue・always

[意図的失敗への対処と正常時の後処理](2026-09-14-lab-base01-block-practice.md)を原画像4枚付きで記録。
rescued1/終了0、正常条件への切替、同条件再実行でtouchのみchanged1を確認。
ホーム内ファイルの制御フロー演習であり、実サービス復旧はNOT RUN。生成物は未追跡で保持。

## 2026-09-14：lab-base01のAnsible loop

[3環境の生成・部分変更・再実行](2026-09-14-lab-base01-loop-practice.md)を原画像5枚付きで記録。
changed2→0→1→0と環境別の変更判定、最終8080/8081/8090を確認。
ホーム内ファイルの演習で、実サービスはNOT RUN。Playbook・生成物は未追跡のまま保持。

## 2026-09-11〜14：lab-base01のAnsibleハンドラー

[変更時の実行と再実行時の抑止](2026-09-14-lab-base01-handlers-practice.md)を原画像5枚付きで記録。
changed4→0→2→0、マーカーmtimeの更新・維持、最終staging/8082を確認。
実サービスのreload/restartはNOT RUN。Playbook・生成物はVM内で未追跡のまま保持。

## 2026-09-11：lab-base01のGit revert

[変更履歴を残す取り消しとmain復帰](2026-09-11-lab-base01-git-revert-practice.md)を原画像3枚付きで記録。
d7b3d4dを打ち消すa4644abを追加し、逆向きの差分と元の変更の保持を確認。
最後はmain clean・本文staging。Ansible反映・VMリポジトリのpushはNOT RUN。

## 2026-09-10：lab-base01のGitマージ・競合解消・中止

[Fast-forward・2つの親を持つマージ・abort前後一致](2026-09-10-lab-base01-git-merge-practice.md)を原画像5枚付きで記録。
最後はmainのa94c1d3・staging・cleanへ復帰し、演習ブランチを保持。
前段でNOT RUNだったVM内マージの追補。Ansible反映・VMからのpushはNOT RUN。

## 2026-09-10：lab-base01のGitブランチ・履歴・除外ルール

[本人VMでの変更保存・履歴検索・除外一致/不一致・後片付け](2026-09-10-lab-base01-git-practice.md)を原画像9枚付きで記録。
作業ブランチにd7b3d4dを残し、mainはa94c1d3・staging・cleanへ復帰。
**VM内のGit演習**で、マージ・コンフリクト・Ansible再実行・pushはNOT RUN。
ディレクトリ除外や追跡済みファイルの比較試験まで完了したとは扱わない。

## 2026-09-09：lab-base01の演習ソースGit管理

[9ファイルの初回コミットa94c1d3とmain clean](2026-09-09-lab-base01-git-intro-practice.md)を原画像4枚付きで記録。
生成物をステージに含めず、identity未設定エラー後にcommit成功を確認。
**VM内のローカルGit入門**で、GitHubへのpushや過去演習の実行版保証ではない。
完全SHA・入力全文・author設定の読戻し・コミット後再実行は未採録またはNOT RUN。

## 2026-09-09：lab-base01のAnsible入力検証

[assertで不正ポート70000を変更前に拒否](2026-09-09-lab-base01-validation-practice.md)した記録を原画像2枚付きで追加。
8081は許可、70000はfailed1/終了2で停止し、出力ファイルの前後SHA-256一致と本文維持を確認。
**ホーム内のファイル生成前の検証**であり、実ポート待受・全入力値・OS設定の検証ではない。
境界値や不正環境名の追加試験はNOT RUN。

## 2026-09-09：lab-base01のAnsibleテンプレート

[テンプレート生成・変更予測・staging/8081適用と通常再実行](2026-09-09-lab-base01-template-practice.md)を原画像4枚付きで記録。
初回changed2、予測で旧本文維持、適用changed1、同指定の再実行changed0を確認。
**ホーム内の設定ファイル生成**であり、ポート待受・アプリ起動・リモート構築はNOT RUN。
入力全文/ハッシュ・独立した権限確認等の未採録範囲を明記する。

## 2026-09-09：lab-base01のAnsible変数ファイル

[環境別ファイルを-e @で読み込む演習](2026-09-09-lab-base01-vars-files-practice.md)を原画像3枚付きで記録。
staging指定のcheckでchanged0、trainingファイル適用でchanged1、同指定の再実行でchanged0を確認。
**同一ホストの演習ファイル本文の切替**であり、複数環境の構築や接続先切替ではない。
training予測コマンド・差分全体は未採録として部分確認とする。

## 2026-09-09：lab-base01のAnsible変数指定

[既定値trainingから実行時指定stagingへの切替と再実行](2026-09-09-lab-base01-variables-practice.md)を原画像3枚付きで追加。
初回changed2、staging指定でchanged1、同指定の再実行でchanged0と本文維持を確認。
**ホーム内のファイル内容の切替**で、実際のステージング環境構築ではない。
予測コマンド・差分全体は画面未採録として、実適用・再実行の確認と区別する。

## 2026-09-09：lab-base01のAnsible切り戻し

[退避Playbookによる旧本文への切り戻しとcheck/diff再確認](2026-09-09-lab-base01-rollback-practice.md)を原画像2枚付きで記録。
予測時はversion2を維持、適用で旧本文へ復帰、旧Playbookのcheckでchanged0を確認。
**ホーム内のファイル変更の切り戻し**であり、OS・全ロール・配備のロールバックではない。
first.ymlのversion2指定と、今回使ったfirst-before-change.ymlの役割を区別する。

## 2026-09-09：lab-base01のAnsible変更予測・適用

[check/diffの予測と実ファイル、適用後の通常再実行](2026-09-09-lab-base01-check-diff-practice.md)を原画像3枚付きで記録。
予測changed1でも旧本文を維持、適用でversion 2へ変更、通常再実行でchanged0を確認。
**最後は--diffのみの通常実行**であり、適用後check mode再確認はNOT RUN。
ホーム内の2タスクの演習として、全モジュール・サーバー全体の保証と区別する。
