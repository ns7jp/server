# 構築手順書

> 💡 **初めて読む方へ**: この文書は実際に`zbx-01`を構築するとき、上から順に実行するコマンド手順書です。「なぜ2回実行するのか」などは[初心者ガイド](beginner-guide.md#05-構築手順書)で先に触れています。

本書は、[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)・[詳細設計書](02-detailed-design.md)・[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を受けて、新規の監視サーバーホスト`zbx-01`(Ubuntu Server 24.04 LTS)へZabbix 7.0 LTS一式を構築し、既存の監視対象ホスト`monitor-01`(既存、[Linux版パック](../build-package/README.md)がすでに構築済み)へZabbix Agent2を追加導入する手順を示します。

本パックは専用Ansible role(`ansible/roles/zabbix_agent`相当)を持たない「未実装」区分のため、0〜10節はすべて次のいずれかです。

| 節 | 区分 | 内容 |
| --- | --- | --- |
| 2節 | 済(自動) | `docker compose -f compose.zabbix.yaml up -d`による非対話コマンド一発の構築 |
| 1・2(前半)・3・4・5・7・8・9節 | 済(手動) | コマンド・UIクリック手順を1つずつ実行する作業 |

「済(自動)」を、既存の`site.yml`のような全自動構築(Ansible role)と混同しないでください。`docker compose up -d`より前のDocker導入・UFW設定・秘密値準備、より後のFrontend UI操作は、すべて本書のコマンド・クリック手順を人手で実行する「済(手動)」です。

## 0. 作業前確認

- 対象: `zbx-01`(Ubuntu Server 24.04 LTSの新規検証用VM1台)、および既存の`monitor-01`(変更範囲はZabbix Agent2の追加導入のみ)
- 管理端末から`zbx-01`・`monitor-01`の両方へ公開鍵SSHとsudoが利用可能
- 対象IP(`zbx-01`: `192.0.2.11/24`、`monitor-01`: `192.0.2.10/24`、管理端末: `192.0.2.20/24`)、例示FQDN(`zbx.example.test`、`monitor.example.test`)、作業時間帯、ロールバック条件を記録済み
- リポジトリの対象commit SHAを固定済み(`git rev-parse HEAD`)
- 実値の秘密情報(DBパスワード、Slack bot token、Zabbix Adminの新パスワード)をIssue、PR、端末ログへ貼らない
- [要件定義書](00-requirements.md)・[パラメータシート](03-parameter-sheet.md)・[ネットワーク設計・IPアドレス表](04-network-ip-plan.md)・[変更・ロールバック計画](08-change-rollback-plan.md)の対象環境、Go / No-Go条件を確認済み
- `monitor-01`は本パックのために作り直さない([Linux版パック](../build-package/README.md)の構築範囲のまま)ことを再確認済み。本書が触るのはZabbix Agent2の追加導入部分だけである

## 1. 管理端末の準備

対象commit SHAの固定と、構成コード(`compose.zabbix.yaml`、`deploy/zabbix/`、`deploy/secrets/*.example`)のレビューに使います。実際の配備は2節で`zbx-01`上に同じcommitを取得して行うため、秘密値を管理端末から`zbx-01`へ転送する必要はありません。

```bash
git clone https://github.com/ns7jp/server-monitor.git
cd server-monitor
git rev-parse HEAD
cat compose.zabbix.yaml
cat deploy/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf.example
```

上記の`git rev-parse HEAD`の出力(40桁commit SHA)を、2節で`zbx-01`上に`git checkout`する対象として記録します。

## 2. zbx-01でのDocker導入とcompose構築(NFR-01、NFR-02)

### 2.1 OSパッケージとUFW/DOCKER-USERの初期設定

```bash
ssh <ssh-user>@192.0.2.11
sudo apt-get update
sudo apt-get install -y ca-certificates curl git gnupg ufw iptables-persistent
```

`iptables-persistent`のインストール中に現在のルールセットを保存するか聞かれた場合は、この時点ではまだtrapper用ルールを追加していないため、そのまま保存して構いません(後述のルール追加後にあらためて保存します)。

UFWは、Docker導入より前に既定deny incomingとSSHのrate limitを設定しておきます([ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を正本とします)。

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 22/tcp
sudo ufw enable
sudo ufw status verbose
```

`${ZABBIX_WEB_PORT:-8081}/tcp`はcompose側で`127.0.0.1`にbindするため、UFWへ個別のallowルールは追加しません(bind address自体が唯一の防御線であるため)。5432/tcp(PostgreSQL)もDocker internal network限定のためUFWルールは不要です。

続けて、[パラメータシート](03-parameter-sheet.md)が宣言するSSHポリシー(root login禁止、password login禁止)を`sshd_config`へ実際に設定します。**先に現在のSSHセッションを切断せず、別ターミナルから鍵認証で新規接続できることを確認してから**次に進んでください(`PasswordAuthentication no`を反映した直後に鍵が使えないと締め出されます。10節のコンソールアクセスも参照)。

Ubuntu cloud imageは`/etc/ssh/sshd_config.d/50-cloud-init.conf`に`PasswordAuthentication yes`を含むfragmentをすでに持っていることがあります。OpenSSHは同じキーワードについて**最初に読んだ値を採用する**ため(`man sshd_config`)、`Include`はファイル名の辞書順に評価されるファイル名`99-...`のような番号では`50-cloud-init.conf`より後に読まれてしまい、こちらの設定が無視されます。`50-cloud-init.conf`より前に評価される番号を使います。

```bash
sudo install -d -m 0755 /etc/ssh/sshd_config.d
printf 'PermitRootLogin no\nPasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/00-zabbix-lab-hardening.conf
sudo sshd -t
sudo systemctl reload ssh
sudo sshd -T | grep -Eix 'permitrootlogin no' \
  || { echo 'PermitRootLogin no did not take effect (check for an earlier-sorting sshd_config.d fragment)' >&2; exit 1; }
sudo sshd -T | grep -Eix 'passwordauthentication no' \
  || { echo 'PasswordAuthentication no did not take effect (check for an earlier-sorting sshd_config.d fragment)' >&2; exit 1; }
```

`sudo sshd -t`は設定ファイルの構文だけを検証し、意味的な誤り(存在しないユーザーの`Match`ブロック等)までは検出しません。上記の`sshd -T`確認は、値を表示するだけでなく**実際に期待値と一致しなければ失敗して知らせる**ようにしています(表示するだけでは、他のfragmentに上書きされていても見落とします)。反映後は**新しい別セッション**で鍵認証接続を確認してから、元のセッションを閉じます。

trapper(10051/tcp)の送信元制限は`DOCKER-USER`chainで行いますが、このchainはDockerデーモンが起動して初めて作成されるため、**Docker Engine導入(2.2節)より後の2.3節で設定します**(ここではまだ設定しません)。

### 2.2 Docker Engine / Docker Composeの導入

`ansible/roles/docker`のDebian系タスクと同じ手順を手動で行います。

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker compose version

sudo usermod -aG docker "$(whoami)"
# 一度ログアウト・再ログインしてgroup変更を反映させる(以降はsudoなしのdocker composeで統一する)
```

### 2.3 DOCKER-USER chainでのtrapper送信元制限

**trapper(10051/tcp)の送信元制限はUFWでは設定しません。** DockerがPublishしたportはDockerが管理するiptablesの`DOCKER`/`FORWARD`chainを経由し、UFWが制御するhostの`INPUT`chainを経由しないため、`ufw allow`ルールは実際には効きません([`docs/security.md`](../security.md)、[ネットワーク設計・IPアドレス表](04-network-ip-plan.md#2-frontendとtrapperで設計思想が異なる理由本書の中心)参照)。代わりに、Docker自身が推奨する`DOCKER-USER`chainへ直接ルールを追加します。このchainはDockerデーモン起動時に自動作成されるため、**2.2節でDocker Engineを導入し、デーモンが起動した後に**この手順を実施します(`sudo docker compose version`が成功していれば、デーモンは起動済みです)。

```bash
sudo iptables -I DOCKER-USER -p tcp --dport 10051 -j DROP
sudo iptables -I DOCKER-USER -p tcp --dport 10051 -s 192.0.2.10 -j ACCEPT
sudo iptables -L DOCKER-USER -n --line-numbers
sudo netfilter-persistent save
```

`-I`はchainの先頭へ挿入するため、**DROPを先に、ACCEPTを後に**実行します(後から挿入した方が先頭に来るため、最終的に「`monitor-01`からのACCEPT」が「それ以外のDROP」より先に評価される順序になります)。`iptables -L DOCKER-USER -n --line-numbers`の出力で、`monitor-01`のIP(`192.0.2.10`)へのACCEPTがDROPより上の行になっていることを確認してください。`netfilter-persistent save`を忘れると、ホスト再起動後にルールが消え、trapperが無制限公開の状態に戻ります(10 立ち上げと受け入れ試験の再起動後確認で検出します)。

### 2.4 リポジトリの取得と秘密値の準備

```bash
sudo mkdir -p /opt/zabbix-lab
sudo chown "$(whoami)":"$(whoami)" /opt/zabbix-lab
git clone https://github.com/ns7jp/server-monitor.git /opt/zabbix-lab
cd /opt/zabbix-lab
git checkout <1節で確認したcommit SHA>
git rev-parse HEAD
```

```bash
chmod 700 deploy/secrets

cp deploy/secrets/zabbix_db_password.txt.example deploy/secrets/zabbix_db_password.txt
openssl rand -base64 24 > deploy/secrets/zabbix_db_password.txt
chmod 644 deploy/secrets/zabbix_db_password.txt

cp deploy/secrets/zabbix_slack_bot_token.txt.example deploy/secrets/zabbix_slack_bot_token.txt
# bot tokenと受信先channelを用意した場合のみ、実際のSlack Bot User OAuth Token(xoxb-...)へ書き換える(5.5節で使用)
# 用意しない場合はプレースホルダ("xoxb-REPLACE-WITH-REAL-BOT-USER-OAUTH-TOKEN")のまま残す
$EDITOR deploy/secrets/zabbix_slack_bot_token.txt
chmod 644 deploy/secrets/zabbix_slack_bot_token.txt

git status --short
git check-ignore deploy/secrets/zabbix_db_password.txt deploy/secrets/zabbix_slack_bot_token.txt
```

`zabbix_db_password.txt`はDocker Composeの`secrets:`でzabbix-server/postgresコンテナへbind mountされます。bind mountはホスト側ファイルの所有者・パーミッションをそのまま引き継ぐため、`chmod 600`(ログインユーザーのみ読み取り可)のままではコンテナ内の非rootユーザーがファイルを読めず、`docker compose up`が失敗します。既存パック(`compose.yaml`)の`ansible/roles/app`と同じ`0644`(secretファイルは世界読み取り可)・`0700`(格納ディレクトリで一般ユーザーからのアクセスを絞る)の組み合わせを踏襲します。`git check-ignore`で両ファイルが出力されること(=Git管理外であること)を確認します。これがZST-03(`git ls-files deploy/secrets`に実値ファイルが含まれない)の前提です。

```bash
cp .env.example .env
$EDITOR .env
```

`.env`の`ZABBIX_SERVER_BIND_ADDRESS`を、既定の`127.0.0.1`から`monitor-01`の着信を受けられる`zbx-01`のinterface addressへ上書きします。

```
ZABBIX_WEB_PORT=8081
ZABBIX_SERVER_BIND_ADDRESS=192.0.2.11
```

既定の`127.0.0.1`のままではtrapperが`monitor-01`から到達不能になります。bindを緩めた分の防御は、2.3節で設定済みの`DOCKER-USER` iptables chainの送信元制限(`monitor-01`のIPのみ許可。UFWではない)が担う設計です([ネットワーク設計・IPアドレス表](04-network-ip-plan.md)を参照)。

### 2.5 初回構築(NFR-01、ZIT-01)

```bash
docker compose -f compose.zabbix.yaml config --quiet
docker compose -f compose.zabbix.yaml up -d
docker compose -f compose.zabbix.yaml ps
```

`postgres`→`zabbix-server`→`zabbix-web`の順に`depends_on`と`healthcheck`で起動が待ち合わされます。全サービスが`running`かつ`healthy`(`zabbix-server`のみ`start_period`中は`starting`表示が残ることがあります)になるまで、次のコマンドで様子を見ます。

```bash
watch -n5 'docker compose -f compose.zabbix.yaml ps'
```

`Ctrl+C`で`watch`を終了し、全サービスの`STATUS`が`Up ... (healthy)`であることを確認したら次へ進みます。

### 2.6 冪等性確認(NFR-02、ZIT-02)

```bash
docker compose -f compose.zabbix.yaml up -d
docker compose -f compose.zabbix.yaml ps
```

出力に`Recreating`や`Recreated`が含まれず、既存コンテナがそのまま`Running`のままであることを確認します。意図しない再作成が発生した場合は、直前の`.env`・compose定義の変更を疑い、原因を修正してから再実行します。

## 3. 初期ログインとAdminパスワード変更(ZST-02、NFR-04必須)

Zabbix Frontendは`127.0.0.1`限定でbindしているため、管理端末からSSH tunnel経由でアクセスします。

```bash
ssh -N -L 8081:127.0.0.1:8081 <ssh-user>@192.0.2.11
```

上記コマンドは接続を保持したまま端末を専有するため、別ターミナルで以降の作業を続けます。

1. ブラウザで`http://127.0.0.1:8081/`を開きます。`zabbix-web`コンテナに`DB_SERVER_HOST`等の環境変数を設定済みのため、通常のインストールウィザードのDB接続入力ステップは値が自動入力された状態で表示されます。値を変更せずに「Next step」を進め、Pre-installation summary(設定概要)を確認して「Finish」まで進めます。
2. ログイン画面が表示されたら、`Username: Admin` / `Password: zabbix`(Zabbix既定値)でログインします。
3. 画面右上のユーザーアイコン(`Admin`)をクリックします。Zabbix 7.0ではこのアイコンから直接ログイン中ユーザー(`Admin`)自身のUser profileページへ遷移します(`Users`一覧を経由するメニューはありません)。
4. 「Change password」チェックボックスを有効化し、新しいパスワードを2回(Password / Password confirm)入力します。
5. 画面下部の「Update」をクリックして保存します。
6. 一度ログアウトし、新しいパスワードで再ログインできることを確認します。続けて、旧パスワード(`Admin` / `zabbix`)でのログインが失敗することも確認します(この失敗確認がZST-02の実施記録です)。
7. 新しいパスワードは、この案件パックのリポジトリでは管理しません。秘密値台帳など別の安全な手段で受け渡し、Issue・PR・端末ログへ平文で残しません。

これで既定管理者アカウントのパスワード変更(NFR-04)が完了します。これは「未実装」ではなく、初回ログイン直後に必ず踏む「済(手動)」の必須ステップです。

## 4. monitor-01へのZabbix Agent2導入とUserParameter配置(FR-02、FR-03)

```bash
ssh <ssh-user>@192.0.2.10
```

### 4.1 Zabbix公式リポジトリの登録とAgent2の導入

Zabbix Agent2のバージョン固定方針は現時点で`NOT SET`です([パラメータシート](03-parameter-sheet.md)の実機記入欄へ実測値を記録します)。以下は執筆時点のリポジトリパッケージ名の例で、実行前に[repo.zabbix.com](https://repo.zabbix.com/zabbix/7.0/release/ubuntu/pool/main/z/zabbix-release/)で現在のファイル名を確認してから読み替えます。

```bash
ZBX_RELEASE_DEB="zabbix-release_latest_7.0+ubuntu24.04_all.deb"
wget "https://repo.zabbix.com/zabbix/7.0/release/ubuntu/pool/main/z/zabbix-release/${ZBX_RELEASE_DEB}"
sudo dpkg -i "${ZBX_RELEASE_DEB}"
sudo apt-get update
sudo apt-get install -y zabbix-agent2
rm -f "${ZBX_RELEASE_DEB}"

zabbix_agent2 -V
```

### 4.2 zabbix_agent2.confの設定

```bash
sudo $EDITOR /etc/zabbix/zabbix_agent2.conf
```

次の2行を確認・設定します(既定はコメントアウトまたは別値のため、行頭の`#`を外し、値を書き換えます)。`Server`行は設定しません(コメントアウトのままにします)。

```
Hostname=monitor-01
ServerActive=192.0.2.11:10051
```

`ServerActive`が本パックの主方式であるactive checkのpush先です。**classic agent(Agent1)にあった`StartAgents=0`のようなpassive check無効化パラメータは、Agent2には存在しません**が、Agent2は`Server`が空(未設定)の場合、passive check自体を無効化し`10050/tcp`のlistenerを起動しません(`Server`を設定して初めてlistenerが起動する設計です)。`Server`行を設定しないことが、本パックでの唯一かつ十分な無効化手段です。念のため、`monitor-01`は素のaptパッケージ導入であり(zbx-01のようなDocker Publishではない)既存Linux版パックのUFW default deny incomingがそのまま適用されるため、`10050/tcp`を許可するUFWルールを追加しない限り、万一listenerが起動していてもネットワーク到達できません(zbx-01のtrapperと異なりUFWが有効な防御層になります)。

設定後、値を確認します。

```bash
grep -E '^(Hostname|ServerActive)=' /etc/zabbix/zabbix_agent2.conf
```

### 4.3 UserParameter(service_monitor.healthz)の配置

配備先の`deploy/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf.example`は`monitor-01`上には存在しないため、一時的にリポジトリを取得してコピーします。`--depth 1`はdefault branchの最新tipを取得してしまい、1節・2.4節で固定したcommit SHAとずれる可能性があるため使わず、同じSHAを明示的に`checkout`します。

配置先は`/etc/zabbix/zabbix_agent2.d/`直下ではなく`plugins.d`配下です。`zabbix_agent2.conf`の既定`Include`は`zabbix_agent2.d/plugins.d/*.conf`だけが有効で、`zabbix_agent2.d/*.conf`は既定で読み込まれないため、`plugins.d`以外へ置くとUserParameterが登録されません。

```bash
git clone https://github.com/ns7jp/server-monitor.git /tmp/server-monitor-zbx
git -C /tmp/server-monitor-zbx checkout <1節で確認したcommit SHA>
sudo install -d -m 0755 /etc/zabbix/zabbix_agent2.d/plugins.d
sudo install -m 0644 \
  /tmp/server-monitor-zbx/deploy/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf.example \
  /etc/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf
cat /etc/zabbix/zabbix_agent2.d/plugins.d/service_monitor_healthz.conf
rm -rf /tmp/server-monitor-zbx
```

ファイルの値は書き換えません(`curl --silent --fail --max-time 3 http://127.0.0.1:8080/healthz`をそのまま使い、200なら`1`、それ以外は`0`を返す設計です)。`curl`が未導入の場合のみ追加します。

```bash
command -v curl >/dev/null || sudo apt-get install -y curl
```

### 4.4 Agent2サービスの起動と単体確認

```bash
sudo systemctl enable --now zabbix-agent2
sudo systemctl restart zabbix-agent2
sudo systemctl status zabbix-agent2 --no-pager
sudo journalctl -u zabbix-agent2 --no-pager -n 30
```

ローカルでの単体テスト(ZUT相当。zbx-01側からの疎通確認は6節で行います)。

```bash
sudo zabbix_agent2 -t agent.ping
sudo zabbix_agent2 -t service_monitor.healthz
```

`service_monitor.healthz`が`1`(server-monitorアプリが`/healthz`で200を返している状態)を返すことを確認します。`monitor-01`側のUFWは、active checkが`monitor-01`から`zbx-01`への発信(egress)であるため、既存のdefault allow outgoingのまま変更は不要です。10050/tcp(passive listener)は既定未使用のため、Firewall側でも新規に開放しません。

## 5. Host / Template / Item / Trigger / Action の登録(Frontend UI手順、済・手動)

3節のSSH tunnel(`http://127.0.0.1:8081/`)を開いたまま、変更後のパスワードでログインした状態で進めます。

### 5.1 Host groupの作成

1. 左メニュー`Data collection` → `Host groups`を開きます。
2. 右上の「Create host group」をクリックします。
3. `Group name`に`SM-ZBX-001 Lab Hosts`と入力します。
4. 「Add」をクリックして保存します。

### 5.2 Hostの登録とTemplateのリンク

1. `Data collection` → `Hosts` → 右上の「Create host」をクリックします。
2. `Host name`に`monitor-01`と入力します(Zabbixの"Host"オブジェクト名も同じ値にします)。
3. `Host groups`に`SM-ZBX-001 Lab Hosts`を選択します。
4. `Description`に「案件ID SM-ZBX-001の監視対象。Linux版パック(SM-LAB-001)のmonitor-01と同一ホスト」のように記録します。
5. `Interfaces`は必須ではありません。本パックのTemplate・カスタムItemはすべて`Zabbix agent (active)`型のため、Agent interfaceを追加しなくても収集できます。将来passive checkを使う場合に備えて追加する場合は、`Agent`インターフェースでIP `192.0.2.10`、Port `10050`を登録しますが、既定では未使用のままにします。
6. `Enabled`のチェックが入っていることを確認します。
7. `Templates`タブへ切り替え、「Link new templates」の検索欄に`Linux by Zabbix agent active`と入力して選択します。
8. 画面下部の「Add」をクリックして保存します。

保存後、`Data collection` → `Hosts`の一覧で`monitor-01`の`Availability`列がしばらくして緑(Zabbix agent (active)が有効)になることを確認します。反映には最初のactive checkのcheck-in(既定`ServerActive`のチェック間隔)を待つ必要があります。

### 5.3 カスタムItemの登録(service_monitor.healthz)

1. `Data collection` → `Hosts` → `monitor-01`の行の「Items」リンクをクリックします。
2. 右上の「Create item」をクリックします。
3. `Name`に`server-monitor healthz status`と入力します。
4. `Type`は`Zabbix agent (active)`を選択します。
5. `Key`に`service_monitor.healthz`と入力します(4.3節で配置したUserParameterのkeyと完全に一致させます)。
6. `Type of information`は`Numeric (unsigned)`を選択します(返り値が`0`/`1`のため)。
7. `Update interval`は`1m`のままにします。
8. 「Add」をクリックして保存します。

### 5.4 Triggerの登録

組み込みTrigger「Zabbix agent is not available」相当(Templateのリンクにより自動追加されます。テンプレート名の都合で表示名の末尾に"(active checks)"等が付く場合がありますが、Severity `Disaster`・機能は同じです)は個別の登録は不要です。カスタムTriggerのみ追加します。

1. `monitor-01`の「Triggers」タブ → 右上の「Create trigger」をクリックします。
2. `Name`に`server-monitor /healthz is failing on {HOST.NAME}`と入力します。
3. `Severity`は`High`を選択します。
4. `Expression`に次の式を入力します。

   ```
   min(/monitor-01/service_monitor.healthz,3m)<>1
   ```

   直近3分間の`service_monitor.healthz`の最小値が`1`以外(=一度でも異常を観測)の場合にPROBLEMとする式です。
5. `OK event generation`は既定(`Expression`)のままにします。式が再び真でなくなった時点でOKに戻ります。
6. 「Add」をクリックして保存します。

### 5.5 Media typeの確認とbot tokenの設定(FR-04。bot tokenと受信先channelを用意した場合のみ)

Zabbix 7.0の組み込みSlack統合は、Incoming Webhook URLではなく**Slack Bot Token**でSlack Web APIを呼び出す方式です。事前にSlack側で`chat:write`スコープを持つAppを作成してBot User OAuth Token(`xoxb-`で始まる値)を発行し、通知先channelへそのbotを招待しておく必要があります(Slack側の作業のため本書の範囲外です)。

1. `Alerting` → `Media types`を開き、組み込みの`Slack`をクリックして開きます。
2. `Parameters`タブに表示される`bot_token`パラメータへ、2.4節で`deploy/secrets/zabbix_slack_bot_token.txt`に設定した値を貼り付けます。
3. 画面下部の「Update」をクリックして保存します。
4. `Users` → 通知を受け取るユーザー(検証では`Admin`でよい)を開き、「Media」タブ → 「Add」をクリックします。
5. `Type`に`Slack`、`Send to`にSlackのchannel名を入力します。`When active`は`1-7,00:00-24:00`のまま、`Use if severity`は`Warning`・`High`・`Disaster`をチェックします(`Warning`を外すと、組み込みTemplateのCPU等の閾値超過通知が[基本設計書](01-basic-design.md)の設計に反して届かなくなります)。
6. 「Add」→ ユーザー編集画面の「Update」をクリックして保存します。

bot tokenと受信先channelを用意していない環境では、5.5節の設定はプレースホルダのままで構いません。その場合、実配信の確認(ZIT-06のSlack到達部分)は`BLOCKED`として記録し、5.6節のTrigger発火確認までは必須のまま行います。

### 5.6 Trigger action(通知)の登録

1. `Alerting` → `Actions` → `Trigger actions` → 右上の「Create action」をクリックします。
2. `Name`に`SM-ZBX-001 monitor-01 notifications`と入力します。
3. `Conditions`タブで「Add」をクリックし、`Host group` `equals` `SM-ZBX-001 Lab Hosts`を追加します。案件専用グループにスコープを絞る意図を明確にするためです。
4. `Operations`タブへ切り替え、「Add」をクリックします。
5. `Send to users`に5.5節でMediaを設定したユーザーを追加し、`Send only to`で`Slack`を選択します。
6. 「Add」→ 画面下部の「Add」をクリックしてActionを保存します。

## 6. 構築後確認

`zbx-01`側:

```bash
docker compose -f compose.zabbix.yaml ps
ssh <ssh-user>@192.0.2.11 'ss -lntup'
ssh <ssh-user>@192.0.2.11 'sudo iptables -L DOCKER-USER -n --line-numbers'
```

`ss -lntup`でFrontendが`127.0.0.1:8081`のみ、trapperが`0.0.0.0:10051`(または設定したinterface address)でlistenしていることを確認します。`10051/tcp`の送信元制限は`ufw status verbose`では確認できません(UFWはDockerが公開したportを経由しません)。`iptables -L DOCKER-USER -n --line-numbers`で、`monitor-01`のIP(`192.0.2.10`)へのACCEPTがDROPより上の行にあることを確認します(ZST-01、ZST-04)。

`monitor-01`側:

```bash
ssh <ssh-user>@192.0.2.10 'systemctl status zabbix-agent2 --no-pager'
ssh <ssh-user>@192.0.2.10 'ss -lntup | grep -E "10050|8080"'
```

`zabbix-agent2`が`active`であることを確認します。`ss -lntup`の結果は、`8080/tcp`がserver-monitorアプリの既存設計どおり`127.0.0.1`限定で待受していること、`10050/tcp`は`grep`の結果に**一切表示されない**ことを確認します(ZIT-03、ZST-01)。`Server`行を設定していないAgent2はpassive check自体を無効化し、`10050/tcp`のlistenerを起動しないためです。`10050/tcp`が何らかの形で表示される場合は、`zabbix_agent2.conf`に`Server`行が誤って残っていないか確認してください。

Frontend側(ZIT-03、ZIT-05):

1. `Monitoring` → `Latest data`を開きます。
2. `Host groups`に`SM-ZBX-001 Lab Hosts`を指定してフィルタします。
3. `agent.ping`等のTemplate組み込みItemと、`service_monitor.healthz`の両方で`Last check`が直近のUpdate interval以内に更新されていることを確認します。

[試験仕様書・結果票](06-test-specification.md)の必須ID(`ZUT-01`〜`03`、`ZIT-01`〜`05`、`ZIT-07`〜`09`、`ZST-01`〜`04`)を実施し、スクリーンショットだけでなく再現コマンドと主要な実出力を保存します。実ホストのIP、route、DNS、待受、HTTP、UFWの確認は、本節の簡易確認とは別に[ネットワーク実機検証手順](09-network-validation-procedure.md)(`ZNW-01`〜`09`)に従って個別の結果票へ記録します。

## 7. バックアップ設定(NFR-05、ZIT-08)

`scripts/ops/zabbix-backup.sh`自体は作成済みですが、実行するにはsystemd timerとしての登録が別途必要です。`/opt/zabbix-lab`へclone済みのリポジトリからunit fileを配置します。

```bash
sudo install -m 0644 /opt/zabbix-lab/deploy/systemd/zabbix-backup.service /etc/systemd/system/zabbix-backup.service
sudo install -m 0644 /opt/zabbix-lab/deploy/systemd/zabbix-backup.timer /etc/systemd/system/zabbix-backup.timer
sudo install -d -m 0750 /var/backups/zabbix
sudo systemctl daemon-reload
sudo systemctl enable --now zabbix-backup.timer
systemctl list-timers zabbix-backup.timer
```

`zabbix-backup.timer`は毎日03:45 Asia/Tokyo(`OnCalendar`にタイムゾーンを明示しているため、zbx-01のhost timezoneがUTCのままでも03:45 JSTで実行されます)に`zabbix-backup.service`を起動し、`scripts/ops/zabbix-backup.sh --project-dir /opt/zabbix-lab`を実行します。動作確認は初回の定時実行を待たず、手動で1回実行して確認します。

```bash
sudo systemctl start zabbix-backup.service
sudo systemctl status zabbix-backup.service --no-pager
ls -la /var/backups/zabbix
```

`/var/backups/zabbix/zabbix-<timestamp>.dump`と対応する`.sha256`が生成されていることを確認します(ZIT-08)。

## 8. D-Z1障害演習(ZIT-07、NFR-08)

1. 事前状態を確認します。

   ```bash
   ssh <ssh-user>@192.0.2.10 'systemctl status zabbix-agent2 --no-pager'
   ```

   Frontendの`Monitoring` → `Problems`で、現在この演習に関係するPROBLEMが無いことを確認します。

2. `monitor-01`のZabbix Agent2を停止します(検知開始の基準時刻を記録)。

   ```bash
   ssh <ssh-user>@192.0.2.10 'sudo systemctl stop zabbix-agent2'
   date -u +%Y-%m-%dT%H:%M:%SZ
   ```

3. Frontendの`Monitoring` → `Problems`を数分おきに更新し、「Zabbix agent is not available」相当のTriggerがPROBLEMとして表示された時刻を検知時刻として記録します。

4. `monitor-01`のZabbix Agent2を復旧させます。

   ```bash
   ssh <ssh-user>@192.0.2.10 'sudo systemctl start zabbix-agent2'
   date -u +%Y-%m-%dT%H:%M:%SZ
   ssh <ssh-user>@192.0.2.10 'systemctl status zabbix-agent2 --no-pager'
   ```

5. Frontendの`Monitoring` → `Problems`で、該当ProblemがRESOLVED(OK)に変わった時刻を復旧時刻として記録します。

6. RTO(検知時刻から復旧時刻までの所要時間)を算出し、検知時刻・復旧時刻・実行したコマンドと実出力を[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)の様式で日付付きevidenceへ保存します。bot tokenと受信先channelを用意している場合は、Slackへの通知到達もあわせて記録します。

## 9. ロールバック

構成コード(compose定義・秘密値ファイルの参照先・UserParameter配置)が原因の場合と、Frontend上の設定変更が原因の場合、データ破損の場合とで手順が異なります。優先順位と記録様式は[変更・ロールバック計画](08-change-rollback-plan.md)を正本とします。

1. **compose定義・配備ファイルのロールバック**: 専用Ansible roleが無いため、Gitの直前commitへ戻したうえで再適用します。

   ```bash
   cd /opt/zabbix-lab
   git log --oneline -5
   git checkout <ロールバック先のcommit SHA> -- compose.zabbix.yaml deploy/zabbix deploy/secrets/*.example .env.example
   docker compose -f compose.zabbix.yaml up -d
   docker compose -f compose.zabbix.yaml ps
   ```

   `deploy/secrets/*.txt`と`.env`はGit管理外の実値ファイルのため、`git checkout`の対象に含めません。

2. **Frontend上の設定(Host / Template / Item / Trigger / Action)のロールバック**: UI操作の結果はGit管理外です。5節の作業直前に、`Data collection` → `Hosts` → 対象Hostを選択 → 「Export」でHost/Item/Trigger構成をエクスポートしておくと、そのXMLを`Import`から読み込むことで変更前の状態へ戻せます。エクスポートを取得していない場合は、5節の手順を逆順にたどって手動で戻します。

3. **データ破損時**: `scripts/ops/zabbix-backup.sh`が採取した直近の正常なdumpから復元します。

   ```bash
   docker compose -f compose.zabbix.yaml stop zabbix-server zabbix-web
   LATEST_DUMP=$(ls -t /var/backups/zabbix/zabbix-*.dump | head -n1)
   # .sha256ファイルはbasenameだけを記録しているため、そのディレクトリで検証する
   ( cd -- "$(dirname -- "${LATEST_DUMP}")" && sha256sum -c "$(basename -- "${LATEST_DUMP}").sha256" )
   docker compose -f compose.zabbix.yaml exec -T postgres \
     pg_restore -U zabbix -d zabbix --clean --if-exists < "${LATEST_DUMP}"
   docker compose -f compose.zabbix.yaml up -d
   ```

いずれの手段を使った場合も、ロールバック後は6節の構築後確認と、影響範囲に応じた試験(該当する`ZIT`/`ZST`)を再実行します。

## 10. 作業終了

- 結果票、実行ログ、Frontendの画面キャプチャを保存します
- 一時ファイルを削除します

  ```bash
  ssh <ssh-user>@192.0.2.10 'rm -rf /tmp/server-monitor-zbx'
  ssh <ssh-user>@192.0.2.10 'rm -f ~/zabbix-release_latest_7.0+ubuntu24.04_all.deb'
  ```

- D-Z1演習は`systemctl stop`/`start`のみで一時的なfirewall許可を追加しないため、演習用の追加ルールの削除は不要です。演習以外で一時的にUFW許可・`DOCKER-USER` chainのルールやテストデータを追加した場合は削除します
- 未解決事項をIssue化します
- [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、計画対実績、実行時間、対象commit SHA、設計差異、障害、残存リスクを記入します
- 報告書の試験集計と個別結果票の件数が一致することを確認します
- [引き渡しチェックリスト](07-handover-checklist.md)を確認し、`NOT RUN` / `BLOCKED`が残る場合は受領可にしません。特にZST-02(Admin初期パスワード変更の実施記録)と、ZIT-06(Slack実配信。bot tokenと受信先channelを用意した場合のみ必須)の扱いを区別して記録します
