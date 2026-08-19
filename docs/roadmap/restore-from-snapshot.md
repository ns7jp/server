# Runbook: スナップショットからの復元（D-2 想定）

ホスト障害（EC2 起動不能 / OS 破損 / EBS 読込不可）から **別 EC2** として復元する
手順。演習シナリオ [D-2 ホスト障害](./D-2-host-failure.md) の正本。

## 1. 発火条件

- Alert: `ServerMonitorUnavailable`、`AlertmanagerDown`、`SLOFastBurnRateAvailability`
  などが **同時または短時間で連続発火**
- ALB の `UnHealthyHostCount` がしきい値を超え、`HTTPCode_ELB_5XX_Count` が継続
- AWS Console / `aws ec2 describe-instance-status` で EC2 が `stopped` / `failed`

## 2. 前提と影響範囲

| 項目 | 内容 |
| --- | --- |
| 対象 | EC2 ホストの完全停止または OS 起動不能 |
| 復元元 | AWS Backup Vault の recovery point（v2.0 `backup` モジュールで日次取得）|
| 復元先 | **新規 EC2**。旧 EC2 はフォレンジック保全のため当面残す |
| 影響 | ダッシュボード / `/metrics` / アラートが復元完了まで停止 |
| RTO 目標 | 60 分（[docs/backup-restore.md](../backup-restore.md)）|
| RPO 目標 | 24 時間（AWS Backup の日次プラン） |

## 3. 初動（5 分以内）

```bash
date
aws sts get-caller-identity   # 自分が正しい account / region か確認

# 状態確認
INSTANCE_ID="<i-xxxxxxxx>"   # docs/aws-architecture.md または terraform output から
aws ec2 describe-instance-status --instance-ids "$INSTANCE_ID" \
  --include-all-instances --output table

# SSM で接続を試す（SSH より早く失敗を返す）
aws ssm start-session --target "$INSTANCE_ID" || echo "SSM 不可"
```

Slack 演習チャンネルへ検知投稿（[docs/incident-comms.md](../incident-comms.md) §2.1）。

| 記録項目 | 内容 |
| --- | --- |
| 検知時刻 | Alertmanager 発火または運用者が気づいた時刻 |
| 影響 | 何が見えなくなっているか、ALB 経由ユーザーへの影響 |
| 直近変更 | 最近の `terraform apply` / `ansible-playbook` / 手動操作 |

## 4. 軽い再起動を試す（5 分）

EBS が読めるなら stop → start で回復する。**まず試す**。

```bash
aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
aws ec2 start-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# 起動後の検証
ALB_DNS=$(cd terraform/environments/prod && terraform output -raw alb_dns_name)
curl -fsS "https://${ALB_DNS}/healthz"
```

復活すればここで終わり（ランブック終了）。**復活しない場合は §5 以降へ**。

## 5. 最新 recovery point の特定（5 分）

AWS Backup のスケジュールは v2.0 の `backup` モジュールで定義済み
（`terraform/modules/backup/`）。タグベース selection で `Application=server-monitor`
の EC2 / EBS が日次でバックアップされる。

```bash
VAULT="server-monitor-prod-vault"   # terraform output backup_vault_name

# 対象 EC2 の最新 recovery point
RESOURCE_ARN=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[InstanceId]' --output text \
  | xargs -I {} echo "arn:aws:ec2:$(aws configure get region):$(aws sts get-caller-identity --query Account --output text):instance/{}")

RECOVERY_POINT_ARN=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT" \
  --by-resource-arn "$RESOURCE_ARN" \
  --query 'RecoveryPoints | sort_by(@,&CreationDate)[-1].RecoveryPointArn' \
  --output text)

echo "最新 recovery point: $RECOVERY_POINT_ARN"
```

EBS のスナップショットを別ルートで使う場合は [docs/backup-naming.md](../backup-naming.md)
の検索コマンドを使う。

## 6. 復元ジョブの開始（15 分）

AWS Backup の `start-restore-job` で **別 EC2** として復元する。**旧 EC2 はそのまま
残し**、復元先のサブネット / SG / IAM プロファイルを指定する。

