# 初心者向け学習ガイド

[入口へ戻る](../README.md) / [全体の学習計画](learning-path.md) / [用語を調べる](server-building-keywords.md)

**最初のゴールは、2 つのサービスを起動し、「応答できる」「認証で守られている」「停止して戻せる」を自分の記録で説明することです。**
教材のリポジトリ名は `server` です。設定内の `server-monitor` はアプリ・監視ジョブの名称、`server-monitor-lab` は Compose のプロジェクト名として使っています。

環境が準備済みなら、Step 1〜5 の初回実習は 90〜120 分を目安に分割できます。準備やエラー調査の時間は別です。最後まで読むことと、自分で実行・説明できることは別々に確認します。

## 今日はここまでできればよい

| 段階 | 学ぶこと | 自分で示すもの |
| --- | --- | --- |
| 最初の実習（Step 1〜5） | アプリと入口、応答、認証、計画停止と再開 | 2 サービスの状態、HTTP 結果、復旧後の結果、30 秒説明 |
| 次の実習（Step 6） | 数値を集める・表示する、ログを調べる | Prometheus の `up=1`、Grafana の数値とログ |
| その後（Level 4〜5） | Linux の自動構築と障害からの復旧 | Ansible の 2 回適用、D-1 の観測と記録 |

最初の実習では Ansible を読みますが、実行しません。計画停止を自動復旧試験として扱わず、AWS の `terraform apply`、D-2 のホスト復元も未実施 `NOT RUN` のまま残します。

## 実行場所と準備

**基本コースのコマンドは、破棄できる専用 Ubuntu 24.04 検証環境の Bash で実行します。**
仕事用・共有・既存ラボと同じホストでは、同名の Compose プロジェクトを操作してしまうため実行しません。Windows PowerShell に Bash のコマンドをそのまま貼り付けないでください。

| 場所 | ここで行うこと |
| --- | --- |
| Windows PC | VM の準備、ブラウザ閲覧。Step 2 のテストだけなら Windows でも可能 |
| Ubuntu のターミナル（Bash） | Git 取得、ファイル準備、Docker の起動・確認・停止 |
| `server` ディレクトリ直下 | このページの Bash コマンドの実行場所。`compose.yaml` がある場所 |
| コンテナ内 | 最初の実習では直接操作しない。アプリが内部で動作する場所 |

