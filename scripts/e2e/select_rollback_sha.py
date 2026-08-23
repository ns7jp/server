#!/usr/bin/env python3
"""Select a rollback commit fetchable from the candidate repository."""

from __future__ import annotations

import argparse
import re
import subprocess


FULL_SHA = re.compile(r"^[0-9a-fA-F]{40}$")
ZERO_SHA = "0" * 40


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def select_rollback_sha(candidate_sha: str, requested_sha: str = "") -> str:
    if not FULL_SHA.fullmatch(candidate_sha):
        raise ValueError("candidate SHA must be a full 40-character commit SHA")
    git("cat-file", "-e", f"{candidate_sha}^{{commit}}")
    if FULL_SHA.fullmatch(requested_sha) and requested_sha != ZERO_SHA:
        git("cat-file", "-e", f"{requested_sha}^{{commit}}")
        return git("merge-base", candidate_sha, requested_sha)
    return git("rev-parse", f"{candidate_sha}^1")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_sha")
    parser.add_argument("requested_sha", nargs="?", default="")
    args = parser.parse_args()
    try:
        print(select_rollback_sha(args.candidate_sha, args.requested_sha))
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
