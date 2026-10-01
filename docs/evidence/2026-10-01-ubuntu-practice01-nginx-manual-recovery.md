# UbuntuでのDocker導入とNginxの計画停止・手動再開（2026-10-01）

[検証証跡台帳](README.md)

## 結果と支援範囲

本人がHyper-V上のUbuntu VMでDockerを準備し、appとNginxの2サービスを起動した。
HTTP応答は、healthzが200、認証なしの画面が401、正しいBasic認証付きAPIが200だった。
Nginxを計画停止するとappはhealthyのまま接続できなくなり、手動再開後は200に戻った。
終了時は両サービスが `Exited (0)` であることを確認した。

**支援区分は `ai-assisted`。AIがコマンドと確認観点を案内し、本人が操作して画面を提示した。**
本文は会話内のスクリーンショットと本人の発言をCodexが整理した記録であり、
AI不使用の独力再現、自動復旧D-1、監視全体の受け入れ実績には数えない。

## 環境と一次資料

| 項目 | 確認できた内容 |
| --- | --- |
| 実施日 | 2026-10-01 JST。全工程の開始・終了時刻、所要時間は未採録 |
| 実行者 | 本人。AIは手順案内、画面読取り、切り分けの提案、文書化を担当 |
| 対象 | Hyper-V上の個人練習用VM `ubuntu-practice01`、一般ユーザー `opsadmin` |
| 接続 | 前半はHyper-V仮想マシン接続、後半はWindows PowerShellからSSH |
| OS | Ubuntu 24.04系。導入ログの `ubuntu.24.04~noble` と診断画面を確認。OSリリース表示全体は未採録 |
| kernel | `Linux 6.8.0-142-generic` |
| Docker / Compose | Docker CLI 29.8.2、Docker Compose v5.5.1 |
| Python / Nginx | Python 3.12.3、Nginx起動ログは1.27.5 |
| コード版 | `a31c05159ad7074b0825ec5e22df55f2b1ac0375`。本人画面の `git rev-parse --short HEAD` は `a31c051`、GitHubの同コミットと対応付けた |
| 作業場所 / プロジェクト | `~/server-nginx-practice`、Compose名 `nginx-practice`（全操作で `-p nginx-practice` を指定） |
| 公開先 | 状態表示でNginxの `127.0.0.1:8080->8080/tcp` を確認 |
| 一次資料 | 本会話内の本人提示画像と発言。原画像ファイル・ハッシュ・連続端末ログはリポジトリに収録していない |

出力は画像から必要箇所を転記したもので、完全な生ログではない。
実IPや秘密値は掲載していない。初回診断のGit作業ツリーはclean表示だったが、
終了時のSHA・差分やイメージのrevision照合は未採録。
本PRで行う文書検査やCIは、本人のVMでの再実行とは区別する。

## 準備とつまずき

| 出来事 | 画面・発言で確認した結果 | 対処と確認範囲 |
| --- | --- | --- |
| Docker導入 | Docker CE、containerd、Compose pluginなどの設定完了ログ | 導入後の `systemctl status docker --no-pager` で `active (running)` と `enabled` を確認 |
| 接続画面で入力不能 | 本人から入力できないとの報告。Windowsメモ帳は入力可能、Hyper-Vの状態は実行中との回答 | 通常シャットダウン・起動の案内後、本人が入力回復を報告。停止・起動操作自体の画面は未採録。入力不能の原因は未特定 |
| 古い接続先でSSH失敗 | 以前の履歴の接続先へのSSHがタイムアウト | 後の `hostname -I` では以前と異なるVMアドレスを確認。タイムアウト時点のIPは未確認で、原因をIP変更と断定しない |
| Docker操作権限 | `docker run --rm hello-world` がDocker socketへの `permission denied` | dockerグループ追加と再ログインを案内後、sudoなしで `Hello from Docker!` を確認。グループ変更自体の出力は未採録 |
| 前提診断 | 最初は `Summary: FAIL=1 WARN=0`。Python venv / ensurepipの不足を表示 | `python3-venv` 導入を案内後、再診断で `FAIL=0 WARN=0`。空き11GiB、8080番未使用もPASS |
| コピーと貼り付け | Hyper-Vのクリップボード操作で入力されないとの報告 | 現在のVM IPを調べ、SSH接続成功の本人報告後、SSH画面でコマンド実行を確認。今回のSSH認証方式は未採録 |
| 設定作成 | `.env` と3つの秘密値ファイルが存在しない画面を確認 | 上書き防止付きの生成ブロックを本人が実行し終了0。秘密値は表示していない |
| Git除外 | `git check-ignore` が4パスを表示、`git ls-files` は空 | 今回のローカル作業ツリーで設定・秘密値が未追跡であることを確認。履歴全体の秘密値検査ではない |

dockerグループは管理者相当の権限を持つことを説明したうえで、個人の練習用VMを対象とした。
日本語の診断文はHyper-V画面で一部表示が崩れていたが、英数字の判定とコマンドは読めた。

## 実行した確認と結果

以下の番号は本記録内の観点であり、既存の受け入れ試験IDではない。

