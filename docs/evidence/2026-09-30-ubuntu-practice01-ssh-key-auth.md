# Ubuntu 新規 VM と SSH 鍵認証の実習（2026-09-30）

[検証証跡台帳](README.md)

## 結果と支援範囲

本人が Windows / Hyper-V 上で新しい Ubuntu VM を用意し、Windows からの SSH パスワード接続、
公開鍵登録、認証失敗の調査を行った。BOM 除去等の修正手順と公開鍵認証限定の再接続を案内した後、
本人から「接続できました」と報告があった。

**AI が手順と原因の切り分けを案内し、本人が操作した実習である。独力再現の完了には数えない。**
この文書は、チャットで本人が提示した画面と発言を Codex が整理したもの。
本人自身の振り返り・判断理由はまだ提出されておらず、代筆しない。

## 環境と記録の限界

| 項目 | 内容 |
| --- | --- |
| 実施日 | 2026-09-30（会話の日付・Windows の表示日付。開始終了時刻、所要時間は未採録） |
| 実行者 | 本人。AI は操作案内・画面読取り・原因の切り分け・文書化を担当 |
| ホスト / 接続元 | Windows、Hyper-V、Windows PowerShell / OpenSSH クライアント |
| 接続先 | 新規 VM の Ubuntu、ユーザー opsadmin。論理名 ubuntu-practice01 |
| インストール媒体 | ubuntu-24.04.5-live-server-amd64.iso を選ぶよう案内。選択完了画面・公式ハッシュ照合は未採録 |
| ディスク | インストーラーの画面で 40GB、LVM、ルート約18.5GB、LVM空き約18.5GBを確認 |
| CPU・メモリ等 | 第2世代・仮想CPU 2個・起動メモリ2048MB・動的メモリ・Ubuntu用Secure Bootを案内。最終設定の読戻しは未採録 |
| ネットワーク | Default Switch を使用するよう案内。インストーラーではDHCP、起動後もeth0にプライベートIPv4を確認。固定IPは未設定 |
| ソフトウェア版 | インストール後のOS版・uname・SSH/PowerShellのバージョン出力は未採録 |
| 対象コード | OS・SSHの手動実習。serverリポジトリのコードをVM上で実行した結果ではない |
| 一次資料 | 本会話内のスクリーンショットと本人の発言。画像ファイル・生ログは本リポジトリに収録していない |

公開用に、ホスト側の個人名・保存場所、実IP、鍵の本文・フィンガープリント・コメントを省略した。
以下の出力は画面から必要箇所を抜粋したもので、完全な生ログではない。
ホストとゲストの時計の同期は確認しておらず、画面の時刻から所要時間を算出しない。

## 操作と確認結果

| 段階 | 会話で確認した内容 | 根拠・範囲 |
| --- | --- | --- |
| Hyper-V確認 | 通常のPowerShellでは権限不足。管理者として起動し直すと仮想スイッチの一覧を表示できた | 提示画面 |
| VM・OS準備 | 本人がVM作成完了を報告。Ubuntuインストーラーの言語・ネットワーク・ディスク・Ubuntu Pro画面を提示。その後、Ubuntuのログイン済みプロンプトとeth0のIP表示を確認 | 設定指示すべての読戻しを示すものではない |
| SSHパスワード接続 | 本人が接続成功を報告。後のUbuntuログにも Accepted password for opsadmin が表示された | 本人報告と提示画面 |
| Windowsでの手順取り違え | Windows側でsshdの起動を試し、サービスが存在しないエラー | Windowsは接続元、Ubuntuは接続先とAIが説明。案内した参考資料にWindowsをサーバーにする手順も含まれていた |
| 鍵の準備 | 初期の.ssh一覧はknown_hostsとそのバックアップのみ。Ed25519鍵の作成を案内し、本人が作成完了を報告 | 後のWindows側ssh-keygen出力で256ビット・ED25519の公開鍵を確認 |
| 公開鍵登録 | Windowsから公開鍵をパイプで渡し、Ubuntuのauthorized_keysへ追記する操作が2回実行された | 提示画面。後に登録ファイルの2行を確認 |
| 公開鍵認証の試行 | 指定鍵・公開鍵認証限定で接続し、Permission denied (publickey,password). | 失敗画面。括弧内のpasswordは、この試行でパスワード認証に成功したという意味ではない |
| 権限確認 | .sshは700、authorized_keysは600、所有者はいずれもopsadmin。ホームは755 | Ubuntuのls出力 |
| 形式確認 | Ubuntuではauthorized_keys is not a public key file.。Windowsの元公開鍵はssh-keygenで読み取れた | 両端の提示画面 |
| 内容確認 | 登録ファイルの2行とも、ssh-ed25519の前にBOM、行末にCRが表示された | Ubuntuのsed出力 |
| 修正・再接続 | バックアップ、BOM/CR除去、鍵読取り確認、公開鍵認証限定での再接続を案内。その後、本人が「接続できました」と報告 | 最終成功は本人報告。修正コマンドの実行出力・修正後の鍵照合・成功画面・サーバーのAccepted publickeyログは未採録 |

