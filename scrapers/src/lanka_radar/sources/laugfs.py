"""LP gas prices from Laugfs Gas. Its price list is a page with one table of refill prices
by district and cylinder size, and no date.

The current prices are a dataset (`datasets/laugfs-gas.json`) the app shows next to
Litro's, with the prices before the last change. A change is news: a feed item dated the
day the workflow first sees it, with every district's prices. The first read only records
the prices, since nothing says when they started. Only the home sizes are kept; the
37.5 kg commercial cylinder stays on the official page.
"""

from __future__ import annotations

import html
import re
from datetime import date
from typing import Any

from lanka_radar import districts
from lanka_radar.items import Item, KeyNumber, short_date
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "laugfs"
PAGE = "https://www.laugfsgas.lk/pricelist.php"
ISSUER = "Laugfs Gas"
DATASET = "laugfs-gas"
HOME_SIZES = ("12.5 kg", "5 kg", "2 kg")
# The district whose prices are a change's key numbers, as with Litro's.
HEADLINE_DISTRICT = "Colombo"
# A price per kilogram outside this is a misread digit or a changed table.
_PER_KG = (150.0, 900.0)

_ROW = re.compile(r"<tr[^>]*>(.*?)</tr>", re.IGNORECASE | re.DOTALL)
_CELL = re.compile(r"<t[dh][^>]*>(.*?)</t[dh]>", re.IGNORECASE | re.DOTALL)
_TAG = re.compile(r"<[^>]+>")
_SIZE = re.compile(r"^(\d+(?:\.\d+)?)\s*kg", re.IGNORECASE)


def parse(page: str) -> tuple[list[str], dict[str, list[float]]]:
    """The home sizes ("12.5 kg") and each district's price for each, from the page.
    Raises ValueError when anything is missing or doesn't add up."""
    sizes: list[str] = []
    columns: list[int] = []
    prices: dict[str, list[float]] = {}
    for row in _ROW.findall(page):
        cells = [
            " ".join(html.unescape(_TAG.sub(" ", cell)).split()) for cell in _CELL.findall(row)
        ]
        if not cells:
            continue
        found = [_SIZE.match(cell) for cell in cells[1:]]
        if not sizes and sum(1 for size in found if size) >= 3:
            for index, size in enumerate(found, start=1):
                if size and f"{size.group(1)} kg" in HOME_SIZES:
                    sizes.append(f"{size.group(1)} kg")
                    columns.append(index)
            continue
        name = districts.district(cells[0]) if sizes else None
        if name is None:
            continue
        if name in prices:
            raise ValueError(f"{name} is listed twice")
        try:
            prices[name] = [float(cells[index].replace(",", "")) for index in columns]
        except (IndexError, ValueError) as error:
            raise ValueError(f"{name}: no price in {cells}") from error
    if tuple(sizes) != HOME_SIZES:
        raise ValueError(f"expected the sizes {HOME_SIZES}, found {sizes}")
    missing = [name for name in districts.DISTRICTS if name not in prices]
    if missing:
        raise ValueError(f"no prices for {', '.join(missing)}")
    kilograms = [float(size.split()[0]) for size in sizes]
    for name, values in prices.items():
        for value, weight in zip(values, kilograms, strict=True):
            if not _PER_KG[0] <= value / weight <= _PER_KG[1]:
                raise ValueError(f"{name}: {value} for {weight} kg doesn't add up")
    return sizes, {name: prices[name] for name in districts.DISTRICTS}


def item_for(
    day: date,
    sizes: list[str],
    prices: dict[str, list[float]],
    before: dict[str, list[float]],
) -> Item:
    """The news of a change on [day]: every district's prices and the ones [before]; the
    headline district's are the key numbers."""
    previous = before.get(HEADLINE_DISTRICT)
    return Item(
        id=f"gas-laugfs-{day.isoformat()}",
        source=NAME,
        topic="prices",
        issuer=ISSUER,
        headline_en=f"Laugfs gas prices from {short_date(day)}",
        published=day,
        effective=day,
        links={"page": PAGE},
        key_numbers=[
            KeyNumber(size, value, "LKR", previous[index] if previous else None)
            for index, (size, value) in enumerate(
                zip(sizes, prices[HEADLINE_DISTRICT], strict=True)
            )
        ],
        data={
            "sizes": sizes,
            "districts": prices,
            "before": before,
            "district": HEADLINE_DISTRICT,
        },
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    sizes, prices = parse(web.get(PAGE).text)
    known: dict[str, Any] = store.read_dataset(DATASET) or {}
    if known.get("sizes") == sizes and known.get("prices") == prices:
        return 0
    if not known:
        # The first read: nothing says when these prices started.
        store.write_dataset(
            DATASET,
            {"sizes": sizes, "prices": prices, "since": None, "before": None},
        )
        return 0
    before = known.get("prices") if known.get("sizes") == sizes else {}
    store.write_dataset(
        DATASET,
        {"sizes": sizes, "prices": prices, "since": today.isoformat(), "before": before},
    )
    return int(store.put_item(item_for(today, sizes, prices, before or {})))
