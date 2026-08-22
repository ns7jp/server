import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_build_package_contains_all_delivery_documents():
    required = {
        "README.md",
        "00-requirements.md",
        "01-basic-design.md",
        "02-detailed-design.md",
        "03-parameter-sheet.md",
        "04-network-ip-plan.md",
        "05-build-procedure.md",
        "06-test-specification.md",
        "07-handover-checklist.md",
        "08-change-rollback-plan.md",
        "09-network-validation-procedure.md",
    }
    actual = {path.name for path in (ROOT / "docs" / "build-package").glob("*.md")}
    assert required <= actual


def test_test_specification_does_not_claim_unrun_results():
    text = (ROOT / "docs" / "build-package" / "06-test-specification.md").read_text(
        encoding="utf-8"
    )
    assert "NOT RUN" in text
    assert "PASS / FAIL / BLOCKED / NOT RUN" in text


def test_network_lab_declares_two_distinct_subnets():
    text = (
        ROOT / "labs" / "network-troubleshooting" / "compose.yaml"
    ).read_text(encoding="utf-8")
    assert "172.28.10.0/24" in text
    assert "172.28.20.0/24" in text
    assert text.count("internal: true") == 1


def test_main_stack_keeps_internal_segments_and_adds_loopback_host_access():
    compose = (ROOT / "compose.yaml").read_text(encoding="utf-8")
    e2e_override = (ROOT / "compose.e2e.yaml").read_text(encoding="utf-8")

    assert compose.count("internal: true") == 2
    assert "host-access:\n    driver: bridge" in compose
    expected_mappings = (
        "127.0.0.1:${MONITOR_PORT:-8080}:8080",
        "127.0.0.1:${PROMETHEUS_PORT:-9090}:9090",
        "127.0.0.1:${ALERTMANAGER_PORT:-9093}:9093",
        "127.0.0.1:${GRAFANA_PORT:-3000}:3000",
        "127.0.0.1:${LOKI_PORT:-3100}:3100",
    )
    for mapping in expected_mappings:
        assert mapping in compose
    for service in ("nginx", "prometheus", "alertmanager", "grafana", "loki"):
        remainder = compose.split(f"  {service}:\n", 1)[1]
        section = re.split(r"\n(?=  [A-Za-z0-9_-]+:)", remainder, maxsplit=1)[0]
        assert "- host-access" in section
    for service in ("app", "alloy", "blackbox", "node-exporter"):
        remainder = compose.split(f"  {service}:\n", 1)[1]
        section = re.split(
            r"\n(?=  [A-Za-z0-9_-]+:)", remainder, maxsplit=1
        )[0]
        assert "- host-access" not in section
    webhook_remainder = e2e_override.split("  webhook-sink:\n", 1)[1]
    webhook_section = re.split(
        r"\n(?=  [A-Za-z0-9_-]+:)", webhook_remainder, maxsplit=1
    )[0]
    assert "- host-access" in webhook_section


def test_directory_sync_preserves_ansible_managed_metadata_and_secrets():
    task = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )

    for setting in ("owner: false", "group: false", "perms: false"):
        assert setting in task
    for option in (
        '"--omit-dir-times"',
        '"--exclude=.env"',
        '"--exclude=deploy/secrets/*.txt"',
        '"--exclude=deploy/alertmanager/alertmanager.ansible.yml"',
    ):
        assert option in task


def test_host_network_validation_covers_required_layers_without_claiming_execution():
    procedure = (
        ROOT / "docs" / "build-package" / "09-network-validation-procedure.md"
    ).read_text(encoding="utf-8")
    result_template = (
        ROOT / "docs" / "evidence" / "templates" / "network-host-validation.md"
    ).read_text(encoding="utf-8")

    for command in ("ping", "dig", "ss", "curl", "tcpdump", "ip route", "ufw"):
        assert command in procedure
    assert "NOT RUN" in procedure
    assert result_template.count("NOT RUN") >= 9


def test_troubleshooting_template_preserves_primary_reasoning_record():
    text = (
        ROOT / "docs" / "evidence" / "templates" / "troubleshooting-worklog.md"
    ).read_text(encoding="utf-8")

    for heading in ("Hypothesis", "Commands", "Result", "Learning"):
        assert heading in text
    assert "AI・外部情報の利用開示" in text


