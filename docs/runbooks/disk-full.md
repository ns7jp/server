# Runbook: ディスク使用率の逼迫

## 発火条件

- Alert: `LinuxNodeFilesystemAlmostFull`
- 条件: いずれかのファイルシステム（`tmpfs` / `overlay` / `squashfs` を除く）の使用率が **85% を超える状態が 15 分継続**
- 定義: `deploy/prometheus/rules.yml`

## 影響

- ログ・バックアップ・イメージの書き込みが失敗し始める可能性がある。
- Docker がディスク不足で新規コンテナを起動できなくなることがある。
- Loki / Prometheus のデータ書き込み失敗は、以後の監視自体を欠損させる。

## 初動

```bash
date
df -h
docker system df
```

記録する項目:

| 項目 | 記録内容 |
| --- | --- |
| 検知時刻 | Alertmanager の発火時刻 |
| 影響 | どのマウントポイントが 85% を超えているか |
| 直近変更 | 大量ログ出力、バックアップの失敗、デプロイの有無 |
| 対応者 | 調査を開始した担当 |

## 切り分け

| 症状 | 確認 | 対応 |
| --- | --- | --- |
| Docker イメージ / ビルドキャッシュの肥大化 | `docker system df -v` | 未使用分を確認して `docker system prune`（`-a` は影響範囲を確認してから） |
| コンテナログの肥大化 | `du -sh /var/lib/docker/containers/*/*-json.log \| sort -h \| tail` | `compose.yaml` に `logging.options.max-size` が未設定のため、`json-file` ドライバの既定では無制限に増える。恒久対応として上限設定を追加する |
| ホストの journal 肥大化 | `journalctl --disk-usage` | `journalctl --vacuum-size=200M` |
| バックアップアーカイブの滞留 | `du -sh` （バックアップ出力先ディレクトリ） | 世代管理・保持ポリシーの確認（[バックアップ命名規則](../backup-naming.md)） |
| Prometheus / Loki のボリューム肥大化 | `docker system df -v` で該当ボリュームを特定 | retention 設定（`compose.yaml` の `--storage.tsdb.retention.time`、`loki-config.yml` の `retention_period`）を確認 |
| 原因不明の急激な消費 | `du -xh --max-depth=1 / 2>/dev/null \| sort -rh \| head` | 該当ディレクトリをさらに掘り下げる |

## 復旧操作

1. 上記切り分けで特定した不要データを削除する（`docker system prune`、ログローテーション、`journalctl --vacuum-size` 等）。
2. `df -h` で使用率が 85% を下回ったことを確認する。
3. Prometheus / Loki への書き込みが復帰しているか、Grafana ダッシュボードで確認する。

```bash
df -h
docker system df
```

復旧後は Alertmanager で `LinuxNodeFilesystemAlmostFull` が resolved になったことを確認する。

## 事後対応

1. 発生時刻、原因、削除したデータ、復旧時刻をインシデント記録へ残す。
2. 同じ原因で再発し得る場合は、ログローテーション設定・retention 設定・アラートの閾値を見直す。
3. 恒常的にディスクが逼迫する傾向であれば、ボリュームサイズの拡張を検討する。

## 参考

- [SLO 定義](../slo.md)
- [バックアップ命名規則](../backup-naming.md)
