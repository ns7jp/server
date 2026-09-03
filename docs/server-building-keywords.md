# 未経験者向けサーバー構築キーワード集

この文書は、`server-monitor` を読みながらサーバー構築の基本用語を学ぶための
キーワード集です。用語の暗記だけでなく、実際のファイルや確認コマンドと結び付けて、
面接で自分の言葉で説明できる状態を目指します。

## このキーワード集の使い方

各用語は同じ4項目で説明します。

- **一言**: 最初に覚える短い意味
- **意味**: 仕組みや必要になる理由
- **このリポジトリ**: 実装を確認できるファイルや機能
- **確認**: 原則として状態を変えない確認コマンド

最初は太字の「一言」だけを読み、次に実例、最後に詳しい意味を確認します。
すべてを一度に暗記する必要はありません。

覚えるときは **1語・1役割・1実例・1確認** の4点を声に出します。例えば、
「Prometheusは数値の収集・保存係。このリポジトリでは`deploy/prometheus/`にあり、
Targets画面で収集状態を確認する」と説明します。当日、翌日、3日後、7日後に
同じ説明を見ずに言えるか確認すると定着しやすくなります。

> **安全上の注意**: コマンドは破棄できるLinux検証環境で実行します。
> `sudo`、Ansibleの本適用、`terraform apply`、データ削除を伴うコマンドは、
> 対象と戻し方を確認してから使います。実行していない確認は `NOT RUN` と記録します。

## まず覚える12語

| キーワード | 一言で覚える | このリポジトリでの役割 |
| --- | --- | --- |
| Linux | サーバーの土台 | アプリと監視基盤が動くOS |
| プロセス | 実行中のプログラム | Flask、Nginxなどの実体 |
| サービス | 継続して機能を提供する仕組み | Web表示、監視、ログ保存 |
| IPアドレス | 通信相手を示す住所 | 管理端末と監視ホストの識別 |
| ポート | サービスを区別する窓口番号 | 8080、3000、9090など |
| Docker Compose | 複数コンテナの起動係 | 監視スタックをまとめて管理 |
| Ansible | サーバー設定の構築係 | OS設定からアプリ配備まで自動化 |
| Prometheus | 数値の収集・保存係 | CPUや稼働状態を定期収集 |
| Grafana | 数値の可視化係 | グラフとダッシュボードを表示 |
| Loki | ログの保存・検索係 | アプリやOSのログを集約 |
| ランブック | 障害対応の手順書 | 症状別の確認、復旧、完了判定 |
| 証跡 | 実行した事実の記録 | 日時、環境、コマンド、結果を保存 |

## 1. サーバーとOSの基礎

### サーバー

- **一言**: 利用者へ機能やデータを提供する側。
- **意味**: 物理コンピューターやVMを指す場合と、Webサーバーのようなソフトウェアを
  指す場合があります。会話では「機械」と「役割」のどちらかを確認します。
- **このリポジトリ**: Linuxホストが、監視画面、メトリクス、ログを提供します。
- **確認**: `hostnamectl`、`uname -a`

### クライアント

- **一言**: サーバーの機能を利用する側。
- **意味**: Webブラウザ、`curl`、管理端末など、サーバーへ要求を送る側です。
  同じコンピューターが場面によってサーバーにもクライアントにもなります。
- **このリポジトリ**: ブラウザはNginxへ、Prometheusはアプリの`/metrics`へ接続します。
- **確認**: `curl -I http://127.0.0.1:8080/healthz`

### ホストとゲスト

- **一言**: ホストは土台、ゲストはその上で動く環境。
- **意味**: DockerではLinux本体がホスト、コンテナが分離された実行環境です。
  VMではハイパーバイザー側がホスト、VM内のOSがゲストです。
- **このリポジトリ**: node-exporterはLinuxホスト、Flaskの`psutil`は主に
  アプリコンテナの状態を見ます。
- **確認**: `docker info`、`docker compose ps`

### OS（Operating System）

- **一言**: ハードウェアとアプリの間を管理する基本ソフトウェア。
- **意味**: CPU、メモリ、ディスク、ネットワーク、ユーザー、プロセスを管理します。
  LinuxはOSの一種です。
- **このリポジトリ**: Ubuntu 22.04 / 24.04とAlmaLinux / Rocky 9向けの
  Ansible設定があります。
- **確認**: `cat /etc/os-release`

### Linux

- **一言**: サーバーで広く使われるOSの系統。
- **意味**: 厳密にはLinuxはカーネル名ですが、一般にはLinuxカーネルを使うOS全体を
  指します。UbuntuとRocky Linuxではパッケージ管理やfirewallの名前が異なります。
- **このリポジトリ**: OS差分は`ansible/roles/*/vars/`へ分離されています。
- **確認**: `uname -r`、`cat /etc/os-release`

### distribution（ディストリビューション）

- **一言**: Linux kernelと基本softwareを使いやすくまとめた配布セット。
- **意味**: Ubuntu、Rocky Linux、AlmaLinuxなどが該当します。同じLinuxでも、
  package manager、service名、標準設定が異なります。
- **このリポジトリ**: Debian系とRHEL系の差をAnsibleのvarsとtasksへ分離します。
- **確認**: `cat /etc/os-release`

### VM（Virtual Machine）

- **一言**: 物理machineの上に作る仮想的なcomputer。
- **意味**: VMは独自のguest OSとkernelを持ちます。host kernelを共有するcontainerより
  分離が強い一方、起動時間やresource使用量は一般に大きくなります。
- **このリポジトリ**: 基準の引き渡し対象はUbuntu Server 24.04の検証用VM 1台です。
- **確認**: `systemd-detect-virt`、`hostnamectl`

### カーネル

- **一言**: OSの中心で、ハードウェアとプロセスを管理する部分。
- **意味**: CPU時間、メモリ、デバイス、ネットワークなどを管理します。コンテナは
  独自のカーネルを持たず、基本的にホストのLinuxカーネルを共有します。
- **このリポジトリ**: node-exporterは`/proc`と`/sys`からカーネル情報を読みます。
- **確認**: `uname -r`、`cat /proc/version`

### プロセス

- **一言**: 実行中のプログラム1つ1つ。
- **意味**: プログラムのコードが、PID、メモリ、権限などを持って動いている状態です。
  同じプログラムから複数プロセスが起動することがあります。
- **このリポジトリ**: ダッシュボードはCPU使用率上位のプロセスを表示します。
- **確認**: `ps -ef`、`ps aux --sort=-%cpu | head`

### サービスとデーモン

- **一言**: バックグラウンドで継続して機能を提供するプロセス。
- **意味**: デーモンは常駐プログラム、サービスは利用者へ提供する機能や
  systemdで管理する単位を指します。文脈は違いますが、重なることが多い用語です。
- **このリポジトリ**: Docker、SSH、バックアップtimerなどをsystemdで管理します。
- **確認**: `systemctl --type=service --state=running`

### PID（Process ID）

- **一言**: 実行中プロセスの識別番号。
- **意味**: OSが各プロセスを区別する番号です。再起動すると同じサービスでもPIDは
  変わるため、PIDだけで恒久的に識別しません。
- **このリポジトリ**: node-exporterはホストのPID情報を読むため`pid: host`を使います。
- **確認**: `ps -o pid,ppid,user,cmd -C sshd`

### 環境変数

- **一言**: プログラムの外側から渡す設定値。
- **意味**: コードを書き換えず環境ごとに設定を変えられます。ただし子プロセスへ
  引き継がれるため、秘密値の扱いには注意が必要です。
- **このリポジトリ**: `MONITOR_NODE_NAME`などをComposeからアプリへ渡します。
- **確認**: `docker compose config`。秘密値そのものは表示・貼り付けしません。

### 終了コード

- **一言**: コマンドが成功したかを示す番号。
- **意味**: 通常は`0`が成功、`0`以外が失敗です。画面の見た目だけでなく、
  自動化やCIは終了コードで成否を判断します。
- **このリポジトリ**: 演習スクリプトは1件でもFAILなら0以外で終了します。
- **確認**: Bashは`echo "$?"`、PowerShellは`$LASTEXITCODE`

### standard outputとstandard error

- **一言**: 通常の結果を出すstdoutと、errorを出すstderr。
- **意味**: commandは結果とerrorを別のstreamへ出せます。CIでは両方と終了codeを保存し、
  見た目だけで成功を判断しません。
- **このリポジトリ**: E2E runnerはcommand出力をartifactへ保存し、終了codeで判定します。
- **確認**: `command >stdout.log 2>stderr.log`は破棄可能な検証環境だけで使います。

## 2. Linux操作とファイル管理

### Git

- **一言**: ファイルの変更履歴を記録し、過去の状態に戻せるバージョン管理システム。
- **意味**: 誰が、いつ、何を変更したかを記録し、複数人での並行作業や巻き戻しを可能にします。
  このリポジトリ自体もGitで管理されています。
- **このリポジトリ**: `.git/`ディレクトリに履歴が保存されています（通常は中身を直接見ません）。
- **確認**: `git --version`、`git log --oneline -5`

### リポジトリ（repository）

- **一言**: プロジェクトのファイルと変更履歴をまとめて管理する保管場所。
- **意味**: ローカル（自分のPC上）とリモート（GitHub等）の2種類があります。
  `git clone`でリモートの複製をローカルに作り、`git pull`で最新化します。
- **このリポジトリ**: `github.com/ns7jp/server`がリモートリポジトリ、
  `git clone`した先がローカルリポジトリです。
- **確認**: `git remote -v`

### clone

- **一言**: リモートリポジトリの内容を、履歴ごと手元に複製すること。
- **意味**: このリポジトリを初めて使う場合、最初に一度だけ実行します。
  2回目以降は複製し直さず`git pull`で最新化します。
- **このリポジトリ**: `git clone https://github.com/ns7jp/server.git`
- **確認**: `git status`（clone直後はcleanな状態のはず）

### commit

- **一言**: 変更を1つの区切りとして記録すること。
- **意味**: commitごとに一意なID（SHA）が振られ、「どの時点のコードか」を正確に指せます。
  このリポジトリ全体で「commit SHA」という言葉が繰り返し出てくるのはこのためです。
- **このリポジトリ**: `git log --oneline`でcommitの履歴を確認できます。
- **確認**: `git rev-parse HEAD`

### ファイルシステムとパス