def test_ansible_directory_source_resolves_from_playbooks_to_repository_root():
    group_vars = (
        ROOT / "ansible" / "inventory" / "group_vars" / "all" / "main.yml"
    ).read_text(encoding="utf-8")
    app_defaults = (
        ROOT / "ansible" / "roles" / "app" / "defaults" / "main.yml"
    ).read_text(encoding="utf-8")
    app_tasks = (
        ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")

    # playbook_dir is <repo>/ansible/playbooks, so two parents are required.
    assert 'server_monitor_source_path: "{{ playbook_dir }}/../.."' in group_vars
    assert 'app_repo_source: "{{ server_monitor_source_path }}"' in app_defaults
    assert 'src: "{{ app_repo_source }}/"' in app_tasks


def test_inventory_variables_live_beside_inventory_sources():
    inventory_dir = ROOT / "ansible" / "inventory"

    assert (inventory_dir / "group_vars" / "all" / "main.yml").is_file()
    assert (inventory_dir / "group_vars" / "monitor" / "main.yml").is_file()
    assert (inventory_dir / "host_vars" / "monitor-01.yml").is_file()
    assert not list((ROOT / "ansible" / "group_vars").rglob("*.yml"))
    assert not list((ROOT / "ansible" / "host_vars").rglob("*.yml"))


def test_ansible_compose_secrets_are_readable_by_non_root_container_uids():
    app_tasks = (
        ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    alertmanager_runbook = (
        ROOT / "docs" / "runbooks" / "alertmanager-down.md"
    ).read_text(encoding="utf-8")

    secrets_dir_task = app_tasks.split("- name: Ensure secrets directory exists", 1)[
        1
    ].split("- name:", 1)[0]
    secret_files_task = app_tasks.split("- name: Render secret files from vault values", 1)[
        1
    ].split("- name:", 1)[0]
    slack_secret_task = app_tasks.split("- name: Render optional Slack webhook secret", 1)[
        1
    ].split("- name:", 1)[0]

    assert "mode: '0700'" in secrets_dir_task
    assert "mode: '0644'" in secret_files_task
    assert "mode: '0644'" in slack_secret_task
    assert "mode: '0600'" not in secret_files_task
    assert "mode: '0600'" not in slack_secret_task
    assert "Compose secrets ファイルが `0644`" in alertmanager_runbook


def test_managed_alertmanager_config_is_readable_by_container_uid():
    app_tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )
    monitoring_tasks = (
        ROOT / "ansible" / "roles" / "monitoring" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")

    render_task = app_tasks.split(
        "- name: Render environment-specific Alertmanager configuration", 1
    )[1].split("- name:", 1)[0]

    assert "src: alertmanager.yml.j2" in render_task
    assert "deploy/alertmanager/alertmanager.ansible.yml" in render_task
    assert "mode: '0644'" in render_task
    assert "notify: Restart managed Alertmanager service" in render_task
    assert "Reconcile environment-specific Alertmanager configuration" not in monitoring_tasks
    assert "Validate Alertmanager configuration with amtool" in monitoring_tasks
    assert "alertmanager.ansible.yml:/etc/alertmanager/alertmanager.yml:ro" in monitoring_tasks


def test_full_stack_e2e_starts_as_not_run_and_requires_disposable_host_opt_in():
    runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )
    workflow = (
        ROOT / ".github" / "workflows" / "full-stack-e2e.yml"
    ).read_text(encoding="utf-8")

    assert 'STATUS["${id}"]="NOT RUN"' in runner
    assert "--confirm-disposable-host" in runner
    assert "changed=0" in runner
    assert "pull_request:" in workflow
    assert "actions/upload-artifact" in workflow
    assert "if: always()" in workflow
    assert "include-hidden-files: true" in workflow
    assert "if-no-files-found: error" in workflow
    assert "--return" not in workflow
    assert "demo-command-success.txt" in workflow


def test_ci_overrides_are_host_vars_and_win_over_monitor_group_defaults():
    inventory = (ROOT / "ansible" / "inventory" / "ci.yml").read_text(
        encoding="utf-8"
    )

    assert "\n  vars:\n" not in inventory
    for setting in (
        "          server_monitor_environment: ci",
        "          server_monitor_timezone: Etc/UTC",
        "          backup_target_dir: /var/backups/server-monitor-e2e",
        "          backup_enabled: false",
        "          app_alertmanager_webhook_enabled: true",
    ):
        assert setting in inventory


def test_directory_sync_excludes_generated_evidence_and_managed_alert_config():
    tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )

    # Both otherwise change between first and second apply and break changed=0.
    assert '"--exclude=.artifacts"' in tasks
    assert '"--exclude=deploy/alertmanager/alertmanager.ansible.yml"' in tasks
    assert "Render environment-specific Alertmanager configuration" in tasks