## 認証失敗の切り分け

画面で確認した診断コマンドは次のとおり。

Ubuntu側:

~~~bash
ls -ld ~ ~/.ssh ~/.ssh/authorized_keys
ssh-keygen -lf ~/.ssh/authorized_keys
sudo journalctl -u ssh -n 20 --no-pager
sed -n '1,3l' ~/.ssh/authorized_keys
~~~

Windows側（公開鍵のみ）:

~~~powershell
ssh-keygen -lf "$env:USERPROFILE\.ssh\id_ed25519_practice01.pub"
~~~

登録ファイルの各行先頭は、sedの表示で次の形だった。鍵本文は省略する。

~~~text
\357\273\277ssh-ed25519 ...
~~~

これはUTF-8のBOM（EF BB BF）であり、公開鍵行の先頭に余分なバイトがあることを確認した。
行末にはCRも表示された。権限を広げる操作ではなく、登録内容の形式を修正する方針をAIが提示した。
BOMを付加した具体的な処理・設定は特定していない。
CRだけでも認証に失敗することを検証したわけではない。

## 案内した修正と再確認

以下は**AIが案内した手順**であり、修正後の端末出力の転記ではない。
本人の成功報告と、個々のコマンドの実行証跡を区別する。

Ubuntu側で元ファイルを保存し、BOMとCRを除去して公開鍵としての読取りを確認する手順:

~~~bash
cp -p ~/.ssh/authorized_keys ~/.ssh/authorized_keys.before-bom-fix
LC_ALL=C sed -i 's/^\xEF\xBB\xBF//; s/\r$//' ~/.ssh/authorized_keys
ssh-keygen -lf ~/.ssh/authorized_keys
~~~

Windows側で指定した鍵を使って再接続する手順（接続先は公開用プレースホルダーへ置換）:

~~~powershell
ssh -i "$env:USERPROFILE\.ssh\id_ed25519_practice01" -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no opsadmin@<VM_IP>
~~~

この指定はクライアントの試行を公開鍵認証に限定する。サーバー側のパスワード認証設定は変更していない。
鍵のパスフレーズとUbuntuアカウントのログインパスワードは別のものとして案内した。
この案内後、本人から「接続できました」と報告された。

## 未確認・次回へ残すこと

- 修正後のファイル内容、Windows側とのフィンガープリント一致、成功ログの採録。
- 重複した公開鍵の整理と、修正前バックアップの存在確認。
- サーバー側のパスワード認証無効化、固定IP、UFW、時刻同期の設定・確認。
- 再起動後の鍵認証の再確認、長時間稼働、監視・バックアップ復元。
- 手順書・公式資料を参照した本人による独力再実施と、本人の言葉での振り返り。

本記録の追加で、[独力再現の手引き](../independent-rerun-guide.md)の未完了状態や、
既存ラボの受け入れ判定を変更しない。
