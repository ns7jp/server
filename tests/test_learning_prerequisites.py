"""Exercise diagnostic decisions with simulated tools; never start a real lab."""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "learning" / "check-prerequisites.sh"
BASH = shutil.which("bash")
pytestmark = pytest.mark.skipif(BASH is None, reason="Bash is required")

# Shell functions isolate the checker from installed Docker and the host's OS.
# Python version checks execute the checker's actual expression with a fake
# version tuple. These are diagnostic regression tests, not Linux/VM evidence.
SIMULATED_TOOLS = r'''
command() {
  if [[ ${1:-} == -v ]]; then
    case "$2" in
      ansible|ansible-playbook) return 1 ;;
    esac
    [[ "$2" == "${TEST_MISSING:-}" ]] && return 1
  fi
  builtin command "$@"
}
uname() { printf '%s\n' "${TEST_OS:-Linux}"; }
git() {
  case "$1" in
    --version) echo 'git version simulated' ;;
    rev-parse) echo true ;;
    status) return 0 ;;
  esac
}
python3() {
  if [[ "$2" == 'import venv, ensurepip' ]]; then
    return "${TEST_VENV_EXIT:-0}"
  fi
  "$TEST_PYTHON" -c 'import os, sys; sys.version_info = (3, int(os.environ.get("TEST_PY_MINOR", "12")), 0); exec(sys.argv[1])' "$2"
}
openssl() { echo 'OpenSSL simulated'; }
curl() { echo 'curl simulated'; }
docker() {
  [[ "$1" == info ]] && return "${TEST_DOCKER_EXIT:-0}"
  echo 'Docker/Compose simulated'
}
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 30000000 1000000 20000000 4%% /\n'; }
awk() {
  if [[ ${2:-} == /proc/meminfo ]]; then
    echo 2097152
  else
    builtin command awk "$@"
  fi
}
ss() { echo "LISTEN 0 128 127.0.0.1:${TEST_LISTEN_PORT:-3000} 0.0.0.0:*"; }
fixture_script=$1
shift
source "$fixture_script" "$@"
'''


def diagnose(*args, cwd=ROOT, **overrides):
    env = os.environ.copy()
    env.update(TEST_PYTHON=Path(sys.executable).as_posix(), **overrides)
    return subprocess.run(
        [BASH, "-c", SIMULATED_TOOLS, "test-prerequisites", SCRIPT.as_posix(), *args],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=20,
        check=False,
    )


def test_minimal_ignores_later_ansible_memory_and_monitoring_ports():
    result = diagnose("--minimal")
    assert result.returncode == 0, result.stderr
    assert "Summary: FAIL=0 WARN=0" in result.stdout
    assert "TCP port 8080" in result.stdout
    assert "TCP port 3000" not in result.stdout
    assert "Step 6" in result.stdout


def test_default_preserves_full_stack_warnings_without_failing():
    result = diagnose()
    assert result.returncode == 0, result.stderr
    for warning in ("ansible/ansible-playbook", "memoryが6 GiB未満", "TCP port 3000は既にlisten"):
        assert warning in result.stdout
    assert "Summary: FAIL=0 WARN=3" in result.stdout


@pytest.mark.parametrize("minor,expected", [("9", 1), ("10", 1), ("11", 0), ("12", 0)])
def test_python_version_matches_the_documented_course(minor, expected):
    result = diagnose("--minimal", TEST_PY_MINOR=minor)
    assert result.returncode == expected, result.stderr
    if expected:
        assert "Python 3.11以上" in result.stdout
        assert "BLOCKED" in result.stdout


@pytest.mark.parametrize(
    "overrides,reason",
    [
        ({"TEST_MISSING": "curl"}, "curlがPATHにありません"),
        ({"TEST_VENV_EXIT": "1"}, "仮想環境の作成"),
        ({"TEST_DOCKER_EXIT": "1"}, "daemonへ接続できません"),
        ({"TEST_OS": "MINGW64_NT"}, "runtime対象はLinux"),
    ],
)
def test_missing_prerequisite_blocks_the_exercise(overrides, reason):
    result = diagnose("--minimal", **overrides)
    assert result.returncode == 1, result.stderr
    assert reason in result.stdout
    assert "BLOCKED" in result.stdout


def test_wrong_working_directory_is_not_a_ready_environment(tmp_path):
    result = diagnose("--minimal", cwd=tmp_path)
    assert result.returncode == 1
    assert "実行場所がserverリポジトリ直下ではありません" in result.stdout


def test_minimal_still_warns_when_the_application_port_is_busy():
    result = diagnose("--minimal", TEST_LISTEN_PORT="8080")
    assert result.returncode == 0
    assert "TCP port 8080は既にlisten" in result.stdout
    assert "Summary: FAIL=0 WARN=1" in result.stdout


def test_unknown_option_does_not_run_diagnostics():
    result = diagnose("--typo")
    assert result.returncode == 2
    assert "unknown argument" in result.stderr
    assert "[PASS]" not in result.stdout
