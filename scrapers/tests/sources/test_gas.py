import json
from collections.abc import Callable
from datetime import date
from typing import Any

import httpx
import pytest

from lanka_radar import districts, ocr
from lanka_radar.sources import gas
from lanka_radar.store import Store

PAGE = "litro_price_list.html"
UPLOADS = "https://www.litrogas.com/wp-content/uploads/2026/10"


def test_parse_finds_the_dated_price_list(fixture_bytes: Callable[[str], bytes]) -> None:
    assert gas.parse(fixture_bytes(PAGE).decode("utf-8")) == [
        (date(2026, 10, 6), f"{UPLOADS}/Price-List-06.10.2026.webp")
    ]


def test_parse_prefers_the_full_size_image() -> None:
    html = (
        f'<img data-src="{UPLOADS}/Price-List-06.10.2026-300x374.webp">'
        f'<img data-src="{UPLOADS}/Price-List-06.10.2026.webp">'
    )

    assert gas.parse(html) == [(date(2026, 10, 6), f"{UPLOADS}/Price-List-06.10.2026.webp")]


def test_parse_rejects_a_page_without_a_dated_list() -> None:
    with pytest.raises(ValueError):
        gas.parse(f'<img data-src="{UPLOADS}/litro-small-logo.png">')


def test_run_makes_one_item_per_price_list(
    fixture_bytes: Callable[[str], bytes],
    make_web: Callable[..., object],
    store: Store,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(ocr, "available", lambda: False)
    web = make_web({"litrogas.com": lambda _: httpx.Response(200, content=fixture_bytes(PAGE))})

    assert gas.run(web, store, date(2026, 10, 16)) == 1

    item = json.loads((store.root / "items/2026/10/gas-litro-2026-10-06.json").read_text("utf-8"))
    assert item["headline"]["en"] == "Litro gas prices from 6 Oct 2026"
    assert item["topic"] == "prices"
    assert item["links"]["image"] == f"{UPLOADS}/Price-List-06.10.2026.webp"
    assert gas.run(web, store, date(2026, 10, 16)) == 0


OCR = "litro_ocr_2026-10-06.txt"
IMAGE = "litro_price_list_2026-10-06.webp"


def test_parse_prices_reads_the_ocr_text(fixture_bytes: Callable[[str], bytes]) -> None:
    sizes, prices = gas.parse_prices(fixture_bytes(OCR).decode("utf-8"))

    assert sizes == ["12.5 kg", "5 kg", "2.3 kg"]
    assert list(prices) == list(districts.DISTRICTS)
    assert prices["Colombo"] == [4365.0, 1750.0, 815.0]
    # Litro's own spellings: Mulative, N Eliya, Vauniya, Baticcaloa.
    assert prices["Mullaitivu"] == [4678.23, 1935.41, 964.73]
    assert prices["Nuwara Eliya"] == [4594.12, 1887.62, 931.28]
    assert prices["Vavuniya"] == [4626.83, 1905.04, 939.62]
    assert prices["Batticaloa"] == [4675.10, 1933.57, 963.28]


@pytest.mark.parametrize(
    ("change", "error"),
    [
        (("Jaffna 4,748.84 1,977.13 999.25", ""), "no prices for Jaffna"),
        (("Colombo 4,365.00", "Colombo 436.50"), "Colombo: 436.5 for 12.5 kg"),
        (("Galle 4,467.42", "Colombo 4,467.42"), "Colombo is listed twice"),
        (("District 12.5kg 5kg 2.3kg", "District"), "expected three cylinder sizes"),
    ],
)
def test_parse_prices_rejects_a_misread_list(
    fixture_bytes: Callable[[str], bytes], change: tuple[str, str], error: str
) -> None:
    text = fixture_bytes(OCR).decode("utf-8").replace(*change)

    with pytest.raises(ValueError, match=error):
        gas.parse_prices(text)


@pytest.mark.skipif(not ocr.available(), reason="tesseract is not installed")
def test_ocr_reads_the_price_list_image(fixture_bytes: Callable[[str], bytes]) -> None:
    sizes, prices = gas.parse_prices(ocr.table_text(fixture_bytes(IMAGE)))

    assert sizes == ["12.5 kg", "5 kg", "2.3 kg"]
    assert prices["Colombo"] == [4365.0, 1750.0, 815.0]
    assert prices["Jaffna"] == [4748.84, 1977.13, 999.25]


def test_run_reads_each_list_once_and_keeps_its_prices(
    fixture_bytes: Callable[[str], bytes],
    make_web: Callable[..., Any],
    store: Store,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    images: list[str] = []

    def image(request: httpx.Request) -> httpx.Response:
        images.append(str(request.url))
        return httpx.Response(200, content=fixture_bytes(IMAGE))

    web = make_web(
        {
            ".webp": image,
            "litrogas.com": lambda _: httpx.Response(200, content=fixture_bytes(PAGE)),
        }
    )
    monkeypatch.setattr(ocr, "available", lambda: True)
    monkeypatch.setattr(ocr, "table_text", lambda data: fixture_bytes(OCR).decode("utf-8"))
    # An earlier list, no longer on the page, already read.
    store.put_item(gas.item_for(date(2026, 9, 1), f"{UPLOADS}/Price-List-01.09.2026.webp"))
    old = {"Colombo": [4100.0, 1650.0, 770.0]}
    store.write_state(
        "gas",
        {
            "lists": {
                "2026-09-01": {
                    "image": f"{UPLOADS}/Price-List-01.09.2026.webp",
                    "reader": gas.READER,
                    "sizes": ["12.5 kg", "5 kg", "2.3 kg"],
                    "prices": old,
                }
            }
        },
    )

    gas.run(web, store, date(2026, 10, 16))

    assert images == [f"{UPLOADS}/Price-List-06.10.2026.webp"]
    item = json.loads((store.root / "items/2026/10/gas-litro-2026-10-06.json").read_text("utf-8"))
    assert item["keyNumbers"] == [
        {"label": "12.5 kg", "value": 4365.0, "unit": "LKR", "previous": 4100.0},
        {"label": "5 kg", "value": 1750.0, "unit": "LKR", "previous": 1650.0},
        {"label": "2.3 kg", "value": 815.0, "unit": "LKR", "previous": 770.0},
    ]
    assert item["data"]["district"] == "Colombo"
    assert item["data"]["districts"]["Kandy"] == [4493.68, 1827.53, 879.28]

    images.clear()
    gas.run(web, store, date(2026, 10, 17))
    assert images == []


def test_a_list_that_cant_be_read_stays_an_image(
    fixture_bytes: Callable[[str], bytes],
    make_web: Callable[..., Any],
    store: Store,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    web = make_web(
        {
            ".webp": lambda _: httpx.Response(200, content=fixture_bytes(IMAGE)),
            "litrogas.com": lambda _: httpx.Response(200, content=fixture_bytes(PAGE)),
        }
    )
    monkeypatch.setattr(ocr, "available", lambda: True)
    monkeypatch.setattr(ocr, "table_text", lambda data: "LITRO\nDistrict 12.5kg")

    gas.run(web, store, date(2026, 10, 16))

    item = json.loads((store.root / "items/2026/10/gas-litro-2026-10-06.json").read_text("utf-8"))
    reading = (store.read_state("gas") or {})["lists"]["2026-10-06"]
    assert item["keyNumbers"] == []
    assert item["links"]["image"] == f"{UPLOADS}/Price-List-06.10.2026.webp"
    assert reading["error"].startswith("ValueError: expected three cylinder sizes")
