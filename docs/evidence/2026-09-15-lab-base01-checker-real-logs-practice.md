# lab-base01：cloneした検証ツールを保存ログへ適用（2026-09-15）

## 結果と範囲

本人VMでclone先のcheck_logs.pyを実行し、保存済みのAnsible変更演習ログ5件が
指定したSHA256SUMS.txtと一致した。SUMMARYはOK=5 MISMATCH=0 MISSING=0 ERROR=0、終了コード0。
実行前後のHEADは一致し、Gitの変更行は表示されなかった。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人がVMで実行・画像提供 |
| 日付 | 対話日2026-09-15 JST。VMのdate -Is表示は2026-09-15T17:39:04+09:00 |
| 環境 | プロンプト表示opsadmin@lab-base01。今回whoami・hostname・Python版の再取得なし |
| 実行場所 | /home/opsadmin/ansible-log-checker-reproduce |
| 保存版HEAD | 88ece6dae2036cc0a6125d64a8d80211e2f1cee4 |
| 対象manifest | /home/opsadmin/ansible-change-extract/SHA256SUMS.txt |
| 原資料 | [本人提供画像1枚・ハッシュ](screenshots/2026-09-15-lab-base01-checker-real-logs-practice/README.md) |

## 確認結果

以下のPASSはE01の表示で確認できる観点に限定する。

| 観点 | 判定 | 表示結果 |
| --- | --- | --- |
| 保存ログへの適用 | PASS | python3 check_logs.pyに上記manifestの絶対パスを指定 |
| 5件の照合 | PASS | preview・apply・repeat・rollback・finalがそれぞれOK |
| 集計 | PASS | OK=5 MISMATCH=0 MISSING=0 ERROR=0 |
| 終了状態 | PASS | checker exit=0 |
| 版の維持 | PASS | 実行前後HEAD一致、main...origin/main、変更行なし |

checkerはmanifestが置かれたディレクトリ内のログを参照する。
今回の結果は、clone先のツールから別ディレクトリにある保存ログを検証できた記録である。

## 証拠の限界

- ハッシュ一致は指定manifestとの整合性を示す。ログ内容の正しさやAnsible操作の成功を再判定した結果ではない。
- 今回Ansibleの再実行、サービス稼働確認、9単体テストの再実行は行っていない。
- 機械可読なログ・manifest・ソース実体は今回の公開用作業で取得していない。
- 同じVM内の既存環境での実行であり、別ホストでの再現や別媒体バックアップではない。
- server側の文書検査・CIと、本人VMの保存版での実行結果を区別する。

[前段：clone再現試験](2026-09-15-lab-base01-checker-reproduce-practice.md) / [検証証跡台帳](README.md)
