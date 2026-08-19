# バックアップ・復旧設計

## 対象データ

| 対象 | 永続化方法 | バックアップ要否 |
| --- | --- | --- |
| アプリコード、Nginx、監視ルール、Grafana dashboard、Loki / Grafana Alloy 設定 | Git リポジトリ | GitHub を正として復元 |
| Prometheus 履歴 | `prometheus_data` volume、既定15日保持 | 学習環境では任意。本番相当では必要 |
| Loki 履歴 | `loki_data` volume、既定30日保持 | 学習環境では任意。インシデント記録を保全する場合は対象 |
| Alloy 読み込み位置 | `alloy_data` volume の positions data | 復元不要（喪失時は古いログを再送し重複が出るが運用継続可） |
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
2. 秘密管理先から `deploy/secrets/*.txt` を復元し、`chmod 644` を設定する（`600` だとコンテナ内の別 UID から読めず起動しないコンテナがある。実機で確認済み）。
3. 必要な volume を作り、バックアップを展開する。
4. `docker compose up -d --build` を実行する。
5. `/healthz`、Prometheus targets、Grafana dashboard、Alertmanager の順に確認する。

## 復旧目標

このラボでの目標は、設定が Git に存在し秘密値を復元できる前提で、監視 UI と収集を60分以内に再構築できることである。履歴喪失を許容しない業務要件では、外部ストレージまたはリモート write を別途設計する。

## RTO / RPO 目標

| 障害種別 | RTO | RPO | 関連ランブック / 演習 |
| --- | --- | --- | --- |
| プロセスダウン | 5 分 | 0 | [docs/drills/D-1-process-down.md](drills/D-1-process-down.md) |
| ホスト障害（OS 起動不能） | 60 分 | 24 時間 | [復元ランブック](roadmap/restore-from-snapshot.md) / [D-2 演習シナリオ](roadmap/D-2-host-failure.md)（いずれも AWS staging 環境待ち） |
| AZ 障害（v2.x 以降の冗長化前提）| 15 分 | 0 | （未演習）|
| リージョン障害 | 24 時間 | 24 時間 | （未演習・Terraform 別リージョン適用）|
| 操作ミスでデータ削除 | 30 分 | 24 時間 | （D-3 別 PR で追加予定）|

## 復旧演習

「バックアップではなく、リストアが運用できることが価値」。手順書だけでは
**いざというときに動かない** ため、定期的な演習で実証する。

| 演習 | 頻度 | 想定時間 | 環境 |
| --- | --- | --- | --- |
| D-1: プロセスダウン → 自動復旧 | 月次 | 15 分 | ローカル Docker |
| D-2: ホスト障害 → 別ホストに復元 | 四半期 | 2 時間 | AWS staging |

一覧は [docs/drills/README.md](drills/README.md)、テンプレートは
[docs/drill-template.md](drill-template.md)、Slack 周知例は
[docs/incident-comms.md](incident-comms.md) を参照。命名規則は
[docs/backup-naming.md](backup-naming.md) で統一する。

### D-1 自動ランナー

```bash
./scripts/drills/d1-process-down.sh
```

`app` コンテナを SIGKILL し、`restart: unless-stopped` による自動復旧までの時間を
計測する。Slack 演習チャンネルにそのまま貼れるサマリーと、機械可読 JSON を出力する。

### CI による日次バックアップ検証

`.github/workflows/backup-verify.yml` で以下を毎日 04:00 UTC に検証する。

| ジョブ | 内容 |
| --- | --- |
| `backup-script-syntax` | Ansible テンプレートをレンダリングし、`bash -n` + `shellcheck` |
| `backup-archive-smoke-test` | ダミー volume を作って tar 圧縮、展開可能性まで確認 |
| `cloud-snapshot-age` | （任意）AWS Backup の最新 recovery point の鮮度を OIDC 経由で確認 |

`cloud-snapshot-age` は GitHub Variable `ENABLE_AWS_BACKUP_VERIFY=true` と
GitHub Secret `AWS_BACKUP_VERIFY_ROLE_ARN` が設定された環境でのみ動く。

## 演習履歴

実行した演習のログはまだ収録されていない。下表は記録先の形式であり、実績値ではない。
実施後は [検証証跡台帳](evidence/README.md) の記録ルールに従って追加する。

| 日付 | 演習 | RTO 実績 | 結果 | 記録 |
| --- | --- | --- | --- | --- |
| 未実施 | D-1 | 未測定 | 未実施 | `docs/drills/logs/YYYY-MM-DD-D-1.md` |
| 未実施 | D-2 | 未測定 | 未実施 | `docs/drills/logs/YYYY-MM-DD-D-2.md` |