def test_ansible_compose_override_uses_untracked_managed_alert_config():
    override = (ROOT / "compose.ansible.yaml").read_text(encoding="utf-8")
    app_tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )
    handler = (
        ROOT / "ansible" / "roles" / "app" / "handlers" / "main.yml"
    ).read_text(encoding="utf-8")
    template = (
        ROOT / "ansible" / "roles" / "app" / "templates" / "alertmanager.yml.j2"
    ).read_text(encoding="utf-8")
    e2e_runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )
    demo_runner = (ROOT / "scripts" / "demo" / "run-demo.sh").read_text(
        encoding="utf-8"
    )

    assert "alertmanager.ansible.yml:/etc/alertmanager/alertmanager.yml:ro" in override
    assert "+ ['compose.ansible.yaml']" in app_tasks
    assert "+ ['compose.ansible.yaml']" in handler
    assert "services:\n      - alertmanager" in handler
    assert "slack_api_url_file: /run/secrets/slack_webhook_url" in template
    assert "api_url: {{ slack_webhook_url" not in template
    assert "compose.ansible.yaml" in e2e_runner
    assert "compose.ansible.yaml" in demo_runner


def test_restore_runner_verifies_checksums_and_refuses_existing_volumes_by_default():
    restore = (ROOT / "scripts" / "ops" / "restore-volumes.sh").read_text(
        encoding="utf-8"
    )

    assert "sha256sum --check SHA256SUMS" in restore
    assert "target volume already exists" in restore
    assert "FORCE=0" in restore
    assert "unsafe path found in archive" in restore


def test_demo_is_reproducible_and_does_not_claim_slack_delivery():
    guide = (ROOT / "docs" / "demo-capture-guide.md").read_text(encoding="utf-8")
    demo = (ROOT / "scripts" / "demo" / "run-demo.sh").read_text(
        encoding="utf-8"
    )

    assert "https://ns7jp.github.io/demo.html" in guide
    assert "実操作の連続録画は未公開" in guide
    assert "実操作の連続録画ではありません" in guide
    assert "Slack実配信ではありません" in guide
    assert "demo.cast" in guide
    assert "PortfolioDemo" in demo
    assert "d1-process-down.sh" in demo


def test_e2e_cleanup_owns_only_resources_created_by_the_current_run():
    runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )

    assert 'CLIENT_CREATED=0' in runner
    assert 'SSH_USER_CREATED=0' in runner
    assert 'RESTORE_OWNED=0' in runner
    assert '[[ "${CLIENT_CREATED}" -eq 1 ]]' in runner
    assert '[[ "${SSH_USER_CREATED}" -eq 1 ]]' in runner
    assert '[[ "${RESTORE_OWNED}" -eq 1' in runner


def test_notification_checks_match_the_current_synthetic_alert_instance():
    runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )
    demo = (ROOT / "scripts" / "demo" / "run-demo.sh").read_text(
        encoding="utf-8"
    )

    assert "wanted_instance" in runner
    assert 'alert_instance="ci-monitor-01-' in runner
    assert "wanted_instance" in demo
    assert 'DEMO_INSTANCE="demo-' in demo


def test_authenticated_ansible_probes_do_not_log_credentials():
    verify = (ROOT / "ansible" / "playbooks" / "verify.yml").read_text(
        encoding="utf-8"
    )

    assert verify.count("no_log: true") >= 2


def test_common_role_prepares_sshd_runtime_directory_before_validation():
    tasks = (
        ROOT / "ansible" / "roles" / "common" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")

    runtime_task = "Ensure sshd runtime directory exists for configuration validation"
    validation_task = "Disable root SSH login"
    assert "path: /run/sshd" in tasks
    assert tasks.index(runtime_task) < tasks.index(validation_task)


def test_docker_daemon_restart_finishes_before_compose_workloads_start():
    tasks = (
        ROOT / "ansible" / "roles" / "docker" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")

    render_task = "Render /etc/docker/daemon.json"
    flush_task = "Apply Docker daemon changes before deploying workloads"
    assert "ansible.builtin.meta: flush_handlers" in tasks
    assert tasks.index(render_task) < tasks.index(flush_task)


def test_backup_template_remains_renderable_by_plain_jinja_smoke_test():
    template = (
        ROOT
        / "ansible"
        / "roles"
        / "backup"
        / "templates"
        / "server-monitor-backup.sh.j2"
    ).read_text(encoding="utf-8")

    # backup-verify.yml renders this with standalone Jinja, without Ansible filters.
    assert "| bool" not in template

