# Runbook: スナップショットからの復元（D-2 想定）

ホスト障害（EC2 起動不能 / OS 破損 / EBS 読込不可）から **別 EC2** として復元する
手順。演習シナリオ [D-2 ホスト障害](./D-2-host-failure.md) の正本です。本手順は
`terraform/environments/staging`専用で、dev/prodのstateやhostには適用しません。
以降のコマンドは、明記がない限りrepository rootから実行します。

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
| 操作端末 | Linux / WSL、Terraform、AWS CLI v2、`jq`、`curl`、Ansible、`session-manager-plugin` |
| SSM転送 | EC2と同じregionの専用S3 bucket。`inventory/aws_ec2.yml`へ実名を設定し、操作roleの利用権限を確認 |

開始前に、AWS account / region、`backend.hcl` / `terraform.tfvars`、通知先、ALB許可CIDR、
SSM転送bucketがstaging専用または演習での利用を承認済みであることを確認します。これらの実値や
認証情報はGitへ保存しません。

### 演習の障害注入前にrecovery pointを用意する

実障害中に新規backupを取る手順ではありません。D-2演習では障害注入前に、日次planが作成した
`COMPLETED` recovery pointを確認します。日次schedule自体のRPOを証明する場合はstagingを少なくとも
1回のschedule完了まで維持します。短時間確認でon-demand backupを使うかは、次のpreflight内の
`USE_ON_DEMAND_BACKUP`で選び、その場合は「日次scheduleのRPO検証ではない」と結果票へ明記します。
source baselineの合格前にはbackupを開始しません。

### 障害注入前のfail-closed preflight

次をすべて通してから停止します。controllerのPython依存はsystem Pythonへ混在させず、専用venvへ
固定します。Vault実値とpassword fileはGit管理外で事前準備し、作り方は
[Ansibleデプロイ手順](../deployment-ansible.md) §3に従います。