Ubuntu VM がまだなければ、[学習計画の準備](learning-path.md#level-0-の前に--検証環境と本体コードを用意する)へ進みます。VM は再作成方法を用意します。WSL2 の場合、Linux の観測対象は WSL2 側であり、Windows ホスト全体の監視実績にはなりません。

Ubuntu で不足する基本ツールを導入する場合は次を実行します。`sudo` は管理者権限で OS のパッケージを変更するため、この検証環境であることを確認してから使います。

```bash
sudo apt-get update
sudo apt-get install -y git python3 python3-venv curl openssl iproute2
```

Docker Engine と Compose plugin は [Docker 公式 Ubuntu 手順](https://docs.docker.com/engine/install/ubuntu/)で導入します。Docker の操作権限は [公式の導入後設定](https://docs.docker.com/engine/install/linux-postinstall/)を確認します。`docker` グループは強い権限を持つため、共有ユーザーへ無条件に追加しません。この実習の前提は `docker info` が自分のユーザーで成功することです。

Python は Ubuntu 24.04 標準の 3.12 または CI で使う 3.11 を使います。古い Python では `requirements-dev.txt` の依存関係を導入できない場合があります。監視全体へ進む場合、前提診断はメモリ 6 GiB・空き容量 10 GiB 未満で警告します。これは診断の目安で、性能保証値ではありません。

初回だけ取得します。すでに取得済みなら、既存の `server` へ `cd` し、再 clone しません。

```bash
git clone https://github.com/ns7jp/server.git
cd server
pwd
git status --short --branch
git rev-parse HEAD
python3 --version
bash scripts/learning/check-prerequisites.sh
echo "$?"
```

`echo "$?"` は **直前のコマンド**の終了コードを表示します。`0` は正常終了、その他はエラーです。途中で別のコマンドを打つと、そのコマンドの結果に変わります。

診断が `FAIL` なら `NEXT` を確認し、解消するまでは Docker 実習を `BLOCKED` と記録します。`WARN` は内容を読みます。Ansible 未導入の警告は Step 1〜6 の実行には影響しません。ポートが使用中なら、既存の用途を調べてから進みます。

これ以降は **コマンドの結果を確認してから次の行へ**進みます。エラーが出たら続きのブロックを貼り付けず、「よくあるつまずき」へ進んでください。

## 1. 見る

まずは 5 語を、身近な役割と結び付けます。

| 用語 | 役割と覚え方 | この実習では |
| --- | --- | --- |
| Linux / OS | 道具を動かす土台 | Ubuntu の検証環境 |
| サービス | 決まった仕事を続けるプログラム | `app` は応答、`nginx` は入口 |
| コンテナ | アプリと実行環境をまとめて動かす単位 | 上の 2 サービスを別々に動かす |
| Docker Compose | 定義を読み、部品を起動する係 | `compose.yaml` を読む |
| ポート | 同じ宛先のサービスを区別する番号 | 利用者は `8080`、内部のアプリは `5000` |

```mermaid
flowchart LR
    User["curl / ブラウザ"] -->|"127.0.0.1:8080"| Nginx["nginx：受付"]
    Nginx -->|"app:5000"| App["app：返答を作る"]
```

リクエストが受付を経由してアプリへ届き、応答は逆向きに戻ります。`127.0.0.1`（ループバック）は **今操作しているコンピューター自身**です。Windows と別の Linux VM では同じ相手を指しません。

最初に読むファイルは [`compose.yaml`](../compose.yaml) の `app`、`nginx`、`ports`、[`app.py`](../app.py) の `/healthz` と認証処理だけです。Ansible の [`site.yml`](../ansible/playbooks/site.yml) は OS 構築全体の入口だと分かれば十分です。

**確認問題**: ブラウザから `5000` へ直接アクセスする構成ですか。

<details>
<summary>解答例</summary>

いいえ。この Compose ではホストの `8080` を nginx に公開し、nginx が内部の `app:5000` に転送します。`expose: 5000` はホストへのポート公開ではありません。

</details>

## 2. 小さく確認する

**目的**: 全体を動かす前に、アプリの認証・応答や、設定・文書の整合を自動テストします。

Ubuntu の Bash、リポジトリ直下で実行します。

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m compileall -q app.py tests
echo "$?"
python -m pytest -q
echo "$?"
```

`venv` はこの教材用の Python 環境、`pip` は必要なライブラリを入れる道具、`pytest` は期待どおりかを検査する道具です。コンパイルと pytest の直後の終了コードがどちらも `0` で、pytest の `passed` 件数を記録できたら、この段階は完了です。件数はコードの更新により変わるため固定値を暗記しません。

テストには文書・構成の整合検査もあります。成功しても、Linux ホストへ Ansible を適用したり、Docker や AWS を動かしたりした証拠にはなりません。

<details>
<summary>Linux の準備前に、Windows PowerShell で Python 部分を確かめる場合</summary>

Python 3.11 または 3.12 と Git が使え、リポジトリ取得済みであることが前提です。PowerShell で `server` ディレクトリへ移動し、次を実行します。仮想環境の有効化は使わず、実行ファイルを直接指定します。

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m compileall -q app.py tests
$LASTEXITCODE
.\.venv\Scripts\python.exe -m pytest -q tests/test_app.py
$LASTEXITCODE
```

この分岐は `test_app.py` に範囲を限定しています。全テストには Bash・Linux 権限などの前提があるため、Windows で一部を実行した結果を全テスト成功とは書きません。以後の Bash 手順は Ubuntu 側の clone で行い、Windows の `.venv` を Linux で再利用しません。

</details>

## 3. 検証環境で起動する

### 3-1. 初回の設定と秘密値を用意する

**実行場所**: 専用 Ubuntu の Bash、`server` 直下。`.env` はポート番号などの設定、`deploy/secrets/` はパスワード・トークンを置く場所です。

まず既存の設定があるか確認します。**`.env` または下の 3 ファイルのどれかが既にある場合、生成ブロックを繰り返さず、内容と用途を確認します。** この実習を再開するときは、以前の値を使って 3-2 へ進みます。別用途の設定がある場合は専用環境を用意してください。

```bash
ls -la .env deploy/secrets/dashboard_password.txt deploy/secrets/metrics_token.txt deploy/secrets/grafana_admin_password.txt
```

初回は `No such file or directory` が出ます。ここだけは「まだ作っていない」という想定どおりの結果です。以下の括弧付きブロックはまとめて実行します。既存ファイルへの上書きや途中の生成失敗があれば、そのブロック内で停止します。

```bash
(
  set -eC
  umask 077
  cat .env.example > .env
  mkdir -p deploy/secrets
  chmod 700 deploy/secrets
  openssl rand -base64 32 > deploy/secrets/dashboard_password.txt
  openssl rand -base64 32 > deploy/secrets/metrics_token.txt
  openssl rand -base64 32 > deploy/secrets/grafana_admin_password.txt
  chmod 644 deploy/secrets/dashboard_password.txt deploy/secrets/metrics_token.txt deploy/secrets/grafana_admin_password.txt
)
echo "$?"
```

`openssl rand` で用途別に異なるランダム値を作ります。親ディレクトリは所有者だけが入れる `700`、ファイルはコンテナ内の別 UID が読むため `644` にします。既存の Grafana データがある状態でパスワードだけ作り直すと、ログイン設定と食い違う場合があるため、再生成をトラブル対処として使いません。

Git に入らないことを、値を表示せず確認します。

```bash
git check-ignore .env deploy/secrets/dashboard_password.txt deploy/secrets/metrics_token.txt deploy/secrets/grafana_admin_password.txt
git ls-files .env 'deploy/secrets/*.txt'
git status --short
```

成功条件は `check-ignore` が 4 パスを表示し、`git ls-files` に何も表示されないことです。秘密値が追跡されていたら公開操作を止め、[セキュリティ設計](security.md)を確認します。`git add -f` で除外を回避しません。

### 3-2. app と nginx だけを起動する

```bash
docker compose config --quiet
echo "$?"
docker compose up -d --build app nginx
echo "$?"
docker compose ps --all app nginx
```

`--build` はアプリのイメージを作り、`-d` はバックグラウンドで動かす指定です。サービス名を指定するので最初は 2 サービスを対象にします。nginx は `depends_on` により app の healthcheck 成功を待って起動します。監視サービスの学習は Step 6 へ分けています。[Compose up の公式仕様](https://docs.docker.com/reference/cli/docker/compose/up/)

`app` が `Up` かつ `healthy`、`nginx` が `Up` になれば次へ進みます。nginx 自体には healthcheck 定義がないため、`healthy` 表示は不要です。初回のビルドや healthcheck には時間がかかります。`Exited`、`Restarting`、`unhealthy` なら Step 4 の調査コマンドを使います。

### 3-3. 応答と認証を分けて確認する

同じ Ubuntu のターミナルで 1 行ずつ実行します。

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/metrics
curl -sS --user monitor -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/stats
```

最後だけパスワードを尋ねられます。`deploy/secrets/dashboard_password.txt` を **ローカルのエディター**で確認して入力します。入力文字は画面に出ません。録画・共有画面・学習記録へ秘密値を写さず、コマンドへ直接書き込みません。初回 `.env.example` のユーザー名は `monitor` です。

| 確認 | 期待する HTTP コード | 何が分かるか |
| --- | --- | --- |
| `/healthz` | `200` | 入口経由で app が応答できる |
| 認証なしの `/` | `401` | 画面を認証で守っている |
| token なしの `/metrics` | `401` | 数値取得にも別の認証が必要 |
| 正しい Basic 認証付き `/api/stats` | `200` | 正しい資格情報で取得できる |

`200` は要求成功、`401` は認証が必要、`503` は設定不足等で処理できない状態です。**この curl は HTTP コードを観測するため `-f` を付けていません。終了コード `0` でも HTTP `401` や `503` の場合があります。** 表の期待値と比較して判定してください。

`healthz` の `200` だけで、ログイン、監視、バックアップまで正常とは言えません。4 件とも期待値どおりか、[記録テンプレート](evidence/templates/beginner-practice-record.md)へ記入します。本文中の期待値は実測結果ではありません。

### 3-4. ブラウザで画面を見る

同じ Linux 上のブラウザなら `http://127.0.0.1:8080/` を開き、`monitor` と上のパスワードでログインします。数字が表示されれば画面を確認できています。

Windows から **別の Linux VM** を見る場合、Linux VM の `127.0.0.1` へは直接届きません。SSH 接続を設定済みなら、Windows PowerShell の別ウィンドウで次の `【記入待ち】` を実値に置き換えて実行します。

```powershell
$LabUser = '【記入待ち: Linux の SSH ユーザー】'
$LabHost = '【記入待ち: Linux VM の IP またはホスト名】'
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 -L 127.0.0.1:3000:127.0.0.1:3000 -L 127.0.0.1:9090:127.0.0.1:9090 "${LabUser}@${LabHost}"
```

SSH が接続したまま待機するのは正常です。Windows のブラウザで `http://127.0.0.1:8080/` を開きます。終了時はこの SSH ウィンドウで `Ctrl+C` を押します。ホスト鍵は管理している VM のものか確認します。SSH が未設定なら、ここは `BLOCKED` として CLI の確認まで記録できます。画面を見るために `.env` の公開先を `0.0.0.0` へ変更しません。

## 4. 一次切り分けを覚える

### 4-1. 調査の順番

覚え方は **状態 → ログ → 通信 → 設定** です。「何が止まったか」「何が起きたか」「どこまで届くか」「設定を読めるか」を順に調べます。

```bash
docker compose ps --all app nginx
docker compose logs --tail=50 app nginx
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
docker compose config --quiet
```

設定全体の表示や `curl -v` は秘密の認証ヘッダー等を記録へ混ぜるおそれがあるため、最初の確認では使いません。分からなければ、出力から確認できた事実と、自分の仮説を分けて [一次記録](evidence/templates/troubleshooting-worklog.md)へ残します。

### 4-2. 計画停止と再開を 1 回練習する

**前提**: Step 3 の正常結果を保存済み、専用検証環境であること。ここでは入口の nginx を自分で停止・再開します。アプリ障害を自動復旧させる D-1 とは別の練習です。

```bash
docker compose stop nginx
docker compose ps --all app nginx
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
```

nginx が停止し、curl は接続エラーになります。`000` は HTTP 応答が取れなかった表示で、サーバーが返した HTTP コードではありません。ここは停止確認が目的なので、この失敗を観測したら再開します。app は引き続き動いているかも状態で確認します。

```bash
docker compose start nginx
docker compose ps --all app nginx
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
```

`200` に戻れば復旧確認です。戻らなければ 4-1 の順で調べます。「なぜ失敗するはずだと思ったか」「app が動いていても利用者が使えない理由」を 1 文ずつ書きます。これは手動再開の記録で、自動復旧時間の実績には使いません。

### 4-3. 終了・次回の再開

Ubuntu の同じディレクトリで、必要な結果を記録してから実行します。

```bash
docker compose down
docker compose ps --all
```

コンテナとネットワークを片付け、サービス行がなくなれば終了です。名前付き volume のデータは保持します。**`docker compose down -v` は永続データを削除するので、この実習では使いません。** [Compose down の公式仕様](https://docs.docker.com/reference/cli/docker/compose/down/)

Python 仮想環境を有効化していたターミナルでは `deactivate` で抜けます。SSH トンネルも `Ctrl+C` で閉じます。VM を止める前にここまで行います。

次回は同じディレクトリ・同じ `.env`・同じ秘密値を使い、`docker compose up -d --build app nginx` で再開します。Step 3-1 の秘密値を作り直しません。監視全体まで起動していた場合は Step 6 の全体起動を使います。

## 5. 説明して定着させる

まず [初心者実習記録](evidence/templates/beginner-practice-record.md)を自分用にコピーします。保存例は Git 対象外の `.artifacts/learning/` です。

```bash
mkdir -p .artifacts/learning
cp -n docs/evidence/templates/beginner-practice-record.md .artifacts/learning/first-practice.md
```

同じファイルがあれば上書きせず続きへ記録するか別名にします。テンプレートの初期値はすべて `NOT RUN` です。公開する場合は、コマンド出力内の秘密値・個人情報・実 IP を確認して必要なマスクを行います。

**30 秒説明の型**:

> この教材は、サーバー構築と動作確認を学ぶ個人ラボです。私は【環境】で【自分が実行した範囲】を行い、【期待値と実結果】を確認しました。【分かった理由を 1 つ】を説明できます。【まだ実行していない範囲】は未実施です。

**3 分説明の配分**:

| 時間 | 話す内容 | 記録から取り出すもの |
| --- | --- | --- |
| 0:00〜0:30 | 目的と自分の実施範囲 | 個人学習の目的、OS、使った構成 |
| 0:30〜1:10 | 構成と工夫 | 利用者 → nginx → app、loopback、認証 |
| 1:10〜2:00 | 確認と停止・再開 | コマンド、期待値、実結果、戻し方 |
| 2:00〜2:30 | 理由・学び | 予想と違った点、状態とログから分かったこと |
| 2:30〜3:00 | 未実施と次の一歩 | まだ説明・実行できないこと、次の小さな課題 |

**想定質問と答える観点**:

| 質問 | 自分の言葉で答える観点 |
| --- | --- |
| なぜ `/healthz` と画面を別々に確認するのですか | 応答できることと、認証・機能が正しいことを分けるため |
| なぜ nginx を止めると使えなくなるのですか | 利用者から app へ届く入口が止まるため |
| なぜポートを loopback に限定したのですか | この学習では自分または SSH 経由のアクセスに限定するため |
| これは実務経験ですか | 個人学習であること、実行環境と自分の担当範囲を伝える |
| AI が書いた部分は理解していますか | 説明できるファイル・確認した結果・まだ説明できない箇所を具体的に分ける |

直後に図を見ずに説明し、翌日は「確認コマンドと期待値」を思い出します。数日後、手順を見直しながら起動・確認・終了をもう一巡します。暗記だけでなく、分からないときに文書へ戻って修正できることも習得の一部です。

## 6. 次の実習：監視を追加する

最初の実習が完了したら、同じ Linux、同じ clone、同じ秘密値で進みます。監視全体の前提診断の警告を再確認します。

```bash
bash scripts/learning/check-prerequisites.sh
docker compose up -d --build
docker compose ps --all
```

サービス名を指定しないので `compose.yaml` の全 10 サービスが対象です。Python テスト成功や最小 2 サービスの起動だけでは、ここはまだ `NOT RUN` です。`running` 表示だけで監視が取れているとは判定せず、以下を順に確認します。

| 部品 | 覚え方 | 確認する内容 |
| --- | --- | --- |
| node-exporter | Linux の計器 | ホスト側の数値を公開する |
| Prometheus | 数値の収集・保存係 | `up` が `1` なら収集先の取得に成功 |
| Grafana | グラフを見せる係 | Prometheus や Loki に問い合わせて表示する |
| Alloy / Loki | ログの収集係 / 保存係 | ログ行を検索できる |
| Alertmanager | 通知を振り分ける係 | 標準設定は外部 Slack に配信しない |

**数値の確認**: `http://127.0.0.1:9090/` の Prometheus で `up{job="server-monitor"}` と `up{job="linux-node"}` を 1 つずつ評価し、各値が `1` か確認します。初回は収集間隔 15 秒を数回待って再確認します。値が `0` なら取得失敗、結果なしなら未収集や問い合わせ条件を調べます。Targets 画面のエラーと `docker compose logs --tail=50 prometheus app node-exporter` を確認します。

**表示の確認**: `http://127.0.0.1:3000/` に `admin` と `grafana_admin_password.txt` の値でログインし、`Infrastructure Lab / Server Monitor Infrastructure Lab` ダッシュボードを開きます。時間範囲を最近 15 分にして数値が出るか確認します。app の `psutil` はコンテナから見える値であり、CPU・メモリ等がすべてコンテナに限定された値とは限りません。Linux 全体は node-exporter 側で見ます。

**ログの確認**: Ubuntu のターミナルで次を実行して nginx にアクセス記録を作ります。401 はここでも想定どおりです。`/healthz` は nginx 側でアクセスログを抑止しているため、ログ生成には `/` を使います。

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
```

Grafana の Explore で Loki を選び、`{compose_project="server-monitor-lab", service="nginx"}` を検索します。最近のログ行が出れば、Alloy → Loki → Grafana の経路を確認できます。出ない場合は数十秒待って再検索し、改善しなければ `docker compose logs --tail=50 alloy loki docker-socket-proxy` と [LogQL ガイド](loki-queries.md)を確認します。

Windows から別 VM の画面を見る場合は Step 3-4 のトンネルを使います。終了は Step 4-3 と同じ `docker compose down` です。

この後の [Level 4](learning-path.md#level-4--ansibleで同じ状態を再現する)で Ansible を 2 回適用し、不要な変更が出ない冪等性を確かめます。[Level 5](learning-path.md#level-5--壊して直して説明する)で D-1 を実施します。初回実習の計画停止とは別に記録してください。

## よくあるつまずき

| 症状 | 最初に確認すること | 次の行動 |
| --- | --- | --- |
| `No such file` / `no configuration file provided` | `pwd`、`ls compose.yaml` | リポジトリ直下へ戻る |
| Python の依存関係を導入できない | `python --version` と pip の最後のエラー | 3.11 / 3.12、通信、venv を確認。依存バージョンを勝手に緩めない |
| `docker: command not found` | `docker --version` | Engine / Compose の導入を確認 |
| Docker socket の `permission denied` | `docker info`、`id` | 公式の権限設定を確認。ソケットを `chmod 777` にしない |
| `port is already allocated` | `ss -lntp` | 使用者と用途を確認。別のサービスを無断で止めない |
| app が `unhealthy` | `docker compose logs --tail=50 app` | 最初のエラーを確認して記録 |
| 認証なしの画面が `401` | Step 3-3 の期待値 | 認証が機能している正常な結果 |
| 正しいはずの認証が `401` | `.env` のユーザーと該当秘密値 | ダッシュボード用と Grafana 用を混同していないか確認 |
| `/healthz` は `200`、画面は `503` | 秘密値ファイルと app のログ | health は認証設定まで保証しない。空・未読の原因を調べる |
| nginx 経由で `502` | app の状態とログ | 入口から app へ届いていない原因を調べる |
| ブラウザだけ接続できない | その `127.0.0.1` がどの PC を指すか | VM と手元の違い、SSH トンネルを確認 |
| Grafana の数値やログが空 | 時間範囲、収集先の状態、各ログ | 空欄を正常と判定せず経路ごとに確認 |

## 理解の確認

1. `docker compose ps` と `docker compose logs` は何が違いますか。
2. 認証なしの `401` はこの実習では失敗ですか。
3. `/healthz` が `200` なら監視や復元も検証済みと言えますか。
4. `docker compose down` と `docker compose down -v` の違いは何ですか。
5. Prometheus と Grafana の役割は何ですか。
6. 自分が実行していない試験は、どの判定にしますか。

<details>
<summary>解答例</summary>

1. `ps` は現在の状態、`logs` は起きた出来事です。
2. 画面と metrics を認証なしで取得できないことを確かめるため、期待どおりです。
3. 言えません。app の応答以外はそれぞれ別に確認します。
4. `down` はコンテナ等を片付け、`-v` を付けると名前付き volume のデータまで消します。
5. Prometheus は数値を集めて保存し、Grafana は問い合わせて表示します。
6. `NOT RUN`。環境の不足で実行できないときは理由を付けて `BLOCKED`、実行結果が期待と違ったときは `FAIL` です。

</details>

分からなかった問いは、該当手順をもう一度確認して記録に残します。全体の道順は [一本道ラーニングパス](learning-path.md)、実務形式の文書の読み方は [案件パック初心者ガイド](build-package/beginner-guide.md)、実測の根拠は [証跡台帳](evidence/README.md)へ進みます。
