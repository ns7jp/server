# 小さな構成を再起動・運用・復元・引き渡しまでつなぐ

[入口](../README.md) / [最初の実習](beginner-learning-guide.md) / [記入用の結果票](evidence/templates/partial-lab-continuation-record.md)

**目的は、既存の app/nginx 2 サービスを自分で再開し、OS 再起動後と 24 時間後にも確認して説明することです。**
その後、保管済み Loki バックアップを新しい VM で読み、別の人が手順を追えるか確認します。
この文書は実行手順です。新しい実行結果、独力での説明、第三者による確認はすべて **NOT RUN** です。
既存の [数値監視](evidence/2026-09-08-lab-base01-monitoring-practice.md)・[ログ復元](evidence/2026-09-08-lab-base01-restore-practice.md)の実績と合算しません。

| 段階 | 実行場所 | 次へ進む条件 |
| --- | --- | --- |
| 1. 環境と資源 | Windows 管理端末と既存の Ubuntu VM | 対象、接続、空き容量、復旧用コンソールを確認 |
| 2. 起動・OS 再起動 | 既存 VM の Bash | 手動 start を挟まず app/nginx と HTTP 本文が復帰 |
| 3. 24 時間をまたぐ点検 | 同じ VM | +0 / +1 / +6 / +24 時間の実測を保存 |
| 4. 別 VM で復元 | 管理端末、新規 Ubuntu VM | 元 VM のデータを参照せず、コピーした archive からログを読める |
| 5. 説明・引き渡し | 本人と実際の確認者 | 本人の説明と、確認者が実行した操作を別々に記録 |

2 GiB は過去の部分演習で使った VM メモリです。長期安定性を保証する値ではありません。
AD・WSUS 等の別用途 VM を停止したり、全10サービスを起動したりすることを前提にしません。
段階4で同時起動が難しければ、元 VM から管理端末へコピーを終え、段階3を終了してから、元 VM を停止して新 VM を起動します。

## 1. 実行前に現在地を確認する

Windows で Hyper-V マネージャーから対象 VM と接続先を確認します。過去の IP を現在の値と決めつけません。
VM コンソールに入れ、SSH が切れた場合も戻せる状態にします。既存の [初期構築記録](evidence/2026-09-08-lab-base01-initial-build.md)は参考資料です。
VM が停止中、接続先不明、操作権限不足なら、その段階を `BLOCKED` と記録して接続確認から再開します。

Ubuntu の Bash、既存 clone の `~/server` で実行します。場所が違えば実際の clone に読み替えます。

```bash
cd ~/server
pwd
hostname
git status --short --branch
git rev-parse HEAD
date --iso-8601=seconds
free -h
df -h /
docker info >/dev/null
echo "$?"
docker compose ps --all
bash scripts/learning/check-prerequisites.sh
echo "$?"
```

コマンドごとの出力と終了コードを確認します。`FAIL` は解消してから先へ進みます。
Ansible 未導入とメモリ 6 GiB 未満の `WARN` は、そのまま結果票へ残します。
他用途のコンテナ、未把握の変更、空き容量不足があれば対象を調べ、勝手に削除しません。
この実習の目安として、起動後の空きディスク 2 GiB 未満、利用可能メモリ 256 MiB 未満、
増え続ける swap、OOM が見えたら中断して構成を見直します。これらは教材の中断目安です。

`.env`、`deploy/secrets/`、既存ボリュームを再生成せず、[初心者ガイドの設定確認](beginner-learning-guide.md)から引き継ぎます。
元データの削除、`down -v`、`volume prune` はこの続編の手順に含みません。
記録は Git 除外済みの `.artifacts/continuation/` に置き、公開する前に個人情報を確認します。

```bash
umask 077
mkdir -p .artifacts/continuation
git check-ignore .artifacts/continuation/probe.txt
git ls-files .artifacts
```

期待結果は前者がパスを表示し、後者が空です。[結果票](evidence/templates/partial-lab-continuation-record.md)をこのディレクトリへコピーします。
以後、秘密値ファイルの本文や認証ヘッダーをログへ出しません。

## 2. 起動後の状態を保存し、OS 再起動と比較する

`docker compose ps --all` で対象を確認し、既存の別サービスが動いていれば用途を調べます。
この段階の観測対象を app/nginx だけにそろえたうえで、次を実行します。

```bash
docker compose up -d app nginx
echo "$?"
docker compose ps --all app nginx
```

