# lab-base01：タグ指定の切替とブランチ復帰（2026-09-14）

## 結果と範囲

本人VMのタグ付きbundle復元先で、practice-validated-v1を指定してdetached HEADへ切り替え、
元のpractice/save-ansible-exercisesへ戻った。開始・切替後・復帰後のコミット表示は38559f2で一致し、
変更行は表示されなかった。**同じコミットを指すブランチとタグの切替**で、新しいAnsible試験ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。操作・撮影の正確な時刻は未採録 |
| 環境 | プロンプトopsadmin@lab-base01。OS/Git版の再取得は未採録 |
| 実行場所 | /home/opsadmin/ansible-tagged-restore（E01のcd入力とプロンプト） |
| ブランチ | practice/save-ansible-exercises |
| タグ | practice-validated-v1 |
| コミット | 短縮SHA38559f2。完全SHAは画像のrev-parse出力を参照 |
| 原資料 | [本人提供画像2枚・ハッシュ](../screenshots/2026-09-14-lab-base01-tag-switch-practice/README.md) |

## 確認結果

TS番号は本結果票専用。PASSは画像で確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| TS-01 | 開始状態 | PASS | ブランチ行のみ、HEADとタグのcommit解決結果が一致（E01） |
| TS-02 | タグ切替 | PASS | switch --detach practice-validated-v1、HEAD is now at 38559f2、HEAD (no branch)（E01） |
| TS-03 | タグ対応 | PASS | HEAD38559f2、describe --exact-match --tags HEADがpractice-validated-v1（E01） |
| TS-04 | ブランチ復帰 | PASS | switchで元のブランチへ戻り、statusのブランチ表示復帰・変更行なし（E02） |
| TS-05 | 参照先維持 | PASS | 復帰後のHEADは同じ38559f2、describeのタグ名も一致（E02） |

switchと後続確認はAND連結で実行されている。数値の終了コードは未採録だが、
成功後のHEAD・status・タグ名の出力を確認した。
detached HEADはブランチ参照ではなくコミットを直接指す状態で、今回は意図した操作結果である。
同じコミット間の切替のため、異なる版のファイル内容が復元された実験とは扱わない。

## 未実施・限界

- ファイル編集・新規コミット・タグ変更・pushは今回案内していない。
- ファイル全文・ハッシュ・権限の前後比較は未採録。Gitの変更行なしの範囲で確認した。
- detached HEADでのコミット作成・その保全や復旧、異なるコミットへの切替は**NOT RUN**。
- タグを指定した新規Ansible実行、実サービス動作検証は**NOT RUN**。
- originの追跡表示は前段bundle cloneの結果で、GitHubとの同期済みを示すものではない。
- 機械可読なGitデータやrawログは未取得。画像用SHA256SUMSはGitコミットSHAとは別。
- server側の文書追加・CIと本人VM内の操作は対象リポジトリ・実行主体が異なる。

## 復習

タグを指定して版を確認し、作業を続けるときはブランチへ戻る。
タグ名とHEADの対応を確認する。この説明はAIによる復習用で、本人独力の説明の採録ではない。

- [前段：タグ付きbundle復元](2026-09-14-lab-base01-tagged-bundle-practice.md)
- [検証証跡台帳](../README.md)