- **一言**: ファイルの保存規則と、その場所を示す住所。
- **意味**: `/`を頂点とする階層でファイルを管理します。`/etc`は設定、`/var`は
  変化するデータ、`/home`は利用者データに使われることが一般的です。
- **このリポジトリ**: アプリは`/opt/server-monitor`、バックアップは
  `/var/backups/server-monitor`を標準候補にします。
- **確認**: `pwd`、`findmnt`、`df -h`

### 絶対パスと相対パス

- **一言**: 絶対パスは`/`から、相対パスは現在地から示す。
- **意味**: 自動化では実行場所による事故を避けるため、絶対パスやスクリプト自身の
  場所を基準にすることが重要です。
- **このリポジトリ**: Ansibleの`playbook_dir`からリポジトリルートを解決します。
- **確認**: `pwd`、`realpath .`

### ユーザー、グループ、root

- **一言**: 誰が何を操作できるかを決める識別単位。
- **意味**: rootはほぼすべてを変更できる管理者です。通常作業は一般ユーザーで行い、
  必要な操作だけ`sudo`で昇格します。
- **このリポジトリ**: アプリ用ユーザーを作り、Docker groupのroot相当権限を与えません。
- **確認**: `id`、`groups`、`getent passwd monitor`

### 所有者、グループ、パーミッション

- **一言**: ファイルを誰が読める・書ける・実行できるかの規則。
- **意味**: `r`は読み取り、`w`は書き込み、`x`は実行です。所有者、グループ、その他の
  3区分に設定します。`chmod 777`は安易に使いません。
- **このリポジトリ**: Compose secretsはコンテナUIDから読める`0644`、
  Vaultパスワードは所有者だけの`0600`にします。
- **確認**: `ls -ld deploy/secrets`、`stat <ファイル>`

### sudo

- **一言**: 許可されたコマンドだけ管理者権限で実行する仕組み。
- **意味**: rootでログインし続けるより操作範囲と記録を限定できます。ただし、
  コマンドの危険性は変わらないため、対象確認が必要です。
- **このリポジトリ**: Ansibleは必要なtaskで`become: true`を使います。
- **確認**: `sudo -l`。設定変更は行いません。

### パッケージマネージャー

- **一言**: ソフトウェアの導入・更新・削除を管理する仕組み。
- **意味**: 依存関係や配布元を管理します。UbuntuはAPT、RHEL系はDNFを使います。
- **このリポジトリ**: AnsibleのOS別varsとtasksでAPT/DNF差分を吸収します。
- **確認**: `apt-cache policy docker-ce`または`dnf info docker-ce`

### venv（Python仮想環境）

- **一言**: プロジェクト専用のPython環境を`.venv`ディレクトリに作る仕組み。
- **意味**: OS共通のPythonへ直接libraryを入れると、別のプロジェクトと版が衝突します。
  `python3 -m venv .venv`で専用環境を作り、`source .venv/bin/activate`で切り替えてから
  installすると、影響がそのディレクトリ内に収まります。作業後は`deactivate`で戻します。
- **このリポジトリ**: 学習ガイドの「小さく確認する」手順で`.venv`を作り、`requirements-dev.txt`をinstallします。
- **確認**: `python3 -m venv --help`、`echo "$VIRTUAL_ENV"`

### systemdとunit

- **一言**: Linuxの起動後にサービスを管理する仕組みと、その設定単位。
- **意味**: `.service`はサービス、`.timer`は定期実行などを定義します。
  起動順序、再起動、ログ確認を統一できます。
- **このリポジトリ**: native配備例とバックアップtimerを`deploy/systemd/`に置きます。
- **確認**: `systemctl status docker`、`systemctl list-timers`

### journalとログ

- **一言**: 何が起きたかを時系列で残す記録。
- **意味**: systemd環境ではjournaldがunitの標準出力・標準エラーを集約します。
  障害時は設定変更より先に発生時刻と最初のエラーを確認します。
- **このリポジトリ**: Alloyはホスト`/var/log`とコンテナログをLokiへ転送します。
- **確認**: `journalctl -u docker --since "10 minutes ago"`

### SSH

- **一言**: 離れたLinuxへ暗号化して接続する仕組み。
- **意味**: 公開鍵認証、接続元制限、rootログイン禁止などで安全性を高めます。
  接続設定を誤ると管理不能になるため、既存セッションを残して検証します。
- **このリポジトリ**: `common` roleがsshd設定とfirewall制限を管理します。
- **確認**: `sshd -T`、`ss -lntp | grep ':22'`

### マウント

- **一言**: ディスクやボリュームをディレクトリへ接続すること。
- **意味**: Linuxではストレージをディレクトリツリー上のmount pointへ接続します。
  誤った対象の初期化はデータ消失につながります。
- **このリポジトリ**: `storage` roleは既存署名や`/`への危険なmountを拒否します。
- **確認**: `findmnt`、`lsblk -f`。初期化コマンドは実行しません。

### LVM、PV、VG、LV

- **一言**: diskを柔軟に束ね、必要な大きさへ分けるstorage管理方式。
- **意味**: PVは物理領域、VGはPVをまとめたpool、LVはVGから切り出す論理volumeです。
  容量追加やonline拡張をしやすくしますが、対象diskの誤指定はdata消失につながります。
- **このリポジトリ**: `storage` roleとB-1演習に安全gateと拡張手順があります。
- **確認**: `sudo pvs`、`sudo vgs`、`sudo lvs`。作成・削除は行いません。

## 3. ネットワーク

### NICとnetwork interface

- **一言**: Linuxがnetworkへ出入りするための接続口。
- **意味**: 物理NICだけでなく、loopback、bridge、VLAN、container用の仮想interfaceも
  同じ操作体系で確認できます。
- **このリポジトリ**: routing labはnetwork namespace内のinterfaceを使います。
- **確認**: `ip -br link`、`ip -br addr`

### IPアドレス

- **一言**: ネットワーク上の通信相手を識別する住所。
- **意味**: IPv4では`192.0.2.10`のように表します。アドレスだけでなく、subnet、
  gateway、DNSと組み合わせて通信経路が決まります。
- **このリポジトリ**: 検証ホストの値はinventoryとネットワーク計画書で管理します。
- **確認**: `ip -br addr`

### loopback

- **一言**: 自分自身だけと通信するためのアドレス。
- **意味**: IPv4の`127.0.0.1`は通常、同じホスト内からだけ接続できます。
  開発用画面を外部へ誤公開しない初期値に向きます。
- **このリポジトリ**: UI、Grafana、Prometheusなどの公開先を既定で`127.0.0.1`にします。
- **確認**: `ss -lntp | grep 127.0.0.1`

### subnetとCIDR

- **一言**: 同じネットワークとして扱うアドレスの範囲。
- **意味**: `192.0.2.0/24`の`/24`はnetwork部分の長さです。subnetを分けると
  通信経路やアクセス制御の境界を作れます。
- **このリポジトリ**: ネットワーク演習は複数subnetを使って切り分けを学びます。
- **確認**: `ip route`、`ipcalc 192.0.2.10/24`（導入済みの場合）

### routeとdefault gateway

- **一言**: 宛先までどこへパケットを渡すかの道順。
- **意味**: 直接接続していない宛先はrouterへ渡します。default routeは、より具体的な
  routeがない場合に使う出口です。
- **このリポジトリ**: ルーティングラボで静的routeと`ip_forward`を確認します。
- **確認**: `ip route`、`ip route get 1.1.1.1`

### DNS

- **一言**: 名前をIPアドレスへ変換する仕組み。
- **意味**: 人が覚えやすいhost名やdomain名を通信可能なIPへ解決します。
  「pingできない」ときは、名前解決と経路を分けて確認します。
- **このリポジトリ**: 実管理端末・組織DNSは恒久ホスト用の受け入れ試験対象です。
- **確認**: `getent hosts example.com`、`dig example.com`

### TCPとUDP

- **一言**: TCPは到達を確認する通信、UDPは軽量な通信。
- **意味**: TCPは接続、順序、再送を管理します。UDPはそれらを省き、低遅延ですが
  必要な信頼性をアプリ側で補います。HTTPやSSHは通常TCPです。
- **このリポジトリ**: Web UI、Prometheus、GrafanaはTCP portを使用します。
- **確認**: `ss -lntup`

### ポート

- **一言**: 同じIP上でサービスを区別する窓口番号。
- **意味**: IPが建物の住所なら、portは部屋番号に例えられます。`LISTEN`していても、
  firewallやbind先により外部から接続できるとは限りません。
- **このリポジトリ**: UIは8080、Grafanaは3000、Prometheusは9090を使います。
- **確認**: `ss -lntp`

### listenとbind

- **一言**: listenは接続待ち、bindは待ち受けるアドレスとportを決めること。
- **意味**: `0.0.0.0`は全IPv4 interface、`127.0.0.1`は自分自身だけです。
  同じportでもbind先により公開範囲が変わります。
- **このリポジトリ**: Composeの`ports`でloopback bindを明示します。
- **確認**: `ss -lntp`。`Local Address:Port`を確認します。

### HTTPとHTTPS

- **一言**: Web通信の規則と、それをTLSで暗号化した通信。
- **意味**: HTTPはrequestとresponseで情報をやり取りします。HTTPSは盗聴・改ざん対策と
  接続先証明のためTLSを使います。
- **このリポジトリ**: ローカルはHTTP、native Linux向けにTLS設定例があります。
- **確認**: `curl -v http://127.0.0.1:8080/healthz`

### HTTP status code

- **一言**: HTTP処理結果を3桁の番号で表したもの。
- **意味**: `2xx`は成功、`4xx`は主にrequest側、`5xx`は主にserver側の問題です。
  `401`は認証が必要、`503`は現在サービスを提供できない状態です。
- **このリポジトリ**: 秘密値未設定時はfail closedで保護画面を`503`にします。
- **確認**: `curl -sS -o /dev/null -w '%{http_code}\n' <URL>`

### endpointとAPI

- **一言**: endpointは機能の接続先、APIはprogram同士が機能を使う規則。
- **意味**: 同じserverにも`/healthz`、`/metrics`、`/api/stats`など目的の異なる
  endpointがあります。公開情報と認証方式をendpointごとに決めます。
- **このリポジトリ**: Flaskがhealth、metrics、dashboard用JSON APIを提供します。
- **確認**: `rg -n "@app.route" app.py`

### reverse proxy

- **一言**: 利用者とアプリの間に立つ入口。
- **意味**: TLS終端、認証、header設定、アクセス制御、複数backendへの振り分けを
  まとめられます。利用者からはproxyがserverに見えます。
