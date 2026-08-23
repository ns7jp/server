import re
import os
import shutil
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]


def role_task_flow(role: str) -> str:
    """Return a role's effective task sequence with ``include_tasks`` expanded.

    ロールを OS ファミリーごとのタスクファイルへ分割したので、``main.yml`` を
    1 本のテキストとして読むだけでは「A が B より先に実行される」という
    不変条件を検査できなくなった。include の順に本文を差し込んだ 1 本の
    テキストへ畳んでから検査する。

    ``firewall-{{ common_firewall_backend }}.yml`` のように変数を含む
    include は、その接頭辞に一致するファイルをすべて、名前順に展開する。
    どの分岐へ入っても順序が保たれていることを確認するため。
    """
    tasks_dir = ROOT / "ansible" / "roles" / role / "tasks"
    include = re.compile(
        r"^\s*ansible\.builtin\.include_tasks:\s*[\"']?([^\"'\n]+)[\"']?\s*$",
        re.MULTILINE,
    )

    def expand(name: str, seen: frozenset) -> str:
        path = tasks_dir / name
        if not path.exists() or name in seen:
            return ""
        body = path.read_text(encoding="utf-8")
        seen = seen | {name}
        out = []
        last = 0
        for match in include.finditer(body):
            out.append(body[last : match.end()])
            last = match.end()
            target = match.group(1).strip()
            if "{{" in target:
                prefix = target.split("{{", 1)[0]
                targets = sorted(
                    child.name
                    for child in tasks_dir.glob(f"{prefix}*.yml")
                )
            else:
                targets = [target]
            for child_name in targets:
                out.append("\n" + expand(child_name, seen))
        out.append(body[last:])
        return "".join(out)

    return expand("main.yml", frozenset())


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

    assert compose.count("internal: true") == 3
    assert "host-access:\n    driver: bridge" in compose
    expected_mappings = (
        "${MONITOR_BIND_ADDRESS:-127.0.0.1}:${MONITOR_PORT:-8080}:8080",
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
    for service in (
        "app",
        "alloy",
        "blackbox",
        "node-exporter",
        "docker-socket-proxy",
    ):
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

    for setting in (
        "owner: false",
        "group: false",
        "perms: true",
        "checksum: true",
    ):
        assert setting in task
    assert "delete: true" in task
    for option in (
        '"--omit-dir-times"',
        '"--exclude=/.env"',
        '"--exclude=/.server-monitor-deploy-revision"',
        '"--exclude=/deploy/secrets/*.txt"',
        '"--exclude=/deploy/alertmanager/alertmanager.ansible.yml"',
    ):
        assert option in task
    assert "Require a clean local checkout for directory mode" in task
    assert "--untracked-files=normal" in task
    assert ".server-monitor-deploy-revision" in task
    assert "Archive only files tracked by the selected checkout revision" in task
    assert "tar.umask=0022" in task
    assert "- path: deploy/tls\n          mode: '0750'" in task
    assert 'src: "{{ app_release_staging.path }}/release/"' in task
    assert "Remove controller release staging directory" in task
    assert "--exclude=/.artifacts/" in task
    ownership_task = task.split("- name: Fix ownership of synced files", 1)[1].split(
        "- name:", 1
    )[0]
    assert "recurse: true" in ownership_task
    assert "follow: false" in ownership_task


def test_git_deployment_fetches_immutable_tracked_release_on_controller():
    group_vars = (
        ROOT / "ansible" / "inventory" / "group_vars" / "all" / "main.yml"
    ).read_text(encoding="utf-8")
    tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )

    assert 'server_monitor_git_version: ""' in group_vars
    assert "^[0-9a-fA-F]{40}$" in tasks
    assert tasks.index("Validate source deployment mode") < tasks.index(
        "Ensure install directory exists"
    )
    assert tasks.index("Refuse a symlink or non-directory install target") < tasks.index(
        "Ensure install directory exists"
    )
    assert "follow: false" in tasks
    assert "app_target_realpath.stdout == app_repo_target" in tasks
    assert "app_repo_target == server_monitor_install_dir" in tasks
    assert "Fetch immutable release source for git mode" in tasks
    assert "Assert fetched git release matches requested immutable revision" in tasks
    assert "(app_git_checkout.after | lower)" in tasks
    assert "recursive: false" in tasks
    assert "Reject submodules that git archive cannot materialize" in tasks
    assert "160000" in tasks
    assert "delegate_to: localhost" in tasks
    assert "Archive only files tracked by the selected checkout revision" in tasks
    assert "- clean\n" not in tasks
    for generated_path in (
        "--exclude=/.env",
        "--exclude=/.artifacts/",
        "--exclude=/.server-monitor-deploy-revision",
        "--exclude=/deploy/secrets/*.txt",
        "--exclude=/deploy/alertmanager/alertmanager.ansible.yml",
        "--exclude=/deploy/tls/server.key",
        "--exclude=/deploy/tls/server.crt",
    ):
        assert generated_path in tasks


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
    assert "Archive only files tracked by the selected checkout revision" in app_tasks
    assert "{{ app_repo_source" in app_tasks
    assert "app_directory_source_toplevel.stdout == app_directory_source_realpath.stdout" in app_tasks


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
    assert "codex/full-stack-e2e-20260822" not in workflow
    for app_input in (
        "Dockerfile",
        ".dockerignore",
        "app.py",
        "requirements.txt",
        "templates/**",
        "static/**",
    ):
        # Every application input must trigger both push and pull-request E2E.
        assert workflow.count(f"- '{app_input}'") == 2


