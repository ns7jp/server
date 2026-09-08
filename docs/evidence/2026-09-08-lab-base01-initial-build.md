# lab-base01：Hyper-V上のUbuntu初期構築・試験記録（2026-09-07〜08）

## 結果と対象範囲

本人がHyper-V上のUbuntu Server 24.04.4 LTSを操作し、固定IP・SSH鍵認証・sudo・UFW・
時刻同期・自動更新を設定した。設定不備を発生させ、クライアントの拒否表示とサーバーログを
照合し、設定修正またはチェックポイントの適用後に復旧を確認した。

**これは本人の手元VMの初期構築演習であり、監視ラボ全体の構築案件 `SM-LAB-001`、
`site.yml` / `foundation.yml` の実行、CI、商用運用の実績ではない。**
AIが手順案内・画像の読取り・本記録の編集を支援した。AIがVMへ接続して試験を代行した記録ではない。
自力での再構築、第三者への引き渡し、長期稼働はこの記録の対象外である。

教材の21 IDを照合した判定は、**PASS 14 / PASS-ADAPTED 4 / PARTIAL 2 / NOT RUN 1**。
加えてT-14の代替演習1件がPASSである。代替を元のT-14に加算せず、
「教材どおり21/21 PASS」「全受け入れ条件を満たした」とは記載しない。
PASSは下表の観測した観点に対する判定で、未採録の全操作や現在の稼働を保証しない。

## 出典・実行主体・版の境界