- **このリポジトリ**: NginxがFlaskアプリの前段でBasic認証と公開範囲を管理します。
- **確認**: `docker compose logs --tail=50 nginx`

### firewall

- **一言**: 許可した通信だけを通す門番。
- **意味**: 送信元、宛先、protocol、portなどで通信を許可・拒否します。
  アプリのbind設定とfirewallは別の防御層です。
- **このリポジトリ**: UbuntuはUFW、RHEL系はfirewalld、AWSはSecurity Groupを使います。
- **確認**: `sudo ufw status verbose`または`sudo firewall-cmd --list-all`

### health check

- **一言**: サービスが応答できるかを機械的に確認する検査。
- **意味**: プロセスの存在だけでなく、必要な処理が応答するかを確認します。
  詳細情報や秘密値を返さない専用endpointが安全です。
- **このリポジトリ**: `/healthz`は認証なしで最小限の稼働状態だけを返します。
- **確認**: `curl -fsS http://127.0.0.1:8080/healthz`

### DHCP（Dynamic Host Configuration Protocol）

- **一言**: 端末が起動時にIPアドレスを自動で受け取る仕組み。
- **意味**: 手作業でIPアドレスを1台ずつ設定しなくても、DHCPサーバーが空いているIPアドレスを
  自動で貸し出します。あわせてgateway、DNSサーバー、ドメイン名も配布できます。
- **このリポジトリ**: [DHCPサーバー構築案件パック](build-package-dhcp/README.md)でisc-dhcp-serverを構築します。
- **確認**: `sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf`（設定の構文検査。実際に配布するには対象セグメントが必要）

### DORA（DISCOVER/OFFER/REQUEST/ACK）

- **一言**: DHCPでIPアドレスが決まるまでの4回のやり取り。
- **意味**: クライアントが全体へ「IPアドレスが欲しい」と呼びかけ（DISCOVER）、サーバーが候補を
  提示し（OFFER）、クライアントがそれを選び（REQUEST）、サーバーが確定させます（ACK）。
- **このリポジトリ**: [DHCPサーバー構築案件パック](build-package-dhcp/README.md)のDIT-02・DNW-06でこの4パケットを実機確認します。
- **確認**: `sudo tcpdump -nn -i <interface> udp port 67 or port 68`

### リース（lease）とスコープ/プール

- **一言**: リースはIPアドレスを貸し出す期限、スコープ/プールは貸し出せるIPアドレスの範囲。
- **意味**: DHCPで配られるIPアドレスは永久に固定されるわけではなく、期限（リース）付きで
  貸し出されます。期限が近づくとクライアントは同じサーバーへ更新（renew）を試みます。
- **このリポジトリ**: [DHCPサーバー構築案件パック](build-package-dhcp/03-parameter-sheet.md)で
  `192.168.50.100`〜`192.168.50.200`をプールとして設計しています。
- **確認**: `cat /var/lib/dhcp/dhcpd.leases`

## 4. Dockerとコンテナ

### コンテナとイメージ

- **一言**: イメージは設計図、コンテナは設計図から動かした実体。
- **意味**: イメージはread-onlyのlayerを持つ配布単位です。コンテナには実行時の
  writable layerが加わりますが、重要データはvolumeへ保存します。
- **このリポジトリ**: `Dockerfile`からアプリimageをbuildし、Composeで起動します。
- **確認**: `docker image ls`、`docker compose ps`

### Dockerfile

- **一言**: コンテナイメージの作り方を書いた手順書。
- **意味**: base image、ファイルcopy、依存導入、実行user、起動commandを定義します。
  buildを再現可能にするためversionや入力を管理します。
- **このリポジトリ**: アプリを非rootで動かす設定を`Dockerfile`に記述します。
- **確認**: `docker build --check .`（対応versionの場合）

### registry、tag、digest

- **一言**: registryはimage保管庫、tagは可変の名前、digestは内容を固定するID。
- **意味**: `latest`などのtagは別内容へ動けます。digestを使うと取得するimage内容を
  固定しやすく、supply chainの再現性を高められます。
- **このリポジトリ**: Docker API proxy imageをSHA-256 digestで固定しています。
- **確認**: `docker image inspect <image> --format '{{json .RepoDigests}}'`

### Docker Compose

- **一言**: 複数コンテナを1つの構成として管理する仕組み。
- **意味**: service、network、volume、secret、起動順序をYAMLで宣言します。
  同じ構成をまとめて起動・停止・確認できます。
- **このリポジトリ**: [`compose.yaml`](../compose.yaml)が標準監視スタックを定義します。
- **確認**: `docker compose config --services`、`docker compose ps`

### Compose service

- **一言**: Composeで管理する役割ごとの定義。
- **意味**: app、nginx、prometheusのように、image、command、network、volumeなどを
  まとめます。service名と実際のcontainer名は同じとは限りません。
- **このリポジトリ**: `docker compose config --services`で一覧を確認できます。
- **確認**: `docker compose config --services`

### volumeとbind mount

- **一言**: volumeはDocker管理の保存領域、bind mountはhostのpathを直接接続。
- **意味**: volumeは永続データに向き、bind mountは設定ファイルの共有に便利です。
  containerを削除しても必要なデータを残せます。
- **このリポジトリ**: Prometheus等のデータはnamed volume、設定はread-only bind mountです。
- **確認**: `docker volume ls`、`docker compose config`

### container network

- **一言**: 必要なコンテナ同士だけを接続する仮想ネットワーク。
- **意味**: service名で名前解決でき、役割ごとに通信範囲を分離できます。
  hostへportを公開することと、container間networkは別です。
- **このリポジトリ**: `frontend`、`monitoring`、`docker-api`を分離します。
- **確認**: `docker network ls`、`docker network inspect <名前>`

### healthcheckとrestart policy

- **一言**: healthcheckは状態検査、restart policyは停止後の再起動規則。
- **意味**: processが存在しても機能が壊れている場合があります。healthcheckで状態を測り、
  restart policyで予期しない停止からの復帰方法を指定します。
- **このリポジトリ**: アプリは`/healthz`を確認し、serviceは`unless-stopped`で再起動します。
- **確認**: `docker compose ps`、`docker inspect <container>`

### Docker secrets

- **一言**: 秘密値を通常の環境変数やimageから分離して渡す方法。
- **意味**: 秘密値をfileとしてcontainerへmountし、設定やログへの露出を減らします。
  元fileの権限とGit除外も必要です。
- **このリポジトリ**: dashboard、metrics、Grafanaの資格情報をfileで管理します。
- **確認**: `git check-ignore deploy/secrets/*.txt`。内容は表示しません。

### non-root、read-only、no-new-privileges

- **一言**: コンテナが奪われた場合の操作範囲を小さくする制限。
- **意味**: non-rootは管理者権限を避け、read-onlyはfilesystem変更を抑え、
  no-new-privilegesは実行中の権限昇格を防ぎます。
- **このリポジトリ**: Flask、Nginx、Lokiなどに複数の制限を組み合わせます。
- **確認**: `docker compose config`、`docker inspect <container>`

### privileged

- **一言**: コンテナにホストへの強い権限（ほぼrootと同等）を与えるオプション。
- **意味**: non-root、read-only、no-new-privilegesとは逆方向で、コンテナの分離をほぼ
  無効化します。ネットワーク名前空間の操作のように、通常のコンテナ権限では出来ない
  操作が必要な場合にのみ使い、何をするか正確に分からないまま付けません。
- **このリポジトリ**: `labs/routing`、`docs/drills`のネットワーク演習ラボが、
  1台のコンテナだけをprivilegedにし、host側には何も残さない設計にしています。
- **確認**: `docker inspect <container> --format '{{.HostConfig.Privileged}}'`

### Docker socket

- **一言**: Docker daemonを操作する強い権限を持つ窓口。
- **意味**: containerから直接socketを使えると、host上のcontainer作成やmountができ、
  実質root相当になる場合があります。
- **このリポジトリ**: Alloyへ直接渡さず、GET/HEAD限定proxyを間に置きます。
- **確認**: `docker compose config | grep docker.sock`

### FlaskとGunicorn

- **一言**: FlaskはWeb application、Gunicornはそれを本番向けに動かすserver。
- **意味**: Flaskはrouteと処理を実装します。Gunicornは複数requestの受付やworker管理を
  担い、開発用serverをそのまま本番利用することを避けます。
- **このリポジトリ**: [`app.py`](../app.py)をGunicornで起動し、前段にNginxを置きます。
- **確認**: `docker compose ps app`、`docker compose logs --tail=50 app`

## 5. AnsibleとTerraform

### IaC（Infrastructure as Code）

- **一言**: インフラ構成をコードとして管理する考え方。
- **意味**: 手作業だけに頼らず、変更履歴、review、再実行、差分確認を可能にします。
  コードがあることと、実環境で検証済みであることは別です。
- **このリポジトリ**: AnsibleでOSとアプリ、TerraformでAWS構成を記述します。
- **確認**: `git log --oneline -- ansible terraform`

### Ansible

- **一言**: 望むサーバー設定を自動でそろえる構成管理ツール。
- **意味**: controllerからSSHでtargetへ接続し、moduleを使って状態を変更します。
  通常はtarget側にagentを常駐させません。
- **このリポジトリ**: OS初期設定、Docker、監視、backupをroleで構築します。
- **確認**: `ansible --version`

### controllerとmanaged node

- **一言**: controllerは指示する側、managed nodeは設定される側。
- **意味**: Ansible commandを実行する端末と、SSH接続されるtarget hostを分けます。
  どちらでcommandを実行するかを手順書で確認します。
- **このリポジトリ**: `docs/deployment-ansible.md`が実行場所を説明します。
- **確認**: `ansible-inventory -i <inventory> --graph`

### inventory

- **一言**: Ansibleが管理するhostとgroupの一覧。
- **意味**: 接続先、group分け、環境別変数を管理します。本番値と検証値を分離し、
  秘密値を直接書かないことが重要です。
- **このリポジトリ**: `ansible/inventory/`にstaging、production、CI例があります。
- **確認**: `ansible-inventory -i inventory/staging.local.yml --graph`

### playbook、play、task

- **一言**: playbookは作業全体、playは対象ごとのまとまり、taskは1つの処理。
- **意味**: YAMLで「どのhostへ、何を、どの順で行うか」を記述します。
  task名は実行結果や障害箇所を読む手掛かりになります。
