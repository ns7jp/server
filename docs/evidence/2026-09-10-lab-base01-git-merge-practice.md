# lab-base01：Fast-forward・コンフリクト解消・abort（2026-09-10）

## 結果と範囲

本人VMでFast-forwardマージ、同じ行の競合と手動解消、別ブランチでの競合再現と
`git merge --abort`を実施した。最後はmainへ戻り、元の本文・clean状態と演習履歴の保持を確認した。
**ホーム内のGit演習**であり、GitHubのPRマージやAnsibleの反映試験ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-10 JST（対話の日付）。各操作の正確な実行時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。今回OS版・Git版を再採録していない |
| 実行場所 | `/home/opsadmin/ansible-first-lab`。公開用serverとは別リポジトリ |
| 開始・最終main | `a94c1d3`、本文environment_name: staging、未コミットの変更なし |
| 証拠 | [本人提供の原画像5枚・ハッシュ](screenshots/2026-09-10-lab-base01-git-merge-practice/README.md) |

## 確認結果

GM番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・原画像 |
| --- | --- | --- | --- |
| GM-01 | 開始状態 | PASS | main clean、a94c1d3と作業ブランチd7b3d4dを確認（E01） |
| GM-02 | Fast-forward | PASS | practice/merge-demoをmainから作成。--ff-onlyでd7b3d4dへ進み、本文staging-test（E01） |
| GM-03 | 両側の変更 | PASS | 共通mainからconflict-a/bを作成。staging-a/bへ別々に変更・commit（E02） |
| GM-04 | 競合検出 | PASS | conflict-bへaをmerge。CONFLICT、UU、HEAD側staging-bと相手側staging-a（E02） |
| GM-05 | 手動解消 | PASS | 本文をstaging-aの1行へ置換し、add→commitでb24f503を作成（E03） |
| GM-06 | マージ履歴 | PASS | b24f503の親がcc10e7eと00d692eの2つ。conflict-b clean（E03） |
| GM-07 | 中止用の競合 | PASS | cc10e7eからabort-demoを作成し、aのmergeで競合を再現（E04） |
| GM-08 | abortで復帰 | PASS | 前後の完全SHA表示が一致。本文staging-b、UUが消えclean（E04） |
| GM-09 | 最終状態 | PASS | mainはa94c1d3・staging・clean。演習ブランチとマージ履歴が残る（E05） |

E03の`git diff --check`は診断出力なしで、数値の終了コードは未採録。
`git diff --cached --check`はAND連結の後続commitが実行されたため成功終了を確認できる。
競合時のmergeの終了コードは未採録だが、CONFLICT・UU・マーカーの表示を確認した。

## 最後に残したブランチ

| ブランチ | 短縮SHA | 本文・役割 |
| --- | --- | --- |
| main | a94c1d3 | staging。開始時の状態を保持 |
| practice/staging-name | d7b3d4d | 前段のstaging-test変更 |
| practice/merge-demo | d7b3d4d | Fast-forwardの取り込み先 |
| practice/conflict-a | 00d692e | staging-aへの変更 |
| practice/conflict-b | b24f503 | staging-aを採用したマージコミット |
| practice/abort-demo | cc10e7e | staging-b。競合を中止して復帰 |

E05の全ブランチ履歴とE01〜E04の本文表示を対応させた表。全ファイルの完全性検査ではない。
演習ブランチは復習用に残した。mainへ演習変更は取り込んでいない。

## 設計案との差異と復習

元の案のlisten_portは実物に存在しなかったため、前段に続きenvironment_nameを使用した。
mainを直接変更せず、同じmainから2本のブランチを分岐させて同じ行を別々に変更した。
abortは解消済みブランチで再mergeするのではなく、解消前のcc10e7eから別ブランチを作って試した。

Fast-forwardは取り込み先の参照を進める。今回の競合解消は2つの親を持つコミットを作る。
abortは進行中のマージを中止する操作で、完成したマージコミットを取り消す操作ではない。
ここはAIによる復習用説明であり、本人独力で説明済みという証跡ではない。

## 未実施・限界

- Ansible再実行・サービス反映・VM演習リポジトリのpush：**NOT RUN**。
- rebase、revert、完成済みマージの取消、複数ファイル競合：**NOT RUN**。
- 未コミットの変更がある状態からのmerge/abortは試していない。
- 連続rawログ、Git bundle、全コミットの完全SHA読戻し、署名検証は未採録。
- 今回の公開用serverコミットやCIは、本人VMのGit操作とは実行主体・対象が異なる。
- 前段結果票のNOT RUNはその時点の記録として保持し、本追補を追加する。

- [前段：ブランチ・履歴・ignore](2026-09-10-lab-base01-git-practice.md)
- [検証証跡台帳](README.md)
