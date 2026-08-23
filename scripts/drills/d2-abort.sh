#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 --source-instance-id i-... --confirm-staging [--restored-instance-id i-...]" >&2
}

SOURCE_INSTANCE_ID=""
RESTORED_INSTANCE_ID=""
CONFIRM_STAGING=false
TF_ENV_DIR="${TF_ENV_DIR:-terraform/environments/staging}"

while (($#)); do
  case "$1" in
    --source-instance-id) SOURCE_INSTANCE_ID="${2:-}"; shift 2 ;;
    --restored-instance-id) RESTORED_INSTANCE_ID="${2:-}"; shift 2 ;;
    --confirm-staging) CONFIRM_STAGING=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ "$CONFIRM_STAGING" != true || ! "$SOURCE_INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]]; then
  usage
  exit 2
fi
if [[ "$TF_ENV_DIR" != "terraform/environments/staging" ]]; then
  echo "Refusing non-staging Terraform root: $TF_ENV_DIR" >&2
  exit 2
fi

terraform -chdir="$TF_ENV_DIR" output -json ec2_instance_ids \
  | jq -e --arg id "$SOURCE_INSTANCE_ID" 'any(.[]; . == $id)' >/dev/null || {
      echo "Refusing source ID that is not in the staging Terraform output" >&2
      exit 2
    }

read -r SOURCE_ENV SOURCE_APP < <(
  aws ec2 describe-instances --instance-ids "$SOURCE_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[Tags[?Key==`Environment`].Value|[0],Tags[?Key==`Application`].Value|[0]]' \
    --output text
)
if [[ "$SOURCE_ENV" != staging || "$SOURCE_APP" != server-monitor ]]; then
  echo "Refusing source without exact staging/server-monitor tags" >&2
  exit 2
fi

TG_ARN=$(terraform -chdir="$TF_ENV_DIR" output -raw target_group_arn)
ALB_HEALTHZ_URL=$(terraform -chdir="$TF_ENV_DIR" output -raw alb_healthz_url)

SOURCE_STATE=$(aws ec2 describe-instances --instance-ids "$SOURCE_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text)
if [[ "$SOURCE_STATE" == stopping ]]; then
  aws ec2 wait instance-stopped --instance-ids "$SOURCE_INSTANCE_ID"
  SOURCE_STATE=stopped
fi
if [[ "$SOURCE_STATE" == stopped ]]; then
  aws ec2 start-instances --instance-ids "$SOURCE_INSTANCE_ID" >/dev/null
fi
aws ec2 wait instance-status-ok --instance-ids "$SOURCE_INSTANCE_ID"
aws elbv2 wait target-in-service --target-group-arn "$TG_ARN" \
  --targets "Id=$SOURCE_INSTANCE_ID,Port=8080"
curl --fail --silent --show-error --max-time 10 "$ALB_HEALTHZ_URL" >/dev/null
echo "D-2 source recovery complete."

# Optional cleanup happens only after service recovery. Missing/invalid restore
# tags cannot prevent the source from being returned to service.
if [[ -n "$RESTORED_INSTANCE_ID" ]]; then
  if [[ ! "$RESTORED_INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]]; then
    echo "Source is healthy; restored instance ID is invalid, so manual cleanup is required." >&2
    exit 2
  fi
  read -r RESTORE_ENV RESTORE_DRILL RESTORE_OWNER < <(
    aws ec2 describe-instances --instance-ids "$RESTORED_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].[Tags[?Key==`Environment`].Value|[0],Tags[?Key==`Drill`].Value|[0],Tags[?Key==`ManagedBy`].Value|[0]]' \
      --output text
  )
  if [[ "$RESTORE_ENV" != staging || "$RESTORE_DRILL" != D-2 || "$RESTORE_OWNER" != aws-backup-restore ]]; then
    echo "Source is healthy; refusing unowned restore cleanup. Review it manually." >&2
    exit 2
  fi
  aws elbv2 deregister-targets --target-group-arn "$TG_ARN" \
    --targets "Id=$RESTORED_INSTANCE_ID,Port=8080"
fi

echo "D-2 abort complete: temporary target deregistered when safely identified."