- **このリポジトリ**: `ansible/playbooks/site.yml`が一括構築の入口です。
- **確認**: `ansible-playbook playbooks/site.yml --list-tasks`

### role

- **一言**: Ansible処理を役割ごとに再利用可能にまとめた単位。
- **意味**: tasks、defaults、handlers、templatesなどを共通構造で整理します。
  大きなplaybookを責務ごとに分けられます。
- **このリポジトリ**: `common`、`docker`、`app`、`monitoring`、`backup`があります。
- **確認**: `find ansible/roles -maxdepth 1 -mindepth 1 -type d`

### variable、group_vars、host_vars

- **一言**: 共通処理へ環境やhostごとの差を渡す値。
- **意味**: group共通値は`group_vars`、host固有値は`host_vars`へ置けます。
  どの値が優先されるか、変数の上書き順序に注意します。
- **このリポジトリ**: OS、環境、配備commit SHAなどをinventory側で管理します。
- **確認**: `ansible-inventory -i <inventory> --host <host>`

### Ansible Vault

- **一言**: Ansibleの秘密値fileを暗号化する仕組み。
- **意味**: Gitに平文のpasswordを置かずに変数を管理できます。復号password自体は
  別の安全な場所で管理し、リポジトリへcommitしません。
- **このリポジトリ**: `vault.yml.example`を複製して暗号化する手順があります。
- **確認**: `ansible-vault view <暗号化済みfile>`は権限のある検証環境だけで使います。

### check modeとdiff

- **一言**: checkは変更予測、diffは変更前後の差分。
- **意味**: `--check --diff`で本適用前に影響を確認します。ただし、未導入packageに
  依存する後続taskなど、fresh hostでは完全な予測にならない場合があります。
- **このリポジトリ**: 配備手順は本適用前のcheck modeを必須の確認にします。
- **確認**: `ansible-playbook ... --check --diff`

### Molecule

- **一言**: Ansibleのroleを実際に起動・冪等性確認・破棄まで行う自動テストツール。
- **意味**: check modeは適用前の「予測」にとどまりますが、Moleculeはcontainer上で
  実際にroleを適用し、2回目の冪等性確認、検証（verify）、破棄までを自動化します。
- **このリポジトリ**: `molecule/`配下にシナリオがあり、CI（`ansible-check.yml`）で実行します。
- **確認**: `molecule test`（対応するroleディレクトリで実行。破壊的操作を伴うため検証用コンテナでのみ実行します）

### 冪等性

- **一言**: 同じ処理を繰り返しても、望む状態から余計に変わらない性質。
- **意味**: 1回目に設定し、2回目は変更不要になるのが基本です。毎回`changed`になるtaskは、
  不要な再起動や予期しない差分を生む可能性があります。
- **このリポジトリ**: E2Eは`site.yml`の2回目が`changed=0`になることを検査します。
- **確認**: 同じplaybookを安全な検証hostへ2回適用しplay recapを比較します。

### handler

- **一言**: 設定変更があったときだけ実行する後処理。
- **意味**: template変更時のservice再起動などを、必要な場合だけ行います。
  taskの`notify`で予約され、通常はplayの終わりに実行されます。
- **このリポジトリ**: roleの`handlers/main.yml`に再起動処理があります。
- **確認**: `rg -n "notify:|listen:" ansible/roles`

### Terraform

- **一言**: Cloud resourceを宣言し、作成・変更・削除を管理するIaCツール。
- **意味**: 現在のstateと設定コードを比較して差分を計画します。`apply`は課金や
  外部公開を伴う可能性があるため、planのreviewが必要です。
- **このリポジトリ**: VPC、ALB、EC2、監視、backupのAWS構成コードがあります。
- **確認**: `terraform fmt -check -recursive`、`terraform validate`

### plan、apply、destroy

- **一言**: planは変更予測、applyは反映、destroyは管理resourceの削除。
- **意味**: planが成功しても実環境での成功や安全性を保証しません。apply/destroy前に
  対象account、workspace、state、cost、rollbackを確認します。
- **このリポジトリ**: AWSの`apply / destroy`は実測証跡がないため`NOT RUN`です。
- **確認**: 入門では`terraform plan`まで。apply/destroyは実行しません。

### Terraform state

- **一言**: Terraformが管理resourceと実物の対応を記録する台帳。
- **意味**: stateを失うと管理関係が分からなくなり、秘密情報を含む場合もあります。
  共有環境ではremote backend、lock、暗号化、access制御を使います。
- **このリポジトリ**: 環境別backend設定例を`terraform/environments/`に置きます。
- **確認**: `terraform state list`は初期化済みの安全な作業環境だけで使います。

## 6. 監視と可観測性

### 監視と可観測性

- **一言**: 監視は既知の異常を見つけ、可観測性は内部状態を外部情報から理解する力。
- **意味**: metrics、logs、tracesなどを組み合わせ、事前に想定していない問題も
  調べられる状態を作ります。
- **このリポジトリ**: metricsはPrometheus、logsはLokiへ集約します。
- **確認**: Grafanaのdatasourceとdashboardを確認します。

### metricsとlogs

- **一言**: metricsは集計しやすい数値、logsは出来事の詳しい記録。
- **意味**: metricsは傾向やthreshold監視に強く、logsは個別事象の文脈に強いです。
  「いつから悪いか」をmetrics、「なぜか」をlogsで追うのが基本です。
- **このリポジトリ**: CPU等をPrometheus、container/host logsをLokiへ保存します。
- **確認**: Prometheus TargetsとGrafana Exploreを確認します。

### exporter

- **一言**: 他のsystemの状態をPrometheus形式へ変換して公開する部品。
- **意味**: 監視対象ごとの情報を`/metrics`で提供します。Prometheusは定期的に
  exporterをscrapeします。
- **このリポジトリ**: node-exporterがLinuxホストのCPU、memory、diskを公開します。
- **確認**: Prometheusの`up{job="linux-node"}`を確認します。

### Prometheus

- **一言**: metricsを定期収集し、時系列で保存・検索する監視system。
- **意味**: targetをscrapeし、label付きの時系列dataとして保存します。PromQLで検索し、
  ruleに一致した異常をAlertmanagerへ送ります。
- **このリポジトリ**: `deploy/prometheus/`にtarget、alert、SLO ruleがあります。
- **確認**: `http://127.0.0.1:9090/targets`

### scrapeとtarget

- **一言**: scrapeは取得動作、targetは取得先。
- **意味**: Prometheusが一定間隔でHTTP endpointを読みます。targetが`DOWN`なら、
  名前解決、route、port、認証、endpointを順に確認します。
- **このリポジトリ**: アプリの`/metrics`はBearer tokenで保護されています。
- **確認**: Prometheusの`/targets`で状態と最後のerrorを確認します。

### time seriesとlabel

- **一言**: time seriesは時刻ごとの値、labelは値を分類する名前札。
- **意味**: metric名とlabelの組み合わせが1本の時系列になります。無制限に増える値を
  labelへ入れるとcardinalityが増え、負荷が高くなります。
- **このリポジトリ**: node名、job、instanceなどで監視対象を分類します。
- **確認**: Prometheusで任意metricのlabel一覧を確認します。

### PromQL

- **一言**: Prometheusのmetricsを検索・計算するquery言語。
- **意味**: filter、集計、rate、時間範囲の計算ができます。dashboardとalert ruleの
  根拠になるため、入力metricと単位を確認します。
- **このリポジトリ**: SLO ruleとGrafana dashboardにqueryがあります。
- **確認**: Prometheusで`up`を実行し、結果のlabelを確認します。

### Grafanaとdashboard

- **一言**: 複数のdata sourceをグラフで見せる可視化systemと画面。
- **意味**: Grafana自身が元metricsを収集するのではなく、PrometheusやLokiへqueryします。
  dashboardは判断に必要な指標を一画面へ整理したものです。
- **このリポジトリ**: Server MonitorとSLO Overview dashboardを自動provisionします。
- **確認**: `http://127.0.0.1:3000/`

### Loki、Alloy、LogQL

- **一言**: Lokiはログ保存、Alloyは収集・転送、LogQLは検索。
- **意味**: Alloyがhost/container logsを集めてLokiへ送り、GrafanaからLogQLで調べます。
  収集・保存・表示を別の役割として覚えます。
- **このリポジトリ**: `deploy/alloy/`、`deploy/loki/`、`docs/loki-queries.md`があります。
- **確認**: Grafana ExploreでLoki datasourceを選び、限定した時間範囲を検索します。

### Alertmanagerとalert

- **一言**: alertは異常条件、Alertmanagerは通知を整理して届ける係。
- **意味**: Prometheusがruleを評価し、Alertmanagerがgrouping、抑制、routingを行います。
  検知成功とSlack等への実配信成功は別の検証です。
- **このリポジトリ**: Slackは秘密値設定後に有効化する例で、実配信は`NOT RUN`です。
- **確認**: `http://127.0.0.1:9093/`。外部送信は事前確認します。

### blackbox monitoring

- **一言**: 対象の外側から利用者に近い方法で確認する監視。
- **意味**: process内部ではなく、HTTP応答やnetwork疎通をprobeします。内部metricsが
  正常でも、入口から利用できない障害を見つけられます。
- **このリポジトリ**: blackbox-exporterがNginx経由の`/healthz`をprobeします。
- **確認**: Prometheusのblackbox targetと`probe_success`を確認します。

### SLI、SLO、SLA

- **一言**: SLIは測定値、SLOは目標、SLAは契約上の合意。
- **意味**: 例として、成功率というSLIに99.5%というSLOを設定します。SLAは未達時の
  対応を含む契約であり、個人ラボのSLOと混同しません。
- **このリポジトリ**: `/healthz`成功率、latency、alert到達時間をSLIにします。
- **確認**: [`docs/slo.md`](slo.md)の定義とqueryを対応付けます。

### error budget

- **一言**: SLOを守りながら許容できる失敗の量。
- **意味**: 100%をSLOにしない場合、許容downtimeや失敗request数を計算できます。
  消費が速ければ変更を抑え、信頼性改善を優先します。
- **このリポジトリ**: 99.5% SLOに対する月間許容downtimeを設計しています。
- **確認**: SLO dashboardの残量とburn rateを確認します。

### availabilityとlatency

- **一言**: availabilityは使えた割合、latencyは応答までの時間。
- **意味**: 応答が成功しても遅すぎれば利用品質は低いため、成功率と時間を別々に測ります。
  averageだけでなくp95などのpercentileも使います。