```bash
set -Eeuo pipefail
TF_ENV_DIR="terraform/environments/staging"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
: "${D2_DRILL_ID:?preflight前に一意な演習IDを設定する}"
[[ "$D2_DRILL_ID" =~ ^[A-Za-z0-9_-]{8,40}$ ]]
SSM_TRANSFER_BUCKET=$(terraform -chdir="$TF_ENV_DIR" output -raw ssm_transfer_bucket_name)
INSTANCE_ID=$(terraform -chdir="$TF_ENV_DIR" output -json ec2_instance_ids | jq -r 'to_entries[0].value')
test -n "$SSM_TRANSFER_BUCKET" && test -n "$INSTANCE_ID"

(
  cd ansible
  python3 -m venv .venv
  . .venv/bin/activate
  python -m pip install --requirement controller-requirements.txt
  ansible-galaxy collection install --requirements-file requirements.yml
  session-manager-plugin --version
  python -c 'import boto3, botocore'

  test -f inventory/group_vars/monitor/vault.yml
  test -f .vault_pass
  export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"
  ansible-vault view inventory/group_vars/monitor/vault.yml >/dev/null

  cp inventory/aws_ec2.yml.example inventory/aws_ec2.yml
  sed -i 's/<REPLACE-WITH-ENVIRONMENT>/staging/' inventory/aws_ec2.yml
  INVENTORY_SOURCE=$(ansible-inventory -i inventory/aws_ec2.yml --host "$INSTANCE_ID")
  jq -e --arg id "$INSTANCE_ID" \
    'type == "object" and length > 0 and .ansible_aws_ssm_instance_id == $id' \
    <<<"$INVENTORY_SOURCE" >/dev/null
  ansible -i inventory/aws_ec2.yml "$INSTANCE_ID" -m ansible.builtin.ping \
    -e ansible_connection=amazon.aws.aws_ssm \
    -e "ansible_aws_ssm_bucket_name=$SSM_TRANSFER_BUCKET" \
    -e "ansible_aws_ssm_region=$AWS_REGION"
  ansible-playbook -i inventory/aws_ec2.yml \
    -e ansible_connection=amazon.aws.aws_ssm \
    -e "ansible_aws_ssm_bucket_name=$SSM_TRANSFER_BUCKET" \
    -e "ansible_aws_ssm_region=$AWS_REGION" \
    playbooks/verify.yml --limit "$INSTANCE_ID"
)

# controllerが短命bucketを実際に読み書き・削除できることを確認する。
SSM_BUCKET_VERSIONING=$(aws s3api get-bucket-versioning \
  --bucket "$SSM_TRANSFER_BUCKET" --query Status --output text)
[[ -z "$SSM_BUCKET_VERSIONING" \
   || "$SSM_BUCKET_VERSIONING" == "None" \
   || "$SSM_BUCKET_VERSIONING" == "Suspended" ]]
PREFLIGHT_OBJECT="preflight/$(date -u +%Y%m%dT%H%M%SZ)-$$"
PREFLIGHT_FILE=$(mktemp)
printf 'D-2 preflight\n' >"$PREFLIGHT_FILE"
aws s3api put-object --bucket "$SSM_TRANSFER_BUCKET" --key "$PREFLIGHT_OBJECT" \
  --body "$PREFLIGHT_FILE" >/dev/null
aws s3api head-object --bucket "$SSM_TRANSFER_BUCKET" --key "$PREFLIGHT_OBJECT" >/dev/null
aws s3api delete-object --bucket "$SSM_TRANSFER_BUCKET" --key "$PREFLIGHT_OBJECT" >/dev/null
if aws s3api head-object --bucket "$SSM_TRANSFER_BUCKET" --key "$PREFLIGHT_OBJECT" \
  >/dev/null 2>&1; then
  echo "SSM transfer object still exists after delete"; exit 1
fi
rm -f "$PREFLIGHT_FILE"

SOURCE_SSM_STATUS=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text)
test "$SOURCE_SSM_STATUS" = "Online"

TG_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw target_group_arn)
ALB_HEALTHZ_URL=$(terraform -chdir="$TF_ENV_DIR" output -raw alb_healthz_url)
aws elbv2 wait target-in-service --target-group-arn "$TG_ARN" \
  --targets "Id=$INSTANCE_ID,Port=8080"
curl --fail --silent --show-error --max-time 10 "$ALB_HEALTHZ_URL" >/dev/null

# 停止前にrestore可能性、24時間以内、日次plan provenanceを確定し、同じARNを保存する。
VAULT=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_vault_name)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
RESOURCE_ARN="arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:instance/${INSTANCE_ID}"
EXPECTED_BACKUP_PLAN_ID=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_plan_id)

USE_ON_DEMAND_BACKUP="${USE_ON_DEMAND_BACKUP:-0}"
[[ "$USE_ON_DEMAND_BACKUP" == "0" || "$USE_ON_DEMAND_BACKUP" == "1" ]]
if [[ "$USE_ON_DEMAND_BACKUP" == "1" ]]; then
  BACKUP_ROLE_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_role_arn)
  mkdir -p .artifacts
  BACKUP_TOKEN_FILE=".artifacts/d2-backup-token-${D2_DRILL_ID}"
  if [[ ! -s "$BACKUP_TOKEN_FILE" ]]; then
    umask 077
    openssl rand -hex 16 >"$BACKUP_TOKEN_FILE"
  fi
  BACKUP_IDEMPOTENCY_TOKEN=$(tr -d '\r\n' <"$BACKUP_TOKEN_FILE")
  [[ "$BACKUP_IDEMPOTENCY_TOKEN" =~ ^[0-9a-f]{32}$ ]]
  BACKUP_JOB_ID=$(aws backup start-backup-job \
    --backup-vault-name "$VAULT" \
    --resource-arn "$RESOURCE_ARN" \
    --iam-role-arn "$BACKUP_ROLE_ARN" \
    --recovery-point-tags Drill=D-2,Environment=staging \
    --idempotency-token "$BACKUP_IDEMPOTENCY_TOKEN" \
    --query BackupJobId --output text)
  BACKUP_TIMEOUT_SECONDS="${BACKUP_TIMEOUT_SECONDS:-3600}"
  BACKUP_DEADLINE=$(( $(date -u +%s) + BACKUP_TIMEOUT_SECONDS ))
  while :; do
    BACKUP_STATUS=$(aws backup describe-backup-job --backup-job-id "$BACKUP_JOB_ID" \
      --query State --output text)
    echo "$(date -u +%H:%M:%SZ) Backup status: $BACKUP_STATUS"
    case "$BACKUP_STATUS" in
      COMPLETED) break ;;
      FAILED|ABORTED|EXPIRED|PARTIAL) echo "backup job失敗: $BACKUP_STATUS"; exit 1 ;;
    esac
    if (( $(date -u +%s) >= BACKUP_DEADLINE )); then
      echo "backup job timeout (${BACKUP_TIMEOUT_SECONDS}s): $BACKUP_JOB_ID"; exit 1
    fi
    sleep 30
  done
fi

REQUIRE_SCHEDULED_RECOVERY_POINT="${REQUIRE_SCHEDULED_RECOVERY_POINT:-0}"
[[ "$REQUIRE_SCHEDULED_RECOVERY_POINT" == "0" \
   || "$REQUIRE_SCHEDULED_RECOVERY_POINT" == "1" ]]
RECOVERY_POINT_FILTER_ARGS=()
if [[ "$REQUIRE_SCHEDULED_RECOVERY_POINT" == "1" ]]; then
  RECOVERY_POINT_FILTER_ARGS+=(--by-backup-plan-id "$EXPECTED_BACKUP_PLAN_ID")
fi
RECOVERY_POINT_JSON=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$VAULT" --by-resource-arn "$RESOURCE_ARN" \
  "${RECOVERY_POINT_FILTER_ARGS[@]}" --output json \
  | jq -c '[.RecoveryPoints[]
      | select(.Status == "COMPLETED" or .Status == "AVAILABLE")]
      | sort_by(.CreationDate) | last // empty')
RECOVERY_POINT_ARN=$(jq -r '.RecoveryPointArn // empty' <<<"$RECOVERY_POINT_JSON")
RECOVERY_POINT_CREATED=$(jq -r '.CreationDate // empty' <<<"$RECOVERY_POINT_JSON")
RECOVERY_POINT_PLAN_ID=$(jq -r '.CreatedBy.BackupPlanId // empty' <<<"$RECOVERY_POINT_JSON")
test -n "$RECOVERY_POINT_ARN" && test -n "$RECOVERY_POINT_CREATED"
RECOVERY_POINT_AGE_SECONDS=$(( $(date -u +%s) - $(date -u -d "$RECOVERY_POINT_CREATED" +%s) ))
(( RECOVERY_POINT_AGE_SECONDS >= 0 && RECOVERY_POINT_AGE_SECONDS <= 86400 ))
if [[ "$REQUIRE_SCHEDULED_RECOVERY_POINT" == "1" ]]; then
  test "$RECOVERY_POINT_PLAN_ID" = "$EXPECTED_BACKUP_PLAN_ID"
fi
mkdir -p .artifacts
printf '%s\n' "$RECOVERY_POINT_JSON" >.artifacts/d2-recovery-point.json
```

