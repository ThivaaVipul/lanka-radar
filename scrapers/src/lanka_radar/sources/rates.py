"""USD/LKR from CBSL's own rate search, with Frankfurter's copy of the CBSL series as a fallback.

Every rate lands in datasets/usd-lkr.json. A feed item appears only when the rate
moves 2% or more within a week, at most one item per week.
"""

from __future__ import annotations

import bisect
import re
from dataclasses import dataclass
from datetime import date, timedelta
from html.parser import HTMLParser
from typing import Any

import httpx

from lanka_radar.items import Item, KeyNumber
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "rates"
DATASET = "usd-lkr"
CBSL_FORM = "https://www.cbsl.gov.lk/cbsl_custom/exrates/exrates_results.php"
CBSL_PAGE = "https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates"
FRANKFURTER = "https://api.frankfurter.dev/v2/rates"
ISSUER = "Central Bank of Sri Lanka"
HISTORY_START = date(2026, 1, 1)
RECHECK_DAYS = 14
MOVE = 0.02
WEEK = timedelta(days=7)

_DAY = re.compile(r"\d{4}-\d{2}-\d{2}")


@dataclass(frozen=True)
class Move:
    day: date
    rate: float
    week_ago: float

    @property
    def change(self) -> float:
        return self.rate / self.week_ago - 1


def cbsl_form(start: date, end: date) -> dict[str, str]:
    return {
        "lookupPage": "lookup_daily_exchange_rates.php",
        "startRange": "2006-11-11",
        "rangeType": "dates",
        "txtStart": start.isoformat(),
        "txtEnd": end.isoformat(),
        "chk_cur[]": "USD~US Dollar",
        "submit_button": "Submit",
    }


def parse_cbsl(html: str) -> dict[date, float]:
    table = _TableRows()
    table.feed(html)
    rates = {
        date.fromisoformat(row[0]): float(row[1])
        for row in table.rows
        if len(row) >= 2 and _DAY.fullmatch(row[0])
    }
    if not rates:
        raise ValueError("no USD/LKR rows in the CBSL results")
    return rates


def parse_frankfurter(payload: list[dict[str, Any]]) -> dict[date, float]:
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


def fetch(web: Web, start: date, end: date) -> tuple[str, dict[date, float]]:
    """CBSL first; Frankfurter (the same CBSL series, sometimes days behind) if CBSL fails."""
    try:
        return "cbsl", parse_cbsl(web.post_form(CBSL_FORM, cbsl_form(start, end)).text)
    except (httpx.HTTPError, ValueError):
        params = {
            "providers": "CBSL",
            "base": "USD",
            "quotes": "LKR",
            "from": start.isoformat(),
            "to": end.isoformat(),
        }
        return "frankfurter", parse_frankfurter(web.get(FRANKFURTER, params=params).json())


def run(web: Web, store: Store, today: date) -> int:
    dataset = store.read_dataset(DATASET) or {}
    known = {date.fromisoformat(row["date"]): row["rate"] for row in dataset.get("rates", [])}
    start = (
        max(HISTORY_START, max(known) - timedelta(days=RECHECK_DAYS)) if known else HISTORY_START
    )
    origin, fresh = fetch(web, start, today)
    rates = {day: rate for day, rate in {**known, **fresh}.items() if day >= HISTORY_START}
    store.write_dataset(
        DATASET,
        {
            "source": origin,
            "rates": [{"date": day.isoformat(), "rate": rates[day]} for day in sorted(rates)],
        },
    )
    return sum(store.put_item(move_item(move)) for move in weekly_moves(rates))


class _TableRows(HTMLParser):
    """Collects the text of each table row's cells."""

    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[str]] = []
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th") and self._row is not None and self._cell is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self.rows.append(self._row)
            self._row = None

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)