`app` が running/healthy、`nginx` が running になるまで確認します。
ビルドが必要な新しい clone なら、先に [初心者ガイド](beginner-learning-guide.md)の最小起動を完了します。
再起動試験の途中で `git pull` や依存更新を行わず、同じ設定・イメージで比較します。

次の確認ブロックを **再起動前、再接続直後、各時点の点検**で繰り返します。
ファイル名は実行時刻付きなので、再確認しても元の記録を残せます。

```bash
cd ~/server
lab_check_time=$(date -u +%Y%m%dT%H%M%SZ)
(
  set -e
  date --iso-8601=seconds
  date +%s
  cat /etc/machine-id
  cat /proc/sys/kernel/random/boot_id
  uptime -s
  git rev-parse HEAD
  git status --short
  sha256sum compose.yaml deploy/nginx/local.conf .env
  systemctl is-active docker
  systemctl is-enabled docker
  systemctl --failed --no-pager
  docker compose ps --all app nginx
  for lab_service in app nginx; do
    lab_container=$(docker compose ps -q "$lab_service")
    test -n "$lab_container"
    docker inspect --format '{{.Name}} {{.Image}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}} {{.RestartCount}} {{.HostConfig.RestartPolicy.Name}}' "$lab_container"
  done
  curl --fail --silent --show-error --max-time 10 -w '\nhealth_http=%{http_code}\n' http://127.0.0.1:8080/healthz
  curl --silent --show-error --max-time 10 -o /dev/null -w 'anonymous_http=%{http_code}\n' http://127.0.0.1:8080/
  free -h
  df -h /
  mapfile -t lab_containers < <(docker compose ps -q app nginx)
  test "${#lab_containers[@]}" -eq 2
  docker stats --no-stream "${lab_containers[@]}"
) > ".artifacts/continuation/${lab_check_time}.log" 2>&1
lab_check_exit=$?
printf 'collector_exit=%s\n' "$lab_check_exit" >> ".artifacts/continuation/${lab_check_time}.log"
cat ".artifacts/continuation/${lab_check_time}.log"
```

採録コマンドの終了0だけでは `PASS` にしません。次の期待値と本文を読み合わせます。

| 確認対象 | 期待する結果 |
| --- | --- |
| Docker / app / nginx | active / running healthy / running。意図しない再起動回数増加なし |
| HTTP | healthz が 200 かつ JSON 本文の `status` が `ok`、未認証は 401 |
| OS と設定 | machine-id は同じ。再起動後だけ boot ID が変わり、SHA・設定ハッシュ・イメージ ID は同じ |
| 資源とエラー | 中断目安を下回らず、failed unit・OOM 等の未説明の異常なし |

認証ありの `/api/stats` も [初心者ガイド](beginner-learning-guide.md)の手順で確認し、HTTP200 と JSON 本文をローカルで読みます。
資源の数値やホスト情報を含む本文を、そのまま公開ファイルへ貼り付けません。
再起動前ログのファイル名を結果票に記入し、別途 `sudo journalctl -p err --since '-30 minutes' --no-pager` で基準となるエラーを確認します。

**対象 VM のコンソールが使え、作業中の別処理がなく、今回の停止時刻を決めてから**、同じ Ubuntu VM 内で実行します。

```bash
date --iso-8601=seconds
sudo systemctl reboot
```

SSH が切れるのは正常です。VM コンソールで起動を確認して再接続し、上の確認ブロックを実行します。
**確認前に `docker compose up/start/restart` を実行しません。** 動かなければ自動復帰は `FAIL` として、
`systemctl status docker`、`docker compose ps --all`、`docker compose logs --tail 50 app nginx`、
`sudo journalctl -b -p err --no-pager` を読み、原因と手動復旧を別に記録します。

全構成向け [acceptance-check.sh](../scripts/ops/acceptance-check.sh) は10サービス以上・監視・backup timerを確認し、
[daily-check.sh](../scripts/ops/daily-check.sh) も Compose 全サービスを期待します。
今回の2サービスには適用せず、上の限定した確認表を使います。全構成の受け入れIDを上書きしません。

## 3. 24 時間をまたいで点検する

再起動直後を +0 とし、+1 / +6 / +24 時間以降に段階2の確認ブロックを繰り返します。
実時刻、boot ID、HTTP 本文、サービス状態、ディスク・メモリ・ログを結果票へ記入します。
最後の採録まで **実時間で24時間以上** 経過しなければ完了にしません。
各回、`sudo journalctl -p err --since '-24 hours' --no-pager` も読み、前回からの増加を確認します。

