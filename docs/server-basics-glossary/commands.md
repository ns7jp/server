# 確認コマンド逆引き表

[用語集の入口](README.md) / [さくいん](index.md) / [前: 一問一答（50 問）](quiz.md) / [次: 覚えた言葉を「使える」状態にする](explain.md)

知りたいことからコマンドを引ける表です。ここに載せるのは、サーバーの状態を変えない確認コマンドだけです。使えるコマンドは環境によって異なるので、`ss` がなければ `netstat`、`ip` がなければ `ifconfig` を試してください。

## サーバーそのものを知る

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| OS の種類とバージョン | `cat /etc/os-release` | `NAME` と `VERSION` の行 |
| カーネルの版と 64 ビットかどうか | `uname -srm` | 末尾に出る `x86_64` や `aarch64` の文字 |
| このサーバーの名前（ホスト名） | `hostname` | 表示された 1 行がそのまま名前です |
| 最後に起動してからの経過時間 | `uptime` | `up` のあとの時間 |
| サーバーが今どれくらい混んでいるか | `uptime` | `load average` の 3 つの数値（1 分、5 分、15 分の平均） |
| CPU の数と種類 | `lscpu` | `CPU(s)` の行と `Model name` の行 |
| メモリがどれくらい空いているか | `free -h` | `Mem` 行の `available` 列 |
| 今ログインしている人 | `who` | ユーザー名と、右側に出る接続元 |
| 自分がどの権限で作業しているか | `id` | `uid=` のユーザー名と `groups=` の一覧 |
| 物理サーバーか仮想サーバーか | `systemd-detect-virt` | `kvm` や `none` などの 1 語 |
| アクセスを制限する仕組みが動いているか | `getenforce` | `Enforcing` などの 1 語（未導入の環境もあります） |

## プロセスとサービス

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| 今動いているプログラムの一覧 | `ps aux` | `COMMAND` 列（プログラム名） |
| CPU やメモリを多く使っているもの | `top`（終了は `q` キー） | 上に並んだ行の `%CPU` と `%MEM` |
| 見やすい画面で同じことを見たい | `htop`（終了は `q` キー） | 色分けされた一覧（未導入の環境もあります） |
| 特定の名前のものが動いているか | `pgrep -a nginx` | 何か表示されれば動いています |
| サービスが動いているか | `systemctl status nginx` | `Active:` の行が `running` かどうか |
| サーバー起動時に自動で立ち上がるか | `systemctl is-enabled nginx` | `enabled` か `disabled` かの 1 語 |
| サービスの一覧をまとめて見たい | `systemctl list-units --type=service` | `ACTIVE` 列と `DESCRIPTION` 列 |
| 起動に失敗しているサービスがないか | `systemctl --failed` | 表示された行がそのまま問題の場所です |
| サービスがどう起動される設定か | `systemctl cat nginx` | `ExecStart=` の行 |
| どのプログラムがどれを起動したか | `pstree -p` | 字下げの親子関係と、括弧内の番号 |

## ディスクとファイル

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| ディスクの空き容量 | `df -h` | `Use%` 列と `Avail` 列 |
| どのフォルダが容量を使っているか | `sudo du -sh /var/*` | 左側に出るサイズ |
| ファイルの数の上限に近づいていないか | `df -i` | `IUse%` 列 |
| ファイルの持ち主と権限 | `ls -l` | 先頭の `-rw-r--r--` と、3 列目の所有者 |
| 隠れているファイルも見たい | `ls -la` | `.` で始まる名前の行 |
| ファイルの先頭だけ見たい | `head -n 20 ファイル名` | 最初の 20 行 |
| ファイルの末尾だけ見たい | `tail -n 20 ファイル名` | 最後の 20 行 |
| そのファイルが何の形式か | `file ファイル名` | `ASCII text` などの説明 |
| ある文字を含む設定ファイルを探す | `sudo grep -rn "検索したい文字" /etc` | ファイル名と行番号 |
| 名前でファイルの場所を探す | `find /etc -name "*.conf"` | 見つかったパスの一覧 |
| どのディスクがどこに割り当てられているか | `findmnt` | `TARGET` 列（置き場所）と `SOURCE` 列（ディスク） |

## ネットワーク

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| 自分の IP アドレス（Windows は `ipconfig`） | `ip addr show` | `inet` で始まる行 |
| ケーブルや回線がつながっているか | `ip link show` | `state UP` か `state DOWN` か |
| 外へ出るときの出口（ゲートウェイ） | `ip route show` | `default via` で始まる行 |
| 相手まで届くかどうか | `ping -c 4 8.8.8.8` | `0% packet loss` になっているか |
| 途中のどこで止まっているか（Windows は `tracert`） | `traceroute 8.8.8.8` | `* * *` が続き始めた行 |
| 待ち受けているポート（`netstat -tuln` でも可） | `ss -tuln` | `Local Address:Port` 列 |
| そのポートを使っているプログラム | `sudo ss -tulnp` | 行末の `users:(("nginx"...))` の部分 |
| 今つながっている通信の相手 | `ss -tn state established` | `Peer Address:Port` 列 |
| 名前から IP アドレスを引けるか | `dig example.com` | `ANSWER SECTION` に IP アドレスがあるか |
| 手早く名前解決を確かめたい | `nslookup example.com` | 下の方の `Address:` の行 |
| どの DNS サーバーに聞いているか | `cat /etc/resolv.conf` | `nameserver` の行 |
| 相手の特定のポートに入れるか | `nc -vz example.com 443` | `succeeded` の文字が出るか |
| 最近やり取りした同じネットワーク内の機器 | `ip neigh` | IP アドレスと、その機器の MAC アドレス |
| ファイアウォールで止めていないか | `sudo ufw status` または `sudo firewall-cmd --list-all` | 使いたいポートが許可されているか |

