from datetime import UTC, datetime, timedelta
from typing import Any

from lanka_radar import status

NOW = datetime(2026, 10, 16, 5, 30, tzinfo=UTC)


def test_success_resets_the_failure_count() -> None:
    report: dict[str, Any] = {}

    status.record(report, "fuel", NOW, "TimeoutError: slow")
    status.record(report, "fuel", NOW + timedelta(hours=3), None)

    assert report["sources"]["fuel"] == {
        "lastRun": "2026-10-16T08:30:00Z",
        "lastSuccess": "2026-10-16T08:30:00Z",
        "lastError": None,
        "failures": 0,
    }


def test_alerts_once_on_the_third_failure_in_a_row() -> None:
    report: dict[str, Any] = {}

    alerts = [
        status.record(report, "fuel", NOW + timedelta(hours=3 * n), "HTTPStatusError: 503")
        for n in range(5)
    ]

    assert alerts == [False, False, True, False, False]
    assert report["sources"]["fuel"]["failures"] == 5
    assert report["sources"]["fuel"]["lastSuccess"] is None


def test_long_errors_are_cut() -> None:
    report: dict[str, Any] = {}

    status.record(report, "fuel", NOW, "x" * 1000)

    assert len(report["sources"]["fuel"]["lastError"]) == 300
