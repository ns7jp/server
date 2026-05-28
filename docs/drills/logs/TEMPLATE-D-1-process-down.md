# D-1 プロセスダウン演習記録テンプレート

## 基本情報

| 項目 | 内容 |
| --- | --- |
| 実行日 | YYYY-MM-DD HH:MM JST |
| 対象 commit | `commit-sha` |
| 環境 | local Linux Docker host |
| シナリオ | app process down |
| 目標 RTO | 15 分 |

## 実行コマンド

```bash
./scripts/drills/d1-process-down.sh
```

## タイムライン

| 時刻 | イベント | 証跡 |
| --- | --- | --- |
| HH:MM:SS | 演習開始 | コマンド実行ログ |
| HH:MM:SS | アプリ停止 | `docker ps` / script output |
| HH:MM:SS | Alert 発火 | Alertmanager / Slack screenshot |
| HH:MM:SS | 復旧操作 | command |
| HH:MM:SS | `/healthz` 復旧 | HTTP status |
| HH:MM:SS | 演習終了 | summary |

## 結果

| 指標 | 目標 | 実測 | 評価 |
| --- | --- | --- | --- |
| 検知時間 | 2 分以内 | ? 分 | PASS / FAIL |
| 復旧時間 RTO | 15 分以内 | ? 分 | PASS / FAIL |
| データ損失 RPO | 0 | ? | PASS / FAIL |
| 通知到達 | 2 分以内 | ? 分 | PASS / FAIL |

## 所見

- 良かった点:
- 見つかった課題:
- 次の対応:
