"""Market prices from the Central Bank's Daily Price Report: one PDF each weekday with
the wholesale and retail prices of everyday food at a few markets. The retail prices
at Pettah, Dambulla and Narahenpita (Negombo for fish) go into
datasets/market-prices.json, one column of prices per item and market, by day.

The report's table is a PDF made from a spreadsheet: numbers are split by stray
spaces ("5 50.00" is 550.00), so each row's prices are read from the characters and
put in a column by where they stand under the header.
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

import httpx
import pdfplumber

from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "market"
LISTING = "https://www.cbsl.gov.lk/en/statistics/economic-indicators/price-report"
FILES = "https://www.cbsl.gov.lk/sites/default/files/cbslweb_documents/statistics/pricerpt"
DATASET = "market-prices"
STATE = "market-prices"
HISTORY_START = date(2026, 1, 1)
BUDGET = 15  # reports read per run, newest first, while the year fills in
MARKETS = ("Pettah", "Dambulla", "Narahenpita", "Negombo")

_REPORT = re.compile(r"price_report_(\d{8})_?e\.pdf", re.IGNORECASE)
_PRICE = re.compile(r"\d[\d ,]*?\.\d{2}|n\.a\.")
_UNITS = {"kg": "kg", "nut": "nut", "ltr": "l", "each": "each"}
_SECTIONS = {"VEGETABLES", "OTHER", "FRUITS", "RICE", "FISH"}


@dataclass(frozen=True)
class Row:
    name: str
    unit: str
    section: str
    retail: dict[str, float | None] = field(default_factory=dict)


def listed_days(page: str) -> list[date]:
    """The days the report listing links, newest first."""
    days = {_day(match.group(1)) for match in _REPORT.finditer(page)}
    return sorted(days, reverse=True)


def report_url(day: date) -> str:
    return f"{FILES}/price_report_{day:%Y%m%d}_e.pdf"


def parse(pdf: bytes) -> list[Row]:
    """The report's rows with each market's retail price today (None for n.a.)."""
    with pdfplumber.open(io.BytesIO(pdf)) as document:
        page = document.pages[-1]
        chars = [char for char in page.chars if char["text"].strip()]
    lines = _lines(chars)
    columns = _columns(lines)
    rows: list[Row] = []
    section = ""
    fish = False
    for band in _bands(lines):
        text = "".join(char["text"] for char in band)
        if text in _SECTIONS:
            section = text.title()
            fish = text == "FISH"
            continue
        label = [char for char in band if char["x0"] < 110]
        unit_chars = [char for char in band if 110 <= char["x0"] < 150]
        unit = "".join(char["text"] for char in unit_chars).lower().removeprefix("rs./")
        if not label or unit not in _UNITS:
            continue
        values = [char for char in band if char["x0"] >= 150]
        retail: dict[str, float | None] = {}
        for (kind, market), price in _prices(values, columns).items():
            if kind == "retail":
                retail["Negombo" if fish and market == "Dambulla" else market] = price
        rows.append(
            Row(
                name=_name("".join(_spaced(label))),
                unit=_UNITS[unit],
                section=section,
                retail=retail,
            )
        )
    if not rows:
        raise ValueError("no prices in the report")
    return rows


def run(web: Web, store: Store, today: date) -> int:
    dataset = _Dataset.read(store.read_dataset(DATASET))
    missing = {_day(day) for day in (store.read_state(STATE) or {}).get("missing", [])}
    listed = listed_days(web.get(LISTING).text)
    newest = listed[0] if listed else today
    # The listing shows the last few reports; older ones are still at the same address,
    # so the weekdays back to January are tried too. Days that had no report are not.
    wanted = set(listed)
    day = newest
    while day >= HISTORY_START:
        if day.weekday() < 5:
            wanted.add(day)
        day -= timedelta(days=1)
    wanted -= set(dataset.days) | missing
    read = 0
    try:
        for day in sorted(wanted, reverse=True)[:BUDGET]:
            try:
                dataset.add(day, parse(web.get(report_url(day)).content))
            except httpx.HTTPStatusError as error:
                if error.response.status_code != 404:
                    raise
                missing.add(day)
            except ValueError:
                # A report laid out some other way is skipped, not retried every run.
                missing.add(day)
            else:
                read += 1
            web.pause(1.0)
    finally:
        store.write_dataset(DATASET, dataset.to_json())
        store.write_state(STATE, {"missing": sorted(f"{day}" for day in missing)})
    return read


@dataclass
class _Dataset:
    """Prices by day while a run adds to them, written as columns."""

    days: dict[date, list[Row]] = field(default_factory=dict)

    @classmethod
    def read(cls, payload: dict[str, Any] | None) -> _Dataset:
        dataset = cls()
        if not payload:
            return dataset
        days = [_day(day) for day in payload.get("days", [])]
        for index, day in enumerate(days):
            dataset.days[day] = [
                Row(
                    name=item["name"],
                    unit=item["unit"],
                    section=item["section"],
                    retail={
                        market: prices[index]
                        for market, prices in item["prices"].items()
                        if index < len(prices)
                    },
                )
                for item in payload.get("items", [])
            ]
        return dataset

    def add(self, day: date, rows: list[Row]) -> None:
        self.days[day] = rows

    def to_json(self) -> dict[str, Any]:
        days = sorted(self.days)
        items: dict[str, dict[str, Any]] = {}
        for index, day in enumerate(days):
            for row in self.days[day]:
                item = items.setdefault(
                    row.name,
                    {"name": row.name, "unit": row.unit, "section": row.section, "prices": {}},
                )
                for market, price in row.retail.items():
                    column = item["prices"].setdefault(market, [None] * len(days))
                    column[index] = price
        for item in items.values():
            item["prices"] = {
                market: column
                for market, column in item["prices"].items()
                if any(price is not None for price in column)
            }
        return {
            "source": "cbsl",
            "note": "Retail prices in rupees, from the Central Bank's Daily Price Report",
            "markets": list(MARKETS),
            "days": [f"{day}" for day in days],
            "items": [item for item in items.values() if item["prices"]],
        }


def _lines(chars: list[dict[str, Any]]) -> list[tuple[float, list[dict[str, Any]]]]:
    """Characters by line (their top, rounded), each line left to right."""
    lines: dict[int, list[dict[str, Any]]] = {}
    for char in chars:
        lines.setdefault(round(char["top"]), []).append(char)
    return [(top, sorted(lines[top], key=lambda char: char["x0"])) for top in sorted(lines)]


def _bands(lines: list[tuple[float, list[dict[str, Any]]]]) -> list[list[dict[str, Any]]]:
    """The table's rows: a row's name, unit and prices can sit a point or two apart, and
    rows are a dozen points apart, so lines within a few points of a row's first line
    belong to it. Each row's characters are left to right."""
    bands: list[tuple[float, list[dict[str, Any]]]] = []
    for top, line in lines:
        if bands and top - bands[-1][0] < 5:
            bands[-1][1].extend(line)
        else:
            bands.append((top, list(line)))
    return [sorted(band, key=lambda char: char["x0"]) for _, band in bands]


