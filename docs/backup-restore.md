# バックアップ・復旧設計

## 対象データ

| 対象 | 永続化方法 | バックアップ要否 |
| --- | --- | --- |
| アプリコード、Nginx、監視ルール、Grafana dashboard、Loki / Promtail 設定 | Git リポジトリ | GitHub を正として復元 |
| Prometheus 履歴 | `prometheus_data` volume、既定15日保持 | 学習環境では任意。本番相当では必要 |
| Loki 履歴 | `loki_data` volume、既定30日保持 | 学習環境では任意。インシデント記録を保全する場合は対象 |
| Promtail 読み込み位置 | `promtail_data` volume の `positions.yaml` | 復元不要（喪失時は古いログを再送し重複が出るが運用継続可） |
| Grafana 設定 | dashboard / datasource はプロビジョニング | 手動変更を禁止すれば volume 復元不要 |
| 資格情報、Slack Webhook | `deploy/secrets/*.txt` または OS の秘密管理 | Git 外の安全な保管先へバックアップ |

## バックアップ例

検証環境で履歴を残す必要がある場合は、サービス停止時間を確保した上で volume をアーカイブする。

```bash
docker compose stop prometheus grafana loki
docker run --rm -v server-monitor-lab_prometheus_data:/data -v "$PWD/backup:/backup" alpine \
  tar czf /backup/prometheus-data.tgz -C /data .
docker run --rm -v server-monitor-lab_grafana_data:/data -v "$PWD/backup:/backup" alpine \
  tar czf /backup/grafana-data.tgz -C /data .
docker run --rm -v server-monitor-lab_loki_data:/data -v "$PWD/backup:/backup" alpine \
  tar czf /backup/loki-data.tgz -C /data .
docker compose start prometheus grafana loki
```

秘密値は別の秘密管理先に保存し、バックアップアーカイブや Git へ混入させない。

## 復旧試験

1. 新しい Linux ホストへリポジトリを取得する。
2. 秘密管理先から `deploy/secrets/*.txt` を復元し、`chmod 600` を設定する。
3. 必要な volume を作り、バックアップを展開する。
4. `docker compose up -d --build` を実行する。
5. `/healthz`、Prometheus targets、Grafana dashboard、Alertmanager の順に確認する。

## 復旧目標

このラボでの目標は、設定が Git に存在し秘密値を復元できる前提で、監視 UI と収集を60分以内に再構築できることである。履歴喪失を許容しない業務要件では、外部ストレージまたはリモート write を別途設計する。