on-demand backupを使った場合は、その成功がBackup roleへの`iam:PassRole`も実際に検証します。
日次recovery pointを使う場合は、停止前に操作roleが同じBackup roleをPassRoleできることをIAM担当者と
確認し、承認記録を結果票へ残します。1項目でも失敗した場合は停止せず、`NOT RUN`として終了します。

### 中断・rollbackコマンド（停止前に確認）

以降で失敗またはtimeoutになったら、別shellから次を実行します。sourceを再起動し、指定した一時restore
だけをTarget Groupから外します。terminateは自動実行しません。exact staging tagと明示確認が一致しない
resourceには作用しません。

```bash
set -Eeuo pipefail
RESTORE_ARGS=()
if [[ -n "${NEW_INSTANCE_ID:-}" ]]; then
  RESTORE_ARGS=(--restored-instance-id "$NEW_INSTANCE_ID")
fi
scripts/drills/d2-abort.sh \
  --source-instance-id "$INSTANCE_ID" \
  "${RESTORE_ARGS[@]}" \
  --confirm-staging
```

このコマンドが成功し、sourceのALB `/healthz`が戻るまで演習を続行しません。

## 2.1 D-2演習だけの安全な障害注入

実障害では§3から§4へ進みます。復元経路を測るD-2演習では、上記の利用可能なrecovery pointを
確保した後に、**stagingの復元元EC2だけ**を停止してそのまま保持し、§4の軽い再起動を省略します。
ディスク破壊、volume detach、OS設定破壊は行いません。これは「EC2停止を用いた復元手順の
シミュレーション」であり、OS/EBS破損そのものを再現・証明する試験ではありません。

```bash
set -Eeuo pipefail

d2_abort_on_error() {
  local status=$?
  trap - ERR INT TERM
  local restore_args=()
  if [[ -n "${NEW_INSTANCE_ID:-}" ]]; then
    restore_args=(--restored-instance-id "$NEW_INSTANCE_ID")
  fi
  scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" \
    "${restore_args[@]}" --confirm-staging || true
  exit "$status"
}
trap d2_abort_on_error ERR INT TERM

DRILL_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
echo "D-2 drill started: $DRILL_STARTED_AT; source kept stopped: $INSTANCE_ID"
```

RTOは停止操作の開始時刻から、復元EC2をTarget Groupへ登録してALB `/healthz` が成功した時刻までを
測ります。異常時は復元EC2を登録せず、復元元EC2をstartして中断します。

## 3. 初動（5 分以内）