これは4時点の**間欠点検**です。間の短い停止を検知した証拠、稼働率100%、72時間試験にはなりません。
PC のスリープや VM 停止で観測が途切れたら、その期間と理由を記録します。時刻を埋めて成功扱いにはしません。
不調があれば段階2の調査と [運用手順](runbooks/README.md)へ戻り、修正後の新しい24時間記録を作ります。
点検期間中は、この対象 VM を維持できる範囲で進めます。

## 4. バックアップを新しい VM で復元する

今回は [9月8日に保管した Loki archive](evidence/2026-09-08-lab-base01-restore-practice.md)を使い、
同じログ2件を別の新規 VM で読めるか確認します。OS 全体の復元や全データの完全性を主張する試験ではありません。
元 VM のデータを削除せず、コピーを管理端末へ退避してから、新しい空の Ubuntu VM を用意します。

### 元 VM の Bash：archive と設定を準備する

過去に保管したパスが今も存在するか確認します。存在しなければ `BLOCKED` とし、過去の成功から現在の存在を推定しません。

```bash
cd ~/lab-backups/loki-20260908
sha256sum -c SHA256SUMS
echo "$?"
ls -lh loki-data.tgz
```

チェックサムが一致してから、次の専用ディレクトリを新規作成します。すでに存在する場合は中止し、前回の試験との関係を確認します。

```bash
(
  set -e
  umask 077
  mkdir ~/loki-crossvm-transfer
  cp ~/lab-backups/loki-20260908/loki-data.tgz ~/loki-crossvm-transfer/
  cp ~/server/deploy/loki/loki-config.yml ~/loki-crossvm-transfer/
  cd ~/loki-crossvm-transfer
  sha256sum loki-data.tgz loki-config.yml > SHA256SUMS
  sha256sum -c SHA256SUMS
)
echo "$?"
```

この設定は復元時に使う設定の保存です。2026-09-08 と同じ版だったことの証明ではありません。
比較用に元 VM の machine-id と現在の Git SHA、archive のハッシュを結果票へ残します。

### Windows PowerShell：管理端末を経由してコピーする

次の3つの `記入待ち` を実際の接続情報へ置き換え、SSH ホスト鍵を VM コンソールの情報と確認します。
既存の SSH 設定で使う鍵を指定してください。秘密鍵そのものをコピーしません。

```powershell
$SourceVm = '記入待ち: ユーザー@元VM'
$RestoreVm = '記入待ち: ユーザー@新VM'
$LabKey = '記入待ち: 管理端末のSSH秘密鍵への絶対パス'
$TransferDir = Join-Path $env:TEMP ('loki-transfer-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $TransferDir -ErrorAction Stop
scp -i $LabKey -r "${SourceVm}:loki-crossvm-transfer" $TransferDir
$LASTEXITCODE
```

終了0と3ファイルの存在を確認します。メモリ不足なら、この時点で段階3を終了し、元 VM だけを通常の手順で停止します。
新 VM は [検証環境の準備](learning-path.md)と [Docker 導入の案内](beginner-learning-guide.md)を使い、
元 VM の clone/checkpoint から戻したものではなく、新しい OS と Docker を準備します。
新 VM 内で `hostname`、`cat /etc/machine-id`、`docker info`、`free -h`、`df -h /` を確認します。
元 VM とは別の machine-id であること、コピー先の `~/loki-crossvm-transfer` がまだ存在しないことを確認して転送します。

```powershell
scp -i $LabKey -r (Join-Path $TransferDir 'loki-crossvm-transfer') "${RestoreVm}:"
$LASTEXITCODE
```

### 新 VM の Bash：別ボリュームへ展開し、本文を照合する

原 VM のボリュームを接続せず、転送したファイルだけで確認します。各ブロックの終了0を確認してから次へ進みます。

```bash
cd ~/loki-crossvm-transfer
sha256sum -c SHA256SUMS
echo "$?"
docker ps -a --format '{{.Names}}'
docker volume ls
ss -lnt
```

`lab-loki-crossvm-check`、`lab-loki-crossvm-data`、3110番が既に使われていれば中止します。
別用途を上書きせず、対象を調べます。未使用を確認して次を実行します。

