"""Exercise the app role's real Git task without deploying any services.

Only disposable repositories are used. Run on an Ansible-capable controller:
python -m unittest discover -s tests -p test_git_source_fetch.py -v
"""

import copy
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

try:
    import yaml
except ImportError:
    yaml = None


ROOT = Path(__file__).resolve().parents[1]
TASK_FILE = ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml"
FETCH_TASK_NAME = "Fetch immutable release source for git mode"


def find_task(tasks, name):
    """Find a named task inside Ansible block/rescue/always sections."""
    for task in tasks:
        if task.get("name") == name:
            return task
        for section in ("block", "rescue", "always"):
            found = find_task(task.get(section, []), name)
            if found is not None:
                return found
    return None


class GitSourceFetchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name == "nt":
            raise unittest.SkipTest(
                "Ansible controller regression requires Linux; Windows is NOT RUN"
            )
        missing = []
        if yaml is None:
            missing.append("PyYAML")
        cls.git = shutil.which("git")
        cls.ansible_playbook = shutil.which("ansible-playbook")
        if cls.git is None:
            missing.append("git")
        if cls.ansible_playbook is None:
            missing.append("ansible-playbook")
        if missing:
            raise unittest.SkipTest(
                "Git task integration NOT RUN: missing " + ", ".join(missing)
            )
        tasks = yaml.safe_load(TASK_FILE.read_text(encoding="utf-8"))
        cls.fetch_task = find_task(tasks, FETCH_TASK_NAME)
        if cls.fetch_task is None:
            raise AssertionError("The app role's immutable Git fetch task is missing")
        if "ansible.builtin.git" not in cls.fetch_task:
            raise AssertionError("The selected task must execute ansible.builtin.git")

    def setUp(self):
        fixture = tempfile.TemporaryDirectory(prefix="git-source-fetch-")
        self.addCleanup(fixture.cleanup)
        self.root = Path(fixture.name)
        self.seed = self.root / "seed"
        self.remote = self.root / "remote.git"
        self.env = os.environ.copy()
        self.env.update(
            {
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_AUTHOR_NAME": "Git source regression",
                "GIT_AUTHOR_EMAIL": "git-source-test@example.invalid",
                "GIT_COMMITTER_NAME": "Git source regression",
                "GIT_COMMITTER_EMAIL": "git-source-test@example.invalid",
                "ANSIBLE_NOCOLOR": "1",
                "ANSIBLE_FORCE_COLOR": "0",
                "ANSIBLE_STDOUT_CALLBACK": "default",
                "ANSIBLE_HOME": str(self.root / "ansible-home"),
                "ANSIBLE_LOCAL_TEMP": str(self.root / "ansible-local"),
                "ANSIBLE_REMOTE_TEMP": str(self.root / "ansible-remote"),
            }
        )
        config = self.root / "ansible.cfg"
        config.write_text("[defaults]\nforks = 1\n", encoding="utf-8")
        self.env["ANSIBLE_CONFIG"] = str(config)

        self._git("init", "--quiet", "--initial-branch=main", str(self.seed))
        (self.seed / "tracked.txt").write_text("main release\n", encoding="utf-8")
        self._git("-C", str(self.seed), "add", "tracked.txt")
        self._git("-C", str(self.seed), "commit", "--quiet", "-m", "Main release")
        self.main_sha = self._git("-C", str(self.seed), "rev-parse", "HEAD").stdout.strip()

        self._git("-C", str(self.seed), "checkout", "--quiet", "-b", "candidate")
        (self.seed / "candidate-only.txt").write_text(
            "candidate release\n", encoding="utf-8"
        )
        self._git("-C", str(self.seed), "add", "candidate-only.txt")
        self._git("-C", str(self.seed), "commit", "--quiet", "-m", "Candidate release")
        self.candidate_sha = self._git(
            "-C", str(self.seed), "rev-parse", "HEAD"
        ).stdout.strip()

        self._git("init", "--quiet", "--bare", "--initial-branch=main", str(self.remote))
        self.remote_url = self.remote.as_uri()
        self._git(
            "-C",
            str(self.seed),
            "push",
            "--quiet",
            self.remote_url,
            self.main_sha + ":refs/heads/main",
            self.candidate_sha + ":refs/pull/259/head",
        )
        advertised_branches_and_tags = self._git(
            "ls-remote", "--heads", "--tags", self.remote_url
        ).stdout
        self.assertIn(self.main_sha, advertised_branches_and_tags)
        self.assertNotIn(self.candidate_sha, advertised_branches_and_tags)

    def _run(self, argv, *, timeout=45, require_success=True):
        result = subprocess.run(
            argv,
            cwd=self.root,
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
        if require_success and result.returncode != 0:
            self.fail(
                "Command failed: "
                + repr(argv)
                + "\n"
                + result.stdout[-6000:]
            )
        return result

    def _git(self, *args, require_success=True):
        return self._run(
            [self.git, *args], require_success=require_success
        )

    def _run_fetch_task(self, revision, label, *, without_refspec=False):
        staging = self.root / label
        staging.mkdir()
        task = copy.deepcopy(self.fetch_task)
        if without_refspec:
            task["ansible.builtin.git"].pop("refspec", None)
        playbook = [
            {
                "name": "Exercise only the immutable source fetch",
                "hosts": "localhost",
                "connection": "local",
                "gather_facts": False,
                "become": False,
                "vars": {
                    "ansible_python_interpreter": sys.executable,
                    "server_monitor_source_mode": "git",
                    "server_monitor_git_repo": self.remote_url,
                    "server_monitor_git_version": revision,
                    "app_release_staging": {"path": str(staging)},
                },
                "tasks": [task],
            }
        ]
        playbook_path = self.root / (label + ".yml")
        playbook_path.write_text(
            yaml.safe_dump(playbook, sort_keys=False), encoding="utf-8"
        )
        result = self._run(
            [
                self.ansible_playbook,
                "-i",
                "localhost,",
                "-c",
                "local",
                str(playbook_path),
            ],
            timeout=90,
            require_success=False,
        )
        return result, staging / "repository"

    def _assert_checkout(self, result, checkout, expected_sha):
        self.assertEqual(result.returncode, 0, result.stdout[-6000:])
        actual_sha = self._git(
            "-C", str(checkout), "rev-parse", "HEAD"
        ).stdout.strip()
        self.assertEqual(actual_sha, expected_sha)
        expected_tree = self._git(
            "-C", str(self.seed), "rev-parse", expected_sha + "^{tree}"
        ).stdout.strip()
        actual_tree = self._git(
            "-C", str(checkout), "rev-parse", "HEAD^{tree}"
        ).stdout.strip()
        self.assertEqual(actual_tree, expected_tree)

    def test_fetches_candidate_reachable_only_from_pull_ref(self):
        # file:// plus --no-local prevents Git's local object-copy optimization
        # from silently including commits outside the default branch refspec.
        ordinary_clone = self.root / "ordinary-clone"
        self._git(
            "clone", "--quiet", "--no-local", self.remote_url, str(ordinary_clone)
        )
        absent = self._git(
            "-C",
            str(ordinary_clone),
            "cat-file",
            "-e",
            self.candidate_sha + "^{commit}",
            require_success=False,
        )
        self.assertNotEqual(absent.returncode, 0)

        # Reproduce the observed checkout failure using the same production task
        # with only the explicit fetch refspec removed.
        negative, _ = self._run_fetch_task(
            self.candidate_sha, "without-refspec", without_refspec=True
        )
        self.assertNotEqual(negative.returncode, 0, negative.stdout[-6000:])
        self.assertIn("unable to read tree", negative.stdout.lower())

        actual, checkout = self._run_fetch_task(self.candidate_sha, "candidate")
        self._assert_checkout(actual, checkout, self.candidate_sha)
        self.assertEqual(
            (checkout / "candidate-only.txt").read_text(encoding="utf-8"),
            "candidate release\n",
        )

    def test_fetches_commit_reachable_from_main(self):
        actual, checkout = self._run_fetch_task(self.main_sha, "main")
        self._assert_checkout(actual, checkout, self.main_sha)
        self.assertFalse((checkout / "candidate-only.txt").exists())

    def test_rejects_nonexistent_commit(self):
        missing_sha = "f" * 40
        absent = self._git(
            "--git-dir",
            str(self.remote),
            "cat-file",
            "-e",
            missing_sha + "^{commit}",
            require_success=False,
        )
        self.assertNotEqual(absent.returncode, 0)
        actual, checkout = self._run_fetch_task(missing_sha, "missing")
        self.assertNotEqual(actual.returncode, 0, actual.stdout[-6000:])
        self.assertIn(missing_sha, actual.stdout)
        if (checkout / ".git").exists():
            selected = self._git(
                "-C", str(checkout), "rev-parse", "HEAD", require_success=False
            )
            self.assertNotEqual(selected.stdout.strip(), missing_sha)


if __name__ == "__main__":
    unittest.main()