```bash
set -Eeuo pipefail
date
aws sts get-caller-identity   # 自分が正しい account / region か確認
TF_ENV_DIR="terraform/environments/staging"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"

# 状態確認
INSTANCE_ID=$(terraform -chdir="$TF_ENV_DIR" output -json ec2_instance_ids \
  | jq -r 'to_entries[0].value')
test -n "$INSTANCE_ID" && test "$INSTANCE_ID" != "null"
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
set -Eeuo pipefail
aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
aws ec2 start-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# 起動後は、EC2 status・対象target・ALB応答を5分の期限内でそろえて確認する。
RESTART_DEADLINE=$(( $(date -u +%s) + 300 ))
RESTART_RECOVERED=0
TG_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw target_group_arn)
ALB_HEALTHZ_URL=$(terraform -chdir="$TF_ENV_DIR" output -raw alb_healthz_url)
while (( $(date -u +%s) < RESTART_DEADLINE )); do
  INSTANCE_STATUS=$(aws ec2 describe-instance-status --include-all-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
    --output text)
  TARGET_STATUS=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --targets "Id=$INSTANCE_ID,Port=8080" \
    --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
  if [[ "$INSTANCE_STATUS" == $'ok\tok' \
     && "$TARGET_STATUS" == "healthy" ]] \
     && curl --fail --silent --show-error --max-time 10 "$ALB_HEALTHZ_URL" >/dev/null; then
    RESTART_RECOVERED=1
    break
  fi
  sleep 10
done

if [[ "$RESTART_RECOVERED" == "1" ]]; then
  echo "source instance recovered; stop the runbook here"
else
  echo "source instance did not recover within 5 minutes; continue to section 5"
fi
```

復活すればここで終わり（ランブック終了）。**復活しない場合は §5 以降へ**。

## 5. preflightで固定したrecovery pointの再確認（5 分）

AWS Backup のスケジュールは v2.0 の `backup` モジュールで定義済み
（`terraform/modules/backup/`）。各environmentの明示的なEC2 ARNだけをselectionし、attached EBSを
同じEC2 backupへ含めます。停止後に別のrecovery pointを選び直さず、preflightで保存したARNを使います。

```bash
set -Eeuo pipefail
TF_ENV_DIR="terraform/environments/staging"
VAULT=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_vault_name)
test -s .artifacts/d2-recovery-point.json
RECOVERY_POINT_JSON=$(<.artifacts/d2-recovery-point.json)
RECOVERY_POINT_ARN=$(jq -r '.RecoveryPointArn // empty' <<<"$RECOVERY_POINT_JSON")
RECOVERY_POINT_CREATED=$(jq -r '.CreationDate // empty' <<<"$RECOVERY_POINT_JSON")
RECOVERY_POINT_PLAN_ID=$(jq -r '.CreatedBy.BackupPlanId // empty' <<<"$RECOVERY_POINT_JSON")
EXPECTED_BACKUP_PLAN_ID=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_plan_id)

echo "最新 recovery point: $RECOVERY_POINT_ARN"
test -n "$RECOVERY_POINT_ARN"
test -n "$RECOVERY_POINT_CREATED"
RECOVERY_POINT_CREATED_EPOCH=$(date -u -d "$RECOVERY_POINT_CREATED" +%s)
RECOVERY_POINT_AGE_SECONDS=$(( $(date -u +%s) - RECOVERY_POINT_CREATED_EPOCH ))
if (( RECOVERY_POINT_AGE_SECONDS < 0 || RECOVERY_POINT_AGE_SECONDS > 86400 )); then
  echo "24時間以内の利用可能なrecovery pointではありません: age=${RECOVERY_POINT_AGE_SECONDS}s"
  exit 1
fi
if [[ "${REQUIRE_SCHEDULED_RECOVERY_POINT:-0}" == "1" \
   && "$RECOVERY_POINT_PLAN_ID" != "$EXPECTED_BACKUP_PLAN_ID" ]]; then
  echo "現行staging日次planのRPO証跡ではありません"; exit 1
fi
if [[ "$RECOVERY_POINT_PLAN_ID" != "$EXPECTED_BACKUP_PLAN_ID" ]]; then
  echo "source=on-demand/other-plan: 日次scheduleのRPO検証として記録しない"
else
  echo "source=current staging scheduled plan: $RECOVERY_POINT_PLAN_ID"
fi
aws backup describe-recovery-point \
  --backup-vault-name "$VAULT" --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --query '{Status:Status,Created:CreationDate,Completed:CompletionDate,Resource:ResourceArn}' \
  --output json | tee .artifacts/d2-recovery-point-recheck.json
RECOVERY_POINT_STATUS=$(jq -r '.Status' .artifacts/d2-recovery-point-recheck.json)
[[ "$RECOVERY_POINT_STATUS" == "COMPLETED" || "$RECOVERY_POINT_STATUS" == "AVAILABLE" ]]
```

