# lab-base01：変更ログのアーカイブ・展開検証（2026-09-15）

## 結果と範囲

本人がVM内の変更作業5ログをSHA-256一覧とともにtar.gzへまとめ、別フォルダーへ展開した。
展開後のsha256sum -cで5件すべてOK、終了0、計6ファイルを確認した。
**同じVM内の保存・展開確認**であり、別媒体バックアップやサーバー復旧ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-15 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | whoami=opsadmin、hostname=lab-base01（E01） |
| 元ログ | /home/opsadmin/ansible-practice-logsのchange-*.log |
| 作業コピー | /home/opsadmin/ansible-change-archive/payload |
| アーカイブ | /home/opsadmin/ansible-change-archive/change-logs.tar.gz |
| 展開先 | /home/opsadmin/ansible-change-extract |
| 原資料 | [本人提供画像3枚・ハッシュ](screenshots/2026-09-15-lab-base01-log-archive-practice/README.md) |

## 確認結果

LA番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| LA-01 | 開始状態 | PASS | VM名・ユーザー、5段階各1ログとサイズ、保存先・展開先NOT FOUND（E01） |
| LA-02 | 作業コピー検証 | PASS | 各段階1件を選ぶループ、cp、SHA一覧生成、sha256sum -cで5件OK（E02） |
| LA-03 | 作成 | PASS | tar -czf、完了メッセージ、archive create exit=0（E02） |
| LA-04 | 収録内容 | PASS | tar -tzfが5ログとSHA256SUMS.txtの6件を表示、archive list exit=0（E02） |
| LA-05 | 展開検証 | PASS | 新規展開先作成、tar -xzf、sha256sum -cで5件OK、extract verify exit=0（E03） |
| LA-06 | 展開一覧 | PASS | 5ログと456バイトのSHA256SUMS.txt、計6ファイル（E03） |

## ファイルサイズ

| 段階 | 元ログ・展開後の表示サイズ |
| --- | --- |
| preview | 1565 bytes |
| apply | 1429 bytes |
| repeat | 1113 bytes |
| rollback | 1724 bytes |
| final | 1119 bytes |

E01とE03の各サイズは一致する。元ログから作業コピーへの個別ハッシュ比較は未実施。
今回SHA256SUMS.txtは作業コピー内で生成しており、検証したのはその一覧と作業コピー・展開後ログの一致である。
元ログと作業コピーのハッシュを独立照合したとは扱わない。

## ハッシュと保存範囲

E02でアーカイブ自身のSHA-256も表示したが、展開後のアーカイブ再ハッシュ比較は未実施。
アーカイブ内のSHA一覧、tar.gz自身のSHA、公開資料の画像用SHA256SUMSはそれぞれ別である。
この公開作業ではログ本文・SHA一覧実体・tar.gzを取得せず、画像での検証結果に限定する。
内部ハッシュ一致は電子署名や改ざん防止の証明ではない。

## 未実施・限界

- 別媒体・Windows・別ホストへのアーカイブ転送、新規OSからの復元は**NOT RUN**。
- 破損・欠落を意図的に与える検出試験、暗号化・署名・世代管理は**NOT RUN**。
- 展開後ログの本文読戻し・Ansible再実行・実サービス復旧は今回未実施。
- mode700とumask077を使う手順を案内したが、保存後の権限・所有者の独立検査は未採録。
- OS/tar版、時刻・所要時間、元ログの作業後不変性検査は未実施。
- 元ログ削除・既存記録の上書きは案内していない。
- server側の文書追加・CIと本人のVM内保存・展開を区別する。

- [前段：5段階のログ照合](2026-09-15-lab-base01-cycle-review-practice.md)
- [検証証跡台帳](README.md)
