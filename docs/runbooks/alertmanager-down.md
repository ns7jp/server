# Runbook: 監視の監視（Alertmanager / blackbox-exporter 停止）

> [共通の実行前提](README.md)を確認し、既定配備先`/opt/server-monitor`で実行します。

## 発火条件

- Alert: `AlertmanagerDown`
  - 条件: `up{job="alertmanager"} == 0` が 5 分継続
- Alert: `BlackboxExporterDown`
  - 条件: `up{job="blackbox"} == 0` が 5 分継続

両者とも「監視の監視」のための観測対象であり、これらが止まると **他のすべての
アラートが届かない / SLI が計測されない** 状態になる。

## 影響

| サービス | 停止時の影響 |
| --- | --- |
| Alertmanager | Prometheus / Loki Ruler から fire しても通知が届かない |
| blackbox-exporter | 可用性 SLI が更新されないため SLO 値が古いまま固定される |

ただし、Alertmanager が落ちている状態では `AlertmanagerDown` 自身の通知も届かない。
このため、Grafana の `Server Monitor SLO` ダッシュボード（`Monitoring of Monitoring`
パネル）と Prometheus `/alerts` 画面を **定常的に運用者が見る** ことが補助手段になる。

## 初動

```bash
cd /opt/server-monitor
date
sudo docker compose ps alertmanager blackbox
sudo docker compose logs --tail=200 alertmanager blackbox
curl http://127.0.0.1:9093/-/healthy
```

| 項目 | 記録内容 |
| --- | --- |
| 検知時刻 | Alertmanager 履歴 or Grafana の up パネルから |
| 影響 | 直近で発火していたアラートと、その通知到達状況 |
| 直近変更 | 設定差分（`alertmanager.yml` の編集、compose 再構築） |

## 切り分け

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| コンテナが exit | `sudo docker compose ps` / `sudo docker compose logs` | exit code と直近ログから原因特定 |
| 設定 syntax error | `sudo docker run --rm --entrypoint /bin/amtool -v $PWD/deploy/alertmanager/alertmanager.ansible.yml:/etc/alertmanager/alertmanager.yml:ro prom/alertmanager:v0.27.0 check-config /etc/alertmanager/alertmanager.yml` | Ansible管理外ではmount元を`alertmanager.yml`に替える。該当行を修正 → コミット → 再適用 |
| Secret mount読み込み失敗 | `slack_webhook_url` などのsecret mount | 親 directory が `0700`、Compose secrets ファイルが `0644` であることを確認（`0600` ではコンテナ内の別 UID が読めない） |
| ホスト全体停止 | `sudo docker ps`、ホスト電源、ディスク | ホスト復旧手順に移行 |
| blackbox 設定エラー | `sudo docker compose logs blackbox` | `deploy/blackbox/blackbox.yml` の構文を確認 |
| Prometheus からスクレイプ不可 | Prometheus `/targets` 画面 | ネットワーク（`monitoring` / `frontend`）と DNS、SG 設定 |

## 復旧操作

```bash
# Alertmanager 単体の再起動
sudo docker compose restart alertmanager
sudo docker compose ps alertmanager
curl http://127.0.0.1:9093/-/healthy

# blackbox-exporter 単体の再起動
sudo docker compose restart blackbox
curl -fsS --get --data-urlencode 'query=up{job="blackbox"}' \
  http://127.0.0.1:9090/api/v1/query
```

復旧後の確認:

1. Prometheus `/targets` で `alertmanager` と `blackbox` が `UP` であること
2. Grafana `Server Monitor SLO` の `Monitoring of Monitoring` パネルがすべて緑
3. テスト用alertを発火。Slackを有効化・引き渡し済みの環境だけSlack到達まで確認する。
   未設定環境ではSlack PASSとせず、local webhook E2Eを別証跡として扱う

## 補助的な防御策

- ホスト OS の `systemd` レベルで Docker のヘルスチェック失敗を検出する
  （`server-monitor-backup.timer` と同様に死活監視用の timer を別途用意できる）
- 二重化したい場合は別ホストにもう 1 セットの Alertmanager / Prometheus を立て、
  互いに `up` を見合う構成にする。本ラボの v1.x 範囲では対象外。

## 事後対応

1. 「監視の監視」が落ちていた時間帯は他のアラートが届いていない可能性があるため、
   その間に発生したインシデントを Loki / Prometheus の履歴から **後追い** で洗う。
2. 同一原因の再発を防ぐため、設定の lint や CI 検証（`amtool check-config` を CI に
   追加するなど）を強化する。
3. 月次レビュー（`docs/roadmap/slo-reviews/`）に「アラート到達 SLO」の達成状況として記録する。

## 参考

- SLO 定義: [docs/slo.md](../slo.md)
- 監視構成: [docs/architecture.md](../architecture.md)
