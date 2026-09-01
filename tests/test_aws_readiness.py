import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def role_tasks(role: str) -> str:
    """ロールの tasks/ 配下をまとめて 1 本のテキストとして返す。

    common ロールを OS ファミリーごとのファイルへ分割したため、
    main.yml だけを見ても firewall 変数の定義箇所を検査できない。
    """
    tasks_dir = ROOT / "ansible" / "roles" / role / "tasks"
    return "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(tasks_dir.glob("*.yml"))
    )


def test_alb_ingress_matches_the_active_listener() -> None:
    alb = text("terraform/modules/alb/main.tf")
    prod_variables = text("terraform/environments/prod/variables.tf")

    assert "client_listener_port = local.use_https ? 443 : 80" in alb
    assert "from_port         = local.client_listener_port" in alb
    assert "to_port           = local.client_listener_port" in alb
    assert 'count = local.use_https ? 1 : 0' in alb
    assert 'for_each = local.use_https ? [] : [1]' in alb
    assert 'length(var.certificate_arn) > 0' in prod_variables


def test_alb_access_log_prefix_matches_bucket_policy_path() -> None:
    alb = text("terraform/modules/alb/main.tf")
    assert "prefix  = local.name" in alb
    assert (
        'Resource = "${aws_s3_bucket.access_logs.arn}/${local.name}/AWSLogs/'
        '${data.aws_caller_identity.current.account_id}/*"'
    ) in alb
    assert 'Service = "logdelivery.elasticloadbalancing.amazonaws.com"' in alb


def test_cloudwatch_target_group_dimension_keeps_required_prefix() -> None:
    outputs = text("terraform/modules/alb/outputs.tf")
    assert 'output "target_group_arn_suffix"' in outputs
    assert "aws_lb_target_group.app.arn_suffix" in outputs
    for environment in ("dev", "staging", "prod"):
        main = text(f"terraform/environments/{environment}/main.tf")
        assert "target_group_arn_suffix  = module.alb.target_group_arn_suffix" in main
        assert 'split(":targetgroup/"' not in main


def test_account_wide_security_controls_have_one_owner() -> None:
    dev = text("terraform/environments/dev/main.tf")
    staging = text("terraform/environments/staging/main.tf")
    prod = text("terraform/environments/prod/main.tf")
    assert re.search(r"enable_guardduty\s*=\s*false", dev)
    assert re.search(r"enable_cloudtrail\s*=\s*false", dev)
    assert re.search(r"enable_guardduty\s*=\s*false", staging)
    assert re.search(r"enable_cloudtrail\s*=\s*false", staging)
    assert re.search(r"enable_guardduty\s*=\s*true", prod)
    assert re.search(r"enable_cloudtrail\s*=\s*true", prod)


def test_backup_cold_storage_retention_and_cloudtrail_kms_are_validated() -> None:
    prod = text("terraform/environments/prod/main.tf")
    backup = text("terraform/modules/backup/main.tf")
    monitoring = text("terraform/modules/monitoring/main.tf")
    cloudtrail_statement = monitoring.split('Sid    = "AllowCloudTrail"', 1)[1].split(
        'Sid    = "AllowSNS"', 1
    )[0]
    assert "backup_retention_days" in prod and "= 180" in prod
    assert "cold_storage_after_days" in prod and "= 90" in prod
    assert "var.backup_retention_days >= var.cold_storage_after_days + 90" in backup
    assert '"kms:Decrypt"' in cloudtrail_statement


def test_short_lived_roots_use_two_alb_azs_and_one_compute_az() -> None:
    for environment in ("dev", "staging"):
        variables = text(f"terraform/environments/{environment}/variables.tf")
        main = text(f"terraform/environments/{environment}/main.tf")
        values = text(f"terraform/environments/{environment}/terraform.tfvars.example")

        assert 'default     = ["ap-northeast-1a", "ap-northeast-1c"]' in variables
        assert 'default     = ["ap-northeast-1a"]' in variables
        assert "azs                   = var.compute_azs" in main
        assert 'azs           = ["ap-northeast-1a", "ap-northeast-1c"]' in values
        assert 'compute_azs   = ["ap-northeast-1a"]' in values


