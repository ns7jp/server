from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

import pytest


ROOT = Path(__file__).resolve().parents[1]


def load_module(relative_path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_git(repository: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=repository, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def commit_file(repository: Path, name: str, content: str, message: str) -> str:
    (repository / name).write_text(content, encoding="utf-8")
    run_git(repository, "add", name)
    run_git(repository, "commit", "-m", message)
    return run_git(repository, "rev-parse", "HEAD")


def test_select_rollback_uses_common_ancestor_for_stale_branch(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    helper = load_module(
        "scripts/e2e/select_rollback_sha.py", "select_rollback_sha_helper"
    )
    repository = tmp_path / "repository"
    repository.mkdir()
    run_git(repository, "init", "-b", "main")
    run_git(repository, "config", "user.name", "CI Test")
    run_git(repository, "config", "user.email", "ci@example.test")
    common = commit_file(repository, "state.txt", "common\n", "common")
    run_git(repository, "switch", "-c", "candidate")
    candidate = commit_file(repository, "candidate.txt", "candidate\n", "candidate")
    candidate_remote = tmp_path / "candidate-remote.git"
    subprocess.run(
        ["git", "clone", "--bare", str(repository), str(candidate_remote)],
        check=True,
        capture_output=True,
        text=True,
    )
    run_git(repository, "switch", "main")
    requested_base = commit_file(repository, "base.txt", "advanced\n", "base advances")

    monkeypatch.chdir(repository)
    selected = helper.select_rollback_sha(candidate, requested_base)

    assert selected == common
    assert run_git(repository, "merge-base", "--is-ancestor", selected, candidate) == ""
    assert selected != requested_base
    run_git(candidate_remote, "cat-file", "-e", f"{selected}^{{commit}}")
    missing_base = subprocess.run(
        ["git", "cat-file", "-e", f"{requested_base}^{{commit}}"],
        cwd=candidate_remote,
        capture_output=True,
        text=True,
    )
    assert missing_base.returncode != 0


def test_listener_validator_rejects_any_specific_non_loopback_binding() -> None:
    helper = load_module(
        "scripts/e2e/check_loopback_listeners.py", "check_loopback_listeners_helper"
    )
    lines = [
        "LISTEN 0 4096 127.0.0.1:8080 0.0.0.0:* users:((\"docker\",pid=1,fd=1))",
        "LISTEN 0 4096 192.0.2.10:8080 0.0.0.0:* users:((\"docker\",pid=1,fd=2))",
        "LISTEN 0 4096 [::1]:9090 [::]:* users:((\"docker\",pid=1,fd=3))",
    ]

    errors = helper.validate_listeners(lines, {8080, 9090})

    assert "port 8080 is exposed on non-loopback address: 192.0.2.10" in errors
    assert not any("missing" in error for error in errors)


def git_bash() -> str | None:
    if os.name != "nt":
        return shutil.which("bash")
    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    candidate = program_files / "Git" / "bin" / "bash.exe"
    return str(candidate) if candidate.exists() else None


def test_rehearsal_option_without_value_exits_two() -> None:
    bash = git_bash()
    if bash is None:
        pytest.skip("bash is unavailable")
    script = ROOT / "scripts/e2e/run-git-rollback-rehearsal.sh"
    if os.name == "nt":
        drive = script.drive.rstrip(":").lower()
        msys_path = f"/{drive}/{script.relative_to(script.anchor).as_posix()}"
        command = [
            bash,
            "-lc",
            f"export PATH=/usr/bin:/bin; bash '{msys_path}' --candidate-sha",
        ]
    else:
        command = [bash, str(script), "--candidate-sha"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)

    assert result.returncode == 2
    assert "--candidate-sha requires a value" in result.stderr
