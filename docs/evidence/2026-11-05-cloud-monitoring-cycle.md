# クラウドの独立構成で、実停止から通知・復旧まで確認

実施者は **Codex（AI）**、実施日は 2026-11-05 です。本人の Hyper-V VM の操作記録や、本人の独力技能を示す記録には数えません。

## 対象と確認方法

- ソース：`36a26b4341914bac95c8493fc3913ca53a558e20` を `git archive` で取り出したコピー。
- 環境：この作業のクラウド環境内の Docker。独立 project `portfolio-cloud-cycle-20261105`。
- 構成：app / nginx / Prometheus / Alertmanager / ローカル webhook 受信器の5サービス。
- 停止：`docker compose stop app` による計画停止。Nginx と監視・通知サービスは稼働を継続。
- 検知：既存 `deploy/prometheus/rules.yml` の `ServerMonitorUnavailable`。`up == 0` の2分継続条件を変更していません。
- 通知：Alertmanager → 同じ構成の `webhook-sink:8081/alerts`。Slack・メール等への送信はしていません。
- 復旧：`docker compose start app` による手動再開。同じ入口の HTTP と同じ scrape の復帰、RESOLVED 受信を確認。

既存のデモにある API からの合成アラート注入は使わず、実際の app 停止によってルールを発火させます。
この構成の Prometheus は app と監視サービス自身だけを収集し、node-exporter・Grafana・Loki・Alloy・blackbox は起動しません。
Alertmanager の `group_wait` / `group_interval` は各5秒です。通常構成の30秒 / 5分とは異なります。
app のビルド時だけ、この環境の CA を BuildKit secret で渡しています。TLS の検証は有効です。

## 実行結果

**PASS：同一構成で、実停止に伴う異常・FIRING・手動復旧・RESOLVED を1回確認しました。**

| 観測時刻（UTC） | 観測結果 |
| --- | --- |
| 02:28:25 | HTTP 200、app の `up=1`、該当通知の受信履歴なし |
| 02:28:26 | app の計画停止完了 |
| 02:28:41 | 同じ入口が HTTP 502、app の `up=0` |
| 02:30:52 | ローカル受信器で `ServerMonitorUnavailable` / `app:5000` の FIRING を受信 |
| 02:30:54 | Prometheus の firing 状態を確認し、app を手動再開 |
| 02:31:10 | 同じ入口が HTTP 200、同じ app の `up=1` |
| 02:31:17 | 同じアラートの RESOLVED を受信 |

時刻は同じクラウド環境の時計によります。日本時間では同日の11時台です。
通知の行は受信器の `received_at`、その他は検査側の観測時刻（秒未満省略）です。
試験は1回で、復旧時間の保証や長期の可用性評価には使いません。

[実測JSON](artifacts/2026-11-05-cloud-monitoring-cycle/result.json) /
[実行ログ](artifacts/2026-11-05-cloud-monitoring-cycle/cycle.log) /
[環境・イメージ・依存ライブラリの版](artifacts/2026-11-05-cloud-monitoring-cycle/runtime.json)

Docker 29.9.2 / Compose 2.40.3、クラウド環境の OS は Debian 13 です。
OS の初期設定を行う既存 `run-full-stack.sh` は使わず、Compose の部分構成だけを起動しました。

試験後、当該 project の5コンテナ・ネットワーク・ボリュームを撤去しました。
02:32:33 UTC の照合では、project ラベルが一致する残存リソースは0件です。
[撤去後の確認](artifacts/2026-11-05-cloud-monitoring-cycle/cleanup.json)。他の既存 project は対象にしていません。

## 準備中に直したこと

一時コピーへ生成した設定・テスト用資格情報ファイルが、実行環境の umask により読み取りを制限されていました。
Prometheus / Alertmanager は設定の読み取りで `permission denied`、app は `/healthz` が200でも `/metrics` が503になりました。
非 root のプロセスが読めるよう、公開用設定とリポジトリの **サンプル資格情報** のコピーを644にし、対象サービスを再起動しました。
実際の秘密情報を公開したり、実環境の秘密ファイルの権限を緩めたりしたものではありません。