def test_alloy_uses_restricted_private_docker_api_proxy():
    compose = (ROOT / "compose.yaml").read_text(encoding="utf-8")
    alloy_config = (ROOT / "deploy" / "alloy" / "config.alloy").read_text(
        encoding="utf-8"
    )
    runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )
    proxy_section = compose.split("  docker-socket-proxy:\n", 1)[1].split(
        "\n  alloy:\n", 1
    )[0]
    alloy_section = compose.split("  alloy:\n", 1)[1].split(
        "\n  blackbox:\n", 1
    )[0]

    assert compose.count("/var/run/docker.sock:/var/run/docker.sock:ro") == 1
    assert "/var/run/docker.sock" not in alloy_section
    assert "CONTAINERS: \"1\"" in proxy_section
    assert "NETWORKS: \"1\"" in proxy_section
    assert "POST: \"0\"" in proxy_section
    assert "ports:" not in proxy_section
    assert "- docker-api" in proxy_section
    assert "- docker-api" in alloy_section
    assert "docker-api:\n    internal: true" in compose
    assert len(
        re.findall(
            r'host\s*=\s*"tcp://docker-socket-proxy:2375"', alloy_config
        )
    ) == 2
    assert "docker-socket-proxy" in runner
    assert "403 Forbidden" in runner
    assert "docker-proxy-ping.txt" in runner
    assert "docker-proxy-denied-post.txt" in runner
    assert "docker-proxy-loki-query.json" in runner
    assert "server-monitor-e2e-docker-log" in runner


def test_application_user_is_not_granted_root_equivalent_docker_group():
    docker_tasks = role_task_flow("docker")
    verify = (
        ROOT
        / "ansible"
        / "roles"
        / "docker"
        / "molecule"
        / "default"
        / "verify.yml"
    ).read_text(encoding="utf-8")
    prepare = (
        ROOT
        / "ansible"
        / "roles"
        / "docker"
        / "molecule"
        / "default"
        / "prepare.yml"
    ).read_text(encoding="utf-8")

    assert "Validate unprivileged application account before host mutation" in docker_tasks
    assert "Inspect application user supplementary groups" in docker_tasks
    assert "Inspect application user primary group" in docker_tasks
    assert "Remove legacy docker group membership" in docker_tasks
    assert "difference([docker_application_user_primary_group.stdout, 'docker'])" in docker_tasks
    assert "append: false" in docker_tasks
    assert "groups: docker" not in docker_tasks
    assert "'docker' not in monitor_groups.stdout.split()" in verify
    assert "'monitor-observer' in monitor_groups.stdout.split()" in verify
    assert "Seed application user with legacy and harmless memberships" in prepare
    assert "- docker" in prepare
    assert "- monitor-observer" in prepare