- **このリポジトリ**: availability 99.5%、`/healthz` p95 500ms未満を目標にします。
- **確認**: SLO Overview dashboardを確認します。

## 7. セキュリティ

### authenticationとauthorization

- **一言**: authenticationは本人確認、authorizationは操作権限の確認。
- **意味**: 「誰か」を確かめた後、「何をしてよいか」を判断します。日本語では認証と
  認可と呼び分けます。
- **このリポジトリ**: UIはBasic認証、metricsはBearer tokenで収集元を確認します。
- **確認**: 認証なしrequestが`401`またはfail closedになることをtestします。

### Basic認証とBearer token

- **一言**: BasicはID/password、Bearerはtokenを持つ者を許可するHTTP認証方式。
- **意味**: Basic認証情報はbase64であり暗号化ではないため、外部通信ではTLSが必要です。
  Bearer tokenも漏えいすると利用されるため秘密値として扱います。
- **このリポジトリ**: 人向けUIとPrometheus向けmetricsで方式を分けます。
- **確認**: test用資格情報だけを使い、`curl -u`や`Authorization` headerを確認します。

### secretとcredential

- **一言**: secretは隠すべき値、credentialは本人・systemを証明する情報。
- **意味**: password、token、private key、webhook URLなどです。code、image、log、
  screenshotへ残さず、rotationできる管理方法を選びます。
- **このリポジトリ**: `.gitignore`、Docker secrets、Ansible Vaultを組み合わせます。
- **確認**: `git status --short`、`git check-ignore <秘密値file>`

### least privilege

- **一言**: 必要最小限の権限だけを与える原則。
- **意味**: 侵害や誤操作が起きても影響範囲を小さくします。user権限、file権限、network、
  API methodをそれぞれ絞ります。
- **このリポジトリ**: 非root、loopback bind、内部network、Docker API proxyを使います。
- **確認**: Compose、user group、listen addressを横断して確認します。

### attack surfaceとhardening

- **一言**: attack surfaceは攻撃可能な入口、hardeningは入口と権限を減らす対策。
- **意味**: 公開port、account、package、API、権限を必要な範囲へ絞ります。
  対策後も残存riskを記録します。
- **このリポジトリ**: SSH、firewall、非root、read-only、maskingを組み合わせます。
- **確認**: `ss -lntup`、package一覧、service一覧を設計値と比較します。

### TLSとcertificate

- **一言**: TLSは通信の暗号化・改ざん検知、certificateは接続先を証明する情報。
- **意味**: certificateの有効期限、host名、trust chainを確認します。自己署名certificateは
  labでは使えますが、警告を無視して本番扱いしません。
- **このリポジトリ**: native Linux向けNginx TLS設定例があります。
- **確認**: `openssl s_client -connect <host>:443 -servername <name>`

### patchとvulnerability

- **一言**: patchは修正、vulnerabilityは悪用され得る弱点。
- **意味**: OS、library、container imageを継続更新し、影響をtestします。scannerの検出は
  risk判断の入口であり、すべてが同じ緊急度ではありません。
- **このリポジトリ**: 自動security update、Dependabot、Trivy、pip-auditを使います。
- **確認**: GitHub ActionsのSecurity scan結果を確認します。

### masking

- **一言**: 表示やlogから識別情報・秘密情報を隠すこと。
- **意味**: 収集自体を止める方法と、表示時に伏せる方法があります。必要性のない情報は
  最初から収集・公開しない方が安全です。
- **このリポジトリ**: host名とOS user名を既定で非表示にします。
- **確認**: API responseとdashboardに実値が出ていないことをtestします。

## 8. 運用、障害対応、ポートフォリオ証跡

### backupとrestore

- **一言**: backupは複製を作り、restoreは複製から戻すこと。
- **意味**: backup fileが存在するだけでは復旧できる証明になりません。checksum、保存先、
  retention、restore手順、復元後の整合性を確認します。
- **このリポジトリ**: Prometheus、Grafana、Loki volumeのbackup/restore手順があります。
- **確認**: [`docs/backup-restore.md`](backup-restore.md)の対象と復元判定を確認します。

### RTOとRPO

- **一言**: RTOは復旧時間、RPOは許容するdata損失時間。
- **意味**: RTOは「いつまでに戻すか」、RPOは「どの時点まで戻せればよいか」です。
  backup頻度、復旧手段、system構成に影響します。
- **このリポジトリ**: D-1演習でRTOを測り、backup設計でRPOを定義します。
- **確認**: 演習開始・復旧時刻と、復元dataの時点を記録します。

### incident

- **一言**: service品質やsecurityへ影響する予期しない出来事。
- **意味**: 影響、開始時刻、検知、暫定対応、復旧、原因、再発防止を記録します。
  個人の責任追及ではなくsystem改善へつなげます。
- **このリポジトリ**: CPU高負荷演習と障害注入logがあります。
- **確認**: `docs/incidents/`と`docs/drills/logs/`を読み比べます。

### runbook

- **一言**: 症状ごとの確認・判断・復旧手順書。
- **意味**: 前提、最初の確認、分岐、危険操作、rollback、完了条件、escalation条件を
  含め、焦っていても再現できるようにします。
- **このリポジトリ**: service停止、disk、memory、latencyなどのrunbookがあります。
- **確認**: [`docs/runbooks/README.md`](runbooks/README.md)から症状を選びます。

### troubleshooting

- **一言**: 事実を集め、原因候補を切り分ける作業。
- **意味**: すぐ設定を変えず、症状、影響範囲、変更履歴、状態、log、network、設定の順で
  仮説を検証します。1回に1つの条件を変えます。
- **このリポジトリ**: 基本順序は「状態 → ログ → 通信 → 設定」です。
- **確認**: `docker compose ps --all`、`logs`、`curl`、`config --quiet`

### rollback

- **一言**: 問題のある変更を、確認済みの状態へ戻すこと。
- **意味**: 単なるfileの上書きではなく、対象version、data互換性、秘密値、実行順序、
  戻した後のhealthを計画します。
- **このリポジトリ**: immutableなcommit SHAを使うGit配備rollback手順があります。
- **確認**: [`docs/build-package/08-change-rollback-plan.md`](build-package/08-change-rollback-plan.md)

### change management

- **一言**: 何を、なぜ、いつ、どう変え、どう戻すかを管理すること。
- **意味**: 目的、影響、review、実施時間、test、rollback、結果を残します。
  小さな変更でも追跡可能性を持たせます。
- **このリポジトリ**: PR templateとchange request Issue templateを用意しています。
- **確認**: `.github/pull_request_template.md`を確認します。

### escalation

- **一言**: 自分だけで安全に解決できない問題を適切な相手へ引き継ぐこと。
- **意味**: 影響拡大、権限不足、復旧見込み超過、security事故などの条件を決めます。
  症状、実施済み確認、変更、log、必要な判断を添えます。
- **このリポジトリ**: 各runbookに復旧完了とescalation条件があります。
- **確認**: runbookの終了条件を作業前に読みます。

### ADR（Architecture Decision Record）

- **一言**: 設計判断を「比較案・採用理由・欠点・見直し条件」の形で残す記録。
- **意味**: 決定した内容だけでなく、なぜ他の案を選ばなかったかを残すことで、後から
  見直す際の判断基準になります。「何を実装したか」ではなく「なぜそう決めたか」を記録します。
- **このリポジトリ**: [`docs/design-decisions.md`](design-decisions.md)にADR-001〜が
  まとめられています。
- **確認**: [`docs/design-decisions.md`](design-decisions.md)のADR見出しを確認します。

### 要件、基本設計、詳細設計

- **一言**: 要件は必要なこと、基本設計は全体方針、詳細設計は実装可能な具体値。
- **意味**: 「何を満たすか」から「どう作るか」へ段階的に具体化します。
  設計値と実際の結果に差があれば記録します。
- **このリポジトリ**: `docs/build-package/00`から`02`へ工程順に整理しています。
- **確認**: 要件IDが設計とtest IDへつながっているか確認します。

### NFR（非機能要件）

- **一言**: 機能そのものではなく、速さ、止まりにくさ、安全性などの品質面の要求。
- **意味**: 「監視画面が見られる」は機能要件、「管理UIをloopbackだけにbindする」
  「2回目の適用で差分が出ない」はNFRです。曖昧になりやすいため、ID、判定方法、
  対応するtest IDを対にして初めて合否を判定できます。
- **このリポジトリ**: `docs/build-package/00-requirements.md`にNFR-01（再現性）からの表があり、
  各NFRが受け入れ試験IDへつながります。
- **確認**: `grep -n "NFR-" docs/build-package/00-requirements.md`

### Gate（工程ゲート）

- **一言**: 次の工程へ進んでよいかを判定する、案件の区切りG0〜G5。
- **意味**: G0要件確定、G1設計確定、G2構築完了、G3試験完了、G4作業完了、G5引き渡しの順に、
  前の条件を満たさないまま先へ進まないための関門です。表の右端は現在の状態で、
  文書が揃っただけの段階と、実測で通過した段階を区別します。
- **このリポジトリ**: 各案件パックのREADMEに「工程ゲート」表があり、冒頭の表の「引き渡し判定」列と対応します。
- **確認**: `grep -n "工程ゲート" docs/build-package/README.md`

### parameter sheet

- **一言**: host名、IP、port、versionなどの設定値を一覧化した表。
- **意味**: 設計書の文章だけでは見落としやすい具体値を一か所で確認します。
  秘密値そのものは記載せず、保管場所や受け渡し方法を書きます。
- **このリポジトリ**: `03-parameter-sheet.md`にOS、SSH、監視設定を整理します。
- **確認**: 実設定とparameter sheetの差分を受け入れ試験で確認します。

### 正本と原本

- **一言**: 正本はその値の正しい出どころ、原本は記入前の元の様式。
- **意味**: 同じ値が複数の文書へ写ると、どれが正しいか分からなくなります。設計値の正本は
  構成codeとparameter sheet、実行結果の正本は日付付きevidenceと決めておきます。
  試験仕様書のような様式は原本を空のまま保ち、結果は複製した日付付きファイルへ記入します。
- **このリポジトリ**: `docs/build-package/03-parameter-sheet.md`が設計値の索引、`docs/evidence/`が結果の正本です。
- **確認**: `grep -n "正本" docs/build-package/00-requirements.md`

### test specificationとacceptance criteria

