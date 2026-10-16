import json
from collections.abc import Callable
from datetime import date

import httpx
import pytest

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
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    web = make_web({"litrogas.com": lambda _: httpx.Response(200, content=fixture_bytes(PAGE))})

    assert gas.run(web, store, date(2026, 10, 16)) == 1

    item = json.loads((store.root / "items/2026/10/gas-litro-2026-10-06.json").read_text("utf-8"))
    assert item["headline"]["en"] == "Litro gas prices from 6 Oct 2026"
    assert item["topic"] == "prices"
    assert item["links"]["image"] == f"{UPLOADS}/Price-List-06.10.2026.webp"
    assert gas.run(web, store, date(2026, 10, 16)) == 0
