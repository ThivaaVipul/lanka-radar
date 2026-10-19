from collections.abc import Callable
from datetime import date

import httpx
import pytest

from lanka_radar.sources import market
from lanka_radar.store import Store

LISTING = "cbsl_price_report_listing.html"
OCTOBER = "cbsl_price_report_20261019.pdf"
JANUARY = "cbsl_price_report_20260102.pdf"


def test_parse_reads_each_markets_retail_price_today(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    rows = market.parse(fixture_bytes(OCTOBER))
    by_name = {row.name: row for row in rows}

    assert len(rows) == 42
    assert [row.section for row in rows][::10] == ["Vegetables", "Other", "Other", "Rice", "Fish"]
    assert by_name["Beans"] == market.Row(
        "Beans", "kg", "Vegetables", {"Pettah": 600.0, "Dambulla": 430.0, "Narahenpita": 700.0}
    )
    assert by_name["Snake gourd"].retail["Dambulla"] == 285.0
    assert by_name["Lime"].retail["Narahenpita"] == 1800.0
    assert by_name["Egg (White)"].unit == "each"
    assert by_name["Coconut oil"].unit == "l"
    assert by_name["Red Onion (Imp)"].retail["Narahenpita"] is None


def test_fish_prices_are_negombos_not_dambullas(fixture_bytes: Callable[[str], bytes]) -> None:
    rows = {row.name: row for row in market.parse(fixture_bytes(OCTOBER))}

    assert rows["Kelawalla"].retail == {"Negombo": 1760.0, "Narahenpita": 2380.0}
    assert rows["Kelawalla"].section == "Fish"


def test_parse_reads_a_report_compared_with_yesterday(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    rows = {row.name: row for row in market.parse(fixture_bytes(JANUARY))}

    assert len(rows) == 42
    assert rows["Beans"].retail == {"Pettah": 500.0, "Dambulla": 680.0, "Narahenpita": 800.0}
    # Its name sits a line above its unit and prices.
    assert rows["Tomato"].retail == {"Pettah": 550.0, "Dambulla": 345.0, "Narahenpita": 700.0}


def test_parse_rejects_a_pdf_without_the_table(fixture_bytes: Callable[[str], bytes]) -> None:
    with pytest.raises(ValueError):
        market.parse(fixture_bytes("gazette-2504-03-en.pdf"))


def test_listed_days_are_newest_first(fixture_bytes: Callable[[str], bytes]) -> None:
    days = market.listed_days(fixture_bytes(LISTING).decode("utf-8"))

    assert days[0] == date(2026, 10, 19)
    assert days[-1] == date(2026, 10, 2)
    assert len(days) == 12


def reports(
    fixture_bytes: Callable[[str], bytes], asked: list[str], blocked: str = ""
) -> dict[str, Callable[[httpx.Request], httpx.Response]]:
    def report(request: httpx.Request) -> httpx.Response:
        asked.append(request.url.path.rsplit("_", 2)[1])
        if blocked and blocked in str(request.url):
            return httpx.Response(403)
        for name in (OCTOBER, JANUARY):
            if name.removeprefix("cbsl_").removesuffix(".pdf") in str(request.url):
                return httpx.Response(200, content=fixture_bytes(name))
        return httpx.Response(404)

    return {
        "price-report": lambda _: httpx.Response(200, content=fixture_bytes(LISTING)),
        "pricerpt": report,
    }


def test_run_fills_the_year_then_reads_nothing_again(
    fixture_bytes: Callable[[str], bytes],
    make_web: Callable[..., object],
    store: Store,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(market, "BUDGET", 400)
    asked: list[str] = []
    web = make_web(reports(fixture_bytes, asked))

    assert market.run(web, store, date(2026, 10, 19)) == 2

    assert asked[0] == "20261019"
    assert "20261017" not in asked  # a Saturday
    assert asked[-1] == "20260101"
    dataset = store.read_dataset("market-prices")
    assert dataset is not None
    assert dataset["days"] == ["2026-01-02", "2026-10-19"]
    beans = next(item for item in dataset["items"] if item["name"] == "Beans")
    assert beans["unit"] == "kg"
    assert beans["prices"]["Narahenpita"] == [800.0, 700.0]
    kelawalla = next(item for item in dataset["items"] if item["name"] == "Kelawalla")
    assert kelawalla["prices"] == {"Negombo": [2240.0, 1760.0], "Narahenpita": [None, 2380.0]}
    assert "Dambulla" not in kelawalla["prices"]

    asked.clear()
    assert market.run(web, store, date(2026, 10, 19)) == 0
    assert asked == []
    assert store.read_dataset("market-prices") == dataset


def test_run_reads_newest_first_within_its_budget(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    asked: list[str] = []
    web = make_web(reports(fixture_bytes, asked))

    assert market.run(web, store, date(2026, 10, 19)) == 1

    assert len(asked) == market.BUDGET
    assert asked[:3] == ["20261019", "20261016", "20261015"]
    asked.clear()
    market.run(web, store, date(2026, 10, 19))
    assert asked[0] == "20260928"  # the weekday before the first run's last, 29 September


def test_run_keeps_what_it_read_when_a_report_is_refused(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    web = make_web(reports(fixture_bytes, [], blocked="20261016"))

    with pytest.raises(httpx.HTTPStatusError):
        market.run(web, store, date(2026, 10, 19))

    dataset = store.read_dataset("market-prices")
    assert dataset is not None
    assert dataset["days"] == ["2026-10-19"]