def test_staging_root_and_restore_outputs_are_complete() -> None:
    staging = ROOT / "terraform/environments/staging"
    required_files = {
        "backend.tf",
        "backend.hcl.example",
        "main.tf",
        "outputs.tf",
        "providers.tf",
        "terraform.tfvars.example",
        "variables.tf",
        "versions.tf",
    }
    assert required_files <= {path.name for path in staging.iterdir()}

    required_outputs = {
        "alb_healthz_url",
        "private_subnet_ids",
        "ec2_security_group_id",
        "ec2_instance_profile_name",
        "target_group_arn",
        "backup_vault_name",
        "backup_role_arn",
    }
    for environment in ("dev", "staging", "prod"):
        outputs = text(f"terraform/environments/{environment}/outputs.tf")
        for name in required_outputs:
            assert f'output "{name}"' in outputs

    workflow = text(".github/workflows/terraform-check.yml")
    assert "environment: [dev, staging, prod]" in workflow


def test_force_destroy_is_isolated_to_short_lived_staging() -> None:
    staging = text("terraform/environments/staging/main.tf")
    assert len(re.findall(r"force_destroy\s*=\s*true", staging)) == 4
    assert "protect_recovery_points = false" in staging
    assert re.search(r"enable_guardduty\s*=\s*false", staging)
    assert re.search(r"enable_cloudtrail\s*=\s*false", staging)

    for module in ("alb", "backup", "synthetics-probe"):
        variables = text(f"terraform/modules/{module}/variables.tf")
        force_destroy = variables.split('variable "force_destroy"', 1)[1].split("}", 1)[0]
        assert "default     = false" in force_destroy

    assert "force_destroy = var.force_destroy" in text("terraform/modules/alb/main.tf")
    backup_main = text("terraform/modules/backup/main.tf")
    assert backup_main.count("force_destroy = var.force_destroy") == 2
    assert "force_destroy = var.force_destroy" in text("terraform/modules/synthetics-probe/main.tf")

    monitoring_variables = text("terraform/modules/monitoring/variables.tf")
    assert 'variable "force_destroy"' not in monitoring_variables

    backup_variables = text("terraform/modules/backup/variables.tf")
    protection = backup_variables.split('variable "protect_recovery_points"', 1)[1].split("}", 1)[0]
    assert "default     = true" in protection


def test_backup_deletion_policy_has_real_break_glass_and_lifecycle_exceptions() -> None:
    module = text("terraform/modules/backup/main.tf")
    variables = text("terraform/modules/backup/variables.tf")
    assert 'variable "recovery_point_delete_principal_arns"' in variables
    assert "length(var.recovery_point_delete_principal_arns) >= 1" in module
    assert "AWSServiceRoleForBackup" in module
    assert "aws_iam_role.backup.arn" in module
    assert "ArnNotEquals" in module
    assert '"backup:UpdateRecoveryPointLifecycle"' in module
    assert '"backup:PutBackupVaultAccessPolicy"' in module
    assert '"backup:DeleteBackupVaultAccessPolicy"' in module
    for environment in ("dev", "prod"):
        main = text(f"terraform/environments/{environment}/main.tf")
        values = text(f"terraform/environments/{environment}/terraform.tfvars.example")
        assert "var.backup_admin_principal_arns" in main
        assert "backup_admin_principal_arns" in values


def test_backup_selection_is_explicitly_environment_scoped() -> None:
    module = text("terraform/modules/backup/main.tf")
    selection = module.split('resource "aws_backup_selection" "this"', 1)[1]
    selection = selection.split("# ----------------------------------------------------------------------------", 1)[0]
    assert "resources = var.instance_arns" in selection
    assert "selection_tag" not in selection


