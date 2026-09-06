"""Exercise read-only daily checks with controlled command results."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def prepare_daily_check(tmp_path):
    bash = shutil.which("bash")
    if bash is None:
        raise unittest.SkipTest("Bash is required to execute daily-check.sh")

    project = tmp_path / "project"
    project.mkdir()
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    stubs = {
        "df": """if [[ "$1" == "--output=pcent,target" ]]; then
  printf 'Use%% Mounted on\\n 20%% /\\n'
else
  printf 'Filesystem Size Used Avail Use%% Mounted on\\ntest 10G 2G 8G 20%% /\\n'
fi
""",
        "systemctl": """case "${SYSTEMCTL_CASE:-empty}" in
  fail) printf 'Failed to connect to bus\\n' >&2; exit 1 ;;
  failed-unit) printf 'example.service loaded failed failed Example\\n' ;;
esac
""",
        "journalctl": """case "${JOURNAL_CASE:-empty}" in
  fail) printf 'Failed to open journal\\n' >&2; exit 1 ;;
  entries)
    if [[ " $* " == *" --output=json "* ]]; then
      printf '%s\\n' '{"MESSAGE":"first line\\nsecond line"}' '{"MESSAGE":"another error"}'
    else
      printf 'first line\\nsecond line\\nanother error\\n'
    fi
    ;;
  empty)
    if [[ " $* " != *" --quiet "* ]]; then
      printf '%s\\n' '-- No entries --'
    fi
    ;;
esac
exit 0
""",
        # No real daemon, sockets, or deployment are accessed by these tests.
        "docker": "exit 1\n",
        "ss": "exit 0\n",
    }
    for name, body in stubs.items():
        command = stub_dir / name
        command.write_text(
            "#!/usr/bin/env bash\n" + body, encoding="utf-8", newline="\n"
        )
        command.chmod(0o755)

    def run(systemctl_case="empty", journal_case="empty"):
        env = os.environ.copy()
        env["PATH"] = f"{stub_dir}{os.pathsep}{env['PATH']}"
        env["SYSTEMCTL_CASE"] = systemctl_case
        env["JOURNAL_CASE"] = journal_case
        return subprocess.run(
            [
                bash,
                str(ROOT / "scripts" / "ops" / "daily-check.sh"),
                "--project-dir",
                str(project),
            ],
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
            env=env,
        )

    return run


class DailyCheckTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.daily_check = prepare_daily_check(Path(directory.name))

    def test_empty_successful_queries_do_not_count_journal_banner(self):
        result = self.daily_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("[OK] failed unit なし", result.stdout)
        self.assertIn("エラーログ件数: 0", result.stdout)
        self.assertIn("[OK] エラーログなし", result.stdout)
        self.assertNotIn("[NG]", result.stdout)

    def test_systemctl_failure_is_not_healthy(self):
        result = self.daily_check(systemctl_case="fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[NG] systemctlからfailed unitを取得できない", result.stdout)
        self.assertNotIn("[OK] failed unit なし", result.stdout)

    def test_journalctl_failure_is_not_healthy(self):
        result = self.daily_check(journal_case="fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[NG] journalctlからエラーログを取得できない", result.stdout)
        self.assertNotIn("[OK] エラーログなし", result.stdout)
        self.assertNotIn("エラーログ件数:", result.stdout)

    def test_failed_units_are_still_reported(self):
        result = self.daily_check(systemctl_case="failed-unit")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("example.service", result.stdout)
        self.assertIn("[NG] failed unit あり", result.stdout)

    def test_journal_counts_entries_including_multiline_messages(self):
        result = self.daily_check(journal_case="entries")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("エラーログ件数: 2", result.stdout)
        self.assertIn("[NG] エラーログが 2 件検出された", result.stdout)
