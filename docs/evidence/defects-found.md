# 欠陥台帳 — 実行して初めて見つかった不具合

> **この文書の位置付け**
>
> 「静的検査は通っていたのに、実際に動かしたら壊れていた」ものを 1 件ずつ記録します。
> README や職務経歴書が件数に言及する場合、**この台帳が正本**です
> （[STATUS §0 ルール 8](https://github.com/ns7jp/ns7jp/blob/main/STATUS.md)）。
>
> 作成日: 2026-08-25。対象は PR #78〜#91（2026-08-23〜24 の作業）。
> 各行の「修正 PR」から実際の diff とコミットメッセージへたどれます。

## 数え方

- **1 件 = 1 つの独立した不具合**。同じコミットで直した別種の不具合は別の行にします。
- 同じ型（例: `|| echo` による二重出力）を別ファイルで踏んだものは、
  **踏んだ回数ぶん**数えます。「同じ型を 3 度踏んだ」という事実自体が記録の対象だからです。
- 「どう見つけたか」は、修正コミットの本文に書いてある事実だけを転記します。

## 集計

| 区分 | 件数 |
| --- | --- |
| 総数 | 45 |
| うち **偽 PASS**（壊れているのに合格と判定していた） | 8（#39〜40を含む） |
| うち **証跡が壊れる / 残らない** | 5 |
| うち **一度も起動・実行できていなかった** | 4 |
| うち **対象 OS / イメージで動かない**（#25, #27〜29, #32, #35） | 6 |
| 静的検査（shellcheck / ansible-lint / molecule / 構文検査）で捕まえられたもの | 0 |

**静的検査で捕まえられたものは 1 件もありません。** 修正時点で shellcheck と構文検査は
いずれも通っており、`meta: end_role` の件は ansible-lint・molecule・構文検査のすべてが
通過していました（[PR #90](https://github.com/ns7jp/server-monitor/pull/90)）。

## 一覧

| # | 症状 | なぜ静的検査で捕まらないか | どう見つけたか | 種別 | 修正 |
| --- | --- | --- | --- | --- | --- |
| 1 | 3 層ラボの nginx が `upstream` ブロックで ap を静的解決していた。ap を stop / start すると IP が変わり、nginx は古い IP を掴んだまま 502 を返し続ける。B-2 の「AP 復帰後の自動回復」が、実際は復旧しているのに FAIL になる | 構文として正しい nginx 設定。起動順と IP 変化という実行時の性質 | 別ラボで同じ罠を踏んだ経験からの見直し | 判定が逆になる | [#78](https://github.com/ns7jp/server-monitor/pull/78) |
| 2 | `lsblk` の FSTYPE は udev の cache 由来で、ext4 が入っているディスクでも null を返すことがある。これを署名判定に使っていたため、**中身のあるディスクを空と誤認して VG を作っていた** | コマンドは正しく、戻り値も正常。cache の性質は実行しないと出ない | `storage-guard-test.sh` の実行 | データ破壊の恐れ | [#78](https://github.com/ns7jp/server-monitor/pull/78) |
| 3 | `grep -c` が失敗時にも値を出力したうえで非ゼロ終了するのに `\|\| echo 0` を付けており、出力が二重（`0\n0`）になって後段の算術比較が構文エラーになる | shellcheck は `\|\| echo` を異常と見ない | `acceptance-check.sh` を初めて実行 | 実行時エラー | [#79](https://github.com/ns7jp/server-monitor/pull/79) |
| 4 | 同上を `curl -w '%{http_code}'` でも踏んでいた（`000000`） | 同上 | 同上 | 実行時エラー | [#79](https://github.com/ns7jp/server-monitor/pull/79) |
| 5 | 同上をもう 1 箇所で踏んでいた | 同上 | 同上 | 実行時エラー | [#79](https://github.com/ns7jp/server-monitor/pull/79) |
| 6 | 層分離の判定に `nc -z` を使っていたが、web コンテナ（nginx:alpine）の busybox `nc` に `-z` が無い。**オプション不正で必ず失敗するので、db へ到達できても PASS になる**。判定したい性質と逆の理由で通る | イメージごとのコマンド差はスクリプトを読んでも分からない | ラボを実行しようとしてコマンド前提を洗い出した | **偽 PASS** | [#80](https://github.com/ns7jp/server-monitor/pull/80) |
| 7 | 同じ web コンテナの busybox `ip` に `-br` が無い | 同上 | 同上 | 実行時エラー | [#80](https://github.com/ns7jp/server-monitor/pull/80) |
| 8 | ap コンテナ（python:3.12-slim）に iproute2 自体が入っていない | 同上 | 同上 | 実行時エラー | [#80](https://github.com/ns7jp/server-monitor/pull/80) |
| 9 | `run-drill.sh:52` で `curl -w` の二重出力（#3〜#5 と同じ型） | 同上 | 1 箇所直して終わりにしていたことに気づき横断確認 | 実行時エラー | [#81](https://github.com/ns7jp/server-monitor/pull/81) |
| 10 | `run-restore-drill.sh:58` でも同じ型。ここは実害が大きく、事故再現後の判定が `!= "200"` なので **`000000` でも通る。データ消失以外の理由でアプリへ到達できない場合でも「データ消失を観測できた」と PASS する** | 同上 | 同上 | **偽 PASS** | [#81](https://github.com/ns7jp/server-monitor/pull/81) |
| 11 | `pg_restore` は無視した警告があると非ゼロ終了することがある。`set -e` のまま呼んでいたため ERR trap で演習全体が中断し、**証跡が 1 行も残らない** | 正常系では起きない | 実行 | 証跡が残らない | [#81](https://github.com/ns7jp/server-monitor/pull/81) |
| 12 | soak モードの観測窓が常に 1 間隔ぶん短い。`--hours 1 --interval 3600` では **0 秒**（1 回測って即終了）。「24 時間連続稼働 結果票」と題した証跡が実際には 23 時間 45 分しか観測していない | 計算式は構文として正しい | baseline / after-reboot / soak を初めて実行 | 証跡が事実と違う | [#82](https://github.com/ns7jp/server-monitor/pull/82) |
| 13 | `docker version --format` は daemon へ繋がらないとき空行を出したうえで非ゼロ終了する。`\|\| echo unknown` だと値が 2 行になり、**証跡の markdown 表がその行で崩れて読めなくなる** | #3 と同じ型だが対象コマンドが違う | 未実行だった証跡出力ブロックを抽出して実行 | 証跡が壊れる | [#83](https://github.com/ns7jp/server-monitor/pull/83) |
| 14 | B1-01 が判定に関わらず実測欄へ「適用完了」を固定で書いていた。mount できていない場合、証跡に `\| 適用完了 \| FAIL \|` という**自己矛盾した行**が残る | 文字列リテラル。静的には正しい | 同上 | 証跡が事実と違う | [#83](https://github.com/ns7jp/server-monitor/pull/83) |
| 15 | 判定に使う `mountpoint` と `df` が `require_tools` に無い。無い環境では mount できていても FAIL になる（**偽 FAIL**） | 前提コマンドの網羅は静的には検査されない | 同上 | 偽 FAIL | [#83](https://github.com/ns7jp/server-monitor/pull/83) |
| 16 | 層分離チェックが `set -e` の下で `out="$(...)"` の直後に `rc=$?` を読もうとしていた。代入文が非ゼロを返すため、**遮断できている（= PASS の）ときにだけ script が落ちて証跡が 0 行になる**。壊れている環境の方が完走する逆転現象 | shellcheck は代入と `$?` の組を警告しない | 3 通りの入力で判定ブロックを実行 | **逆転現象** | [#84](https://github.com/ns7jp/server-monitor/pull/84) |
| 17 | `bash` は `set +e` でも ERR trap を実行する。意図した失敗のたびに「演習が途中で終了した」と誤報が出る | 挙動の細部。実行しないと出ない | 同上 | 誤報 | [#84](https://github.com/ns7jp/server-monitor/pull/84) |
| 18 | RTO / RPO を `date +%s` の秒粒度で引き算していたため、**実測値が 0 秒**になる。しかも秒境界で 0 か 1 に揺れる。RTO / RPO を出すことがこの演習の目的 | 計算は正しい。粒度の問題 | スタブ環境で B-3 を通しで実行 | 証跡が無意味 | [#85](https://github.com/ns7jp/server-monitor/pull/85) |
| 19 | 画面に `FAIL: 8021q カーネルモジュールがない` と出しながら、証跡には `SKIP-ENV` と記録していた。**未検証と不合格の取り違え**で、この演習群が最も避けたいもの | 表示文字列。静的には正しい | routing ラボをスタブで通しで実行 | 表示の誤り | [#86](https://github.com/ns7jp/server-monitor/pull/86) |
| 20 | B-2 障害 B（AP 停止）の期待値が 502 だったが、実測は 504。原因は自分の `resolver valid=10s` 設定で、stop 後 `sleep 3` の観測窓では必ず 504 になる。**期待値が演習自身の設定と矛盾していた** | 期待値の妥当性は実測しないと分からない | 実コンテナ（nginx / gunicorn / PostgreSQL 16）で実行 | 期待値の誤り | [#88](https://github.com/ns7jp/server-monitor/pull/88) |
| 21 | routing ラボが router に各セグメントの `.1` を要求していたが、Docker は既定で bridge 自身へ `.1` を割り当てる。`Address already in use` で **この演習は一度も起動できていなかった** | compose 定義として正しい | 初めて起動を試みた | 一度も動いていない | [#88](https://github.com/ns7jp/server-monitor/pull/88) |
| 22 | Docker が endpoint ごとに入れる `iptables -t raw -A PREROUTING -d <IP> ! -i <bridge> -j DROP` により、別セグメントから router 宛のパケットが FORWARD へ届く前に落ちる。**bridge network を 3 つ並べる構成では L3 疎通が原理的に成立しない** | Docker 自身の挙動。設定ファイルには現れない | パケットキャプチャと iptables counter で切り分け | 設計が成立しない | [#88](https://github.com/ns7jp/server-monitor/pull/88) [#89](https://github.com/ns7jp/server-monitor/pull/89) |
| 23 | コンテナ内の `/proc/sys` が read-only で `ip_forward` を切り替えられない。演習の主眼のひとつが実行できない | 同上 | 同上 | 設計が成立しない | [#89](https://github.com/ns7jp/server-monitor/pull/89) |
| 24 | VLAN の有無を `/sys/module/8021q` の存在で判定していたため、**組み込み（`=y`）でビルドされた kernel を「無い」と誤判定**する | パス確認としては正しい | 実行 | 誤判定 | [#89](https://github.com/ns7jp/server-monitor/pull/89) |
| 25 | `meta: end_role` は ansible-core 2.18 以降にしかない。**Ubuntu 24.04 LTS が同梱するのは 2.16.3 で、そこでは storage role が play ごと落ちる。** CI は pip で入れた 2.21.3 を使っていたため通っていた | **ansible-lint も molecule も構文検査も捕まえていない。** 検査に使う版と配布先の版が違うことが原因 | 実機（qemu 上の Ubuntu 24.04）で B-1 を実行 | 対象 OS で動かない | [#90](https://github.com/ns7jp/server-monitor/pull/90) |
| 26 | storage role が冪等でない。1 回目は成功するが、2 回目は **自分が作った LV を自分の安全装置が「子デバイスがある」として拒否する**。`site.yml` を 2 回流せず、Ansible の role として成立していなかった | 1 回目だけを見る検査では出ない | 同上 | 冪等性の破れ | [#90](https://github.com/ns7jp/server-monitor/pull/90) |
| 27 | el9 の Molecule scenario が role 本体のタスクへ到達する前（Gathering Facts の時点）で毎回失敗する。`sudo: PAM account management error: Authentication service cannot retrieve authentication info`。**common / docker 両 role で再現し、2 回連続で再現**（flake ではない） | ansible-lint・molecule scenario の構文検査・syntax-check のいずれも捕まえない。実行しないと出ない | 2026-08-25 に `ansible-integration.yml` を el9 で初めて実行 | 対象イメージで動かない | [#98](https://github.com/ns7jp/server-monitor/pull/98) |
| 28 | RHEL 系で `curl` パッケージのインストールが dnf の依存解決で失敗する。AlmaLinux / Rocky の最小構成イメージが同梱する `curl-minimal` と provides が衝突する（`package curl-minimal ... conflicts with curl ... from baseos`）。common role・docker role の両方で同じ型を踏んでいた | 同上。パッケージの実インストールでしか出ない | 同上（#27 の修正後に到達した次のエラー） | 対象 OS で動かない | [#98](https://github.com/ns7jp/server-monitor/pull/98) |
| 29 | `sshd -t` によるドロップイン検証が、ホスト鍵が 1 つも無い状態で必ず失敗する（`sshd: no hostkeys available -- exiting`）。`openssh-server` インストール直後の最小構成コンテナでは鍵生成サービスがまだ走っていない | 同上。ホスト鍵が既にある開発環境では再現しない | 同上（#28 の修正後に到達した次のエラー） | 対象 OS で動かない | [#99](https://github.com/ns7jp/server-monitor/pull/99) |
| 30 | `common` role が新設する管理者アカウント（`common_admin_user`、Ansible自動化基盤構築案件パックでは`ansible-admin`）は、SSH公開鍵だけを登録しパスワードを一切設定しない。一方`common_admin_sudo_nopasswd`の既定値は`false`（sudoにpasswordを要求）のため、既定のままだと**sudoが恒久的に成功しないアカウント**ができる | ansible-lint・`--syntax-check`・sudoersの`visudo -cf`検証はいずれも文法・構文レベルの検査であり、「実際にそのpasswordで認証できるか」という意味論までは検査しない | 2026-09-04、実機VM（Hyper-V上のUbuntu 24.04、論理ホスト名`ans-01`）へ`foundation.yml`を初適用し、作成された`ansible-admin`でsudoを試した | 機能が使えない | [PR](https://github.com/ns7jp/server/pull/146) |
| 31 | `common` role の`selinux.yml`が、RHEL系で`container_manage_cgroup`というSELinux booleanを有効化しようとしていたが、このboolean は`container-selinux`パッケージが提供するポリシーモジュールに属する。`common` roleは`docker` roleより先に実行される設計のため、`docker-ce`（`container-selinux`を依存として引き込む）がまだ入っていない時点でこのtaskが実行され、**「boolean is not defined in persistent policy」で必ず失敗する** | ansible-lint・`--syntax-check`は通る。CIの`ansible-integration.yml`（`geerlingguy/docker-rockylinux9-ansible`イメージでの実`molecule test`）も2026-09-04 02:25のrunで成功していた。これはそのMoleculeテスト用イメージが`container-selinux`を最初から同梱しており、パッケージ導入順序の問題が再現しなかったため | 2026-09-04、実機VM（Hyper-V上のAlmaLinux 9.7、論理ホスト名`ans-el9-01`）へ`foundation.yml`を初適用した | 実行順序の誤り | [PR](https://github.com/ns7jp/server/pull/154) |
| 32 | Ubuntu 24.04では`hwclock`が`util-linux`パッケージから`util-linux-extra`パッケージへ分離されている。`common`ロール（全パック共通）の`common_os_packages`（Debian系）には`util-linux`しか無く、`community.general.timezone`タスクが`Failed to find required executable "hwclock"`で必ず失敗する | `dhcpd -t`等の構文検査やansible-lintはパッケージの実インストールを行わないため、hwclockバイナリの実在は検査しない | 2026-09-04、network namespaceラボの`dhcp01`（Ubuntu 24.04.4 LTS）へ`common`ロールを含む`dhcp.yml`を初適用し、timezoneタスクで実際に失敗した | 対象OSで動かない | [PR](https://github.com/ns7jp/server/pull/151) |
| 33 | isc-dhcp-server 4.4.3-P1は`default-lease-time`に300秒以下を指定しても、実際に払い出す`lease-time`（DHCPACKのoption 51）を300秒へ暗黙にクランプする。設定値どおりの短いリース時間が払い出されると期待して短縮すると、実際の値が食い違う | `dhcpd -t`の構文検査は通過し、dhcpd.conf自体も文法上は正しいため、値のクランプは検査に現れない | 2026-09-04、DIT-05（リース更新実測）用に`dhcp_server_default_lease_time`を60秒へ一時変更したところ、DHCPACKの`Lease-Time`optionが実際には300秒だった。値を60/100/299/300/301/500/3600と変えながら実測し300秒がしきい値と確認した | 設定が意図通りに反映されない | [PR](https://github.com/ns7jp/server/pull/151) |
| 34 | isc-dhcp-serverはLinux上でinterfaceに直結したraw socket（LPF）経由でDHCPパケットを受信するため、netfilter（iptables/UFW）のINPUT chainを経由しない。`dhcp_server`ロールのUFW許可rule（UDP 67をinterface `dhcp_server_interface`限定でACCEPT）は、実際にはdhcpdの受信を制御していない | UFWのrule自体は正しく生成・適用されており（`ufw status verbose`で意図どおりに見える）、静的検査・構文検査のいずれもnetfilterとraw socketの関係までは検証しない | 2026-09-04、DIT-05（RENEW/REBIND実測）のためRENEWを`iptables -I INPUT -i seg0 -p udp --dport 67 -j DROP`で遮断しようとしたが、dhcpdは変わらず受信・応答した。対照実験として同じ形のDROPルールが通常のUDPソケット（`nc`）宛の通信は確実に遮断することを確認し、dhcpd固有の受信経路であることを切り分けた。さらに`/proc/<dhcpdのpid>/net/udp`と`/proc/<同>/net/packet`を直接確認し、dhcpdがUDPソケット（port 67）と同時にraw AF_PACKETソケット（`SOCK_RAW`）を保持していることを確認。同じDROPルールを適用したままclient01から完全なDORAを送出しても実際にACKまで得られ新規リースが作成されることも確認した（netfilterのDROPカウンタ自体は加算されるが、raw socketがそれより前段でパケットを受け取るため無関係という整合的な説明が付いた） | セキュリティ制御の実効性が説明と異なる | [PR](https://github.com/ns7jp/server/pull/151) |
| 35 | #32の修正（`common_os_packages`へ`util-linux-extra`を無条件追加）が、別のOSバージョンを壊していた。`util-linux-extra`はUbuntu 24.04(noble)以降にしか存在しないパッケージで、22.04(jammy)には無い（jammyでは`util-linux`本体が`/sbin/hwclock`を含む）。そのため**`common` role適用がjammy上では「No package matching 'util-linux-extra' is available」で必ず失敗する**状態になっていた | ansible-lintと`--syntax-check`はパッケージ名の存在をOSバージョンごとに検証しない。CIのMolecule "default" scenario（`geerlingguy/docker-ubuntu2204-ansible`、jammy）の**フルlifecycle**（`molecule test`）は`ansible-integration.yml`がworkflow_dispatch限定のため、#32の修正後は一度も実行されていなかった | 2026-09-07、[SM-ANS-001](../build-package-ansible/README.md)のfoundation合成scenario追加作業の一環で`ansible-integration.yml`を初めて実行し、`molecule (common / default)`が発覚 | 対象OSで動かない | [PR](https://github.com/ns7jp/server/pull/161) |
| 36 | #31の修正（`container_manage_cgroup` SELinux booleanのtaskを`common` roleから`docker` roleへ移動）が、`docker` role単独実行（`common` roleがplayに無い）という別の使い方を壊していた。`when`条件が`common_manage_selinux \| default(true)`だったため、`common` role未実行で変数自体が未定義だと`default(true)`が常に勝ってtaskが実行され、`python3-libselinux`（`common` roleのRedHat.ymlが導入）が無いホストでは**「Failed to import the required Python library (libselinux-python)」で必ず失敗する** | ansible-lintと`--syntax-check`はJinjaの`default`フィルタが「変数が本当に定義されているか」の意味論までは検証しない。CIのMolecule `docker / el9`の**フルlifecycle**も#31の修正後は一度も実行されていなかった（#35と同じ理由） | 2026-09-07、#35と同じ`ansible-integration.yml`実行で`molecule (docker / el9)`が発覚 | 実行条件の誤り | [PR](https://github.com/ns7jp/server/pull/161) |
| 37 | WSUS版パック手順書`ENABLED_COLLECTORS=cpu,cs,...`の`cs`コレクターは、実際に導入したwindows_exporter 0.31.8では廃止済みで、イベントID102「couldn't enable collectors err="unknown collector cs"」でサービスが起動しない | コレクター名がインストールしたバージョンに実在するかは、そのバイナリを実行しない限り分からない | 2026-09-07、`wsus-01`実機（Hyper-V上のWindows Server 2022評価版VM）へ手順書どおりwindows_exporterを導入し、サービスが起動しないことで発覚 | 対象バージョンで動かない | [PR](https://github.com/ns7jp/server/pull/174) |
| 38 | WSUS版パック手順書の`Set-WsusProduct -UpdateServer $wsus` / `Set-WsusClassification -UpdateServer $wsus`が、**存在しないパラメーター`-UpdateServer`**を指定していた（実際の構文はパイプライン経由の`-Product <WsusProduct> [-Disable]` / `-Classification <WsusClassification> [-Disable]`のみ） | PowerShellのコードブロックとして構文は正しく、cmdletの実引数一覧は実行時のエラーでしか分からない | 2026-09-07、`wsus-01`実機で手順書のコマンドをそのまま実行し、パラメーターエラーで発覚 | 実行時エラー | [PR](https://github.com/ns7jp/server/pull/174) |
| 39 | WSUS版パック手順書・パラメータシートが対象製品として`"Windows Server 2022"`という製品タイトルを指定していたが、**WSUSカタログにこの名前の製品は存在しない**（実際の提供名は`Microsoft Server operating system-21H2`）。指定したタイトルでは対象製品が0件のまま承認ルールが「見た目は成功」で保存されてしまう | 製品カタログの実際のタイトルは、対象WSUSサーバーが実際に同期した後でしか確認できない | 2026-09-07、`wsus-01`実機で承認ルールを保存後に読み戻し、対象製品が0件であることに気づいて発覚 | 偽PASS | [PR](https://github.com/ns7jp/server/pull/174) |
| 40 | WSUS版パック手順書が分類名を英語リテラル（`"Critical Updates"`等）で指定していたが、**日本語(ja-JP)環境のWSUSでは分類名がローカライズされており0件マッチ**する（実際は`重要な更新`・`セキュリティ問題の修正プログラム`・`更新`・`修正プログラム集`）。#39と同様、対象0件のまま承認ルールが見た目は成功で保存される | 分類名のローカライズは対象OS/WSUSサーバーの言語設定に依存し、静的なコードレビューでは気づけない | 2026-09-07、`wsus-01`実機（ja-JP）で承認ルールを保存後に読み戻し、分類が0件であることに気づいて発覚 | 偽PASS | [PR](https://github.com/ns7jp/server/pull/174) |
| 41 | WSUS版パック手順書が、WSUSロールのインストールが自動生成するFirewall許可ルール（`WSUS` 8530/Any、8531/Any、いずれも送信元`Any`）を無効化する手順を欠いていた。WinRMのquickconfigルールについては同じ手順書内で「限定ルールへ一本化する」と明記されているのに、WSUS側だけこの手当てが抜けていた | ロールインストーラーが自動生成するFirewallルールの存在は、実際にロールを導入した後の`Get-NetFirewallRule`でしか確認できない | 2026-09-07、`wsus-01`実機でWSUSロール導入後にFirewallルール一覧を確認し発覚 | 設計・手順の抜け | [PR](https://github.com/ns7jp/server/pull/174) |
| 42 | WSUS版パック手順書に、WSUSサーバー側の`TargetingMode`を`Client`(クライアント側ターゲティング)へ変更する手順が欠けていた。既定値`Server`のままだとGPOで配布した`TargetGroupEnabled`/`TargetGroup`が無視され、クライアントの自己登録先グループを制御するFR-04が成立しない | GPO自体は正常に適用されるため、`gpresult`等の構文・適用確認では発見できない。クライアントが実際にどのグループへ登録されるかを見て初めて分かる | 2026-09-07、`wsus-01`実機の自己登録(SIT-04)が意図したグループへ入らないことから切り分けて発覚 | 機能が使えない | [PR](https://github.com/ns7jp/server/pull/174) |
| 43 | WSUS版パック手順書の8節が承認ルールを`Enabled=false`のまま保存するよう指示する一方、9節の`$rule.ApplyRule()`は「この承認規則は、有効でないため適用できません」と拒否する。**8節と9節が互いに矛盾**しており、設計意図(無人承認を避けつつ手動実行)を`Enabled=false`のままでは実現できない | 8節単体・9節単体はそれぞれ構文上正しく、組み合わせて通しで実行して初めて矛盾が表面化する | 2026-09-07、`wsus-01`実機で9節を実行し`ApplyRule()`が拒否したことで発覚 | 設計・手順の矛盾 | [PR](https://github.com/ns7jp/server/pull/174) |
| 44 | WSUS版パック手順書9節に、承認前のダウンロード量見積もりと、暴走時に停止する手順が欠けていた。この欠落により、実機で`ApplyRule()`を実行した際に分類・製品・グループの絞り込みが効かず557件中555件が全件承認され、**345GB(`GetContentDownloadProgress().TotalBytesToDownload`)のダウンロードが開始**した。ホストC:の空きは28.95GBで、放置すれば同居するドメインコントローラー`ad-dc02`を巻き添えにする状態だった。検知から約1分で`Stop-Service WsusService -Force`により停止し、依存案件への実害はなかった（実ダウンロード量は**最低でも約809MB以上**＝クリーンアップが解放した724MB＋残存するMSRT 85MB。正確な値は`NOT SET`） | 承認ルールの`ApplyRule()`が実際に絞り込みへ従うかどうかは、WSUS APIの意味論であり、手順書の構文レビューでは検証できない | 2026-09-07、`wsus-01`実機でSIT-06実施中に`ApprovedUpdateCount=555`という想定外の値と、その後のコンテンツダウンロード見積もりで発覚 | 重大インシデント(データ消失・巻き添えリスク) | [PR](https://github.com/ns7jp/server/pull/174) |
| 45 | WSUS版パック03のバックアップ設計が、SUSDBのバックアップに`sqlcmd`の使用を前提としていたが、**WID(Windows Internal Database)単体構成には`sqlcmd.exe`が同梱されない**ため、記載のままでは実行できない | `sqlcmd`が既定で使えるかどうかは、対象ホストの実際のインストール構成(WID単体か、フルSQL Serverクライアントツール込みか)に依存し、コードレビューでは分からない | 2026-09-07、`wsus-01`実機でSIT-08(バックアップ・リストア)実施中に`sqlcmd`が見つからず発覚。.NET `System.Data.SqlClient`で名前付きパイプへ直接接続する方式に置き換えて代替 | 前提コマンド不在 | [PR](https://github.com/ns7jp/server/pull/174) |

## この台帳に載せていないもの

- **SELinux の `reboot_required` を無視して次の task が落ちる件**（[#91](https://github.com/ns7jp/server-monitor/pull/91)）は、
  修正コミットが「実機（AlmaLinux 9）で踏んだ」と書いていますが、**その実行の証跡ファイルがありません**。
  証跡の無い項目を台帳へ載せない方針のため、ここには数えていません。
  該当箇所の「実機で踏んだ」という記述も、証跡を採録するまでは想定として書き直します。
- ドキュメントの誤り、リンク切れ、表記ゆれ。動作に影響しないため対象外です。

## この台帳から言えること・言えないこと

**言えること**: 静的検査（shellcheck / ansible-lint / molecule / 構文検査）を全部通しても、
「一度も起動できていない」「壊れているのに PASS する」「証跡が残らない」ものは残ります。
36 件のうち **6 件が偽 PASS** で、テストが無いより悪い状態でした。
うち 3 件（#27〜29）は 2026-08-25 に el9 の Molecule scenario を初めて実行して
見つけたもので、いずれも「対象 OS の既定パッケージ・イメージでは動かない」型でした。
1 件直すと次のエラーが出る、を 3 回繰り返しています。
さらに #35・#36 は、Molecule の**フルlifecycle**（`molecule test`、実コンテナの
create→converge→idempotence→verify）を回す`ansible-integration.yml`が
`workflow_dispatch`限定で自動実行されないため、#31・#32 の修正がそれぞれ
別のOS/使い方を壊したまま2週間近く誰にも気付かれず`main`に残っていたことを
示しています。「構文検査・scenario検出だけの自動CI」と「フルlifecycleは手動」
という構成自体の弱点です。

**言えないこと**: これは学習ラボでの件数であり、本番システムの品質指標ではありません。
また、そもそも自分（と AI 支援）が書いたコードの欠陥なので、
「他人のコードのバグを見つけた」実績ではありません。