def test_management_alb_cidrs_reject_full_open() -> None:
    for environment in ("dev", "staging", "prod"):
        variables = text(f"terraform/environments/{environment}/variables.tf")
        assert '!contains(var.allowed_ingress_cidrs, "0.0.0.0/0")' in variables


def test_dynamic_inventory_can_limit_a_restored_instance_id() -> None:
    inventory = text("ansible/inventory/aws_ec2.yml.example")
    terraform_readme = text("terraform/README.md")
    ansible_ignore = text("ansible/.gitignore")

    hostnames = inventory.split("hostnames:", 1)[1].split("compose:", 1)[0]
    assert hostnames.index("- instance-id") < hostnames.index("- tag:Name")
    assert "ansible_aws_ssm_instance_id: instance_id" in inventory
    assert 'tag:Environment: "<REPLACE-WITH-ENVIRONMENT>"' in inventory
    assert "amazon.aws.aws_ssm" in inventory
    assert "app_monitor_bind_address: \"'0.0.0.0'\"" in inventory
    assert "server_monitor_alb_source_cidr: tags.AlbHealthCheckSourceCidr" in inventory
    assert "ansible/inventory/aws_ec2.yml.example" in terraform_readme
    assert "inventory/aws_ec2.yml" in ansible_ignore


def test_d2_runbook_is_staging_scoped_and_avoids_state_rewrites() -> None:
    scenario = text("docs/roadmap/D-2-host-failure.md")
    runbook = text("docs/roadmap/restore-from-snapshot.md")

    assert "terraform/environments/staging" in scenario
    assert "terraform/environments/staging" in runbook
    assert "terraform/environments/prod" not in runbook
    assert "terraform state rm" not in runbook
    assert "terraform import" not in runbook
    assert "get-recovery-point-restore-metadata" in runbook
    assert "start-backup-job" in runbook
    assert "日次scheduleのRPO検証ではない" in runbook
    assert "BACKUP_DEADLINE" in runbook
    assert "RESTORE_DEADLINE" in runbook
    assert "PARTIAL" in runbook
    assert '.Status == "COMPLETED"' in runbook
    assert "RECOVERY_POINT_AGE_SECONDS" in runbook
    assert "EXPECTED_BACKUP_PLAN_ID" in runbook
    assert '--by-backup-plan-id "$EXPECTED_BACKUP_PLAN_ID"' in runbook
    assert "--copy-source-tags-to-restored-resource" not in runbook
    assert ".NetworkInterfaces, .networkInterfaces" in runbook
    assert "--idempotency-token" in runbook
    assert "Key=ManagedBy,Value=aws-backup-restore" in runbook
    assert '.SecurityGroupIds = $security_groups' in runbook
    assert 'ansible_aws_ssm_instance_id: instance_id' in text(
        "ansible/inventory/aws_ec2.yml.example"
    )
    assert "(\n  cd ansible" in runbook
    assert "monitor: \"tags.Application == 'server-monitor'\"" in text(
        "ansible/inventory/aws_ec2.yml.example"
    )
    assert 'playbooks/verify.yml --limit "$NEW_INSTANCE_ID"' in runbook
    assert "scripts/drills/d2-abort.sh" in runbook
    assert "terraform -chdir=\"$TF_ENV_DIR\" plan -destroy" in runbook
    assert "RESTART_DEADLINE" in runbook
    assert "SystemStatus.Status,InstanceStatus.Status" in runbook
    assert "TARGET_STATUS" in runbook


def test_staging_ssm_transfer_path_is_self_contained() -> None:
    staging = text("terraform/environments/staging/main.tf")
    outputs = text("terraform/environments/staging/outputs.tf")
    requirements = text("ansible/requirements.yml")
    runbook = text("docs/roadmap/restore-from-snapshot.md")
    assert 'resource "aws_s3_bucket" "ssm_transfer"' in staging
    assert 'resource "aws_iam_policy" "ssm_transfer_controller"' in staging
    assert 'output "ssm_transfer_bucket_name"' in outputs
    assert 'output "ssm_transfer_controller_policy_arn"' in outputs
    assert 'output "backup_plan_id"' in outputs
    assert 'version: "11.4.0"' in requirements
    assert "controller-requirements.txt" in runbook
    assert "ansible-vault view" in runbook
    assert "s3api put-object" in runbook and "s3api delete-object" in runbook


