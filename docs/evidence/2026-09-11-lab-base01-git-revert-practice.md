# lab-base01：履歴を残して変更を取り消すrevert演習（2026-09-11）

## 結果と範囲

本人VM内で作業ブランチの変更コミットd7b3d4dをrevertし、逆向きの変更を持つ
新しいコミットa4644abを作成した。元の変更と取り消しの両方を履歴に残し、
最後はmainへ戻って本文staging・cleanを確認した。

**VM内のGit演習**である。Ansible再実行、サービスの切り戻し、GitHubのPR取り消しや
公開リポジトリへのpushを実施したという意味ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-11 JST（対話の日付）。各操作・撮影時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。OS版とGit版は今回再採録していない |
| 実行場所 | `/home/opsadmin/ansible-first-lab`。serverとは別リポジトリ |
| 開始main | a94c1d3、未コミットの変更なし、environment_name: staging |
| 練習ブランチ | practice/staging-nameから作ったpractice/revert-demo |
| 対象・結果 | d7b3d4dを取り消すa4644abを追加（短縮SHA） |
| コミット表示日時 | Fri Sep 11 17:44:26 2026 +0900（E02/E03）。時計精度は未検証 |
| 原資料 | [原画像3枚・ハッシュ](screenshots/2026-09-11-lab-base01-git-revert-practice/README.md) |

## 確認結果

GR番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・原画像 |
| --- | --- | --- | --- |
| GR-01 | 開始状態 | PASS | main clean、a94c1d3、本文staging、既存ブランチの履歴を確認（E01） |
| GR-02 | 練習用の分岐 | PASS | revert-demoをstaging-nameから作成。d7b3d4d・本文staging-test（E02） |
| GR-03 | 取り消し保存 | PASS | revert --no-edit d7b3d4dでa4644abを作成。1行追加・1行削除（E02） |
| GR-04 | 本文と履歴 | PASS | 本文staging、revert-demo clean。a4644ab・d7b3d4d・a94c1d3を確認（E02） |
| GR-05 | 逆向きの変更 | PASS | showでstaging-test削除・staging追加とThis reverts commitの本文（E03） |
| GR-06 | 最終状態 | PASS | mainへ復帰、main clean、本文staging。main..revert-demoに変更と取り消しの2件（E03） |

表示されたコミット結果・差分・statusを根拠とする。各コマンドの数値の終了コードは未採録。
全ファイルのツリー一致検査や、全コミットSHAの機械可読な取得は行っていない。

## 最後の状態と復習

mainは元のa94c1d3に残り、practice/revert-demoはa4644abを指す。
practice/staging-nameとpractice/merge-demoはd7b3d4dに残ることをE02/E03の履歴表示で確認した。
練習ブランチを削除せず復習用に保持した。

今回のrevertは元のコミットを削除せず、その変更を打ち消すコミットを追加した。
前段のmerge --abortは進行中のマージを中止する操作であり、用途が異なる。
これはAIによる復習用説明で、本人独力による説明の採録ではない。

## 未実施・限界

- Ansible再実行・実サービスの切り戻し・VM演習リポジトリのpush：**NOT RUN**。
- マージコミットのrevert、revert中の競合・abort、複数コミットの取り消し：**NOT RUN**。
- 連続rawログ、Git bundle、署名検証、OS/Git版の再取得：未採録。
- 完全SHAとauthorはE03の画面表示に限り、機械可読な読戻し・本人性の独立検証は未実施。
- server側の文書追加コミットやCIは、本人VM内の操作とは実行主体・対象が異なる。
- 前段結果票のrevert NOT RUNは当時の記録として保持し、本追補で今回の実施範囲を示す。

- [前段：マージ・コンフリクト・abort](2026-09-10-lab-base01-git-merge-practice.md)
- [検証証跡台帳](README.md)
