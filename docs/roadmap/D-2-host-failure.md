# D-2: ホスト障害 → 別ホストに復元

## 1. 目的

EC2 ホストが応答しなくなった状態を再現し、**AWS Backup の recovery point** から
別ホストへ復元する手順を実機で検証する。「バックアップは取れているがリストアは
やったことがない」を確実に潰す。

| 項目 | 値 |
| --- | --- |
| 頻度 | 四半期 |
| 想定時間 | 2 時間（操作 60 分 + 検証 30 分 + 振り返り 30 分） |
| 環境 | `terraform/environments/staging`で作る短時間AWS staging（**本番では実施しない**） |
| RTO 目標 | **60 分以内**（[docs/backup-restore.md](../backup-restore.md) 参照）|
| RPO 目標 | **24 時間以内**（AWS Backup 日次プラン） |
| 関連ランブック | [restore-from-snapshot.md](./restore-from-snapshot.md) |
| 関連 SLO | 可用性 99.5%（[docs/slo.md](../slo.md)）|

## 2. 事前準備

| 項目 | 確認方法 |
| --- | --- |
| 専用staging stateと実値file | `backend.hcl` / `terraform.tfvars`がdev/prodと別で、Git管理外 |
| staging構成のdriftなし | `terraform -chdir=terraform/environments/staging plan -detailed-exitcode`が`0` |
| 最新の AWS Backup recovery point が存在 | `aws backup list-recovery-points-by-backup-vault` |
| 演習対象の EC2 タグ | `Application=server-monitor`、`Environment=staging` |
| 演習チャンネル開設 | Slack `#server-monitor-drills` |
| 観測役 / 操作役 / 司会 | 役割分担を Slack 上で明示 |
| `aws` CLI バージョン | `aws --version`（v2.x ピン留め）|
| 開始前バックアップ | 日次planの`COMPLETED` recovery pointを確認。短時間確認でon-demandを使う場合は日次RPO証跡と区別 |

stagingはALB用networkを2 AZ、復元元EC2を1 AZに絞った短時間の非本番環境です。可用性や性能をproduction相当と
主張しません。stagingだけはALB access-log bucket、Backup Vault、archive bucket、SSM transfer bucketを
`force_destroy=true`、Vaultの削除拒否policyを無効にし、承認済みの`terraform destroy`で
演習用データも削除できる設計です。dev/prodの既定値は保護側のままです。account/regionで共有される
GuardDutyとaccount-wide CloudTrailはstagingでは作成しません。演習後は証跡を外部へ保存し、
destroy結果とCost Explorerの反映を確認します。

## 3. シナリオ

> staging サーバー `monitor-stg-01` が突如応答しなくなった。
> 監視ダッシュボード（Grafana / Prometheus）が全停止している。

演習の障害注入は、利用可能なrecovery pointを確認した後にstagingの復元元EC2を停止し、そのまま
保持する方法に限定します。復元経路を測るため通常の「軽い再起動」は意図的に省略し、開始時刻を
停止操作の開始時刻として記録します。ディスク破壊、volume detach、OS設定破壊は行わず、
OS/EBS破損の再現実績とは主張しません。異常時は復元元EC2をstartし、新EC2をTarget Groupへ
登録せずに中断します。

## 4. 復旧手順

[restore-from-snapshot.md](./restore-from-snapshot.md) を
正本として参照する。タイムライン上のコマンドはランブックからコピーする。

主なステップ:

1. 障害宣言（Slack）
2. 現状確認（`aws ec2 describe-instance-status`、SSM、SSH）
3. 実障害なら軽い再起動を試行。D-2演習では安全なEC2 stop後に省略
4. `COMPLETED` / `AVAILABLE`かつ24時間以内のrecovery pointを特定
5. AWS Backup から **別 EC2 として** 復元
6. Ansible で復元EC2へOS / アプリ構成を適用し、単体verify
7. staging Target Groupへ復元EC2を一時登録（DNS / Terraform stateは変更しない）
8. ALB smoke test（`/healthz` → Prometheus targets → Grafana ヘルス）

## 5. 計測項目

[docs/drill-template.md](../drill-template.md) の計測表を流用しつつ、本シナリオ向けの
内訳を残す。

| 項目 | 目標 | 実測 |
| --- | --- | --- |
| 検知（Alertmanager から Slack 到達）| 2 分 | _要記録_ |
| 1 次切り分け完了 | 5 分 | _要記録_ |
| 最新 recovery point 特定 | 5 分 | _要記録_ |
| 復元ジョブ開始 → 完了 | 15 分 | _要記録_ |
| 一時Target Group登録とhealthy待機 | 10 分 | _要記録_ |
| Ansible 適用 | 15 分 | _要記録_ |
| smoke test | 5 分 | _要記録_ |
| **RTO 合計** | **60 分** | _要記録_ |

## 6. 安全策

- `terraform/environments/staging`の`terraform plan`出力をSlackに貼り、承認を得てから`apply`
- 復元中はトラフィックを **新 EC2 に切替えない**（旧の DNS / TG はそのまま）
- ALB Target Group の付替前に新 EC2 単体で `/healthz` を確認
- 演習中はdev/prodのTerraform stateを変更せず、復元EC2はstagingの一時resourceとして扱う
- 演習中の異常系は迷わず中断、本番影響を最優先に判断

## 7. 想定発見事項のヒント

- AWS Backup の Restore Job がパラメータ不足で失敗する（IAM、KMS、サブネット ID）
- 復元先 EC2 が古いセキュリティグループに紐付き、ALB から到達できない
- Ansible Vault のパスワードが本人の環境にしかなく、操作役が複数いると詰まる
- スナップ命名がばらばらで最新の特定に時間がかかる → [docs/backup-naming.md](../backup-naming.md) 改訂

## 8. 振り返り

[docs/drill-template.md](../drill-template.md) のフォーマットで
`docs/drills/logs/YYYY-MM-DD-D-2.md` に記録。改善アクションは Issue or PR を起こし、
翌月の SLO レビュー（[docs/roadmap/slo-reviews/](./slo-reviews/)）で進捗を確認する。
