# バックアップ・スナップショット命名規則

復旧演習で「最新スナップショットがどれか」を素早く特定するため、すべての
バックアップアーティファクトに **共通のタグと命名規則** を適用する。

## 1. 適用対象

| 種類 | 場所 | 命名 / タグ |
| --- | --- | --- |
| AWS Backup recovery point | AWS Backup Vault | environment別Vault・明示resource ARN・plan IDで特定 |
| EBS スナップショット（手動 / 追加取得） | EC2 → スナップショット | 後述の命名規則を適用 |
| ローカル tarball スナップショット | `/var/backups/server-monitor/` | ISO 8601 UTC タイムスタンプ |
| S3 への長期アーカイブ | `server-monitor-prod-archive-*` バケット | プレフィックス + ISO 日付 |

## 2. 共通タグ

| タグ | 値 | 用途 |
| --- | --- | --- |
| `Project` | `server-monitor` | プロジェクト全体識別 |
| `Environment` | `dev` / `staging` / `prod` | 環境分離 |
| `Application` | `server-monitor` | inventory / cleanup用。Backup selection自体は明示EC2 ARN |
| `Source` | `<EC2-instance-id>` または `<hostname>` | 復元元の特定 |
| `BackupType` | `daily` / `weekly` / `pre-change` / `manual` | バックアップ目的の識別 |
| `RetentionDays` | 数値（例: `14`、`30`） | 保持日数 |
| `CreatedBy` | `aws-backup` / `terraform` / `ansible` / `<user>` | 作成主体 |

## 3. 命名規則

### 3.1 EBS スナップショット（手動 / 演習用）

```
<env>-<role>-<source>-<utc-timestamp>[-<purpose>]
```

| 要素 | 例 |
| --- | --- |
| `env` | `prod`、`stg`、`dev` |
| `role` | `monitor`（ロール名） |
| `source` | `i-0123...` または `monitor-01` |
| `utc-timestamp` | `20260527T0230Z`（ISO 8601 basic、秒省略可） |
| `purpose` | `pre-upgrade`、`drill-d2`、`manual`（省略可） |

例:

- `prod-monitor-monitor-prod-01-20260527T0230Z-daily`
- `stg-monitor-monitor-stg-01-20260527T1500Z-drill-d2`

### 3.2 ローカル tarball（Ansible backup role）

`v1.2` の `server-monitor-backup.sh` が生成するパス：

```
/var/backups/server-monitor/<utc-timestamp>/<volume>.tgz
```

例:

- `/var/backups/server-monitor/20260527T173000Z/prometheus_data.tgz`
- `/var/backups/server-monitor/20260527T173000Z/grafana_data.tgz`
- `/var/backups/server-monitor/20260527T173000Z/loki_data.tgz`

タイムスタンプは `date -u +%Y%m%dT%H%M%SZ` で生成。`/var/backups/server-monitor` 直下
のサブディレクトリ単位で `find -mtime` でローテーションする。

### 3.3 S3 アーカイブ（長期保管）

`s3://server-monitor-<env>-archive-<random>/<utc-date>/<artifact>` を基準とする。

例:

- `s3://server-monitor-prod-archive-ab12cd34/20260527/grafana.db.gz`
- `s3://server-monitor-prod-archive-ab12cd34/20260527/prometheus_data.tgz`

`<utc-date>` は `YYYYMMDD`。`<artifact>` は復元単位のアーティファクト名と圧縮拡張子。

## 4. 探索コマンド

「最新スナップを 1 つだけ取り出す」典型ケース：

```bash
# AWS Backup の最新 recovery point（environment rootが明示選択したEC2 ARN）
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name server-monitor-prod-vault \
  --by-resource-arn "<EC2-or-EBS-ARN>" \
  --query 'RecoveryPoints | sort_by(@,&CreationDate)[-1].RecoveryPointArn' \
  --output text

# EBS スナップショット（手動命名規則ベース）
aws ec2 describe-snapshots \
  --filters "Name=tag:Project,Values=server-monitor" \
            "Name=tag:Source,Values=<instance-id>" \
  --query 'Snapshots | sort_by(@,&StartTime)[-1].SnapshotId' \
  --output text

# ローカル tarball
ls -t /var/backups/server-monitor/ | head -1
```

「特定の用途タグで絞り込む」：

```bash
aws ec2 describe-snapshots \
  --filters "Name=tag:BackupType,Values=pre-change" \
  --query 'Snapshots[].[StartTime,SnapshotId,Tags[?Key==`Source`].Value|[0]]' \
  --output table
```

## 5. 改善履歴

| 日付 | 変更 | 起点となった演習 |
| --- | --- | --- |
| 2026-05-27 | 初版（v1.3 backup-drill）| 設計書 §6.5 の発見事項を反映 |