EBS のスナップショットを別ルートで使う場合は [docs/backup-naming.md](../backup-naming.md)
の検索コマンドを使う。

## 6. 復元ジョブの開始（15 分）

AWS Backup の `start-restore-job` で **別 EC2** として復元する。**旧 EC2 はそのまま
残し**、復元先のサブネット / SG / IAM プロファイルを指定する。

```bash
set -Eeuo pipefail
# 復元先の値はstaging root moduleの明示outputだけから取得する。
TF_ENV_DIR="terraform/environments/staging"
SUBNET_ID=$(terraform -chdir="$TF_ENV_DIR" output -json private_subnet_ids \
  | jq -r 'to_entries[0].value')
SG_ID=$(terraform -chdir="$TF_ENV_DIR" output -raw ec2_security_group_id)
PROFILE_NAME=$(terraform -chdir="$TF_ENV_DIR" output -raw ec2_instance_profile_name)
RESTORE_ROLE_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw backup_role_arn)

# recovery point固有のmetadataを正本にし、復元先だけを安全なstaging値へ上書きする。
RESTORE_METADATA=$(aws backup get-recovery-point-restore-metadata \
  --backup-vault-name "$VAULT" \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --query RestoreMetadata --output json)
RESTORE_METADATA=$(jq \
  --arg subnet "$SUBNET_ID" \
  --arg security_groups "$(jq -cn --arg sg "$SG_ID" '[$sg]')" \
  --arg profile "$PROFILE_NAME" \
  'del(
     .SubnetId, .subnetId,
     .SecurityGroupIds, .securityGroupIds,
     .NetworkInterfaces, .networkInterfaces,
     .Placement, .placement,
     .IamInstanceProfileName, .iamInstanceProfileName,
     .RequireIMDSv2, .requireImdsV2
   )
   | .SubnetId = $subnet
   | .SecurityGroupIds = $security_groups
   | .IamInstanceProfileName = $profile
   | .RequireIMDSv2 = "true"' <<<"$RESTORE_METADATA")

# retryしても同じrestore jobを再利用するようtokenをGit管理外へ永続化する。
mkdir -p .artifacts
RECOVERY_POINT_KEY=$(printf '%s' "$RECOVERY_POINT_ARN" | sha256sum | cut -c1-12)
RESTORE_TOKEN_FILE="${RESTORE_TOKEN_FILE:-.artifacts/d2-restore-token-${D2_DRILL_ID}-${RECOVERY_POINT_KEY}}"
if [[ ! -s "$RESTORE_TOKEN_FILE" ]]; then
  umask 077
  openssl rand -hex 16 >"$RESTORE_TOKEN_FILE"
fi
RESTORE_IDEMPOTENCY_TOKEN=$(tr -d '\r\n' <"$RESTORE_TOKEN_FILE")
[[ "$RESTORE_IDEMPOTENCY_TOKEN" =~ ^[0-9a-f]{32}$ ]]

RESTORE_JOB=$(aws backup start-restore-job \
  --recovery-point-arn "$RECOVERY_POINT_ARN" \
  --iam-role-arn "$RESTORE_ROLE_ARN" \
  --metadata "$RESTORE_METADATA" \
  --idempotency-token "$RESTORE_IDEMPOTENCY_TOKEN" \
  --query RestoreJobId --output text)

# 進捗をポーリング
RESTORE_TIMEOUT_SECONDS="${RESTORE_TIMEOUT_SECONDS:-3600}"
RESTORE_DEADLINE=$(( $(date -u +%s) + RESTORE_TIMEOUT_SECONDS ))
while :; do
  STATUS=$(aws backup describe-restore-job --restore-job-id "$RESTORE_JOB" \
    --query Status --output text)
  echo "$(date -u +%H:%M:%SZ) Restore status: $STATUS"
  case "$STATUS" in
    COMPLETED) break ;;
    FAILED|ABORTED|PARTIAL)
      echo "復元失敗: $STATUS。sourceをrollbackする"
      scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" --confirm-staging
      exit 1 ;;
  esac
  if (( $(date -u +%s) >= RESTORE_DEADLINE )); then
    echo "restore job timeout (${RESTORE_TIMEOUT_SECONDS}s): $RESTORE_JOB"
    scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" --confirm-staging
    exit 1
  fi
  sleep 30
done

# 復元された EC2 ID
NEW_INSTANCE_ID=$(aws backup describe-restore-job --restore-job-id "$RESTORE_JOB" \
  --query CreatedResourceArn --output text | awk -F/ '{print $NF}')
echo "新 EC2: $NEW_INSTANCE_ID"
test -n "$NEW_INSTANCE_ID" && test "$NEW_INSTANCE_ID" != "None"

# sourceのTerraform所有tagをコピーせず、一時restoreの所有権とcleanup検索キーを明示する。
VPC_CIDR=$(terraform -chdir="$TF_ENV_DIR" output -raw vpc_cidr)
aws ec2 create-tags --resources "$NEW_INSTANCE_ID" --tags \
  Key=Name,Value="server-monitor-staging-d2-${NEW_INSTANCE_ID}" \
  Key=Application,Value=server-monitor \
  Key=Environment,Value=staging \
  Key=AnsibleHost,Value=true \
  Key=AlbHealthCheckSourceCidr,Value="$VPC_CIDR" \
  Key=ManagedBy,Value=aws-backup-restore \
  Key=Drill,Value=D-2 \
  Key=RestoreJobId,Value="$RESTORE_JOB" \
  Key=SourceInstanceId,Value="$INSTANCE_ID"

# restoreにより作られた全volumeも同じcleanup keyで所有管理する。
RESTORED_VOLUME_IDS=$(aws ec2 describe-instances --instance-ids "$NEW_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[].Ebs.VolumeId' --output text)
test -n "$RESTORED_VOLUME_IDS" && test "$RESTORED_VOLUME_IDS" != "None"
aws ec2 create-tags --resources $RESTORED_VOLUME_IDS --tags \
  Key=Environment,Value=staging \
  Key=ManagedBy,Value=aws-backup-restore \
  Key=Drill,Value=D-2 \
  Key=RestoreJobId,Value="$RESTORE_JOB" \
  Key=SourceInstanceId,Value="$INSTANCE_ID"

if ! aws ec2 wait instance-status-ok --instance-ids "$NEW_INSTANCE_ID"; then
  scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" \
    --restored-instance-id "$NEW_INSTANCE_ID" --confirm-staging
  exit 1
fi
SSM_DEADLINE=$(( $(date -u +%s) + 600 ))
while :; do
  NEW_SSM_STATUS=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$NEW_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text)
  [[ "$NEW_SSM_STATUS" == "Online" ]] && break
  if (( $(date -u +%s) >= SSM_DEADLINE )); then
    scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" \
      --restored-instance-id "$NEW_INSTANCE_ID" --confirm-staging
    exit 1
  fi
  sleep 15
done
```

