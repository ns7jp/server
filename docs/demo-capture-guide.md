# 2〜3 分デモ収録ガイド

採用担当者が短時間で「実際に動かしている」と判断できるよう、
`デプロイ → わざと壊す → アラート確認 → 復旧` を 1 本の短い動画にする。

---

## 見せる流れ

| 時間 | 画面 | 見せること |
| --- | --- | --- |
| 0:00-0:20 | ターミナル | `docker compose ps`、対象 commit、起動中のサービス |
| 0:20-0:45 | Grafana | Server Monitor / SLO dashboard が動いている状態 |
| 0:45-1:15 | ターミナル | D-1 演習で app または nginx を停止 |
| 1:15-1:50 | Alertmanager / Slack | FIRING 通知、runbook_url、影響範囲 |
| 1:50-2:20 | ターミナル | 復旧コマンドと `/healthz` 確認 |
| 2:20-2:45 | Alertmanager / Slack | RESOLVED 通知、RTO 実測 |

---

## 収録前チェック

- [ ] webhook URL、公開 IP、個人名、AWS account ID、秘密値が画面に出ない。
- [ ] ブラウザのブックマークバー、通知、個人アカウント名を隠す。
- [ ] 対象 commit と実行日時をメモに残す。
- [ ] 失敗してもそのまま原因調査ログとして残せるよう、録画前に目的を決める。

---

## 収録時に読む要点

1. 「これは Linux サーバー監視を想定したローカルラボです」
2. 「Grafana でメトリクス、Loki でログ、Alertmanager で通知を確認します」
3. 「今から app を意図的に止め、アラートが出るか確認します」
4. 「ランブックに沿って復旧し、Resolved まで確認します」
5. 「実測時間と証跡は `docs/drills/logs/` に残します」

---

## 収録後に更新する場所

| 場所 | 更新内容 |
| --- | --- |
| `docs/evidence/README.md` | 動画、スクリーンショット、対象 commit、実行日時を追記 |
| `docs/drills/logs/YYYY-MM-DD-D-1.md` | RTO、通知到達時間、改善点を記録 |
| `README.md` | デモ動画リンクを上部へ追加 |
| `docs/roadmap/slo-reviews/YYYY-MM.md` | 演習で消費したバジェットや気づきを記録 |

---

## 保存ファイル名

```text
docs/evidence/screenshots/demo-d1-process-down_<commit>_YYYYMMDD.png
docs/drills/logs/YYYY-MM-DD-D-1.md
```

動画本体は GitHub の容量に応じて、GitHub Release、YouTube 限定公開、または
ポートフォリオサイト側に置き、リポジトリからリンクする。
