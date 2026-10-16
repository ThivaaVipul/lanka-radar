import json
from collections.abc import Callable
from datetime import date, timedelta
from urllib.parse import parse_qsl

import httpx

from lanka_radar.sources import rates
from lanka_radar.store import Store

CBSL = "cbsl_usd_rates.html"
FRANKFURTER = "frankfurter_usd_lkr.json"


def series(start: date, values: list[float]) -> dict[date, float]:
    return {start + timedelta(days=offset): value for offset, value in enumerate(values)}


def test_parse_cbsl_reads_the_results_table(fixture_bytes: Callable[[str], bytes]) -> None:
    found = rates.parse_cbsl(fixture_bytes(CBSL).decode("utf-8"))

    assert len(found) == 12
    assert min(found) == date(2026, 10, 1)
    assert found[date(2026, 10, 16)] == 331.286


def test_frankfurter_carries_the_same_cbsl_numbers(fixture_bytes: Callable[[str], bytes]) -> None:
    cbsl = rates.parse_cbsl(fixture_bytes(CBSL).decode("utf-8"))
    copy = rates.parse_frankfurter(json.loads(fixture_bytes(FRANKFURTER)))

    shared = set(cbsl) & set(copy)
    assert shared
    assert all(abs(cbsl[day] - copy[day]) < 0.0001 for day in shared)


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
    forms: list[dict[str, str]] = []

    def cbsl(request: httpx.Request) -> httpx.Response:
        forms.append(dict(parse_qsl(request.content.decode())))
        return httpx.Response(200, content=fixture_bytes(CBSL))

    web = make_web({"cbsl.gov.lk": cbsl})

    rates.run(web, store, date(2026, 10, 16))
    rates.run(web, store, date(2026, 10, 17))

    assert [(form["txtStart"], form["txtEnd"]) for form in forms] == [
        ("2026-01-01", "2026-10-16"),
        ("2026-10-02", "2026-10-17"),
    ]
    dataset = store.read_dataset("usd-lkr")
    assert dataset is not None
    assert dataset["source"] == "cbsl"
    assert dataset["rates"][-1] == {"date": "2026-10-16", "rate": 331.286}


def test_falls_back_to_frankfurter_when_cbsl_fails(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    web = make_web(
        {
            "cbsl.gov.lk": lambda _: httpx.Response(503),
            "api.frankfurter.dev": lambda _: httpx.Response(
                200, content=fixture_bytes(FRANKFURTER)
            ),
        }
    )

    rates.run(web, store, date(2026, 10, 16))

    dataset = store.read_dataset("usd-lkr")
    assert dataset is not None
    assert dataset["source"] == "frankfurter"
    assert dataset["rates"][0] == {"date": "2026-10-01", "rate": 330.7005}