**メモ**: `start-restore-job` の `metadata` キーは元リソース種別ごとに必須 / 任意が
異なる。EBS だけ復元したい場合は recovery point の `ResourceType` が `EBS` のものを
使い、Volume を作ってから `aws ec2 attach-volume` する。EC2 単位のリカバリーポイント
であれば EC2 が直接立ち上がる。

## 7. 一時復元hostへのAnsible適用（25 分）

復元EC2を既存Terraform resourceへ`state rm/import`しません。演習中はstaging stateを不変に保ち、
復元EC2を一時hostとして検証します。恒久的なstate取り込みはD-2の時間計測外で、別changeとして
plan、review、rollbackを用意して実施します。

preflightで作成したGit管理外inventory、専用venv、Vault password file、Terraformが作成したSSM
transfer bucketを再利用します。inventoryはinstance IDをhostnameの第一候補にし、host変数が空でない
ことをassertしてから、復元hostだけを`--limit`します。

```bash
set -Eeuo pipefail
SSM_TRANSFER_BUCKET=$(terraform -chdir=terraform/environments/staging output -raw ssm_transfer_bucket_name)
(
  trap - ERR INT TERM
  set -Eeuo pipefail
  cd ansible
  . .venv/bin/activate
  export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"
  ansible-inventory -i inventory/aws_ec2.yml --graph
  INVENTORY_RESTORE=$(ansible-inventory -i inventory/aws_ec2.yml --host "$NEW_INSTANCE_ID")
  jq -e --arg id "$NEW_INSTANCE_ID" \
    'type == "object" and length > 0 and .ansible_aws_ssm_instance_id == $id' \
    <<<"$INVENTORY_RESTORE" >/dev/null
  ansible-playbook -i inventory/aws_ec2.yml \
    -e ansible_connection=amazon.aws.aws_ssm \
    -e "ansible_aws_ssm_bucket_name=$SSM_TRANSFER_BUCKET" \
    -e "ansible_aws_ssm_region=$AWS_REGION" \
    playbooks/site.yml --limit "$NEW_INSTANCE_ID"
  ansible-playbook -i inventory/aws_ec2.yml \
    -e ansible_connection=amazon.aws.aws_ssm \
    -e "ansible_aws_ssm_bucket_name=$SSM_TRANSFER_BUCKET" \
    -e "ansible_aws_ssm_region=$AWS_REGION" \
    playbooks/verify.yml --limit "$NEW_INSTANCE_ID"
)
```

