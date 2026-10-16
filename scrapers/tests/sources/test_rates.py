import json
from collections.abc import Callable
from datetime import date, timedelta

import httpx
import pytest

from lanka_radar.sources import rates
from lanka_radar.store import Store

FRANKFURTER = "frankfurter_usd_lkr.json"


def series(start: date, values: list[float]) -> dict[date, float]:
    return {start + timedelta(days=offset): value for offset, value in enumerate(values)}


def test_parse_reads_the_cbsl_series(fixture_bytes: Callable[[str], bytes]) -> None:
    found = rates.parse(json.loads(fixture_bytes(FRANKFURTER)))

    assert min(found) == date(2026, 10, 1)
    assert found[date(2026, 10, 1)] == 330.7005


def test_parse_rejects_an_empty_answer() -> None:
    with pytest.raises(ValueError):
        rates.parse([])


def test_reports_a_weekly_move_of_2_percent_once() -> None:
    moves = rates.weekly_moves(series(date(2026, 3, 1), [300.0] * 8 + [307.0] * 10))

    assert [(move.day, move.week_ago) for move in moves] == [(date(2026, 3, 9), 300.0)]
    assert round(moves[0].change, 4) == 0.0233


def test_ignores_small_moves() -> None:
    drift = [300.0 + day * 0.1 for day in range(40)]

    assert rates.weekly_moves(series(date(2026, 3, 1), drift)) == []


def test_move_item_reads_naturally() -> None:
    item = rates.move_item(rates.Move(date(2026, 3, 9), 294.0, 300.0))

    assert item.id == "rates-usd-lkr-2026-03-09"
    assert item.headline_en == "USD/LKR down 2.0% in a week, to 294.00"
    assert item.alert is True


def test_reads_from_january_first_then_rechecks_two_weeks(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    asked: list[tuple[str, str]] = []

    def frankfurter(request: httpx.Request) -> httpx.Response:
        asked.append((request.url.params["from"], request.url.params["to"]))
        return httpx.Response(200, content=fixture_bytes(FRANKFURTER))

    web = make_web({"api.frankfurter.dev": frankfurter})

    rates.run(web, store, date(2026, 10, 16))
    rates.run(web, store, date(2026, 10, 17))

    last = max(rates.parse(json.loads(fixture_bytes(FRANKFURTER))))
    assert asked == [
        ("2026-01-01", "2026-10-16"),
        ((last - timedelta(days=14)).isoformat(), "2026-10-17"),
    ]
    dataset = store.read_dataset("usd-lkr")
    assert dataset is not None
    assert dataset["source"] == "frankfurter"
    assert dataset["rates"][0] == {"date": "2026-10-01", "rate": 330.7005}