def _columns(lines: list[tuple[float, list[dict[str, Any]]]]) -> list[_Column]:
    """The header's markets, left to right: wholesale Pettah and Dambulla, then retail
    Pettah, Dambulla and Narahenpita. Each name is centred over two prices: the last
    report's on its left ("Yesterday" or "Last Friday") and today's on its right."""
    for _, line in lines:
        markets = [
            (text, centre)
            for text, centre in _words(line)
            if text in ("Pettah", "Dambulla", "Narahenpita")
        ]
        if len(markets) == 5:
            kinds = ("wholesale", "wholesale", "retail", "retail", "retail")
            return [
                _Column(kind, name, centre)
                for kind, (name, centre) in zip(kinds, markets, strict=True)
            ]
    raise ValueError("no market header in the report")


@dataclass(frozen=True)
class _Column:
    kind: str
    market: str
    centre: float


def _prices(
    chars: list[dict[str, Any]], columns: list[_Column]
) -> dict[tuple[str, str], float | None]:
    """Each column's price today: a number belongs to the nearest market, and is
    today's when it stands right of the market's name."""
    text = "".join(char["text"] for char in chars)
    found: dict[tuple[str, str], float | None] = {}
    for match in _PRICE.finditer(text):
        part = chars[match.start() : match.end()]
        centre = (part[0]["x0"] + part[-1]["x1"]) / 2
        column = min(columns, key=lambda column: abs(column.centre - centre))
        if centre > column.centre:
            value = match.group(0)
            found[(column.kind, column.market)] = (
                None if value == "n.a." else float(re.sub(r"[ ,]", "", value))
            )
    return found


def _words(line: list[dict[str, Any]]) -> list[tuple[str, float]]:
    """A line's words (split at gaps) with their centres."""
    words: list[list[dict[str, Any]]] = []
    for char in line:
        if words and char["x0"] - words[-1][-1]["x1"] < 2:
            words[-1].append(char)
        else:
            words.append([char])
    return [
        ("".join(c["text"] for c in word), (word[0]["x0"] + word[-1]["x1"]) / 2) for word in words
    ]


def _spaced(chars: list[dict[str, Any]]) -> list[str]:
    """Characters with a space where the gap is wider than a letter's."""
    out: list[str] = []
    for index, char in enumerate(chars):
        if index and char["x0"] - chars[index - 1]["x1"] > 1.2:
            out.append(" ")
        out.append(char["text"])
    return out


def _name(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("(lmp)", "(Imp)")).strip()


def _day(text: str) -> date:
    digits = text.replace("-", "")
    return date(int(digits[:4]), int(digits[4:6]), int(digits[6:8]))