## 8. ALB Target Group での一時検証（D-2 PASSに必須）

§7の単体検証に合格した後、既存staging Target Groupへ復元EC2を一時登録してALB経由を
確認します。dev/prodのTarget GroupやDNSは変更しません。ここを省略した結果はrestore-onlyの
`PARTIAL`であり、D-2/RTOのPASSにしません。失敗時は中断scriptでsourceへrollbackします。

```bash
set -Eeuo pipefail
# Target Group に新 EC2 を登録
aws elbv2 register-targets \
  --target-group-arn "$(terraform -chdir=terraform/environments/staging output -raw target_group_arn)" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080"

# ヘルスチェック合格まで待つ
if ! aws elbv2 wait target-in-service \
  --target-group-arn "$(terraform -chdir=terraform/environments/staging output -raw target_group_arn)" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080"; then
  scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" \
    --restored-instance-id "$NEW_INSTANCE_ID" --confirm-staging
  exit 1
fi
aws elbv2 describe-target-health \
  --target-group-arn "$(terraform -chdir=terraform/environments/staging output -raw target_group_arn)" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080" --output table
```

## 9. smoke test（5 分）

```bash
set -Eeuo pipefail
ALB_HEALTHZ_URL=$(terraform -chdir=terraform/environments/staging output -raw alb_healthz_url)
if ! curl -fsS "$ALB_HEALTHZ_URL"; then
  scripts/drills/d2-abort.sh --source-instance-id "$INSTANCE_ID" \
    --restored-instance-id "$NEW_INSTANCE_ID" --confirm-staging
  exit 1
fi
(
  trap - ERR INT TERM
  set -Eeuo pipefail
  cd ansible
  . .venv/bin/activate
  export ANSIBLE_VAULT_PASSWORD_FILE="$PWD/.vault_pass"
  ansible-playbook -i inventory/aws_ec2.yml \
    -e ansible_connection=amazon.aws.aws_ssm \
    -e "ansible_aws_ssm_bucket_name=$SSM_TRANSFER_BUCKET" \
    -e "ansible_aws_ssm_region=$AWS_REGION" \
    playbooks/verify.yml --limit "$NEW_INSTANCE_ID"
)
# RTOを機械計算し、目標超過も含めてGit管理外artifactへ保存する。
DRILL_RECOVERED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DRILL_STARTED_EPOCH=$(date -u -d "$DRILL_STARTED_AT" +%s)
DRILL_RECOVERED_EPOCH=$(date -u -d "$DRILL_RECOVERED_AT" +%s)
RTO_SECONDS=$(( DRILL_RECOVERED_EPOCH - DRILL_STARTED_EPOCH ))
RTO_RESULT=PASS
(( RTO_SECONDS <= 3600 )) || RTO_RESULT=FAIL
mkdir -p .artifacts
jq -n \
  --arg started "$DRILL_STARTED_AT" \
  --arg recovered "$DRILL_RECOVERED_AT" \
  --arg result "$RTO_RESULT" \
  --argjson seconds "$RTO_SECONDS" \
  '{started_at:$started,recovered_at:$recovered,rto_seconds:$seconds,target_seconds:3600,result:$result}' \
  | tee .artifacts/d2-rto.json
# service復旧とRTO計測点まで到達。最終PASS/FAILはartifactと全checkを集計して判定する。
# 以後は承認済みcleanupで、source auto-rollbackは解除する。
trap - ERR INT TERM
```

## 10. 事後対応

1. 演習ログを `docs/drills/logs/YYYY-MM-DD-D-2.md` に作成（[テンプレ](../drill-template.md)）
2. 復元EC2をTarget Groupからderegisterし、証跡確認後に承認を得てterminateする（下記）
3. staging root moduleのdestroy planをreview・承認して適用し、残存resourceを確認する（下記）
4. 改善アクションを Issue / PR にして、翌月の SLO レビューでクローズ確認
5. 失敗手順があれば本ランブックを **その場で修正** し PR を作る

