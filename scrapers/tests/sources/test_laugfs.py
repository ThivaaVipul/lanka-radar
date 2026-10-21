import json
from collections.abc import Callable
from datetime import date

import httpx
import pytest

from lanka_radar import districts
from lanka_radar.sources import laugfs
from lanka_radar.store import Store
from lanka_radar.web import Web

PAGE = "laugfs_pricelist.html"


def test_parse_reads_the_home_sizes_for_every_district(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    sizes, prices = laugfs.parse(fixture_bytes(PAGE).decode("utf-8"))

    assert sizes == ["12.5 kg", "5 kg", "2 kg"]
    assert list(prices) == list(districts.DISTRICTS)
    assert prices["Colombo"] == [4965.0, 1988.0, 795.0]
    # Laugfs writes Nuwaraeliya.
    assert prices["Nuwara Eliya"] == [5184.0, 2119.0, 850.0]
    assert prices["Kilinochchi"] == [5268.0, 2170.0, 868.0]


@pytest.mark.parametrize(
    ("change", "error"),
    [
        (("<td>Jaffna</td>", "<td>Somewhere</td>"), "no prices for Jaffna"),
        (("<td>4965.00</td>", "<td>496.50</td>"), "Colombo: 496.5 for 12.5 kg"),
        (("5kg (Rs)", "5 litres"), "expected the sizes"),
    ],
)
def test_parse_rejects_a_changed_table(
    fixture_bytes: Callable[[str], bytes], change: tuple[str, str], error: str
) -> None:
    page = fixture_bytes(PAGE).decode("utf-8").replace(*change, 1)

    with pytest.raises(ValueError, match=error):
        laugfs.parse(page)


def site(page: str) -> Web:
    return Web(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, text=page)),
        sleep=lambda seconds: None,
    )


def test_the_first_read_records_the_prices_and_a_change_is_news(
    fixture_bytes: Callable[[str], bytes], store: Store
) -> None:
    page = fixture_bytes(PAGE).decode("utf-8")

    assert laugfs.run(site(page), store, date(2026, 10, 21)) == 0
    dataset = store.read_dataset(laugfs.DATASET) or {}
    assert dataset["prices"]["Colombo"] == [4965.0, 1988.0, 795.0]
    assert dataset["since"] is None
    assert not list(store.root.glob("items/*/*/*.json"))

    # The same prices again: nothing new.
    assert laugfs.run(site(page), store, date(2026, 10, 22)) == 0

    cheaper = page.replace("<td>4965.00</td>", "<td>4765.00</td>")
    assert laugfs.run(site(cheaper), store, date(2026, 11, 5)) == 1

    item = json.loads((store.root / "items/2026/11/gas-laugfs-2026-11-05.json").read_text("utf-8"))
    assert item["headline"]["en"] == "Laugfs gas prices from 5 Nov 2026"
    assert item["topic"] == "prices"
    assert item["alert"] is True
    assert item["keyNumbers"][0] == {
        "label": "12.5 kg",
        "value": 4765.0,
        "unit": "LKR",
        "previous": 4965.0,
    }
    assert item["data"]["before"]["Colombo"] == [4965.0, 1988.0, 795.0]
    dataset = store.read_dataset(laugfs.DATASET) or {}
    assert dataset["since"] == "2026-11-05"
    assert dataset["before"]["Colombo"][0] == 4965.0
