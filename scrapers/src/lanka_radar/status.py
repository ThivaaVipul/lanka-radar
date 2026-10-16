"""Per-source run history for status.json, so the app can flag a source that went quiet."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

# The scrape run fails (and GitHub emails) once, when a source reaches this many
# failures in a row. Later failures are only recorded, so a long outage is one email.
FAILURES_BEFORE_ALERT = 3


def stamp(moment: datetime) -> str:
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def record(report: dict[str, Any], source: str, now: datetime, error: str | None) -> bool:
    """Updates one source's entry. True when this run is its FAILURES_BEFORE_ALERT-th failure."""
    entry = report.setdefault("sources", {}).setdefault(
        source, {"lastRun": None, "lastSuccess": None, "lastError": None, "failures": 0}
    )
    entry["lastRun"] = stamp(now)
    if error is None:
        entry.update(lastSuccess=entry["lastRun"], lastError=None, failures=0)
        return False
    entry["lastError"] = error[:300]
    entry["failures"] += 1
    return entry["failures"] == FAILURES_BEFORE_ALERT
