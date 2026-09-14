"""D-1 command-stub tests. No real Docker, HTTP, sudo or signal is used."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BASH = os.environ.get("D1_TEST_BASH") or shutil.which("bash")
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/drills/d1-process-down.sh"
STUB = r"""#!/usr/bin/env bash
set -eu
cmd=$(basename "$0")
case "$cmd" in
  sudo) printf '%s\n' "$*" >> "$D1_TEST_TMP/calls"; : > "$D1_TEST_TMP/killed" ;;
  sleep) : ;;
  curl)
    if [[ -f "$D1_TEST_TMP/killed" ]]; then
      case "$D1_TEST_CASE" in
        non_200) printf 204; exit 0 ;;
        http_failure) printf 503; exit 22 ;;
      esac
    fi
    printf 200 ;;
  date)
    if [[ "$*" == *"+%s"* ]]; then
      n=0
      [[ ! -f "$D1_TEST_TMP/tick" ]] || read -r n < "$D1_TEST_TMP/tick"
      echo $((n + 1)) > "$D1_TEST_TMP/tick"
      if [[ "$D1_TEST_CASE" == clock_back && "$n" -gt 0 ]]; then echo 999
      else echo $((1000 + n)); fi
    else printf '2026-09-14T00:00:00Z\n'; fi ;;
  docker)
    if [[ "$1" == compose ]]; then
      [[ "$*" != *"version"* ]] || exit 0
      if [[ "$D1_TEST_CASE" == multiple ]]; then printf 'cid-a\ncid-b\n'
      elif [[ -f "$D1_TEST_TMP/killed" && "$D1_TEST_CASE" == replaced ]]; then echo cid-b
      else echo cid-a; fi
    elif [[ "$1" == inspect ]]; then
      case "$3" in
        *RestartCount*)
          if [[ "$D1_TEST_CASE" == invalid_count ]]; then echo invalid
          elif [[ -f "$D1_TEST_TMP/killed" && "$D1_TEST_CASE" != unchanged ]]; then echo 1
          else echo 0; fi ;;
        *State.Pid*) if [[ "$D1_TEST_CASE" == unsafe_pid ]]; then echo 0; else echo 1234; fi ;;
        *State.Running*) if [[ "$D1_TEST_CASE" == stopped ]]; then echo false; else echo true; fi ;;
        *) exit 94 ;;
      esac
    else exit 95; fi ;;
  *) exit 96 ;;
esac
"""

@unittest.skipUnless(BASH, "Bash required for command-stub D-1 checks")
class RecoveryProofTests(unittest.TestCase):
    def run_case(self, scenario, expected, preflight=False):
        with tempfile.TemporaryDirectory(prefix="d1-command-stubs-") as temporary:
            folder = Path(temporary)
            binary = folder / "bin"
            binary.mkdir()
            for name in ("docker", "curl", "sudo", "date", "sleep"):
                file = binary / name
                file.write_text(STUB, encoding="utf-8", newline="\n")
                file.chmod(0o755)
            env = os.environ.copy()
            for name in ("BASH_ENV", "ENV"):
                env.pop(name, None)
            mock_bin, mock_dir = binary.as_posix(), folder.as_posix()
            if os.name == "nt":
                mock_bin = "/" + mock_bin[0].lower() + mock_bin[2:]
                mock_dir = "/" + mock_dir[0].lower() + mock_dir[2:]
            env.update(D1_TEST_BIN=mock_bin, D1_TEST_TMP=mock_dir,
                       D1_TEST_CASE=scenario)
            # Check command shadowing before running the real script text.
            lookup = subprocess.run([BASH, "--noprofile", "--norc", "-c",
                                     'export PATH="$D1_TEST_BIN:$PATH"; for c in docker curl sudo; do command -v "$c"; done'],
                                    env=env, capture_output=True, text=True, check=True)
            self.assertEqual(len(lookup.stdout.splitlines()), 3)
            self.assertTrue(all("d1-command-stubs-" in p for p in lookup.stdout.splitlines()), lookup.stdout)
            result = subprocess.run([BASH, "--noprofile", "--norc", "-c",
                                     'export PATH="$D1_TEST_BIN:$PATH"; exec bash "$@"',
                                     "d1-test", SCRIPT.as_posix(), "--timeout", "3"],
                                    env=env, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=15)
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
            if preflight:
                self.assertFalse((folder / "killed").exists())
            else:
                self.assertEqual((folder / "calls").read_text().strip(), "kill -9 1234")
                lines = result.stdout.splitlines()
                self.assertTrue(lines[-1].startswith("RESULT_JSON="))
                data = json.loads(lines[-1].split("=", 1)[1])
                self.assertEqual(data["verdict"], "PASS" if expected == 0 else "FAIL")
                if expected == 0:
                    self.assertGreater(int(data["restart_count_after"]),
                                       int(data["restart_count_before"]))

    def test_same_running_container_restarted(self):
        self.run_case("normal", 0)

    def test_unchanged_restart_count(self):
        self.run_case("unchanged", 1)

    def test_replaced_container(self):
        self.run_case("replaced", 1)

    def test_successful_curl_with_non_200_response(self):
        self.run_case("non_200", 1)

    def test_transport_failure(self):
        self.run_case("http_failure", 1)

    def test_not_running_after_restart(self):
        self.run_case("stopped", 1)

    def test_clock_backwards(self):
        self.run_case("clock_back", 1)

    def test_pid_zero_rejected_before_signal(self):
        self.run_case("unsafe_pid", 2, preflight=True)

    def test_ambiguous_target_rejected_before_signal(self):
        self.run_case("multiple", 2, preflight=True)

    def test_invalid_counter_rejected_before_signal(self):
        self.run_case("invalid_count", 2, preflight=True)
