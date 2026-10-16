"""Works out the next release from git history and writes the release notes.

Run from the repo root: `python scripts/release/next_release.py`. In GitHub Actions it
also writes the `version`, `build_number` and `release` step outputs.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from version import (
    Commit,
    build_number,
    changelog_section,
    latest_version,
    next_release,
    parse_commit,
    render_notes,
)

PUBSPEC = Path("app/pubspec.yaml")
CHANGELOG = Path("CHANGELOG.md")
# Releases ship the app, so only commits that change it count.
APP = "app"


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def pubspec_version() -> str:
    text = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)", text, re.MULTILINE)
    if not match:
        raise SystemExit(f"{PUBSPEC} has no X.Y.Z version")
    return match.group(1)


def commits_since(last_version: str | None) -> list[Commit]:
    """App commits since the last release; scraper and tooling work never ships a release."""
    log_range = f"v{last_version}..HEAD" if last_version else "HEAD"
    raw = git("log", "--format=%h%x1f%s%x1f%b%x1e", log_range, "--", APP)
    commits = []
    for entry in raw.split("\x1e"):
        if entry.strip():
            sha, subject, body = (entry.strip().split("\x1f") + ["", ""])[:3]
            commits.append(parse_commit(sha, subject, body))
    return commits


def main() -> None:
    last_version = latest_version(git("tag", "--list", "v*", "--merged", "HEAD").splitlines())
    commits = commits_since(last_version)
    result = next_release(last_version, pubspec_version(), commits)

    changelog = CHANGELOG.read_text(encoding="utf-8") if CHANGELOG.exists() else ""
    notes = changelog_section(changelog, result.version) or render_notes(commits)
    Path(os.environ.get("RELEASE_NOTES", "release-notes.md")).write_text(notes, encoding="utf-8")

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"version={result.version}\n")
            handle.write(f"build_number={build_number(result.version)}\n")
            handle.write(f"release={str(result.release).lower()}\n")

    if result.release:
        print(f"Next release: v{result.version} ({result.reason})")
    else:
        print(f"No release: {result.reason}")


if __name__ == "__main__":
    main()
