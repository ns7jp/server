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
| 総数 | 29 |
| うち **偽 PASS**（壊れているのに合格と判定していた） | 6 |
| うち **証跡が壊れる / 残らない** | 5 |
| うち **一度も起動・実行できていなかった** | 4 |
| うち **対象 OS / イメージで動かない**（#25〜29） | 4 |
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

## この台帳に載せていないもの

- **SELinux の `reboot_required` を無視して次の task が落ちる件**（[#91](https://github.com/ns7jp/server-monitor/pull/91)）は、
  修正コミットが「実機（AlmaLinux 9）で踏んだ」と書いていますが、**その実行の証跡ファイルがありません**。
  証跡の無い項目を台帳へ載せない方針のため、ここには数えていません。
  該当箇所の「実機で踏んだ」という記述も、証跡を採録するまでは想定として書き直します。
- ドキュメントの誤り、リンク切れ、表記ゆれ。動作に影響しないため対象外です。

## この台帳から言えること・言えないこと

**言えること**: 静的検査（shellcheck / ansible-lint / molecule / 構文検査）を全部通しても、
「一度も起動できていない」「壊れているのに PASS する」「証跡が残らない」ものは残ります。
29 件のうち **6 件が偽 PASS** で、テストが無いより悪い状態でした。
うち 3 件（#27〜29）は 2026-08-25 に el9 の Molecule scenario を初めて実行して
見つけたもので、いずれも「対象 OS の既定パッケージ・イメージでは動かない」型でした。
1 件直すと次のエラーが出る、を 3 回繰り返しています。

**言えないこと**: これは学習ラボでの件数であり、本番システムの品質指標ではありません。
また、そもそも自分（と AI 支援）が書いたコードの欠陥なので、
「他人のコードのバグを見つけた」実績ではありません。
