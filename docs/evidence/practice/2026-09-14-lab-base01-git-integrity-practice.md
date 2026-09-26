# lab-base01：Windows側Git整合性検査（2026-09-14）

## 結果と範囲

本人がWindowsで復元済みのリポジトリにgit fsck --fullを実行し、31オブジェクトの検査と終了0を確認した。
転送済みbundleのverifyもis okay・終了0となり、最後のGit状態は変更なしだった。
**Gitデータの整合性確認**であり、Playbookの動作や全練習ブランチの保存を保証するものではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | ホストWindowsのPowerShell。OS/Git版は今回再取得していない |
| 対象リポジトリ | Documents内のAnsibleBundleRestore-識別子フォルダー（E01） |
| 対象bundle | Documents内のAnsibleBundle-識別子フォルダーのpractice.bundle（E01） |
| 原資料 | [本人提供画像1枚・ハッシュ](../screenshots/2026-09-14-lab-base01-git-integrity-practice/README.md) |

## 確認結果

GI番号は本結果票専用。すべてE01で確認した範囲である。

| ID | 観点 | 判定 | 結果 |
| --- | --- | --- | --- |
| GI-01 | 対象 | PASS | 復元先変数・パス存在のガードを通過し、確認先を表示 |
| GI-02 | fsck | PASS | ref database 1/1、object directories 256/256、objects 31/31、fsck exit=0 |
| GI-03 | bundle verify | PASS | complete history、hash algorithm sha1、is okay、bundle verify exit=0 |
| GI-04 | 収録ref | PASS | practice/save-ansible-exercisesと短縮SHA38559f2に対応する完全SHA表示 |
| GI-05 | 最終状態 | PASS | status --short --branchは追跡ブランチ行のみで変更行なし |

fsckが検査する対象とbundle verifyの対象は別である。前者は復元リポジトリのGitオブジェクト等、
後者は指定bundleの形式・前提履歴等についての検査として区別して記録する。
bundleが指定refのcomplete historyを含む表示は、ほかの練習ブランチ全体を含む意味ではない。

## 未実施・限界

- Windows上のAnsible実行、実サービス起動、生成結果の再現は**NOT RUN**。
- 今回のHEAD読戻し・ソース全文比較・個別ファイルハッシュ・bundle再ハッシュ比較は未採録。
- 異常がない結果は今回の検査で検出される範囲に限定し、ソースの意味的正しさや全バックアップ範囲は保証しない。
- 破損データを意図的に与える拒否試験、ホスト故障や別媒体からの復旧は**NOT RUN**。
- Windows ACL、時刻・所要時間、電子署名・改ざん防止は未検証。
- 修復・削除を伴うオプションは案内していないが、全ディスク内容の前後比較は実施していない。
- bundle実体や復元ソース実体を公開作業で取得・添付していない。
- server側の文書検査・CIと本人のWindows検査を区別する。

## 復習

ファイルの存在確認に加え、Gitの整合性検査と終了コードを確認する。
データの整合性と実行時の動作は別の検証である。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：Windows bundle復元](2026-09-14-lab-base01-windows-bundle-practice.md)
- [検証証跡台帳](../README.md)