| ID | 操作・観点 | 結果 |
| --- | --- | --- |
| NP-01 | Dockerの稼働・一般ユーザーでのコンテナ実行 | `active (running)`、sudoなしで `Hello from Docker!` |
| NP-02 | Composeと実習前提 | Compose v5.5.1、診断 `FAIL=0 WARN=0` |
| NP-03 | コード版・設定とGit除外 | `a31c051`、生成終了0、4ファイル除外・追跡なし |
| NP-04 | Compose設定の形式 | `docker compose -p nginx-practice config --quiet` の直後に終了0 |
| NP-05 | 最小2サービスの起動状態 | appは `Up (healthy)`、nginxは `Up` |
| NP-06 | 入口経由の応答 | `GET /healthz` → 200 |
| NP-07 | 認証なしの画面 | `GET /` → 401 |
| NP-08 | 正しいBasic認証でAPIへアクセス | `GET /api/stats` → 200 |
| NP-09 | Nginxアクセスログ | `GET / HTTP/1.1" 401`、`GET /api/stats HTTP/1.1" 200` を確認 |
| NP-10 | Nginxのみ計画停止 | nginxは `Exited (0)`、appは `Up (healthy)` のまま |
| NP-11 | 停止中の入口への接続 | curlの接続失敗（7）と `000` を表示 |
| NP-12 | Nginxを手動再開 | nginxが `Up`、appはhealthy、healthzが200へ復帰 |
| NP-13 | 終了時に2サービスを停止 | app・nginxとも `Exited (0)` |

この13観点は提示画面で確認した範囲ではすべて期待どおりだった。
`up -d --build app nginx` の実行を案内し、その後の状態は確認したが、ビルドの全出力は未採録。
コンテナやネットワークを削除する `down` は今回行っておらず、停止までを記録する。

## 再現に使った主なコマンド

対象版の[初心者向け学習ガイド](https://github.com/ns7jp/server/blob/a31c05159ad7074b0825ec5e22df55f2b1ac0375/docs/beginner-learning-guide.md)をもとに、
別の練習用Compose名を指定した。設定・秘密値は準備済みで、リポジトリ直下から操作した。

~~~bash
docker compose -p nginx-practice config --quiet
echo "$?"
docker compose -p nginx-practice ps --all app nginx
curl --max-time 10 -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
curl --max-time 10 -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
~~~

認証付きAPIは、パスワードを表示せずファイルから読み込む次のコードを本人が実行し、200を確認した。

~~~bash
python3 - <<'PY'
from base64 import b64encode
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, ProxyHandler, build_opener

password = Path("deploy/secrets/dashboard_password.txt").read_text().strip()
token = b64encode(f"monitor:{password}".encode()).decode()
request = Request(
    "http://127.0.0.1:8080/api/stats",
    headers={"Authorization": f"Basic {token}"},
)
try:
    with build_opener(ProxyHandler({})).open(request, timeout=10) as response:
        print(response.status)
except HTTPError as error:
    print(error.code)
except URLError:
    print("Connection failed")
PY
~~~

状態・ログ・通信を確認しながら、入口だけを停止・再開した。

~~~bash
docker compose -p nginx-practice logs --tail=20 nginx
docker compose -p nginx-practice stop nginx
docker compose -p nginx-practice ps --all app nginx
curl --max-time 10 -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
docker compose -p nginx-practice start nginx
docker compose -p nginx-practice ps --all app nginx
curl --max-time 10 -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz
docker compose -p nginx-practice stop nginx app
docker compose -p nginx-practice ps --all app nginx
~~~

停止中の `000` はHTTPステータスではなく、curlがHTTP応答を取得できなかった表示。
`/healthz` のアクセスログはNginx側で抑止する設定なので、
ログ確認には認証なしの `/` と認証付き `/api/stats` の記録を使った。
CLIのStarted/Stoppedの秒数を、利用者視点の復旧時間として扱わない。

## 本人の説明

終了確認の際、「appが動いていても、Nginxを止めると通信できないのはなぜか」と問いかけたところ、
本人は次のように回答した。

> Nginxがappの通信を行う入り口になっているからです。

今回の構成では要求がNginxを経由し、appの5000番はホストへ直接公開していないため、この説明と観測結果は整合する。
この回答はAIの説明と実習を経た後の本人の発言である。
[9月8日の実習](2026-09-08-lab-base01-compose-practice.md)で未確認だった説明に対応する新しい記録として残すが、
過去の記録を書き換えたり、構築全体の独力習得を証明したりするものではない。

## 未実施と次の練習

- AIの逐次案内なしでの独力再実行、`ps` と `logs` の違いなど他の理解確認。
- このVMでのpytest、全API、誤った資格情報、metricsトークン認証の試験。
- 監視全10サービス、アラート実配信、Ansible適用、自動復旧D-1。
- ホスト障害からの復元、再起動後のapp/nginx自動復帰、24時間・72時間稼働。
- RTO/RPOや性能の計測、Windowsブラウザからの画面表示、今回のSSH認証方式の確認。
- コンテナ・ネットワークの削除、停止後の秘密値ファイルの再確認。
- 画像原本とハッシュ、連続端末ログの公開保存。

次回は同じ小構成を手順書に沿って本人の判断で再実行し、迷った箇所と参照先を記録する。
本記録の追加で[独力再現ガイド](../independent-rerun-guide.md)の未完了状態や、
既存の受け入れ試験の判定は変更しない。