def test_fresh_host_check_mode_skips_runtime_only_operations():
    docker_tasks = role_task_flow("docker")
    app_tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )
    app_handler = (
        ROOT / "ansible" / "roles" / "app" / "handlers" / "main.yml"
    ).read_text(encoding="utf-8")
    monitoring_tasks = (
        ROOT / "ansible" / "roles" / "monitoring" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    verify = (ROOT / "ansible" / "playbooks" / "verify.yml").read_text(
        encoding="utf-8"
    )
    ansible_workflow = (
        ROOT / ".github" / "workflows" / "ansible-check.yml"
    ).read_text(encoding="utf-8")

    assert docker_tasks.count("when: not ansible_check_mode") >= 2
    compose_task = app_tasks.split("- name: Bring the compose stack up", 1)[1].split(
        "- name:", 1
    )[0]
    assert "when: not ansible_check_mode" in compose_task
    assert "- not ansible_check_mode" in app_handler
    assert monitoring_tasks.count("- not ansible_check_mode") >= 4
    assert "Skip runtime verification during check mode" in verify
    assert "ansible.builtin.meta: end_play" in verify
    # ロールごとの scenario をすべて走査する形へ変えたので、固定の
    # default だけを見るのではなく、走査そのものが残っていることを確認する。
    assert 'for scenario in molecule/*/' in ansible_workflow
    assert '"${scenario}/prepare.yml" --syntax-check' in ansible_workflow


def test_successful_full_stack_e2e_is_recorded_with_scope_boundaries():
    evidence = (
        ROOT / "docs" / "evidence" / "2026-08-22-full-stack-e2e.md"
    ).read_text(encoding="utf-8")

    for fact in (
        "32563104045",
        "f4ea31993d6d5e3b8478789f8f0d008ed5f44961",
        "23 ID",
        "IT-08-local",
        "changed=0 / failed=0",
        "RTO目標300秒以内",
        "Slackへの実配信",
        "AWS `terraform apply / destroy`",
        "D-2",
    ):
        assert fact in evidence
    assert "Slackへの実配信を示す`IT-08`へは\n読み替えません" in evidence


def test_main_merge_workflow_revalidation_is_distinct_from_feature_evidence():
    evidence = (
        ROOT / "docs" / "evidence" / "2026-08-22-full-stack-e2e.md"
    ).read_text(encoding="utf-8")

    assert "main merge後の再検証" in evidence
    assert "43d36ee674f090108153b09451e825e3383494c1" in evidence
    for run_id in (
        "32566169563",
        "32566169574",
        "32566169577",
        "32566169582",
        "32566169583",
    ):
        assert run_id in evidence
    assert "AWS jobのskipをAWS実環境のPASSとして扱いません" in evidence


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
    assert '"--exclude=/.artifacts/"' in tasks
    assert '"--exclude=/deploy/alertmanager/alertmanager.ansible.yml"' in tasks
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
    tasks = role_task_flow("common")

    runtime_task = "Ensure sshd runtime directory exists for configuration validation"
    validation_task = "Disable root SSH login"
    assert "path: /run/sshd" in tasks
    assert tasks.index(runtime_task) < tasks.index(validation_task)


def test_install_path_and_account_are_validated_before_any_host_mutation():
    common = role_task_flow("common")
    app = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )
    nginx = (
        ROOT / "ansible" / "roles" / "nginx" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    monitoring = (
        ROOT / "ansible" / "roles" / "monitoring" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    runner = (ROOT / "scripts" / "e2e" / "run-full-stack.sh").read_text(
        encoding="utf-8"
    )

    assert common.index("Validate install directory syntax") < common.index(
        "Ensure required packages are installed"
    )
    assert common.index("Refuse non-canonical or non-directory install target") < (
        common.index("Ensure required packages are installed")
    )
    assert app.index("Validate source deployment mode") < app.index(
        "Ensure install directory exists"
    )
    app_validation_task = app.split(
        "Validate source deployment mode and target path before mutation", 1
    )[1].split("- name:", 1)[0]
    assert "\n  vars:\n" in app_validation_task
    assert "\n    vars:\n" not in app_validation_task
    assert nginx.index("Validate TLS path and account") < nginx.index(
        "Ensure TLS directory exists"
    )
    assert monitoring.index("Validate monitoring paths and account") < monitoring.index(
        "Ensure deploy target directory exists"
    )
    for text in (common, app, nginx, monitoring):
        assert "'/./' not in" in text
        assert "'/../' not in" in text
        assert "realpath" in text
        assert "!= 'root'" in text
        assert "!= 'docker'" in text
    assert "nginx_tls_dir == server_monitor_install_dir ~ '/deploy/tls'" in nginx
    assert "Inspect TLS material without following leaf symlinks" in nginx
    assert "Refuse unsafe or incomplete TLS material before OpenSSL" in nginx
    assert "ansible.builtin.command:\n    argv:" in nginx
    tls_directory = nginx.split("Ensure TLS directory exists", 1)[1].split(
        "- name:", 1
    )[0]
    assert "state: directory" in tls_directory
    assert "follow: false" in tls_directory
    tls_generation = nginx.split("Generate self-signed TLS material", 1)[1].split(
        "- name:", 1
    )[0]
    assert "- /usr/sbin/runuser" in tls_generation
    assert '- "{{ server_monitor_user }}"' in tls_generation
    assert "become_user:" not in tls_generation
    tls_permissions = nginx.split("Tighten permissions on TLS material", 1)[1]
    assert "state: file" in tls_permissions
    assert "follow: false" in tls_permissions
    assert "monitoring_deploy_target == server_monitor_install_dir ~ '/deploy'" in monitoring
    assert "server_monitor_secrets_dir == monitoring_deploy_target ~ '/secrets'" in monitoring
    assert "Inspect monitoring-managed paths without following final symlinks" in monitoring
    assert "follow: false" in monitoring
    assert "monitoring_deploy_target ~ '/alertmanager'" in monitoring
    assert "Validate Docker bind sources before runtime checks" in monitoring
    assert "Refuse missing, redirected, or incorrectly typed Docker bind sources" in monitoring
    assert "server_monitor_secrets_dir == app_repo_target ~ '/deploy/secrets'" in app
    assert "Refuse a symlinked or redirected secrets directory" in app
    assert "install_dir_canonical=$(realpath -m" in runner
    assert '== *"/../"*' in runner
    assert '== *"/./"*' in runner

    # runuser（util-linux）で権限を落として TLS 素材を作るため、どの OS
    # ファミリーの package 一覧にも util-linux が入っていること。
    # 片方のファミリーだけ入れ忘れると、そのファミリーでだけ nginx ロールが
    # 落ちる。
    common_vars_dir = ROOT / "ansible" / "roles" / "common" / "vars"
    common_vars_files = sorted(common_vars_dir.glob("*.yml"))
    assert {path.name for path in common_vars_files} == {"Debian.yml", "RedHat.yml"}
    for path in common_vars_files:
        assert "- util-linux" in path.read_text(encoding="utf-8"), path.name

    guarded_directory_tasks = (
        (common, "Ensure application install directory exists"),
        (app, "Ensure install directory exists"),
        (app, "Ensure secrets directory exists"),
        (nginx, "Ensure TLS directory exists"),
        (monitoring, "Ensure deploy target directory exists"),
        (monitoring, "Ensure alertmanager directory exists"),
    )
    for role_tasks, task_name in guarded_directory_tasks:
        task = role_tasks.split(task_name, 1)[1].split("- name:", 1)[0]
        assert "state: directory" in task
        assert "follow: false" in task

    backup = (
        ROOT / "ansible" / "roles" / "backup" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    backup_directory = backup.split("Ensure backup target directory exists", 1)[1].split(
        "- name:", 1
    )[0]
    assert "state: directory" in backup_directory
    assert "follow: false" in backup_directory


def test_revision_marker_is_written_only_after_compose_reconciliation():
    tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )

    compose_index = tasks.index("Bring the compose stack up")
    flush_index = tasks.index("Complete notified app handlers before recording the revision")
    marker_index = tasks.index("Record successfully reconciled source revision")
    assert compose_index < flush_index < marker_index
    assert "ansible.builtin.meta: flush_handlers" in tasks[flush_index:marker_index]
    marker_task = tasks.split(
        "- name: Record successfully reconciled source revision", 1
    )[1]
    assert "content: |" in marker_task


def test_alertmanager_handler_respects_absent_compose_state():
    handlers = (
        ROOT / "ansible" / "roles" / "app" / "handlers" / "main.yml"
    ).read_text(encoding="utf-8")

    assert "app_compose_state == 'present'" in handlers


def test_generated_secrets_are_reconciled_to_an_explicit_allowlist():
    tasks = (ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
        encoding="utf-8"
    )

    assert "Remove Slack webhook secret when the overlay is disabled" in tasks
    assert "Find generated secret files for allowlist reconciliation" in tasks
    assert "Remove generated secret files that are no longer configured" in tasks
    assert "app_configured_secret_names" in tasks
    assert "app_secrets | map(attribute='name')" in tasks
    assert "^[A-Za-z0-9._-]+[.]txt$" in tasks
    assert "unique | list | length" in tasks
    assert "'slack_webhook_url.txt' not in app_secret_names" in tasks
    assert "file_type: any" in tasks
    assert "hidden: true" in tasks
    assert tasks.count("follow: false") >= 3


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
    assert "-regextype posix-extended" in template
    assert "[0-9]{8}T[0-9]{6}Z" in template


def test_backup_role_validates_inputs_before_any_target_mutation():
    tasks = (
        ROOT / "ansible" / "roles" / "backup" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")

    assert tasks.index("Validate backup inputs and target") < tasks.index(
        "Ensure backup target directory exists"
    )
    assert tasks.index("Refuse a symlinked or redirected backup target") < tasks.index(
        "Ensure backup target directory exists"
    )
    backup_validation_task = tasks.split(
        "Validate backup inputs and target before mutation", 1
    )[1].split("- name:", 1)[0]
    assert "\n  vars:\n" in backup_validation_task
    assert "\n    vars:\n" not in backup_validation_task
    assert "^/(var/backups|srv/backups)/" in tasks
    assert "backup_compose_dir == server_monitor_install_dir" in tasks
    assert "Refuse a missing, symlinked, or redirected backup Compose directory" in tasks
    assert tasks.count("'/../' not in") >= 2
    assert "backup_compose_realpath.stdout == backup_compose_dir" in tasks
    assert "(backup_retention_days | int) >= 1" in tasks
    assert "(backup_retention_days | int) <= 3650" in tasks
    assert "backup_volume_names | unique" in tasks
    assert "backup_service_names | unique" in tasks
    assert "follow: false" in tasks


def test_internal_markdown_links_resolve_inside_the_repository():
    documents = [ROOT / "README.md", *(ROOT / "docs").rglob("*.md")]
    link_pattern = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
    failures = []

    for document in documents:
        text = document.read_text(encoding="utf-8")
        for raw_target in link_pattern.findall(text):
            raw_target = raw_target.strip()
            if raw_target.startswith("<") and ">" in raw_target:
                target = raw_target[1 : raw_target.index(">")]
            else:
                target = raw_target.split(maxsplit=1)[0]

            parsed = urlsplit(target)
            if parsed.scheme or target.startswith(("#", "//")) or not parsed.path:
                continue

            candidate = (document.parent / unquote(parsed.path)).resolve()
            try:
                candidate.relative_to(ROOT.resolve())
            except ValueError:
                failures.append(f"{document.relative_to(ROOT)} -> outside repo: {target}")
                continue
            if not candidate.exists():
                failures.append(f"{document.relative_to(ROOT)} -> missing: {target}")

    assert not failures, "\n".join(failures)


def test_daily_check_targets_the_deployed_project_and_detects_missing_services():
    script = (ROOT / "scripts" / "ops" / "daily-check.sh").read_text(
        encoding="utf-8"
    )
    workflow = (
        ROOT / ".github" / "workflows" / "python-check.yml"
    ).read_text(encoding="utf-8")

    for expected in (
        "--project-dir",
        "SCRIPT_DIR=",
        ".server-monitor-deploy-revision",
        "--project-directory",
        "compose.slack.yaml.example",
        "compose.ansible.yaml",
        "ps --all",
        "--status running",
        "must be an integer from 1 to 100",
        "df --output=pcent,target",
        "df-over-threshold.awk",
        "配備対象にcompose.yamlがあるがDocker Compose commandを利用できない",
    ):
        assert expected in script
    assert script.index("compose.slack.yaml.example") < script.index(
        "compose.ansible.yaml"
    )
    assert "git ls-files '*.sh'" in workflow
    assert "daily-check.sh --disk-threshold 0" in workflow


def test_disk_usage_parser_preserves_spaces_and_detects_threshold_breach():
    awk = shutil.which("awk")
    if awk is None:
        return

    sample = "Use% Mounted on\n 95% /srv/data volume\n 20% /\n"
    result = subprocess.run(
        [
            awk,
            "-v",
            "threshold=80",
            "-f",
            str(ROOT / "scripts" / "ops" / "df-over-threshold.awk"),
        ],
        input=sample,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "/srv/data volume 95%"


def test_daily_check_reports_missing_service_and_preserves_overlay_order(tmp_path):
    if os.name == "nt":
        return
    bash = shutil.which("bash")
    if bash is None:
        return

    project = tmp_path / "project"
    (project / "deploy" / "secrets").mkdir(parents=True)
    (project / "deploy" / "alertmanager").mkdir(parents=True)
    for relative in (
        "compose.yaml",
        "compose.slack.yaml.example",
        "compose.ansible.yaml",
        "deploy/secrets/slack_webhook_url.txt",
        "deploy/alertmanager/alertmanager.ansible.yml",
    ):
        (project / relative).write_text("test\n", encoding="utf-8")

    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    docker_stub = stub_dir / "docker"
    docker_stub.write_text(
        """#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_STUB_LOG:?}"
if [[ "$1" == "info" || "$1 $2" == "compose version" ]]; then
  exit 0
fi
if [[ " $* " == *" config --services "* ]]; then
  printf 'app\nnginx\n'
elif [[ " $* " == *" ps --services --status running "* ]]; then
  printf 'app\n'
elif [[ " $* " == *" ps --all --format table "* ]]; then
  printf 'SERVICE STATUS\napp Up\n'
elif [[ " $* " == *" ps --all --format "* ]]; then
  printf 'app Up\n'
else
  exit 1
fi
""",
        encoding="utf-8",
    )
    docker_stub.chmod(0o755)
    docker_log = tmp_path / "docker-args.log"
    env = os.environ.copy()
    env["PATH"] = f"{stub_dir}{os.pathsep}{env['PATH']}"
    env["DOCKER_STUB_LOG"] = str(docker_log)

    result = subprocess.run(
        [
            bash,
            str(ROOT / "scripts" / "ops" / "daily-check.sh"),
            "--project-dir",
            str(project),
        ],
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )

    assert result.returncode != 0
    assert "runningでないservice:" in result.stdout
    assert "nginx" in result.stdout
    compose_call = next(
        line for line in docker_log.read_text(encoding="utf-8").splitlines()
        if "config --services" in line
    )
    assert compose_call.index("compose.yaml") < compose_call.index(
        "compose.slack.yaml.example"
    ) < compose_call.index("compose.ansible.yaml")


def test_real_host_inventory_templates_pin_an_immutable_git_release():
    templates = (
        ROOT / "ansible" / "inventory" / "staging.local.yml.example",
        ROOT / "ansible" / "inventory" / "production.yml",
    )

    for template in templates:
        text = template.read_text(encoding="utf-8")
        assert "server_monitor_source_mode: git" in text
        assert 'server_monitor_git_version: "replace-with-40-character-commit-sha"' in text

    workflow = (ROOT / ".github" / "workflows" / "ansible-check.yml").read_text(
        encoding="utf-8"
    )
    assert "cp inventory/staging.local.yml.example inventory/staging-ci.yml" in workflow
    assert "ansible-inventory -i inventory/staging-ci.yml --host monitor-01" in workflow
    assert "ansible-inventory -i inventory/production.yml --host monitor-prod-01" in workflow
    assert 'value["server_monitor_source_mode"] == "git"' in workflow
    assert 'value["server_monitor_environment"] == "production"' in workflow


def test_runbooks_use_commands_available_in_the_deployed_stack():
    runbook_dir = ROOT / "docs" / "runbooks"
    index = (runbook_dir / "README.md").read_text(encoding="utf-8")
    service_down = (runbook_dir / "service-down.md").read_text(encoding="utf-8")
    latency = (runbook_dir / "latency-spike.md").read_text(encoding="utf-8")
    disk = (runbook_dir / "disk-full.md").read_text(encoding="utf-8")
    memory = (runbook_dir / "memory-pressure.md").read_text(encoding="utf-8")
    alertmanager = (runbook_dir / "alertmanager-down.md").read_text(
        encoding="utf-8"
    )

    for filename in (
        "service-down.md",
        "latency-spike.md",
        "disk-full.md",
        "memory-pressure.md",
        "alertmanager-down.md",
    ):
        assert filename in index
    assert "compose.ansible.yaml" in index
    assert "sudo docker compose" in service_down
    assert "slack_api_url_file:" in service_down
    assert "sudo test -s" in service_down
    assert service_down.index("compose.slack.yaml.example") < service_down.index(
        "compose.ansible.yaml"
    )
    assert "python -c 'import time, urllib.request" in latency
    assert "docker compose exec app curl" not in latency
    assert "max-size=10m" in disk
    assert "未設定のため" not in disk
    assert "docker compose stats --no-stream prometheus loki" in memory
    assert "docker stats --no-stream prometheus loki" not in memory
    assert "api/v1/query" in alertmanager
    assert "http://blackbox:9115" not in alertmanager
    assert "Secret mount" in alertmanager


def test_rollback_verify_reuses_the_external_vault_inputs():
    rollback = (
        ROOT / "docs" / "build-package" / "08-change-rollback-plan.md"
    ).read_text(encoding="utf-8")
    rollback_section = rollback.split("## 6. コード・設定のロールバック", 1)[1]
    verify_command = rollback_section.rsplit("playbooks/deploy.yml\n", 1)[1].split(
        "ansible monitor", 1
    )[0]

    assert '--vault-password-file "$VAULT_PASSWORD_FILE"' in verify_command
    assert '-e "@$ACTIVE_VAULT"' in verify_command
    assert "playbooks/verify.yml" in verify_command
    assert "set -euo pipefail" in rollback_section
    assert 'REPO_ROOT="$(git rev-parse --show-toplevel)"' in rollback_section
    assert 'test ! -e "$ROLLBACK_WORKTREE"' in rollback_section


def test_current_docs_separate_rollback_and_external_acceptance_boundaries():
    evidence = (ROOT / "docs" / "evidence" / "README.md").read_text(
        encoding="utf-8"
    )
    rollback_evidence = (
        ROOT
        / "docs"
        / "evidence"
        / "2026-08-23-change-CI-GIT-ROLLBACK.md"
    ).read_text(encoding="utf-8")
    handover = (
        ROOT / "docs" / "build-package" / "07-handover-checklist.md"
    ).read_text(encoding="utf-8")
    build_package = (
        ROOT / "docs" / "build-package" / "README.md"
    ).read_text(encoding="utf-8")
    detailed_design = (
        ROOT / "docs" / "build-package" / "02-detailed-design.md"
    ).read_text(encoding="utf-8")
    rollback_plan = (
        ROOT / "docs" / "build-package" / "08-change-rollback-plan.md"
    ).read_text(encoding="utf-8")
    parameters = (
        ROOT / "docs" / "build-package" / "03-parameter-sheet.md"
    ).read_text(encoding="utf-8")
    network = (
        ROOT / "docs" / "build-package" / "04-network-ip-plan.md"
    ).read_text(encoding="utf-8")

    assert "構成commit / 設定rollback rehearsal" in evidence
    assert "YYYY-MM-DD-change-<ID>.md" in evidence
    assert "2026-08-23-change-CI-GIT-ROLLBACK.md" in evidence
    for expected in (
        "32611251044",
        "84e149254d463a8a27a4cabcd09efa4504d1b47e",
        "59aa88ed1c8ccb7ba188909f0e079b834e9126c7",
        "GIT_MODE_ROLLBACK_REHEARSAL=PASS",
        "candidate-runtime-manifest.diff`は0 byte",
        "rollback-runtime-manifest.diff`は0 byte",
        "LOOPBACK_LISTENERS=PASS",
        "使い捨てrunner",
    ):
        assert expected in rollback_evidence
    for not_run_boundary in (
        "永続host / staging / productionへの変更適用とロールバック: **NOT RUN**",
        "実hostの再起動、24時間・72時間継続確認: **NOT RUN**",
        "AWS `terraform apply / destroy`、AWS Backup restore、D-2: **NOT RUN**",
        "AlertmanagerからSlackへの実配信: **NOT RUN**",
    ):
        assert not_run_boundary in rollback_evidence
    for current_doc in (handover, build_package, detailed_design, rollback_plan):
        assert "2026-08-23-change-CI-GIT-ROLLBACK.md" in current_doc
    assert "引き渡し対象hostの構成commit / 設定rollback rehearsal" in handover
    assert "引き渡し対象hostでは`NOT RUN`" in build_package
    assert "永続hostでは`NOT RUN`" in detailed_design
    assert "引き渡し対象の永続host" in rollback_plan
    assert "Docker API proxy" in parameters
    assert "manifest digest" in parameters
    assert "全送信元" in parameters
    assert "rate limitをsource制限の証跡にはしません" in network


def test_full_stack_ci_executes_scoped_git_mode_rollback_rehearsal():
    script = (
        ROOT / "scripts" / "e2e" / "run-git-rollback-rehearsal.sh"
    ).read_text(encoding="utf-8")
    workflow = (
        ROOT / ".github" / "workflows" / "full-stack-e2e.yml"
    ).read_text(encoding="utf-8")

    for expected in (
        "--confirm-disposable-host",
        "for sha_name in CANDIDATE_SHA ROLLBACK_SHA",
        "must be a full 40-character commit SHA",
        "--git-repo-url must not contain embedded credentials",
        'merge-base --is-ancestor "${ROLLBACK_SHA}" "${CANDIDATE_SHA}"',
        "server_monitor_source_mode=git",
        "app_compose_build_policy: always",
        'worktree add --detach "${CANDIDATE_WORKTREE}" "${CANDIDATE_SHA}"',
        'worktree add --detach "${ROLLBACK_WORKTREE}" "${ROLLBACK_SHA}"',
        "candidate-check.log --check --diff",
        "rollback-check.log --check --diff",
        "candidate revision marker mismatch",
        "rollback revision marker mismatch",
        "write_checkout_runtime_manifest",
        "write_container_runtime_manifest",
        "running app content does not match",
        "app container was not replaced between candidate and rollback",
        "failed to write rollback evidence summary",
        "check_loopback_listeners.py",
        "stale release marker survived rollback synchronization",
        "rollback-loki-query.json",
        "not a persistent/production host, AWS recovery, D-2, or Slack delivery",
    ):
        assert expected in script

    assert "fetch-depth: 0" in workflow
    assert "Run immutable git deployment and rollback rehearsal" in workflow
    assert "github.event.pull_request.head.sha || github.sha" in workflow
    assert "github.event.pull_request.base.sha || github.event.before" in workflow
    assert "select_rollback_sha.py" in workflow
    assert "--requested-rollback-sha" in workflow
    assert "run-git-rollback-rehearsal.sh" in workflow
    assert "change-rollback-summary.md" in workflow
    assert "candidate-actual-runtime-manifest.sha256" in workflow
    assert "rollback-actual-runtime-manifest.sha256" in workflow
    assert "test -s \"$evidence_dir/change-rollback-summary.md\"" in workflow