```bash
(
  set -e
  if docker volume inspect lab-loki-crossvm-data >/dev/null 2>&1; then
    printf '復元先 volume が存在するため中止\n' >&2
    exit 1
  fi
  docker volume create lab-loki-crossvm-data
  docker run --rm \
    --mount type=volume,src=lab-loki-crossvm-data,dst=/restore \
    --mount type=bind,src="$PWD",dst=/backup,readonly \
    alpine:3.22 tar xzf /backup/loki-data.tgz -C /restore
)
echo "$?"
```

取得エラーは `BLOCKED`、展開エラーは `FAIL` として保存します。失敗後のボリュームを成功した新規復元先として再利用しません。
復元コンテナの起動前から終了までの実時刻を保存します。既存の記録に合わせて Loki 2.9.0 を使います。

```bash
date --iso-8601=seconds
docker run -d --name lab-loki-crossvm-check \
  --user 10001:10001 \
  -p 127.0.0.1:3110:3100 \
  --mount type=volume,src=lab-loki-crossvm-data,dst=/loki \
  --mount type=bind,src="$PWD/loki-config.yml",dst=/etc/loki/loki-config.yml,readonly \
  grafana/loki:2.9.0 -config.file=/etc/loki/loki-config.yml
echo "$?"
docker inspect --format '{{.Image}} {{json .Mounts}}' lab-loki-crossvm-check
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:3110/ready
```

初期化中ならログを確認してから再試行します。`ready` と HTTP200 を確認してログを照会します。
新 VM のローカルファイルへ保存し、`status: success`、2件の目印、GET/401、元の時刻と本文を比較します。

```bash
curl --fail --silent --show-error --max-time 30 -G \
  http://127.0.0.1:3110/loki/api/v1/query_range \
  --data-urlencode 'query={compose_project="server-monitor-lab",service="nginx"} |= "loki-first"' \
  --data-urlencode 'start=2026-09-08T06:50:00Z' \
  --data-urlencode 'end=2026-09-08T07:10:00Z' \
  --data-urlencode 'limit=10' > restored-query.json
echo "$?"
python3 -m json.tool restored-query.json
date --iso-8601=seconds
```

HTTP200だけ、空の `result` だけでは成功にしません。期間外・保持期間経過・設定違いはログと照会条件から調べます。
この試験は特定2件の読取りを確認します。RPO や全ログの完全性、別物理ホストの災害対策は `NOT RUN` のままです。
元と新 VM が同じ Hyper-V PC 上なら、その事実も書きます。確認後は以下で専用コンテナだけを撤去し、ボリュームと退避ファイルを保管します。

```bash
docker stop lab-loki-crossvm-check
docker rm lab-loki-crossvm-check
docker volume inspect lab-loki-crossvm-data
sha256sum -c SHA256SUMS
```

## 5. 本人の説明と、別の人による引き渡し確認

まず本人が次の4点を自分の言葉で説明し、分からなかった点と参照した資料を結果票へ残します。

1. 利用者から nginx、app へ届く経路と、SSH トンネルの役割。
2. `up`、`healthy`、HTTP200と本文が、それぞれ何を確認しているか。
3. 今回の失敗1件について、最初の観測、選んだコマンドの理由、原因、修正後の確認。
4. 同じボリュームの再利用、archive の復元、別 VM 復元の違いと、まだ確認していないこと。

次に実際の確認者へ、対象 VM、構成図、起動・停止・状態確認、復旧手順、残存課題を渡します。
[引き渡しチェックリスト](build-package/07-handover-checklist.md)の観点を使い、今回の小構成の結果票へ記入します。
本人が確認者を兼ねたり、AI が確認者として署名したりしません。人が未定なら `BLOCKED`、未実行なら `NOT RUN` を維持します。

確認者は専用の検証環境で、手順を読んで app/nginx の起動・HTTP 本文確認・計画停止と再開を実行します。
既存の [初心者ガイド](beginner-learning-guide.md)を手渡し、本人の補足が必要だった箇所、迷った箇所、修正案を残します。
初めから全コマンドを本人が代行すると、引き渡し確認になりません。確認者の生ログと本人の説明を別の欄へ記録します。

終了時に、実際のサービス状態、保持した archive・ボリューム、次回再開位置を記録します。
公開するのは確認済みの結果と必要な範囲の証拠だけです。元の記録は保持し、
原ログ、接続情報、鍵、バックアップ本体、確認者の個人情報をそのまま Git へ追加しません。