def test_aws_app_port_contract_preserves_loopback_default() -> None:
    compose = text("compose.yaml")
    app_tasks = text("ansible/roles/app/tasks/main.yml")
    common_tasks = role_tasks("common")
    assert "${MONITOR_BIND_ADDRESS:-127.0.0.1}:${MONITOR_PORT:-8080}:8080" in compose
    assert "MONITOR_BIND_ADDRESS={{ app_monitor_bind_address }}" in app_tasks
    assert "common_ufw_alb_source_cidr" in common_tasks
    for environment in ("dev", "staging", "prod"):
        main = text(f"terraform/environments/{environment}/main.tf")
        assert "AlbHealthCheckSourceCidr = var.vpc_cidr" in main


def test_terraform_files_have_balanced_braces() -> None:
    for path in (ROOT / "terraform").rglob("*.tf"):
        content = path.read_text(encoding="utf-8")
        assert content.count("{") == content.count("}"), path


def test_dependabot_terraform_directories_match_version_constraint_files() -> None:
    """Dependabot の監視対象と、provider 制約を宣言しているディレクトリを一致させる。

    provider 制約は複数の versions.tf に分散している。一部だけが更新されると
    `~> 5.50, ~> 6.58` のような両立しない制約になり、terraform init が必ず
    失敗する（PR #44 / #45 で実際に起きた）。

    そのとき対策として `directories` を列挙したが、件数をコメントへ手で固定
    したため environments/staging の登録漏れに気づけなかった。
    網羅すべき集合を手で列挙した時点で、次に漏れる。集合の一致を検査する。
    """
    import yaml

    config = yaml.safe_load((ROOT / ".github" / "dependabot.yml").read_text(encoding="utf-8"))
    terraform_updates = [u for u in config["updates"] if u["package-ecosystem"] == "terraform"]
    assert terraform_updates, "terraform ecosystem entry is missing"

    watched = set()
    for update in terraform_updates:
        for directory in update.get("directories", []):
            watched.add(directory.rstrip("/") or "/")
        if "directory" in update:
            watched.add(update["directory"].rstrip("/") or "/")

    declared = set()
    for path in (ROOT / "terraform").rglob("*.tf"):
        if "required_providers" not in path.read_text(encoding="utf-8"):
            continue
        declared.add("/" + path.parent.relative_to(ROOT).as_posix())

    assert declared, "no terraform files declare required_providers"
    assert declared == watched, (
        "dependabot.yml directories and the directories declaring required_providers differ.\n"
        f"  only in dependabot.yml: {sorted(watched - declared)}\n"
        f"  only in terraform/:     {sorted(declared - watched)}"
    )


def test_aws_provider_version_constraints_are_identical() -> None:
    """全 versions.tf の aws provider 制約が 1 つに揃っていること。

    ばらけた瞬間に terraform init が失敗する。
    """
    constraints = {}
    for path in (ROOT / "terraform").rglob("versions.tf"):
        content = path.read_text(encoding="utf-8")
        match = re.search(
            r'aws\s*=\s*\{[^}]*?version\s*=\s*"([^"]+)"', content, re.DOTALL
        )
        if match:
            constraints[path.relative_to(ROOT).as_posix()] = match.group(1)
    assert constraints, "no aws provider constraints found"
    assert len(set(constraints.values())) == 1, constraints


