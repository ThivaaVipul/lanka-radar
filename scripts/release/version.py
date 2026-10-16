"""Pure helpers that work out the next release from Conventional Commits.

feat -> minor, fix/perf/revert -> patch, "!" or "BREAKING CHANGE:" -> major.
Other types (docs, chore, ci, test, refactor, style, build) don't release.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass

_HEADER = re.compile(r"^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$")
_BREAKING_FOOTER = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)
_VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
_PATCH_TYPES = {"fix", "perf", "revert"}
_LEVELS = ("none", "patch", "minor", "major")


@dataclass(frozen=True)
class Commit:
    sha: str
    type: str | None
    scope: str | None
    subject: str
    breaking: bool


@dataclass(frozen=True)
class Release:
    release: bool
    version: str
    reason: str


def parse_commit(sha: str, subject: str, body: str = "") -> Commit:
    match = _HEADER.match(subject.strip())
    breaking = bool(match and match.group(3)) or bool(_BREAKING_FOOTER.search(body))
    if not match:
        return Commit(sha, None, None, subject.strip(), breaking)
    scope = match.group(2) or None
    return Commit(sha, match.group(1).lower(), scope, match.group(4).strip(), breaking)


def release_level(commits: list[Commit]) -> str:
    level = 0
    for commit in commits:
        if commit.breaking:
            return "major"
        if commit.type == "feat":
            level = max(level, 2)
        elif commit.type in _PATCH_TYPES:
            level = max(level, 1)
    return _LEVELS[level]


def parse_version(text: str | None) -> tuple[int, int, int] | None:
    match = _VERSION.match(text or "")
    if not match:
        return None
    major, minor, patch = (int(part) for part in match.groups())
    return major, minor, patch


def bump(version: str, level: str) -> str:
    major, minor, patch = _require(version)
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    if level == "patch":
        return f"{major}.{minor}.{patch + 1}"
    return version


def latest_version(tags: list[str]) -> str | None:
    """Highest vX.Y.Z tag, or None."""
    versions = [tag.strip().removeprefix("v") for tag in tags]
    valid = [version for version in versions if parse_version(version)]
    return max(valid, key=_require) if valid else None


def build_number(version: str) -> int:
    """Android version code. It grows with every version while minor and patch stay below 1000."""
    major, minor, patch = _require(version)
    if minor >= 1000 or patch >= 1000:
        raise ValueError(f"{version}: minor and patch must stay below 1000")
    return major * 1_000_000 + minor * 1_000 + patch


def next_release(last_version: str | None, base_version: str, commits: list[Commit]) -> Release:
    """Decides the next release.

    Without an earlier release, the pubspec version ships once there is a change to ship.
    A pubspec version above the computed one wins, so a version can still be set by hand.
    """
    if not parse_version(base_version):
        raise ValueError(f'pubspec version "{base_version}" is not X.Y.Z')
    level = release_level(commits)
    if last_version is None:
        if level == "none":
            reason = "nothing to ship yet (no feat, fix or perf commits)"
            return Release(False, base_version, reason)
        return Release(True, base_version, "first release, from pubspec.yaml")
    bumped = bump(last_version, level)
    version = base_version if _require(base_version) > _require(bumped) else bumped
    if _require(version) <= _require(last_version):
        reason = f"no feat, fix, perf or breaking commits since v{last_version}"
        return Release(False, last_version, reason)
    reason = "version set in pubspec.yaml" if level == "none" else f"{level} change"
    return Release(True, version, reason)


_SECTIONS: tuple[tuple[str, Callable[[Commit], bool]], ...] = (
    ("Breaking changes", lambda c: c.breaking),
    ("Features", lambda c: not c.breaking and c.type == "feat"),
    ("Fixes", lambda c: not c.breaking and c.type == "fix"),
    ("Performance", lambda c: not c.breaking and c.type == "perf"),
    ("Reverts", lambda c: not c.breaking and c.type == "revert"),
)


def render_notes(commits: list[Commit]) -> str:
    """Release notes grouped by change type, one line per commit."""
    parts = []
    for title, matches in _SECTIONS:
        lines = [
            f"- {f'**{c.scope}:** ' if c.scope else ''}{c.subject} ({c.sha})"
            for c in commits
            if matches(c)
        ]
        if lines:
            parts.append(f"### {title}\n\n" + "\n".join(lines))
    return "\n\n".join(parts) + "\n" if parts else "Maintenance release.\n"


def changelog_section(markdown: str, version: str) -> str | None:
    """The CHANGELOG.md section for a version ("## 0.2.0 - date"), or None."""
    lines = markdown.splitlines()
    start = next(
        (
            i
            for i, line in enumerate(lines)
            if line == f"## {version}" or line.startswith(f"## {version} ")
        ),
        None,
    )
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    section = "\n".join(lines[start + 1 : end]).strip()
    return f"{section}\n" if section else None


def _require(version: str) -> tuple[int, int, int]:
    parsed = parse_version(version)
    if parsed is None:
        raise ValueError(f'"{version}" is not X.Y.Z')
    return parsed
