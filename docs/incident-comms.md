# インシデント / 演習周知テンプレート

障害対応と復旧演習で Slack に流す定型テキスト。即興で打つと抜け漏れが出やすいので、
発火パターン別にコピペできる形でまとめる。

## 1. 使用ルール

- 投稿は **演習チャンネル**（例: `#server-monitor-drills`）または
  **インシデントチャンネル**（例: `#incident-monitor`）。
- すべてのタイムスタンプは **JST、秒精度**（`HH:MM:SS`）。
- 1 件のインシデント / 演習は **同じスレッド** にぶら下げる。最初に新規投稿、以後返信。
- 状態遷移は次の 4 段階。各遷移で投稿する。
  - 🔔 **検知**（detected）
  - 🛠️ **対応中**（mitigating）
  - ✅ **暫定復旧**（mitigated）
  - 📝 **完了**（resolved + 振り返り済み）

## 2. テンプレート

### 2.1 検知（インシデント）

```
:bell: [INCIDENT] server-monitor 検知 / detected
時刻: 2026-MM-DD HH:MM:SS JST
影響: <ダッシュボード閲覧不可 / アラート停止 / etc>
発火アラート: <Alert 名>
ランブック: <runbook_url>
担当: @<onCall>
スレッドで状況更新します。
```

### 2.2 検知（演習）

```
:test_tube: [DRILL] D-<N> <シナリオ名> 開始
時刻: 2026-MM-DD HH:MM:SS JST
環境: staging
シナリオ: docs/drills/D-<N>-...md
実施者: @you
RTO 目標: <分>  RPO 目標: <時間>
スレッドで時系列を残します。
```

### 2.3 対応中

```
:hammer_and_wrench: [STATUS] 対応中 / mitigating (HH:MM:SS JST)
現状: <切り分け完了 / 復旧手順実行中 / etc>
次のアクション: <具体的に>
完了予定: <時刻 or "未定">
```

### 2.4 暫定復旧

```
:white_check_mark: [STATUS] 暫定復旧 / mitigated (HH:MM:SS JST)
復旧確認: <healthz 200 / Prometheus targets UP / etc>
残対応: <根本対応 / 監視強化 / 顧客連絡など>
振り返り会: <日時>
```

### 2.5 完了

```
:memo: [POSTMORTEM] resolved (HH:MM:SS JST)
RTO 実績: <分> (目標 <分>)
RPO 実績: <時間> (目標 <時間>)
タイムライン: <docs/drill-logs/... or docs/incidents/...>
改善アクション: <件数、担当、期限>
```

## 3. よくある変則ケース

| 状況 | 取扱い |
| --- | --- |
| 検知前に運用者が気づいた | `:bell:` の代わりに `:eyes:` を使い、検知アラートが発火しなかった旨を明記。アラート設計の改善対象 |
| 複数並行インシデント | スレッドは別、本文の `関連:` で相互リンク |
| 演習中に本物のインシデントが発生 | 演習を即時中断し、`:rotating_light:` 付きで切替を宣言。演習側は時刻だけ控える |
| Alertmanager 自身が停止 | 通知が来ない前提で、ダッシュボードを定常監視している運用者が手動投稿（`docs/runbooks/alertmanager-down.md` 参照） |

## 4. 例（演習 D-2 抜粋）

```
:test_tube: [DRILL] D-2 ホスト障害 開始
時刻: 2026-06-15 14:00:00 JST
環境: staging
シナリオ: docs/roadmap/D-2-host-failure.md
実施者: @shimada
RTO 目標: 60 分  RPO 目標: 24 時間
スレッドで時系列を残します。
```

スレッド返信:

```
14:00:42 :bell: AlertmanagerDown 発火、Slack 到達。検知 OK
14:02:15 :hammer_and_wrench: aws ec2 describe-instance-status: stopped
14:09:48 :hammer_and_wrench: 最新スナップショット特定 (prod-monitor-...-20260615T0230Z)
14:24:12 :hammer_and_wrench: terraform apply -var "recovery_volume_id=..." 完了
14:38:03 :hammer_and_wrench: ansible-playbook site.yml 完了
14:41:09 :white_check_mark: /healthz 200。Grafana / Prometheus UI も OK
14:47:00 :memo: RTO 実績 47 分 / 目標 60 分。ログを docs/drills/logs/2026-06-15-D-2.md に追記
```

## 5. 関連ドキュメント

- 演習テンプレート: [docs/drill-template.md](drill-template.md)
- 演習一覧: [docs/drills/README.md](drills/README.md)
- ランブック一覧: [docs/runbooks/](runbooks/)
- 命名規則: [docs/backup-naming.md](backup-naming.md)