def test_managed_node_can_use_the_ssm_file_transfer_bucket() -> None:
    """SSM 経由で Ansible を流すには、管理対象ノード側にも S3 権限が要る。

    AmazonSSMManagedInstanceCore には amazon.aws.aws_ssm が使う S3 転送
    バケットの権限が含まれない。controller 側の policy だけを用意しても、
    apply は通るが構成適用の段階で AccessDenied になる。
    ssh_ingress_cidrs = [] の環境では SSM が唯一の経路なので、そこで
    詰まると入る手段が無くなる。
    """
    compute = text("terraform/modules/compute/main.tf")
    staging = text("terraform/environments/staging/main.tf")
    assert 'resource "aws_iam_role_policy" "ssm_file_transfer"' in compute
    assert "s3:GetObject" in compute and "s3:PutObject" in compute
    assert "ssm_file_transfer_bucket = aws_s3_bucket.ssm_transfer.bucket" in staging


def test_alb_access_log_bucket_allows_the_regional_elb_account() -> None:
    """ALB アクセスログの principal は、リージョンによって 2 通りある。

    ap-northeast-1（全 tfvars の既定）はサービスプリンシパルではなく
    リージョンごとの ELB アカウント ID を要求する。service principal だけを
    書くと aws_lb 作成時に Access Denied になり、ALB が作れないまま以降が
    全部止まる。
    """
    alb = text("terraform/modules/alb/main.tf")
    assert 'data "aws_elb_service_account" "current"' in alb
    assert "data.aws_elb_service_account.current.arn" in alb


def test_backup_vault_policy_cannot_lock_out_the_caller() -> None:
    """resource-based policy の explicit Deny はアカウント管理者でも回避できない。

    例外リストに実行中の principal を入れ忘れると、以後 vault policy を
    書き換えられず、recovery point も消せず、terraform destroy も通らない。
    """
    backup = text("terraform/modules/backup/main.tf")
    assert "vault_policy_admin_arns" in backup
    assert "caller_role_arn" in backup
    assert 'data.aws_caller_identity.current.arn' in backup


def test_central_observability_defaults_off_and_wires_remote_write_when_enabled() -> None:
    """外部probe / AMPはコストを伴うため、明示的に有効化しない限り作られない。

    有効化したときにEC2 instance roleへremote_write権限が届かないと、
    Prometheusのsigv4 remote_writeがAccessDeniedで無言で失敗し続ける。
    """
    variables = text("terraform/environments/staging/variables.tf")
    assert 'variable "enable_central_observability"' in variables
    enable_block = variables.split('variable "enable_central_observability"', 1)[1].split("}", 1)[0]
    assert "default     = false" in enable_block

    main = text("terraform/environments/staging/main.tf")
    assert main.count("count  = var.enable_central_observability ? 1 : 0") == 2
    assert 'module "central_metrics"' in main
    assert 'module "synthetics_probe"' in main
    assert (
        "additional_iam_policy_arns = var.enable_central_observability "
        "? [module.central_metrics[0].remote_write_policy_arn] : []"
    ) in main
    assert "alarm_sns_topic_arn = module.monitoring.sns_topic_arn" in main

    central_metrics_outputs = text("terraform/modules/central-metrics/outputs.tf")
    assert 'output "remote_write_policy_arn"' in central_metrics_outputs
    assert 'output "remote_write_url"' in central_metrics_outputs

    compute_variables = text("terraform/modules/compute/variables.tf")
    assert 'variable "additional_iam_policy_arns"' in compute_variables


def test_synthetics_canary_name_respects_the_aws_length_limit() -> None:
    """CloudWatch Syntheticsのcanary名は21文字を超えると apply 時に弾かれる。

    局所的な文字列だけを見ると気づきにくいので、環境側で実際に渡す値と
    モジュール側のvalidationを両方検査する。
    """
    variables = text("terraform/modules/synthetics-probe/variables.tf")
    assert "length(var.canary_name) <= 21" in variables

    main = text("terraform/environments/staging/main.tf")
    canary_name = main.split('canary_name = "', 1)[1].split('"', 1)[0]
    assert len(canary_name) <= 21