- **一言**: test specificationは確認方法、acceptance criteriaは合格条件。
- **意味**: 実行前に入力、手順、期待値、判定基準を決めます。結果に合わせて基準を
  書き換えず、差異をFAILやBLOCKEDとして残します。
- **このリポジトリ**: `06-test-specification.md`にID、手順、期待値、結果欄があります。
- **確認**: 必須testがすべて結果と証跡linkを持つか確認します。

### commit SHA

- **一言**: Gitの特定状態を識別する変更不能なID。
- **意味**: branch名は別commitへ動くため、実行したcodeを正確に示すには完全なSHAを
  記録します。同じSHAなら同じtracked file集合を参照できます。
- **このリポジトリ**: AnsibleのGit配備は40文字SHAへ固定します。
- **確認**: `git rev-parse HEAD`

### CI（Continuous Integration）

- **一言**: 変更のたびにtestや静的検査を自動実行する仕組み。
- **意味**: 人による確認漏れを減らし、mainへ統合する前に問題を見つけます。
  CI成功は、CIが対象にした環境・項目だけの証拠です。
- **このリポジトリ**: pytest、Ansible、security scan、E2EなどをActionsで実行します。
- **確認**: commit SHAとGitHub Actions runを対応付けます。

### static validation、runtime validation、E2E

- **一言**: staticは実行前の検査、runtimeは起動後の検査、E2Eは入口から出口までの検査。
- **意味**: 文法や設定構造が正しくても、service起動やnetwork通信が成功するとは限りません。
  どの層まで実行したtestかを明記します。
- **このリポジトリ**: Windows上のstatic testと、使い捨てUbuntu runnerのE2E証跡を分けます。
- **確認**: test名、実行環境、期待値、artifact、commit SHAを対応付けます。

### regression testとnegative test

- **一言**: regressionは直した機能の再発防止、negativeは危険・誤入力を拒否する検査。
- **意味**: 正常系だけでなく、秘密値不足、危険なdisk、認証なしなどが安全に失敗することも
  品質です。修正した問題は自動testにして再発を防ぎます。
- **このリポジトリ**: 初心者導線の回帰testとstorage安全gateのnegative testがあります。
- **確認**: `pytest -q`と、対象test名・期待する失敗条件を確認します。

### 前提診断

- **一言**: 演習を始める前に、必要な道具が揃っているかだけを読み取り専用で調べること。
- **意味**: 足りないものに気づかないまま構築へ進むと、原因の切り分けが難しくなります。
  前提診断は設定変更、package install、sudo、container起動を行わず、Linux、Git、Python、
  OpenSSL、Docker、Compose、Ansible、空き容量、memory、portの状態だけを表示します。
- **このリポジトリ**: `scripts/learning/check-prerequisites.sh`が学習の最初の1手です。
- **確認**: `./scripts/learning/check-prerequisites.sh --help`

### compileallとpytest

- **一言**: compileallは構文だけの検査、pytestは実際に動かす自動test。
- **意味**: `python -m compileall app.py tests`はPythonの文法error（typoやindent崩れ）を
  実行前に見つけます。文法が通ることと期待どおり動くことは別なので、続けて`pytest`で
  振る舞いを確認します。見るのは終了コードとtest件数です。
- **このリポジトリ**: `tests/`にAPI認証、masking、metricsなどのtestがあります。
- **確認**: `python -m compileall --help`、`pytest -q --collect-only`

### PASS、FAIL、BLOCKED、NOT RUN

- **一言**: 成功、失敗、前提不足、未実行を区別する結果状態。
- **意味**: PASSは期待値を満たした実測、FAILは実行して不一致、BLOCKEDは依存条件で
  完了不能、NOT RUNは実行していない状態です。推測をPASSにしません。
- **このリポジトリ**: test結果票と証跡台帳で同じ状態を使います。
- **確認**: 各PASSに日時、環境、command、出力、SHAがあるか確認します。

### WARNとNEXT

- **一言**: WARNは合格ではない注意、NEXTは次に何をすればよいかの指示行。
- **意味**: 前提診断はPASS、WARN、FAILの3種類を表示します。FAILは必須条件の不足なので
  先へ進まず、その項目のNEXTに従います。WARNは今の段階では必須でない不足（例: Ansibleは
  Level 4で必要）で、影響を理解したうえで続行できます。解消前の結果は`BLOCKED`と記録します。
- **このリポジトリ**: `scripts/learning/check-prerequisites.sh`が`[PASS]`、`[WARN]`、`[FAIL]`と
  `NEXT:`行を出し、末尾に`Summary: FAIL=n WARN=n`を表示します。
- **確認**: `grep -n "NEXT" scripts/learning/check-prerequisites.sh`

### NOT SETとNOT READY

- **一言**: NOT SETは値や承認がまだ決まっていない、NOT READYは条件を満たさず先へ進めない。
- **意味**: PASS、FAIL、BLOCKED、NOT RUNがtest結果の状態であるのに対し、この2語は案件側の
  状態です。実案件の承認者や日時が未定なら`NOT SET`、必須testが未実施で引き渡せない工程
  ゲートは`NOT READY`と書き、「未定」を「完了」に見せません。
- **このリポジトリ**: 各案件パックREADMEの工程ゲート表と、冒頭の引き渡し判定欄で使います。
- **確認**: `grep -n "NOT SET\|NOT READY" docs/build-package/README.md`

### evidenceとartifact

- **一言**: evidenceは判断根拠、artifactは保存された出力物。
- **意味**: log、screenshot、結果表、terminal記録などがartifactです。evidenceとして使うには、
  対象、環境、日時、SHA、期待値との関係が必要です。
- **このリポジトリ**: `docs/evidence/`とActions artifactへ保存します。
- **確認**: [`docs/evidence/README.md`](evidence/README.md)で境界を確認します。

### reproducibility

- **一言**: 別の人や別の時点でも同じ手順を再実行できる性質。
- **意味**: version固定、前提、command、入力、期待値、rollbackを明記します。
  ただし外部serviceやOS imageの変化もあるため、環境情報を残します。
- **このリポジトリ**: IaC、Compose、test、日付付きevidenceを組み合わせます。
- **確認**: cleanな破棄可能環境で手順を先頭から再実行します。

## 9. AWS発展キーワード

この節はTerraform codeを読むための発展用語です。このリポジトリではAWSの
`terraform apply / destroy`を実行していないため、以下は**実装・設計上の例**であり、
AWS実環境での稼働実績ではありません。

### VPCとsubnet

- **一言**: VPCはAWS内の仮想network、subnetはその中を分けたaddress範囲。
- **意味**: Availability Zone、route、Internet接続、resource配置の境界を設計します。
  public/privateという名前だけでなく、routeとpublic IPの有無を確認します。
- **このリポジトリ**: `terraform/modules/network/`がVPCとsubnetを定義します。
- **確認**: `terraform plan`のresource差分。applyは行いません。

### EC2、AMI、EBS

- **一言**: EC2は仮想server、AMIは起動image、EBSはblock storage。
- **意味**: instance typeでCPU/memory、AMIで初期OS、EBSでdisk性能と保存期間を決めます。
  instance削除時にEBSを残すかも設計事項です。
- **このリポジトリ**: `terraform/modules/compute/`が監視hostをcode化します。
- **確認**: moduleのvariablesとplanを確認します。EC2は作成しません。

### ALBとtarget group

- **一言**: ALBはHTTP/HTTPSの入口、target groupは転送先serverの集合。
- **意味**: requestをhealthyなtargetへ転送し、TLS certificateやhealth checkを管理します。
  applicationのlocalhost bindとは異なるCloud側の入口です。
- **このリポジトリ**: `terraform/modules/alb/`にlistenerとtarget設定があります。
- **確認**: ALB moduleとarchitecture文書を照合します。

### Security Group

- **一言**: AWS resource単位で通信を許可するstateful firewall。
- **意味**: inboundとoutbound ruleでprotocol、port、source/destinationを制限します。
  Linux内のUFW/firewalldとは別の防御層です。
- **このリポジトリ**: ALBからEC2など、必要な通信だけをTerraformで定義します。
- **確認**: plan上のCIDR、port、参照元Security Groupをreviewします。

### IAM roleとpolicy

- **一言**: roleはAWS内の権限を引き受ける主体、policyは許可・拒否の規則。
- **意味**: access keyをserverへ固定保存せず、一時credentialで必要最小権限を与えます。
  action、resource、conditionを絞ります。
- **このリポジトリ**: monitoringやbackup resourceへ必要な権限をcode化します。
- **確認**: TerraformのIAM policy documentを読み、wildcard範囲を確認します。

### S3とKMS

- **一言**: S3はobject storage、KMSは暗号鍵を管理するservice。
- **意味**: backupやlogを保存するとき、公開設定、暗号化、versioning、retention、
  access policyを組み合わせます。
- **このリポジトリ**: backup moduleに保存と暗号化の設計があります。
- **確認**: codeとplanを確認します。bucketやkeyは作成しません。

### CloudWatchとSNS

- **一言**: CloudWatchはAWS監視、SNSはeventやnotificationの配送service。
- **意味**: AWS resourceのmetrics、logs、alarmを管理し、SNS topicから購読先へ通知できます。
  Prometheus/Alertmanagerとは監視範囲と運用主体が異なります。
- **このリポジトリ**: `terraform/modules/monitoring/`に設計例があります。
- **確認**: threshold、通知先、課金見込みをcodeとplanで確認します。

## 10. Active Directory（AD）の基礎

この節は`docs/build-package-ad/`（AD サーバー構築案件パック、案件ID`SM-AD-001`）を読むための用語です。
このリポジトリではAD自体をまだ実機構築していないため、以下は**設計・手順書上の例**であり、
実機での稼働実績ではありません。実測と未実測の境界は[案件パックREADME](build-package-ad/README.md)を参照してください。

### フォレストとドメイン

- **一言**: ドメインは1つの管理単位、フォレストはドメインの集合全体の一番外側の境界。
- **意味**: 小規模構成では1フォレストに1ドメインだけを作ることが多く、この案件パックもその形です。
  フォレストが違うと、既定では信頼関係（trust）が無い限り管理範囲が分かれます。
- **このリポジトリ**: `corp.example.test`という1つの新規フォレスト・新規ドメインを設計しています。
- **確認**: `Get-ADForest`、`Get-ADDomain`（設計値は[要件定義書](build-package-ad/00-requirements.md)参照）

### ドメインコントローラー（DC）

