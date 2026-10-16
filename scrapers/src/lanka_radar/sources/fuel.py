"""Fuel prices from CEYPETCO's own price feed.

The feed only has today's prices, so every run merges them into a per-product price
history (datasets/fuel.json). Each effective date in that history becomes one feed
item, with the price before it where the history knows it.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from typing import Any

from lanka_radar.items import Item, KeyNumber, short_date
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "fuel"
URL = "https://api.ceypetco.gov.lk/api/admin/fuel-prices/active?limit=100"
PAGE = "https://ceypetco.gov.lk/marketing-sales/"
ISSUER = "Ceylon Petroleum Corporation"
HISTORY_START = date(2026, 1, 1)

History = dict[str, list[dict[str, Any]]]


@dataclass(frozen=True)
class Price:
    product: str
    price: float
    effective: date


def parse(payload: dict[str, Any]) -> list[Price]:
    """Retail fuels only (type "fuel"); the fuel oils sold to industry are left out."""
    if not payload.get("success"):
        raise ValueError("the CEYPETCO feed reported a failure")
    prices = [
        Price(
            row["product"].strip(),
            float(row["price"]),
            date.fromisoformat(row["effectiveDate"][:10]),
        )
        for row in payload["data"]
        if row.get("type") == "fuel" and row.get("status") == "active"
    ]
    if not prices:
        raise ValueError("the CEYPETCO feed has no fuel prices")
    return sorted(prices, key=lambda price: price.product)


def merge_history(history: History, prices: list[Price]) -> History:
    """Adds today's prices; a price already known for the same day is replaced (a correction)."""
    merged = {product: list(entries) for product, entries in history.items()}
    for price in prices:
        day = price.effective.isoformat()
        entries = [entry for entry in merged.get(price.product, []) if entry["effective"] != day]
        entries.append({"effective": day, "price": price.price})
        merged[price.product] = sorted(entries, key=lambda entry: entry["effective"], reverse=True)
    return dict(sorted(merged.items()))


def items_from(history: History) -> list[Item]:
    by_day: dict[date, list[KeyNumber]] = defaultdict(list)
    for product, entries in history.items():
        for index, entry in enumerate(entries):
            day = date.fromisoformat(entry["effective"])
            if day < HISTORY_START:
                continue
            previous = entries[index + 1]["price"] if index + 1 < len(entries) else None
            by_day[day].append(KeyNumber(product, entry["price"], "LKR/l", previous))
    return [
        Item(
            id=f"fuel-{day.isoformat()}",
            source=NAME,
            topic="prices",
            issuer=ISSUER,
            headline_en=f"Fuel prices from {short_date(day)}",
            published=day,
            effective=day,
            links={"page": PAGE},
            key_numbers=sorted(numbers, key=lambda number: number.label),
            alert=True,
        )
        for day, numbers in sorted(by_day.items())
    ]


def run(web: Web, store: Store, today: date) -> int:
    prices = parse(web.get(URL).json())
    dataset = store.read_dataset(NAME) or {}
    history = merge_history(dataset.get("products", {}), prices)
    store.write_dataset(NAME, {"products": history})
    return sum(store.put_item(item) for item in items_from(history))
