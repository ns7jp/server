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
        ROOT / "ansible" / "group_vars" / "all" / "main.yml"
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


def test_ansible_compose_secrets_are_readable_by_non_root_container_uids():
    app_tasks = (
        ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml"
    ).read_text(encoding="utf-8")
    alertmanager_runbook = (
        ROOT / "docs" / "runbooks" / "alertmanager-down.md"
    ).read_text(encoding="utf-8")

    assert "mode: '0700'" in app_tasks
    assert app_tasks.count("mode: '0644'") == 2
    assert "mode: '0600'" not in app_tasks
    assert "Compose secrets ファイルが `0644`" in alertmanager_runbook

