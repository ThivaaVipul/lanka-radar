import pytest
from version import (
    Commit,
    build_number,
    changelog_section,
    latest_version,
    next_release,
    parse_commit,
    release_level,
    render_notes,
)


def commit(subject: str, body: str = "", sha: str = "abc1234") -> Commit:
    return parse_commit(sha, subject, body)


def test_parse_commit_reads_type_scope_and_breaking_marks() -> None:
    parsed = parse_commit("abc", "feat(gazettes): read the list")
    assert (parsed.type, parsed.scope, parsed.subject, parsed.breaking) == (
        "feat",
        "gazettes",
        "read the list",
        False,
    )
    assert parse_commit("abc", "feat!: new data format").breaking
    assert parse_commit("abc", "fix: x", "BREAKING CHANGE: items moved").breaking
    assert parse_commit("abc", "Merge pull request #1 from a/b").type is None


def test_release_level_picks_the_biggest_change() -> None:
    assert release_level([commit("docs: a"), commit("chore: b")]) == "none"
    assert release_level([commit("fix: a"), commit("docs: b")]) == "patch"
    assert release_level([commit("fix: a"), commit("feat: b")]) == "minor"
    assert release_level([commit("feat: a"), commit("fix!: b")]) == "major"


def test_first_release_waits_for_a_change_to_ship() -> None:
    assert not next_release(None, "0.1.0", [commit("chore: set up the project")]).release
    first = next_release(None, "0.1.0", [commit("feat: show the feed")])
    assert (first.release, first.version) == (True, "0.1.0")


@pytest.mark.parametrize(
    ("subject", "expected"),
    [("fix: a", "0.1.1"), ("feat: a", "0.2.0"), ("feat!: a", "1.0.0")],
)
def test_bumps_from_the_last_release(subject: str, expected: str) -> None:
    assert next_release("0.1.0", "0.1.0", [commit(subject)]).version == expected


def test_skips_when_nothing_is_releasable() -> None:
    result = next_release("0.1.0", "0.1.0", [commit("docs: a")])
    assert (result.release, result.version) == (False, "0.1.0")


def test_a_higher_pubspec_version_wins() -> None:
    result = next_release("0.4.1", "1.0.0", [commit("docs: a")])
    assert (result.release, result.version) == (True, "1.0.0")


def test_rejects_a_malformed_pubspec_version() -> None:
    with pytest.raises(ValueError):
        next_release(None, "next", [])


def test_latest_version_finds_the_newest_tag() -> None:
    assert latest_version(["v0.1.0", "v0.10.0", "v0.9.1", "nightly", ""]) == "0.10.0"
    assert latest_version([""]) is None


def test_build_number_grows_with_the_version() -> None:
    assert build_number("0.1.0") == 1_000
    assert build_number("1.2.3") == 1_002_003
    assert build_number("0.9.999") < build_number("0.10.0") < build_number("1.0.0")
    with pytest.raises(ValueError):
        build_number("1.1000.0")


def test_notes_group_by_type() -> None:
    notes = render_notes(
        [
            commit("feat(app): show the feed", sha="a1"),
            commit("fix: sync", sha="b2"),
            commit("docs: readme", sha="c3"),
        ]
    )
    assert "### Features\n\n- **app:** show the feed (a1)" in notes
    assert "### Fixes\n\n- sync (b2)" in notes
    assert "readme" not in notes


def test_changelog_section_is_read_by_version() -> None:
    markdown = (
        "# Changelog\n\n## 0.2.0 - 2026-11-01\n\nBig one.\n\n## 0.1.0 - 2026-10-20\n\nFirst.\n"
    )
    assert changelog_section(markdown, "0.2.0") == "Big one.\n"
    assert changelog_section(markdown, "0.2.1") is None
