# lab-base01：Ansible Vault入門演習（2026-09-14）

## 結果と範囲

本人VM内でダミー変数を暗号化し、パスワード付きのPlaybook実行で値の一致を確認した。
パスワードを指定しない実行は復号用secretがないエラーで終了1となった。
**ダミー値を使うローカルVault演習**であり、実際の認証情報の配備・管理や実サービス接続の実績ではない。

## 来歴

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。AIが手順を提示し、本人が実行・画像提供 |
| 日付 | 2026-09-14 JST（対話の日付）。正確な操作・撮影時刻は未採録 |
| 環境 | Hyper-V VM lab-base01、opsadmin。ansible-vault core 2.16.3、Python 3.12.3（E01） |
| 実行場所 | /home/opsadmin/ansible-first-lab。公開用serverとは別 |
| ファイル | vault-demo-vars.ymlとvault-demo.yml。VM内で未追跡のまま保持 |
| 原資料 | [本人提供画像4枚・ハッシュ](screenshots/2026-09-14-lab-base01-vault-practice/README.md) |

## 確認結果

VP番号は本結果票専用。PASSは画像から確認できた観点に限定する。

| ID | 観点 | 判定 | 結果・証拠 |
| --- | --- | --- | --- |
| VP-01 | 前提 | PASS | main、既存6パス未追跡、今回の2ファイルNOT FOUND、Vault版情報（E01） |
| VP-02 | ダミー入力作成 | PASS | umask 077・set -Cのサブシェル内でダミー値をhere-documentで作成、エラー表示なし（E02） |
| VP-03 | 暗号化 | PASS | encrypt実行、Encryption successful、終了0、先頭行$ANSIBLE_VAULT;1.1;AES256（E02） |
| VP-04 | パスワード付き実行 | PASS | --ask-vault-pass、assertタスクok、後続確認メッセージ、ok2/changed0/failed0、終了0（E03） |
| VP-05 | 保存形式の維持 | PASS | 成功実行後も先頭行がVault形式（E03） |
| VP-06 | パスワードなし拒否 | PASS（想定失敗） | オプションなし実行でAttempting to decrypt but no vault secrets found、終了1（E04） |
| VP-07 | 最終状態 | PASS | 先頭行はVault形式。main、今回2ファイルを含む8パス未追跡。追跡済みファイルの変更行なし（E04） |

公開用のダミー値は`practice-only-not-a-real-secret`である。E03にはPlaybook作成の入力があり、
vars_filesで変数を読み、同じ文字列との一致をassertし、no_log: trueを指定した構成が見える。
実行出力ではassert結果の値は表示されず、後続タスクの固定メッセージを確認した。
ファイルの独立した全文読戻し・ハッシュによる入力同一性確認は未採録。

## パスワードと出力の扱い

Vaultパスワードは本人が対話プロンプトへ入力した。画像には入力文字が表示されておらず、
この記録にパスワードを収録しない。暗号化済み変数ファイル本体も公開用serverにはコピーしない。
画像のハッシュはVaultファイルのハッシュではない。

no_logは当該タスクの実行結果を隠す指定として使用した。Playbookの作成入力にあるダミー値は
画像に表示されているため、「全出力から値を隠した」とは扱わない。
また、今回の一致判定は既知のダミー値を比較する演習であり、実際の秘密値をPlaybookへ直書きする設計ではない。

パスワードなしの試験はこの環境・実行時の条件での拒否を示す。誤ったパスワードの試験や
別の復号用secret供給設定を含む検証ではない。終了1は想定分岐で、成功実行の終了0と区別する。

## 最終状態・未実施

- vault-demo.ymlとvault-demo-vars.ymlは未追跡のまま保持。Gitコミット・push・削除は未実施。
- 暗号化前後と各実行後の全ファイルハッシュは未採録。Vault形式の維持は先頭行の確認に限定する。
- umaskの指定は画像で確認したが、保存後の権限をstat等で独立に確認した結果は未採録。
- 誤パスワード、rekey、view/edit/decrypt、vault-id、password-fileの演習は**NOT RUN**。
- 実際の認証情報の保管、実サービスへの配備・接続、バックアップ・鍵管理設計は**NOT RUN**。
- OS版、実行対象コミット、連続rawログ、独立した実ファイル読戻しは未採録。
- server側の文書追加・CIは本人VM内の実行主体・対象とは別。

## 復習

暗号化して保存し、必要なときにパスワードを与えて読み込む。今回のPlaybook実行では
ディスク上のファイルを平文へ書き換えずに値を使用し、表示されたヘッダーはVault形式を維持した。
これはAIによる復習用説明で、本人独力で説明した証跡ではない。

- [前段：block・rescue・always](2026-09-14-lab-base01-block-practice.md)
- [検証証跡台帳](README.md)
