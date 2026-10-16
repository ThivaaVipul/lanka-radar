import json
from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace
from typing import Any

from lanka_radar import cli
from lanka_radar.items import Item
from lanka_radar.store import Store

# 20:00 UTC is 01:30 the next morning in Sri Lanka.
NOW = datetime(2026, 10, 16, 20, 0, tzinfo=UTC)


def source(run: Any) -> Any:
    return SimpleNamespace(NAME="test", run=run)


def broken(web: Any, store: Store, today: date) -> int:
    raise ValueError("the page layout changed")


def test_one_broken_source_does_not_stop_the_others(store: Store) -> None:
    days: list[date] = []

    def fine(web: Any, store: Store, today: date) -> int:
        days.append(today)
        store.put_item(Item(id="x-1", source="x", topic="prices", headline_en="x", published=today))
        return 1

    code = cli.run(store, None, ["b", "a"], NOW, {"a": source(fine), "b": source(broken)})

    assert code == 0
    assert days == [date(2026, 10, 17)]
    report = json.loads((store.root / "status.json").read_text(encoding="utf-8"))
    assert report["sources"]["a"]["failures"] == 0
    assert report["sources"]["b"] == {
        "lastRun": "2026-10-16T20:00:00Z",
        "lastSuccess": None,
        "lastError": "ValueError: the page layout changed",
        "failures": 1,
    }
    latest = json.loads((store.root / "latest.json").read_text(encoding="utf-8"))
    assert [entry["id"] for entry in latest["items"]] == ["x-1"]
    month = json.loads((store.root / "months" / "2026-10.json").read_text(encoding="utf-8"))
    assert [entry["id"] for entry in month["items"]] == ["x-1"]


def test_exits_1_once_when_a_source_fails_three_runs_in_a_row(store: Store) -> None:
    sources = {"b": source(broken)}

    codes = [cli.run(store, None, ["b"], NOW + timedelta(hours=3 * n), sources) for n in range(4)]

    assert codes == [0, 0, 1, 0]


def test_drops_the_status_of_a_removed_source(store: Store) -> None:
    store.write_status({"sources": {"fuel": {"failures": 1}}}, NOW)

    cli.run(store, None, ["b"], NOW, {"b": source(lambda web, store, today: 0)})

    report = json.loads((store.root / "status.json").read_text(encoding="utf-8"))
    assert list(report["sources"]) == ["b"]
