import json
from collections.abc import Callable
from datetime import date

import httpx
import pytest

from lanka_radar.items import KeyNumber
from lanka_radar.sources import fuel
from lanka_radar.store import Store

FEED = "ceypetco_fuel_prices.json"


def test_parse_keeps_retail_fuels_only(fixture_bytes: Callable[[str], bytes]) -> None:
    prices = fuel.parse(json.loads(fixture_bytes(FEED)))

    assert [price.product for price in prices] == [
        "Lanka Auto Diesel",
        "Lanka Industrial Kerosene",
        "Lanka Kerosene",
        "Lanka Petrol 92 Octane",
        "Lanka Petrol 95 Octane Euro 4",
        "Lanka Super Diesel 4 Star Euro 4",
    ]
    assert prices[0] == fuel.Price("Lanka Auto Diesel", 392.0, date(2026, 9, 30))


def test_parse_rejects_a_failed_feed() -> None:
    with pytest.raises(ValueError):
        fuel.parse({"success": False, "data": []})


def test_first_run_makes_one_item_per_effective_date(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    web = make_web(
        {"api.ceypetco.gov.lk": lambda _: httpx.Response(200, content=fixture_bytes(FEED))}
    )

    assert fuel.run(web, store, date(2026, 10, 16)) == 3

    item = json.loads((store.root / "items/2026/09/fuel-2026-09-30.json").read_text("utf-8"))
    assert item["headline"]["en"] == "Fuel prices from 30 Sep 2026"
    assert item["alert"] is True
    assert [number["label"] for number in item["keyNumbers"]] == [
        "Lanka Auto Diesel",
        "Lanka Petrol 92 Octane",
        "Lanka Petrol 95 Octane Euro 4",
        "Lanka Super Diesel 4 Star Euro 4",
    ]
    assert all("previous" not in number for number in item["keyNumbers"])
    assert store.has_item("fuel-2026-05-30")
    assert store.has_item("fuel-2026-04-01")
    assert fuel.run(web, store, date(2026, 10, 16)) == 0


def test_a_price_change_shows_the_previous_price() -> None:
    history = fuel.merge_history({}, [fuel.Price("Lanka Auto Diesel", 382.0, date(2026, 8, 31))])
    history = fuel.merge_history(
        history, [fuel.Price("Lanka Auto Diesel", 392.0, date(2026, 9, 30))]
    )

    items = fuel.items_from(history)

    assert [item.id for item in items] == ["fuel-2026-08-31", "fuel-2026-09-30"]
    assert items[1].key_numbers == [KeyNumber("Lanka Auto Diesel", 392.0, "LKR/l", 382.0)]


def test_a_correction_replaces_the_same_day() -> None:
    history = fuel.merge_history({}, [fuel.Price("Lanka Kerosene", 280.0, date(2026, 5, 30))])
    history = fuel.merge_history(history, [fuel.Price("Lanka Kerosene", 285.0, date(2026, 5, 30))])

    assert history == {"Lanka Kerosene": [{"effective": "2026-05-30", "price": 285.0}]}


def test_prices_from_before_2026_make_no_item() -> None:
    history = fuel.merge_history({}, [fuel.Price("Lanka Kerosene", 270.0, date(2025, 12, 1))])

    assert fuel.items_from(history) == []
