"""USD/LKR as a backup series: Frankfurter's copy of CBSL's daily rate, often days behind.

CBSL's own rate search refuses most servers outside Sri Lanka, so the app reads it on
the phone for the same-day rate. Every rate here lands in datasets/usd-lkr.json, and a
feed item appears when the rate moves 2% or more within a week, at most one a week.
The app makes the same items with the same IDs, so whichever copy arrives first wins.
"""

from __future__ import annotations

import bisect
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

from lanka_radar.items import Item, KeyNumber
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "rates"
DATASET = "usd-lkr"
FRANKFURTER = "https://api.frankfurter.dev/v2/rates"
CBSL_PAGE = "https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates"
ISSUER = "Central Bank of Sri Lanka"
HISTORY_START = date(2026, 1, 1)
RECHECK_DAYS = 14
MOVE = 0.02
WEEK = timedelta(days=7)


@dataclass(frozen=True)
class Move:
    day: date
    rate: float
    week_ago: float

    @property
    def change(self) -> float:
        return self.rate / self.week_ago - 1


def parse(payload: list[dict[str, Any]]) -> dict[date, float]:
    rates = {
        date.fromisoformat(row["date"]): float(row["rate"])
        for row in payload
        if row.get("base") == "USD" and row.get("quote") == "LKR"
    }
    if not rates:
        raise ValueError("no USD/LKR rows from Frankfurter")
    return rates


def weekly_moves(rates: dict[date, float]) -> list[Move]:
    """Days where the rate is 2% or more away from a week earlier, at most one per week."""
    days = sorted(rates)
    moves: list[Move] = []
    for day in days:
        before = bisect.bisect_right(days, day - WEEK)
        if before == 0:
            continue
        move = Move(day, rates[day], rates[days[before - 1]])
        if abs(move.change) >= MOVE and (not moves or day - moves[-1].day >= WEEK):
            moves.append(move)
    return moves


def move_item(move: Move) -> Item:
    direction = "up" if move.change > 0 else "down"
    percent = abs(move.change) * 100
    return Item(
        id=f"rates-usd-lkr-{move.day.isoformat()}",
        source=NAME,
        topic="rates",
        issuer=ISSUER,
        headline_en=f"USD/LKR {direction} {percent:.1f}% in a week, to {move.rate:.2f}",
        published=move.day,
        links={"page": CBSL_PAGE},
        key_numbers=[KeyNumber("USD/LKR", move.rate, "LKR", move.week_ago)],
        data={"change": round(move.change, 4)},
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    dataset = store.read_dataset(DATASET) or {}
    known = {date.fromisoformat(row["date"]): row["rate"] for row in dataset.get("rates", [])}
    start = HISTORY_START
    if known:
        start = max(HISTORY_START, max(known) - timedelta(days=RECHECK_DAYS))
    params = {
        "providers": "CBSL",
        "base": "USD",
        "quotes": "LKR",
        "from": start.isoformat(),
        "to": today.isoformat(),
    }
    fresh = parse(web.get(FRANKFURTER, params=params).json())
    rates = {day: rate for day, rate in {**known, **fresh}.items() if day >= HISTORY_START}
    rows = [{"date": day.isoformat(), "rate": rates[day]} for day in sorted(rates)]
    store.write_dataset(DATASET, {"source": "frankfurter", "rates": rows})
    return sum(store.put_item(move_item(move)) for move in weekly_moves(rates))