## Web と証明書

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| Web サーバーが返事をするか | `curl -I https://example.com` | 1 行目の `200` などの 3 桁の数字 |
| どんな中身が返ってくるか | `curl https://example.com` | 画面に出た HTML の本文 |
| 転送（リダイレクト）の行き先 | `curl -IL https://example.com` | `Location:` の行 |
| 応答までにかかる時間 | `curl -o /dev/null -s -w "%{time_total}\n" https://example.com` | 表示される秒数 |
| サーバーの中からなら動くか | `curl -I http://localhost` | 返事があれば、アプリ自体は動いています |
| 証明書の期限が切れていないか | `curl -vI https://example.com` | `expire date:` の行の日付 |
| 証明書が誰に対して発行されたか | `openssl s_client -connect example.com:443 -servername example.com < /dev/null` | `subject=` の行 |
| 証明書の検証が通っているか | `openssl s_client -connect example.com:443 -servername example.com < /dev/null` | `Verify return code: 0 (ok)` の行 |
| 手元にある証明書ファイルの中身 | `openssl x509 -in cert.pem -noout -text` | `Not After` と `Subject Alternative Name` |
| Web サーバーの設定に書き間違いがないか | `sudo nginx -t` または `sudo apachectl configtest` | `syntax is ok` または `Syntax OK` の文字 |

`curl -I` は HEAD という短い問い合わせを使います。これを受け付けないサイトでは、`405` などの数字が返ることがあります。

## ログと時刻

| 知りたいこと | コマンド | 見るところ |
| --- | --- | --- |
| 最近のログを説明つきで終わりから見る | `journalctl -xe` | 一番下に近いエラーの行 |
| 特定のサービスのログだけ見る | `journalctl -u nginx` | `error` や `failed` の文字がある行 |
| 操作しながらログを流し見する | `journalctl -f`（終了は `Ctrl` と `C`） | 操作した瞬間に増える行 |
| 今回の起動以降のログだけ見る | `journalctl -b` | 起動直後に出た失敗メッセージ |
| 昔ながらのログファイルを読む | `less /var/log/syslog`（終了は `q` キー） | 日付と時刻、その右のメッセージ |
| ログがディスクをどれだけ使っているか | `journalctl --disk-usage` | 表示される合計サイズ |
| サーバーの現在時刻とタイムゾーン | `timedatectl` | `Local time` と `Time zone` の行 |
| 時刻が正しく合わせられているか | `timedatectl` | `System clock synchronized: yes` かどうか |
| どこから時刻をもらっているか | `chronyc sources` または `ntpq -p` | 先頭に `^*` や `*` が付いた行 |
| 誰がいつログインしたか | `last` | ユーザー名、日時、接続元 |

ログの置き場所やファイル名は、環境によって異なります。たとえば `/var/log/syslog` ではなく `/var/log/messages` の環境もあります。`ls -lt /var/log` で中を見て、更新日時が新しいファイルから当たってください。ログの読み取りに権限が必要な環境では、コマンドの前に `sudo` を付けます。

## 「つながらない」ときに見る順番

「つながりません」と言われたら、いきなりアプリを疑わないでください。土台に近い方から順に、1 つずつ確かめます。手前が壊れていれば、その先はすべて失敗するからです。

1. **電源とケーブルを確かめます。** サーバーが起きているか、回線がつながっているかを見ます。`uptime` で起動を確認し、`ip link show` が `state UP` かを見ます。
2. **IP アドレスを確かめます。** 住所がなければ通信は始まりません。`ip addr show` を実行し、`inet` の行に想定どおりのアドレスがあるか見ます。
3. **外へ出る道を確かめます。** `ip route show` で `default via` の行を確認します。そのゲートウェイに `ping -c 4 ゲートウェイの IP アドレス` が届くかも試します。
4. **名前解決を確かめます。** `dig example.com` で IP アドレスが返るか見ます。返らなければ `cat /etc/resolv.conf` で問い合わせ先を確認します。
5. **ポートが開いているか確かめます。** サーバー側は `ss -tuln` で待ち受けを見ます。手元側は `nc -vz example.com 443` で到達を見ます。ここで止まるなら、ファイアウォールやクラウド側の設定も疑います（確認方法は環境によって異なります）。
6. **アプリが返事をするか確かめます。** サーバーの中から `curl -I http://localhost` を試します。返事がなければログを読みます。`systemctl status サービス名` と `journalctl -u サービス名` を使います。
7. **権限や証明書を確かめます。** つながるのに断られる場合です。`curl -I https://example.com` の数字を見ます。`401` は「認証が必要」、`403` は「権限がない」という意味です。あわせて `ls -l` の権限と、`curl -vI` の `expire date:` も確かめます。

> **覚え方**: 下から順に「線・番地・道・名前・扉・中身・鍵」です。線がつながり、番地があり、道が通じ、名前が引けて、扉が開き、中身が動いて、最後に鍵が合う、と覚えてください。

---

[用語集の入口](README.md) / [さくいん](index.md) / [前: 一問一答（50 問）](quiz.md) / [次: 覚えた言葉を「使える」状態にする](explain.md)