- **一言**: フォレスト・ドメインの認証とディレクトリ情報を持つ本体サーバー。
- **意味**: ユーザーやコンピューターのログオン、パスワードポリシー、グループポリシーの配布などを担います。
  1台構成は単一障害点（SPOF）になるため、実務では複数台に分けるのが一般的です。
- **このリポジトリ**: 論理ホスト名`ad-dc01`が最初の1台目のDCです。2台目追加は発展課題として言及のみです。
- **確認**: `netdom query fsmo`、`Get-Service NTDS`

### OU（組織単位）

- **一言**: ユーザーやコンピューターを整理し、グループポリシーを適用する単位になるフォルダー。
- **意味**: 既定の`CN=Users`・`CN=Computers`コンテナにはグループポリシーを直接適用できないため、
  管理したい単位でOUを作り直すのが実務での定石です。
- **このリポジトリ**: `_Tier0-Admins`、`Servers`、`Workstations`、`Users`配下の`Employees`等のOUを設計しています。
- **確認**: `Get-ADOrganizationalUnit -Filter *`（設計は[パラメータシート](build-package-ad/03-parameter-sheet.md)参照）

### GPO（グループポリシーオブジェクト）

- **一言**: 「この範囲のパソコンやユーザーには、この設定を配る」というルールのまとまり。
- **意味**: ドメイン・OUなどの単位にリンクし、パスワードポリシーや画面ロックなどを一括で強制できます。
  Ansibleの`site.yml`が構成をコードで揃えるのと似た「まとめて同じ状態にそろえる」考え方です。
- **このリポジトリ**: 既定ドメインGPOでパスワードポリシー（最小長14文字等）を設定しています。
- **確認**: `Get-ADDefaultDomainPasswordPolicy`

### FSMO（5つの役割）

- **一言**: フォレスト・ドメインの中で「1台だけが持つべき」特別な役割の名前。
- **意味**: スキーママスターなど5種類があり、通常はすべて最初のDCが持ちます。DCが複数台になったとき、
  誰がどの役割を持つかを意識する必要があります。
- **このリポジトリ**: 単一DC構成のため、`ad-dc01`が5役割すべてを保持する設計です。
- **確認**: `netdom query fsmo`

### DSRM（ディレクトリサービス復元モード）

- **一言**: DCが壊れて通常起動できないときに使う、AD専用の緊急復旧モード。
- **意味**: フォレスト作成時に専用パスワードを設定します。実値はリポジトリのどの文書にも書かず、
  Git管理外の秘密値台帳で管理します。
- **このリポジトリ**: [要件定義書](build-package-ad/00-requirements.md)の前提条件に記載しています（値は非公開）。
- **確認**: 実機でのみ`DSRMAdminLogon`等の設定状況を確認します（このリポジトリでは実測なし）。

### Kerberos

- **一言**: ADの標準的な認証方式。チケットを使って「なりすまし」を防ぐ仕組み。
- **意味**: 時刻のずれが大きい（既定5分超）と認証に失敗するため、時刻同期（W32Time）がADの前提になります。
- **このリポジトリ**: PDCエミュレータを権威時刻源とし、外部NTPと同期する設計です。
- **確認**: `w32tm /query /status`、`klist`

### LDAP

- **一言**: ディレクトリ（AD）に「このユーザーはいますか」のように問い合わせるための通信の仕組み。
- **意味**: 平文のLDAP（389番）と暗号化されたLDAPS（636番）があり、近年は署名・チャネルバインディングの
  必須化がMicrosoftから求められています。
- **このリポジトリ**: LDAP署名とチャネルバインディングを必須化する設計です（NFR-05）。
- **確認**: レジストリの`LDAPServerIntegrity`・`LdapEnforceChannelBinding`

### SYSVOL

- **一言**: GPOの設定ファイルなどを、DC間で共有するための共有フォルダー。
- **意味**: SMB（445番）を使ってDC間・クライアント間で複製されます。SYSVOLが読めないと、
  グループポリシーが正しく配布されません。
- **このリポジトリ**: 単一DC構成のためDC間複製は発生しませんが、ポート設計上445番を確保しています。
- **確認**: `\\corp.example.test\SYSVOL`への到達性（実機のみ）

### グローバルカタログ

- **一言**: フォレスト全体を横断して検索できる、ADの検索用インデックス。
- **意味**: 通常のLDAP（389番）はドメイン内の検索が中心ですが、グローバルカタログ（3268番）は
  フォレスト全体を検索できます。単一ドメインでは差が目立ちませんが、複数ドメインで重要になります。
- **このリポジトリ**: 単一DCがグローバルカタログを兼ねる設計です。
- **確認**: `nltest /dsgetdc:corp.example.test /GC`

### NetBIOS名

- **一言**: ドメインFQDNとは別に持つ、短い（15文字以内）昔ながらのドメイン呼び名。
- **意味**: `CORP\ユーザー名`のような表記で使われる短縮名です。FQDN（`corp.example.test`）と
  NetBIOS名（`CORP`）は別の値なので、文書やコマンドで混同しないようにします。
- **このリポジトリ**: FQDN`corp.example.test`に対し、NetBIOS名`CORP`を設計しています。
- **確認**: `Get-ADDomain`の`NetBIOSName`

### tombstone lifetime（保持期間）

- **一言**: ADでオブジェクトを削除してから、AD ごみ箱等で復元できる期限。
- **意味**: 既定180日（フォレスト機能レベルWindows Server 2008 R2以降）で、期限を過ぎると
  復元できなくなります。バックアップの保持世代（14日）とは別の期限であることに注意します。
- **このリポジトリ**: 既定の180日をそのまま使う設計です（[基本設計書](build-package-ad/01-basic-design.md)参照）。
- **確認**: `Get-ADObject`の`msDS-DeletedObjectLifetime`

## 11. Zabbix監視基盤の基礎

この節は`docs/build-package-zabbix/`（Zabbix監視基盤構築案件パック、案件ID`SM-ZBX-001`）を
読むための用語です。既存のPrometheus/Grafanaスタック（`docs/build-package/`）とは別に、
同じ監視対象ホスト`monitor-01`を独立した2本目の経路であるZabbixからも監視できるようにする
設計・手順書上の例であり、実機での稼働実績ではありません。実測と未実測の境界は
[案件パックREADME](build-package-zabbix/README.md)を参照してください。

### Host（ホスト）

- **一言**: Zabbixが監視する対象1台を表すオブジェクトの名前。
- **意味**: OSのホスト名と紛らわしいですが、Zabbix内部の「監視対象の登録簿の1行」だと考えると
  分かりやすいです。Itemはこの1行に紐づいて集められます。
- **このリポジトリ**: `monitor-01`という1つのHostを作り、組み込みテンプレートをリンクする設計です。
- **確認**: Frontendの`Data collection` → `Hosts`（設計は[要件定義書](build-package-zabbix/00-requirements.md)参照）

### Template（テンプレート）

- **一言**: 「このHostにはこのItem/Triggerの束を適用する」という設定のひな形。
- **意味**: 監視項目を1つずつ手作りしなくても、テンプレートをリンクするだけで一式のItem/Triggerが
  適用されます。カスタムテンプレートを自作するか、組み込みを使うかは設計判断の1つです。
- **このリポジトリ**: 組み込みの「Linux by Zabbix agent active」をそのままリンクし、自作しません。
- **確認**: Frontendの`Data collection` → `Templates`

### Item（アイテム）

- **一言**: 実際に集める1つの数値・データ項目。
- **意味**: 「CPU使用率」のような組み込みItemのほか、UserParameterで独自に定義したItemも
  同じ扱いで集計・グラフ化・Trigger判定の対象になります。
- **このリポジトリ**: `service_monitor.healthz`というカスタムItemをUserParameterで追加しています。
- **確認**: `zabbix_agent2 -t service_monitor.healthz`（対象ホスト上でItemの値を単体確認）

### Trigger（トリガー）

- **一言**: Itemの値が条件を満たしたときに「異常（Problem）」を宣言するルール。
- **意味**: 「3分間healthzが1以外」のような条件式を書き、条件を満たすとProblem状態になり、
  満たさなくなるとOKへ自動的に戻ります。障害の検知と復旧の両方を表現できます。
- **このリポジトリ**: エージェント到達不能相当のTriggerと、`service_monitor.healthz`用のカスタムTriggerを使います。
- **確認**: Frontendの`Monitoring` → `Problems`（設計は[詳細設計書](build-package-zabbix/02-detailed-design.md)参照）

### Action / Media type

- **一言**: Triggerが発火したときに「誰に・どうやって」知らせるかの設定。
- **意味**: Media typeが通知の「経路」（Slack、メール等）、Actionが「どのTrigger条件のとき、
  誰にどのMedia typeで送るか」という配線を担います。
- **このリポジトリ**: 組み込みの`Slack (webhook)` media typeへ、Docker secretsで注入したwebhook URLを設定します。
- **確認**: Frontendの`Alerts` → `Media types` / `Actions`（webhookと受信先を用意した場合のみ実配信を試験）

### Severity（重要度）

- **一言**: Triggerの深刻さを表すランク。
- **意味**: `Not classified`から`Disaster`まで段階があり、通知経路や色分けの判断材料になります。
  一律に最高ランクにすると本当に重大な障害が埋もれるため、段階を分けて設計します。
- **このリポジトリ**: Disaster（Agent自体unreachable）/ High（healthz異常）/ Warning（閾値超過）の3段階です。
- **確認**: Frontendの`Monitoring` → `Problems`のSeverity列

### active check / passive check

- **一言**: メトリクスを「エージェントから送る」か「サーバーが取りに行く」かの2方式。
- **意味**: active checkはエージェントがサーバーへpushし、passive checkはサーバーがエージェントへ
  取りに行きます（pull）。監視対象ホストが増えたときに、サーバー側から新しい経路を増やさずに
  済むのはactive checkです。
- **このリポジトリ**: active checkを主方式とし、passive checkは既定で未使用（将来拡張として設計のみ）です。
- **確認**: `grep -E '^(Server|ServerActive)' /etc/zabbix/zabbix_agent2.conf`（active checkの送信先設定）

### trapper（トラッパー）

- **一言**: active checkのpushを受け取る、Zabbix Server側の受け口。
- **意味**: `10051/tcp`で待ち受け、他ホストのエージェントからの着信を受ける唯一の監視系ポートです。
  管理UIと違いloopback限定にはできず、送信元CIDR制限で守ります。