app は資格情報を起動時に読むため、ファイルの権限変更だけでなく app の再起動も必要でした。
その後、HTTP 200・`up=1`・該当アラートの受信履歴なしを確認してから、一巡の試験を開始しました。

## 再実行する場合

以下はこのクラウド環境のローカル Docker socket を使った検証の再実行手順です。
本人の現在の app / nginx 構成へそのまま適用せず、独立した検証用コピーで使います。
同名 project のコンテナ・ボリューム・ネットワークが既にある場合は処理を中止し、別の作業のリソースを上書きしません。

[実行スクリプト](artifacts/2026-11-05-cloud-monitoring-cycle/run_cycle.py)と、今回使った設定を同梱しています。
公開サンプル資格情報を使うため、すべてのホスト側ポートは127.0.0.1限定です。

```bash
# server リポジトリ直下で実行
set -euo pipefail
cycle_repo=$(pwd -P)
cycle_inputs="$cycle_repo/docs/evidence/artifacts/2026-11-05-cloud-monitoring-cycle"
cycle_run_dir=$(mktemp -d /tmp/portfolio-cloud-monitoring-cycle-XXXXXX)
mkdir "$cycle_run_dir/source"
git archive 36a26b4341914bac95c8493fc3913ca53a558e20 | tar -x -C "$cycle_run_dir/source"
cp "$cycle_inputs/run_cycle.py" "$cycle_inputs/source-sha.txt" "$cycle_run_dir/"
cp "$cycle_inputs/Dockerfile.cloud" "$cycle_inputs/compose.cloud.yaml" "$cycle_run_dir/source/"
cp "$cycle_inputs/prometheus.cloud.yml" "$cycle_run_dir/source/deploy/prometheus/"
cp "$cycle_inputs/alertmanager.cloud.yml" "$cycle_run_dir/source/deploy/alertmanager/"
for name in dashboard_password metrics_token grafana_admin_password; do
  cp "$cycle_run_dir/source/deploy/secrets/$name.txt.example" "$cycle_run_dir/source/deploy/secrets/$name.txt"
done
chmod 644 "$cycle_run_dir/source/deploy/prometheus/prometheus.cloud.yml" \
  "$cycle_run_dir/source/deploy/alertmanager/alertmanager.cloud.yml" \
  "$cycle_run_dir/source/deploy/secrets/"*.txt
cd "$cycle_run_dir/source"
cycle_docker() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY \
    -u DOCKER_CERT_PATH docker --host=unix:///var/run/docker.sock "$@"
}
cycle_compose() {
  cycle_docker compose -p portfolio-cloud-cycle-20261105 \
    -f compose.yaml -f compose.e2e.yaml -f compose.cloud.yaml "$@"
}
test -z "$(cycle_docker ps -aq --filter label=com.docker.compose.project=portfolio-cloud-cycle-20261105)" || exit 1
test -z "$(cycle_docker volume ls -q --filter label=com.docker.compose.project=portfolio-cloud-cycle-20261105)" || exit 1
test -z "$(cycle_docker network ls -q --filter label=com.docker.compose.project=portfolio-cloud-cycle-20261105)" || exit 1
cycle_compose up -d --wait --wait-timeout 180 --no-deps app nginx prometheus alertmanager webhook-sink
python3 ../run_cycle.py
# 結果は $cycle_run_dir/result.json に残る。試験後はこの project だけを撤去する。
cycle_compose down -v --remove-orphans
```

`run_cycle.py` はエラー時に FAIL を設定し、停止した app の再開を試みます。
Docker 自体のエラーなどで再開に失敗すると結果ファイルの最終保存にも到達できないため、
終了コード・ログを確認し、同じ project で `cycle_compose start app` と状態確認を行ってから、
上の `down` で検証用リソースを撤去します。
これは1回の計画停止の検証です。本人の判断、Slack の実通知、自動復旧、OS の初期構築・再起動、長期稼働、バックアップ復元、監視全体、本番運用は今回の対象外です。

[本人管理環境での次の実施](../real-environment-validation-plan.md#まず一つの構成で確認する) / [検証証跡台帳](README.md)