```bash
set -Eeuo pipefail
TF_ENV_DIR="terraform/environments/staging"
TG_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw target_group_arn)

# D-2で作った一時EC2だけを対象にする。5つの所有tagとIDを機械確認してから承認を得る。
test "$NEW_INSTANCE_ID" != "$INSTANCE_ID"
RESTORED_INSTANCE_JSON=$(aws ec2 describe-instances --instance-ids "$NEW_INSTANCE_ID" --output json)
jq -e --arg id "$NEW_INSTANCE_ID" --arg job "$RESTORE_JOB" --arg source "$INSTANCE_ID" '
  [.Reservations[].Instances[]
   | select(.InstanceId == $id)
   | (.Tags // [] | map({key: .Key, value: .Value}) | from_entries) as $tags
   | select(
       $tags.Environment == "staging"
       and $tags.Drill == "D-2"
       and $tags.ManagedBy == "aws-backup-restore"
       and $tags.RestoreJobId == $job
       and $tags.SourceInstanceId == $source
     )]
  | length == 1' <<<"$RESTORED_INSTANCE_JSON" >/dev/null
aws ec2 describe-instances --instance-ids "$NEW_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].{Id:InstanceId,State:State.Name,Tags:Tags}' --output table
aws ec2 describe-instances --instance-ids "$NEW_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[].{Device:DeviceName,Volume:Ebs.VolumeId,DeleteOnTermination:Ebs.DeleteOnTermination}' \
  --output json | tee .artifacts/d2-restored-volume-map.json
RESTORED_VOLUME_IDS=$(jq -r '.[].Volume' .artifacts/d2-restored-volume-map.json)
test -n "$RESTORED_VOLUME_IDS"

aws elbv2 deregister-targets --target-group-arn "$TG_ARN" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080"
aws elbv2 wait target-deregistered --target-group-arn "$TG_ARN" \
  --targets "Id=$NEW_INSTANCE_ID,Port=8080"
# 承認後のみ実行
aws ec2 terminate-instances --instance-ids "$NEW_INSTANCE_ID"
aws ec2 wait instance-terminated --instance-ids "$NEW_INSTANCE_ID"

# DeleteOnTermination=false等で残ったvolumeは、保存済みIDと5つのtagが一致する場合だけ削除する。
for VOLUME_ID in $RESTORED_VOLUME_IDS; do
  VOLUME_JSON=$(aws ec2 describe-volumes --volume-ids "$VOLUME_ID" --output json 2>/dev/null || true)
  [[ -z "$VOLUME_JSON" ]] && continue
  jq -e --arg id "$VOLUME_ID" --arg job "$RESTORE_JOB" --arg source "$INSTANCE_ID" '
    [.Volumes[]
     | select(.VolumeId == $id and .State == "available")
     | (.Tags // [] | map({key: .Key, value: .Value}) | from_entries) as $tags
     | select(
         $tags.Environment == "staging"
         and $tags.Drill == "D-2"
         and $tags.ManagedBy == "aws-backup-restore"
         and $tags.RestoreJobId == $job
         and $tags.SourceInstanceId == $source
       )]
    | length == 1' <<<"$VOLUME_JSON" >/dev/null
  # 承認後のみ実行
  aws ec2 delete-volume --volume-id "$VOLUME_ID"
  aws ec2 wait volume-deleted --volume-ids "$VOLUME_ID"
done

# destroy対象をreviewし、承認後に保存済みplanだけを適用する。
terraform -chdir="$TF_ENV_DIR" plan -destroy -var-file=terraform.tfvars -out=destroy.tfplan
terraform -chdir="$TF_ENV_DIR" show destroy.tfplan
# 承認後のみ実行
terraform -chdir="$TF_ENV_DIR" apply destroy.tfplan
```

AWS Backup Vault内のrecovery point / underlying snapshotは手動削除せず、staging Vaultの承認済み
destroyへ委ねます。一時EC2の全volumeは上記の保存済みmappingと所有tagで照合し、削除完了後に
KMS keyを含むTerraform destroyへ進みます。所有を証明できないresourceは削除せず調査します。
KMS keyは`deletion_window_in_days = 7`のため、destroy直後は`PendingDeletion`が正常です。
Cost Explorerは反映遅延があるため、翌日にもstaging tagとrestore artifactの費用を再確認します。

## 11. AWS CLI 互換性

本ランブックは AWS CLI v2.x を前提とする。CLI バージョンによっては
`describe-restore-job` のレスポンス形式が異なるため、演習前に `aws --version`
を控え、差分があれば `aws --cli-binary-format`/`--no-cli-pager` 等を併用する。

## 12. 参考

- [AWS Backup ベストプラクティス](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)
- [Google SRE Book — Chapter 26: Data Integrity](https://sre.google/sre-book/data-integrity/)
- 設計書: [docs/backup-restore.md](../backup-restore.md)
- AWS 構成: [docs/aws-architecture.md](../aws-architecture.md)