- **このリポジトリ**: `zbx-01`の`10051/tcp`が`monitor-01`のIPのみ許可するUFWルールで保護されています。
- **確認**: `ss -lntup | grep 10051`（zbx-01側）、`zabbix_get -s <対象IP> -k agent.ping`（passive check側の疎通確認に使う専用CLI）

### Agent2

- **一言**: 監視対象ホストへ導入する収集エージェントのソフトウェア本体。
- **意味**: 旧来のZabbix Agentの後継で、プラグインによる拡張やTLS対応など機能が強化されています。
- **このリポジトリ**: `monitor-01`へZabbix公式リポジトリからAgent2を導入する設計です。
- **確認**: `zabbix_agent2 -V`、`systemctl status zabbix-agent2`

### UserParameter（ユーザーパラメータ）

- **一言**: 組み込みのItemだけでは取れない値を、設定ファイルに1行追加して独自に定義する仕組み。
- **意味**: `UserParameter=<key>,<実行コマンド>`という1行で、任意のシェルコマンドの出力をItemの値に
  できます。既存の安全設計（外部非公開のエンドポイント等）を緩めずに監視したいときに使えます。
- **このリポジトリ**: `/healthz`が既存パックの設計でloopback限定のため、`monitor-01`自身の
  Agent2からcurlさせるUserParameterとして`service_monitor.healthz`を定義しています。
- **確認**: `zabbix_agent2 -t service_monitor.healthz`（設定ファイルの記述例は
  [ネットワーク設計](build-package-zabbix/04-network-ip-plan.md)・[詳細設計書](build-package-zabbix/02-detailed-design.md)参照）

## 12. Windows Server監視対象ホストの基礎

この節は`docs/build-package-windows/`（Windowsサーバー構築案件パック、案件ID`SM-WIN-001`）を
読むための用語です。このリポジトリではWindows Server自体をまだ実機構築していないため、
以下は**設計・手順書上の例**であり、実機での稼働実績ではありません。実測と未実測の境界は
[案件パックREADME](build-package-windows/README.md)を参照してください。より丁寧な解説と
現場用語ブリッジは[案件パック初心者ガイド（Windows版）](build-package-windows/beginner-guide.md)に
あります。

### WinRM（Windows Remote Management）

- **一言**: Linuxの SSH に相当する、Windows をリモートから操作するための仕組み。
- **意味**: HTTP（5985）とHTTPS（5986）の2経路があり、本パックはHTTPS専用とし、
  平文相当のBasic認証を無効化します。
- **このリポジトリ**: `monitor-win-01`への管理経路として、証明書によるHTTPSリスナーを設計しています。
- **確認**: `Test-WSMan -ComputerName <対象> -UseSSL`（対象ホスト上で実行する場合は`Test-WSMan`のみ）

### IIS（Internet Information Services）

- **一言**: Windows標準のWebサーバー機能。
- **意味**: Linux版のNginx + Flaskアプリにおける「監視される側」の役割を、このパックでは
  IISが担います。
- **このリポジトリ**: 検証用サイトをIISで公開する設計です。
- **確認**: `Get-Service W3SVC`、`Invoke-WebRequest http://localhost/`

### windows_exporter

- **一言**: WindowsホストのCPU・memory・disk等をPrometheus形式で公開する部品。
- **意味**: Linux版のnode-exporterに相当するWindows版です。
- **このリポジトリ**: `monitor-win-01`へ導入し、既定9182/tcpで公開する設計です
  （中央Prometheusからのscrapeはフェーズ2、`monitoring`ネットワークの制約で`BLOCKED`）。
- **確認**: `Invoke-WebRequest http://localhost:9182/metrics`

### 系統A / 系統B

- **一言**: このパックが扱う2つの運用パターン。
- **意味**: 系統A（ワークグループ、本パックの既定）はローカルAdministratorと証明書認証、
  系統B（ADドメイン参加）はドメインアカウントとKerberos認証を使います。Linux版の
  Debian系／RHEL系の違いに近い位置づけです。
- **このリポジトリ**: 基準・既定は系統Aで、系統Bは差分の記載にとどめています。
- **確認**: [基本設計書](build-package-windows/01-basic-design.md)2.1節の比較表

### 済（自動） / 済（手動） / 未実装

- **一言**: この案件パックだけで使う実装状態の3区分。
- **意味**: 済（自動）は既存のAnsible機能で今すぐ実行できるもの（`app_node_exporter_targets`
  への1行追加のみ）、済（手動）はAnsible化されていないが本パックのPowerShell手順で今すぐ
  実施できるもの、未実装は設計のみでコードが無いものです。Linux版の「済／未実装」の
  2区分より1段階細かい区分です。
- **このリポジトリ**: [要件定義書](build-package-windows/00-requirements.md)冒頭で定義しています。
- **確認**: 各文書の該当欄がこの3区分のどれに当たるかを確認します。

### RDP（リモートデスクトップ）

- **一言**: 画面ごと遠隔操作するWindows標準のプロトコル。
- **意味**: 本パックは既定Disableとし、必要時のみ管理元CIDR限定で一時有効化します
  （WinRMが主な管理経路です）。
- **このリポジトリ**: [ネットワーク設計](build-package-windows/04-network-ip-plan.md)で
  RDP（3389/tcp）を必要時のみの経路として設計しています。
- **確認**: `Get-NetFirewallRule -DisplayGroup "リモート デスクトップ"`（対象ホスト上）

### Windows Defender Firewall

- **一言**: Windows標準のFirewall。
- **意味**: 本パックはDefault Inbound Blockとし、WinRM／IIS／windows_exporterの3経路だけを、
  経路ごとに送信元を個別制限して許可します。LinuxのUFW/firewalldに相当します。
- **このリポジトリ**: [パラメータシート](build-package-windows/03-parameter-sheet.md)に
  許可ルールの設計値があります。
- **確認**: `Get-NetFirewallProfile`、`Get-NetFirewallRule`

## 混同しやすい用語の比較

| 用語A | 用語B | 違いを一言で |
| --- | --- | --- |
| サーバー | クライアント | 提供する側 / 利用する側 |
| ホスト | コンテナ | 土台のLinux / 分離された実行環境 |
| プログラム | プロセス | 保存されたcode / 実行中の実体 |
| IPアドレス | ポート | 通信相手の住所 / serviceの窓口 |
| listen | 接続成功 | 待受中 / routeやfirewallも通過済み |
| HTTP | HTTPS | 平文のWeb通信 / TLSで保護したWeb通信 |
| イメージ | コンテナ | 起動前のひな型 / 起動した実体 |
| volume | bind mount | Docker管理領域 / host pathの直接接続 |
| Prometheus | Grafana | metricsの収集・保存 / query・可視化 |
| Loki | Alloy | logsの保存・検索 / logsの収集・転送 |
| alert | notification | 異常条件の成立 / 人やsystemへの送信 |
| authentication | authorization | 誰かの確認 / 何を許すかの確認 |
| backup | restore | 復旧用copy作成 / copyから戻す |
| RTO | RPO | 復旧までの時間 / 戻せるdata時点 |
| check mode | 本適用 | 変更予測 / 実際の変更 |
| plan | apply | Cloud変更予測 / Cloudへの反映 |
| PASS | NOT RUN | 実測で合格 / まだ実行していない |

## 15分の確認演習

すべて読み取り中心の確認です。秘密値は表示しません。

1. `docker compose config --services`でservice名を確認する。
2. [`compose.yaml`](../compose.yaml)で各serviceのnetworkを確認する。
3. `127.0.0.1`にbindするportを探し、外部公開を抑える理由を説明する。
4. [`ansible/playbooks/site.yml`](../ansible/playbooks/site.yml)でroleの順序を確認する。
5. Prometheus、Grafana、Loki、Alloyの役割を一文ずつ書く。
6. [`docs/evidence/README.md`](evidence/README.md)から`NOT RUN`を1件探し、
   なぜPASSと書けないか説明する。
7. `git rev-parse HEAD`を実行し、学習記録へcommit SHAを残す。

## 面接での説明テンプレート

次の空欄を自分の言葉で埋めます。

```text
このポートフォリオは、[目的]のためのLinuxサーバー構築・監視ラボです。
[Ansibleの役割]によって構築を再現可能にし、
[Prometheusの役割]と[Grafanaの役割]によって状態を確認できます。
障害時は[切り分けの順序]で事実を集め、[runbookや証跡]へ記録します。
今回実測した範囲は[PASSの範囲]で、[未実施項目]はNOT RUNと区別しています。
```

## 確認問題

1. hostとcontainerの監視値を分けて考える必要があるのはなぜですか。
2. `127.0.0.1`と`0.0.0.0`のbind範囲はどう違いますか。
3. Prometheus、Grafana、Loki、Alloyの役割を説明してください。
4. Ansibleを2回適用して`changed=0`を確認する理由は何ですか。
5. `terraform plan`成功をAWS構築成功と書けない理由は何ですか。
6. backup fileの存在だけで復旧可能と判断できない理由は何ですか。
7. PASSとNOT RUNにはどのような証拠の違いがありますか。

<details>
<summary>解答例</summary>

1. containerはhostの一部であり、container内の値だけではhost全体のCPUやmemoryを
   表さないためです。
2. `127.0.0.1`は同じhost内からだけ、`0.0.0.0`は全IPv4 interfaceで待ち受けます。
3. Prometheusはmetrics収集・保存、Grafanaは可視化、Lokiはlogs保存・検索、
   Alloyはlogs収集・転送です。
4. 同じ処理を繰り返しても不要な変更が出ない冪等性を確認するためです。
5. planは変更予測であり、実際の作成、通信、費用、削除を検証していないためです。
6. 展開、設定復元、service起動、data整合性、RTO/RPOを確認していないためです。
7. PASSには実行環境、command、期待値を満たした出力があります。NOT RUNには
   実行結果がありません。

</details>

## 次に読む文書

- 全体の学習順: [初心者向け学習ガイド](beginner-learning-guide.md)
- 要件から引き渡し: [Linuxサーバー構築案件パック](build-package/README.md)（初めての場合は先に[案件パック 初心者ガイド](build-package/beginner-guide.md)）
- 構成と通信: [インフラ監視ラボ設計](architecture.md)
- 自動構築: [Ansible配備手順](deployment-ansible.md)
- 障害対応: [運用ランブック](runbooks/README.md)
- 実測と未実施の境界: [検証証跡台帳](evidence/README.md)