| 項目 | 内容 |
| --- | --- |
| 実施者 | ns7jp本人。対話で提示された手順を本人が入力し、結果画像を提供 |
| 実施期間 | 2026-09-07〜08（JST、対話の日付に基づく）。全コマンドの正確な実行日時は未採録 |
| 教材 | [Phase 1：空のVMからの初期構築](https://github.com/ns7jp/ns7jp/blob/main/docs/learning-plan/05-phase1-exercise-design.md)。2026-09-08取得時のGit blob SHAは `a836462b476a70a03a0e84fa52ac66fbb7aa11ba` |
| 記録作成の基点 | `ns7jp/server` main `33f1fae9b9c5bc4854831e70553a3009c8f8e097`。報告書を追加する基点であり、VMの配備commitではない |
| VMの配備commit | 未採録／今回の手動OS初期構築に対応するアプリ配備SHAはない。Git checkoutやAnsible適用を実施したとは扱わない |
| 一次資料 | 本人提供のスクリーンショット42枚。原画像を無加工でコピーし、[画像一覧・由来](screenshots/2026-09-07-08-lab-base01/README.md)とハッシュを添付 |
| rawログ | `script` / `Start-Transcript`の連続記録は未提供。スクリーンショット内の出力のみを採録 |
| 初期導入の証拠 | インストーラ画面の提示と本人の進捗申告、導入後のOS表示あり。空VM作成設定・ISOハッシュ一致・全インストール工程の連続証跡は未採録 |

画像に表示される日時は各OSの時計による。NTP同期前の時刻を確定した外部時刻として扱わない。
初期VM作成（第2世代・2 vCPU・2GiB・20GB VHDX）、チェックポイント作成・適用、
自動起動設定の3項目 `enabled`、T-14代替演習の後片付けは本人の完了申告も利用する。
GUIの設定画面や一覧が提出されていない部分は、画像で確認済みの結果と区別する。

## 実施環境と最終構成

| 項目 | 実測・申告内容 |
| --- | --- |
| 管理端末 | Windows PowerShell / Windows OpenSSH。ホストPCがHyper-V・管理端末・Default Switchを兼ねる。OSの詳細ビルドとOpenSSH版数は未採録 |
| ゲスト | `lab-base01` / Ubuntu 24.04.4 LTS（[E01]） |
| ユーザー | 初期ユーザー `labadmin`、管理ユーザー `opsadmin`。sudoのパスワード必須とrootパスワードロックを確認（[E10]） |
| 通常NIC | `eth0`：Default SwitchのDHCP。`eth1`：`lab-internal`、`192.168.56.10/24`。Windows側は `192.168.56.1` |
| 経路 | デフォルト経路は `eth0`。DHCPアドレスは再起動等で変化したため固定値とは扱わない（[E03]、[E09]） |
| Netplan | `50-cloud-init.yaml`はeth0のDHCP、`60-lab-internal.yaml`はeth1の固定IP（[E42]）。教材の `enp0s8` は実機の `eth1` に読み替え |
| SSH | 22/tcp、鍵認証成功、パスワード方式拒否、実効値 `permitrootlogin no`。socket activationを利用（[E02]、[E05]、[E13]） |
| UFW | `deny incoming / allow outgoing`。許可は22/tcpの送信元 `192.168.56.0/24`（[E06]、[E24]） |
| 時刻・言語 | `Asia/Tokyo`、NTP同期yes、`LANG=ja_JP.UTF-8`（[E09]、[E11]） |
| ストレージ | `/`・`/var`・`/var/tmp`は同一ext4 LV、表示サイズ9.8G、試験前空き約4.7G（[E31]）。20GB VHDX全体の利用可能容量と混同しない |
| 復元ポイント | `key-login-ok` → `base-clean` → 日本語設定を含む `before-drill`（作成は本人申告）。後の復元試験は `before-drill` を使用 |
| 最終状態 | 試験用eth2撤去・eth1維持（[E30]）、T18鍵登録とWindows側2ファイル削除、通常鍵接続成功（[E38]〜[E40]）。tmpfs撤去は本人申告 |

## 21項目の照合表

判定は `PASS`（観測した観点を満たす）、`PASS-ADAPTED`（環境・復旧方法を変更して成功）、
`PARTIAL`（機能を確認したが教材の条件の一部未採録）、`NOT RUN`（元の試験を未実施）とする。
画像にないコマンドを実行済みとして補完しない。

| ID | 観点 | 判定 | 実際の結果・資料 | 変更・限界 |
| --- | --- | --- | --- | --- |
| T-01 | ホスト名 | PASS | `lab-base01`（[E01]、[E20]） | `hostname` / `hostnamectl --static`でも確認 |
| T-02 | タイムゾーン | PASS | `Asia/Tokyo`（[E09]） | `timedatectl status`で観測 |
| T-03 | NTP同期 | PASS | `System clock synchronized: yes`（[E09]） | 起動直後のnoから同期待ち後にyes。時刻精度の測定ではない |
| T-04 | 固定IP | PASS | `eth1 192.168.56.10/24`（[E03]、[E30]） | 教材のNIC名と設定ファイル名を実環境へ読み替え |
| T-05 | sudoと認証要求 | PASS | `sudo -k`後の`sudo -n true`が認証要求・終了1、認証後`root`（[E10]） | opsadminで実施 |
| T-06 | SSH鍵ログイン | PASS | 指定鍵による`whoami`が`opsadmin`（[E04]、[E40]） | 演習専用の名前付き鍵を`-i`で明示 |
| T-07 | パスワード認証拒否 | PASS | 公開鍵を無効にした接続が`Permission denied (publickey)`（[E05]） | SSHハードニング4項目の実効値を同時表示した画像は未採録。拒否動作を確認 |
| T-08 | rootのSSH拒否 | PASS | `permitrootlogin no`とroot宛接続拒否（[E13]、[E14]） | root用の有効鍵を登録した比較試験ではない |
| T-09 | 許可・未開放ポート | PARTIAL | 許可元から22番・鍵接続成功、80番失敗、未許可元の遮断ログ（[E14]、[E25]、[E28]、[E29]） | `Test-NetConnection`使用。教材の「5秒」の所要時間と各SSHの終了コード0は未採録 |
| T-10 | 再起動後の復帰 | PASS-ADAPTED | 固定IP・経路・NTP・UFW維持、鍵接続（[E09]、[E24]、[E25]） | `ssh.socket` / ufw / systemd-timesyncdのenabledは本人申告。教材のssh.service enabledをそのまま必須化しない |
| T-11 | チェックポイント復元 | PASS-ADAPTED | 一時ホスト名から`lab-base01`へ戻り、ja_JP維持（[E19]、[E20]） | 復元先は`before-drill`。適用操作は本人実施の申告と前後画像で確認。RTO未採録 |
| T-12 | 未登録鍵拒否とログ | PASS | 拒否表示と`Failed publickey for opsadmin`、送信元56.1（[E15]、[E16]） | 試験鍵をサーバーへ登録せず実施 |
| T-13 | 未許可元のSSH遮断 | PARTIAL | 57.1から57.10へping成功・22番拒否、UFW BLOCK/DPT=22（[E28]、[E29]）、撤去（[E30]、[E42]） | 遮断機能は成功。「5秒でタイムアウト」の定量条件は未採録。Windowsスイッチ削除は本人の操作手順・申告に基づく |
| T-14 | /var全体の容量枯渇 | NOT RUN | 同一ルートLVであることを確認（[E31]） | 元の/var枯渇を実施せず。下記のT-14-ALTを別記 |
| T-15 | SSH誤設定検出と復元 | PASS | `LabInvalidOption`を検出・終了255→復元後構文正常0→鍵接続（[E21]〜[E25]） | 失敗時入力にコマンド重複あり。最終正常確認は単独コマンド。タイムアウトの原因は未確定 |
| T-16 | 自動更新設定欠落と復元 | PASS-ADAPTED | ファイル退避後欠落・終了1、復元後2項目とも1（[E26]、[E27]） | 教材の配布テンプレートからのコピーではなく、退避した原本を戻した |
| T-17 | サーバー側鍵ファイル権限 | PASS | 666で拒否とbad ownership or modes、600へ戻して接続成功（[E17]、[E18]） | 既存接続を維持し、公開鍵登録ファイルのみ変更 |
| T-18 | クライアント秘密鍵権限 | PASS-ADAPTED | Windows Users権限追加で警告・拒否、削除で成功、鍵の失効・削除（[E35]〜[E40]） | Windows ACL版。Linuxのchmod 644/600による試験はNOT RUN |
| T-19 | ロケール | PASS | `ja_JP.utf8`、`LANG=ja_JP.UTF-8`（[E11]） | インストール時の英語から変更。既存セッションの表示言語とは区別 |
| T-20 | 自動更新の動作 | PASS | パッケージ導入済み、設定2項目1、enabled、dry-run終了0（[E12]） | スケジュールによる実際の更新適用・長期運用は未確認 |
| T-21 | rootパスワードロック | PASS | `passwd -S root`の第2列L（[E10]） | パスワードロックの確認。sudo等の権限昇格すべてを禁止した意味ではない |

### T-14-ALT：専用tmpfsの容量不足・復旧（PASS）

`/var/tmp/lab-t14`に上限64MiBのtmpfsを作成。65MiBの書込みを試すと
`No space left on device`・終了1となり、64M/100%を確認した（[E32]）。
作業中断後はマウントがなく空ディレクトリのみだった（[E33]）。再起動・umountのどちらで
消えたかはこの画像だけでは確定できず、削除による復旧実績として扱わず再実施した。

再実施では64MiBの専用tmpfsを確認後、容量不足・終了1→`fill.bin`削除→空き64M→
1MiBの`recovery.bin`書込み・終了0を観測した（[E34]）。
最後のファイル削除・umount・rmdirは本人が「後片付け完了」と申告した。
これは**専用tmpfsのENOSPCからの復旧**であり、ルートディスク・/var全体の枯渇、
ログ書込み不能時のサービス影響、ext4の予約ブロック挙動を実測したものではない。

### T-18 Windows版の後片付け

試験専用 `id_ed25519_lab_t18` のみにUsers（SID `S-1-5-32-545`）の読み取り権限を追加。
通常使用の秘密鍵のACLは変更していない。復旧後はサーバーの公開鍵登録からコメント
`lab-t18`の行を除去し、試験鍵の接続拒否を確認した（[E38]、[E39]）。
Windows上の秘密鍵・公開鍵の`Test-Path`が両方Falseで、通常鍵による接続が成功した（[E40]）。
T-12用の未登録鍵 `id_ed25519_lab_wrongkey` のWindows側削除は画像で未確認であり、
「すべての試験ファイルを削除した」とは記載しない。

## 失敗・調査・復旧で分かったこと

| 事象 | 確認した事実と対応 | 確定していないこと |
| --- | --- | --- |
| SSHサービスがinactive | socketがactiveで22番待受を確認後、接続成功（[E02]、[E04]） | serviceの表示だけで停止と判定しない |
| 初回のホスト鍵不一致 | Windowsのknown_hostsと提示された鍵の不一致警告（[E41]）。コンソールで指紋照合後に対象IPの記録のみ更新する手順を案内し、本人がログイン成功を申告 | 過去VMが原因とは断定しない。指紋照合・known_hosts更新の実行画像は未採録 |
| 鍵登録時のパスワード再入力 | 1回拒否された後に処理が戻り、公開鍵接続に成功（[E04]） | 入力内容・誤入力理由は不明。秘密値は記録しない |
| 再起動直後NTP未同期 | active/noから待機後yesに変化（最終結果[E09]） | 時刻を手動変更して直したとは扱わない |
| SSH設定復元後の接続タイムアウト | コンソールで構文正常、IP・22番待受・UFWを確認し、再試行で接続成功（[E22]〜[E25]） | 根本原因・復旧秒数は未確定。起動待ち・ネットワーク等と決め付けない |
| 試験用Netplan削除時にファイルなし | ディレクトリ一覧と統合設定にeth2がなく、VMのNIC撤去も確認（[E42]、[E30]） | 削除が起きた正確な時点は不明。既存のeth1設定を削除しない |

## 未実施・未採録と引き渡しの境界

- T-09/T-13の5秒条件を測定した出力、T-14原仕様、T-18のLinux版は未実施または未採録。
- ISOのSHA-256一致、VM設定画面、初期OS導入の全過程、SSH実効設定4項目の一括出力、
  チェックポイント一覧と復元所要時間は未採録。部分画像から補完しない。
- 自動更新はdry-runであり、定時実行による更新適用、全パッケージ更新済みの保証ではない。
- 構築手順の差分（NIC名、Netplanファイル名、名前付き鍵、socket、復元先）を再実施時に読み替える。
  教材の固定IP切り戻しコマンドをそのままこのVMへ適用した実績はない。
- `SM-LAB-001`の監視・通知・バックアップ受け入れ、組織DNS、AWS、Slack、Ansible、
  Dockerアプリ配備、3層構築、長期稼働、独力での再現・3分説明、第三者の受領は **NOT RUN**。
- `before-drill`は途中の復元ポイントであり、今回のすべての試験ログや最終記録を含むとは限らない。
  元画像はVM外の本ディレクトリへ保存した。
- 今回のPRは記録追加である。VMの再試験や教材の全21項目をこのPR作成環境で実行したものではない。
  Markdown・リンク・ハッシュ等の文書検査はPR説明の別欄に記録する。

## 次の演習へ渡す内容

固定IP・鍵認証・接続元制限を備えるVMを用意し、異常の表示とログを確認して復旧した。
次の演習前には上記の未採録項目を補い、VMの現在状態と復元ポイントを確認する。
外部公開・商用の受け入れ完了とは扱わない。

説明例：

> Hyper-V上のUbuntu Serverに固定IP、SSH鍵認証、接続元制限を設定しました。
> 設定ミスや権限不備を再現し、ログと接続結果を使って復旧を確認しました。
> 容量不足は専用tmpfsで代替し、Windowsの秘密鍵権限はACLで試験しました。
> 手順はAIの支援を受け、操作と結果確認は自分で行いました。

参照資料：

- [検証証跡台帳](README.md)
- [元画像42枚・SHA-256対応](screenshots/2026-09-07-08-lab-base01/README.md)
- [教材の学習計画](https://github.com/ns7jp/ns7jp/tree/main/docs/learning-plan)

[E01]: screenshots/2026-09-07-08-lab-base01/E01-initial-os.png
[E02]: screenshots/2026-09-07-08-lab-base01/E02-ssh-socket.png
[E03]: screenshots/2026-09-07-08-lab-base01/E03-static-ip.png
[E04]: screenshots/2026-09-07-08-lab-base01/E04-key-login.png
[E05]: screenshots/2026-09-07-08-lab-base01/E05-password-denied.png
[E06]: screenshots/2026-09-07-08-lab-base01/E06-ufw.png
[E07]: screenshots/2026-09-07-08-lab-base01/E07-key-after-ufw.png
[E08]: screenshots/2026-09-07-08-lab-base01/E08-apt-upgrade.png
[E09]: screenshots/2026-09-07-08-lab-base01/E09-reboot-ntp.png
[E10]: screenshots/2026-09-07-08-lab-base01/E10-sudo-root-lock.png
[E11]: screenshots/2026-09-07-08-lab-base01/E11-locale.png
[E12]: screenshots/2026-09-07-08-lab-base01/E12-auto-update.png
[E13]: screenshots/2026-09-07-08-lab-base01/E13-root-policy.png
[E14]: screenshots/2026-09-07-08-lab-base01/E14-root-and-port80.png
[E15]: screenshots/2026-09-07-08-lab-base01/E15-wrong-key-denied.png
[E16]: screenshots/2026-09-07-08-lab-base01/E16-wrong-key-log.png
[E17]: screenshots/2026-09-07-08-lab-base01/E17-authorized-keys-mode.png
[E18]: screenshots/2026-09-07-08-lab-base01/E18-authorized-keys-recovery.png
[E19]: screenshots/2026-09-07-08-lab-base01/E19-hostname-before-restore.png
[E20]: screenshots/2026-09-07-08-lab-base01/E20-hostname-after-restore.png
[E21]: screenshots/2026-09-07-08-lab-base01/E21-sshd-invalid.png
[E22]: screenshots/2026-09-07-08-lab-base01/E22-restore-ssh-timeout.png
[E23]: screenshots/2026-09-07-08-lab-base01/E23-sshd-valid.png
[E24]: screenshots/2026-09-07-08-lab-base01/E24-restore-server-state.png
[E25]: screenshots/2026-09-07-08-lab-base01/E25-restore-connectivity.png
[E26]: screenshots/2026-09-07-08-lab-base01/E26-auto-update-missing.png
[E27]: screenshots/2026-09-07-08-lab-base01/E27-auto-update-restored.png
[E28]: screenshots/2026-09-07-08-lab-base01/E28-outside-client.png
[E29]: screenshots/2026-09-07-08-lab-base01/E29-outside-ufw-log.png
[E30]: screenshots/2026-09-07-08-lab-base01/E30-network-cleanup.png
[E31]: screenshots/2026-09-07-08-lab-base01/E31-storage-layout.png
[E32]: screenshots/2026-09-07-08-lab-base01/E32-tmpfs-full-first.png
[E33]: screenshots/2026-09-07-08-lab-base01/E33-tmpfs-resume.png
[E34]: screenshots/2026-09-07-08-lab-base01/E34-tmpfs-recovery.png
[E35]: screenshots/2026-09-07-08-lab-base01/E35-windows-key-baseline.png
[E36]: screenshots/2026-09-07-08-lab-base01/E36-windows-key-denied.png
[E37]: screenshots/2026-09-07-08-lab-base01/E37-windows-key-recovered.png
[E38]: screenshots/2026-09-07-08-lab-base01/E38-test-key-unregistered.png
[E39]: screenshots/2026-09-07-08-lab-base01/E39-test-key-revoked.png
[E40]: screenshots/2026-09-07-08-lab-base01/E40-final-key-cleanup.png
[E41]: screenshots/2026-09-07-08-lab-base01/E41-host-key-warning.png
[E42]: screenshots/2026-09-07-08-lab-base01/E42-netplan-cleanup.png