```bash
# 復元先のメタデータ（terraform output から取得するのが安全）
cd terraform/environments/prod
SUBNET_ID=$(terraform output -json ec2_instance_ids | jq -r 'to_entries[0].value' \
  | xargs -I {} aws ec2 describe-instances --instance-ids {} \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)
SG_ID=$(terraform output -raw ec2_security_group_id 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=server-monitor-prod-ec2-sg" \
    --query 'SecurityGroups[0].GroupId' --output text)
PROFILE_NAME="server-monitor-prod-ec2-profile"
RESTORE_ROLE_ARN=$(terraform output -raw backup_role_arn 2>/dev/null)

# 復元実行（IamInstanceProfileName は AWS Backup の Metadata 仕様に従う）
RESTORE_JOB=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --iam-role-arn "$RESTORE_ROLE_ARN" \
  --metadata "SubnetId=${SUBNET_ID},SecurityGroupIds=${SG_ID},IamInstanceProfileName=${PROFILE_NAME}" \
  --query RestoreJobId --output text)

# 進捗をポーリング
while :; do
  STATUS=$(aws backup describe-restore-job --restore-job-id "$RESTORE_JOB" \
    --query Status --output text)
  echo "$(date -u +%H:%M:%SZ) Restore status: $STATUS"
  case "$STATUS" in
    COMPLETED) break ;;
    FAILED|ABORTED) echo "復元失敗。AWS Console で詳細確認"; exit 1 ;;
  esac
  sleep 30
done

# 復元された EC2 ID
NEW_INSTANCE_ID=$(aws backup describe-restore-job --restore-job-id "$RESTORE_JOB" \
  --query CreatedResourceArn --output text | awk -F/ '{print $NF}')
echo "新 EC2: $NEW_INSTANCE_ID"
```

**メモ**: `start-restore-job` の `metadata` キーは元リソース種別ごとに必須 / 任意が
異なる。EBS だけ復元したい場合は recovery point の `ResourceType` が `EBS` のものを
使い、Volume を作ってから `aws ec2 attach-volume` する。EC2 単位のリカバリーポイント
であれば EC2 が直接立ち上がる。

## 7. Terraform / Ansible の反映（25 分）

復元された EC2 は元の Terraform 管理対象 **ではない** 状態。次のいずれかで取り込む。

| 方針 | 内容 | 推奨ケース |
| --- | --- | --- |
| 構成を最初から再作成 | `terraform taint` して旧 EC2 を作り直し、新 EC2 から AMI を取って起動 | 短期復旧重視で本筋に戻したい |
| 一時的に手動運用 | 新 EC2 で稼働継続させながら、別途 Terraform 化のメンテ枠を取る | 業務時間外、影響を最小化したい |

Terraform 取り込みの例（参考）:

```bash
# 旧 EC2 を state から外す（実体は AWS 側に残す）
cd terraform/environments/prod
terraform state rm 'module.compute.aws_instance.this["ap-northeast-1a"]'

# 新 EC2 を state へ import
terraform import \
  'module.compute.aws_instance.this["ap-northeast-1a"]' \
  "$NEW_INSTANCE_ID"

terraform plan   # 差分 0 を確認してから apply
```

Ansible で構成適用（[docs/deployment-ansible.md](../deployment-ansible.md)）:

```bash
cd ansible
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml --limit "$NEW_INSTANCE_ID"
```

## 8. ALB Target Group の付替（必要な場合）

復元のついでに Target Group 自体を作り直した場合は、Route 53 のエイリアスや ALB の
DNS が変わるため、`docs/aws-architecture.md` を参照しながら以下を更新する。

```bash
# Target Group に新 EC2 を登録
aws elbv2 register-targets \
  --target-group-arn "$(cd terraform/environments/prod && terraform output -raw target_group_arn)" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080"

# ヘルスチェック合格まで待つ
aws elbv2 describe-target-health \
  --target-group-arn "<TG ARN>" --output table
```

## 9. smoke test（5 分）

```bash
curl -fsS "https://${ALB_DNS}/healthz"

# Prometheus targets
curl -fsS "http://127.0.0.1:9090/api/v1/targets?state=active" | jq '.data.activeTargets | length'

# Grafana ヘルス
curl -fsS "http://127.0.0.1:3000/api/health"

# SLO ダッシュボードの probe_success が回復していることを目視
echo "Grafana: Server Monitor SLO dashboard を開く"
```

## 10. 事後対応

1. 演習ログを `docs/drills/logs/YYYY-MM-DD-D-2.md` に作成（[テンプレ](../drill-template.md)）
2. 旧 EC2 の保全期間を決め、フォレンジック資料を取得後に terminate
3. 改善アクションを Issue / PR にして、翌月の SLO レビューでクローズ確認
4. 失敗手順があれば本ランブックを **その場で修正** し PR を作る

## 11. AWS CLI 互換性

本ランブックは AWS CLI v2.x を前提とする。CLI バージョンによっては
`describe-restore-job` のレスポンス形式が異なるため、演習前に `aws --version`
を控え、差分があれば `aws --cli-binary-format`/`--no-cli-pager` 等を併用する。

## 12. 参考

- [AWS Backup ベストプラクティス](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)
- [Google SRE Book — Chapter 26: Data Integrity](https://sre.google/sre-book/data-integrity/)
- 設計書: [docs/backup-restore.md](../backup-restore.md)
- AWS 構成: [docs/aws-architecture.md](../aws-architecture.md)
