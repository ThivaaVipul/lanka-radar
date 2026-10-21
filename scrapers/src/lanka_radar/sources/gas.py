"""LP gas prices from Litro. The price list is one image whose file name carries the date
(e.g. Price-List-06.10.2026.webp), so a new file name means new prices.

Each list's image is read once with OCR (see ocr.py) into a price per district for each
cylinder size, checked (every district, every size, a sensible price per kilogram)
before it is used. A list that can't be read stays a link to its image. The lists the
page no longer shows are read from their stored items.
"""

from __future__ import annotations

import difflib
import re
import subprocess
from datetime import date
from typing import Any

import httpx

from lanka_radar import ocr
from lanka_radar.items import Item, KeyNumber, short_date
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "gas"
PAGE = "https://www.litrogas.com/price-list/"
ISSUER = "Litro Gas Lanka"
HISTORY_START = date(2026, 1, 1)
# The OCR reader's version, kept with each list's reading.
READER = 1
# The district whose prices are the item's key numbers (Litro's own headline price).
HEADLINE_DISTRICT = "Colombo"

DISTRICTS = (
    "Ampara",
    "Anuradhapura",
    "Badulla",
    "Batticaloa",
    "Colombo",
    "Galle",
    "Gampaha",
    "Hambantota",
    "Jaffna",
    "Kalutara",
    "Kandy",
    "Kegalle",
    "Kilinochchi",
    "Kurunegala",
    "Mannar",
    "Matale",
    "Matara",
    "Monaragala",
    "Mullaitivu",
    "Nuwara Eliya",
    "Polonnaruwa",
    "Puttalam",
    "Ratnapura",
    "Trincomalee",
    "Vavuniya",
)
# Litro's own spellings that are too far from the usual ones to be matched.
_ALIASES = {"mulative": "Mullaitivu", "n eliya": "Nuwara Eliya", "vauniya": "Vavuniya"}
# A price per kilogram outside this is a misread digit.
_PER_KG = (150.0, 900.0)

_IMAGE = re.compile(
    r"https://www\.litrogas\.com/wp-content/uploads/[\w./%-]*?"
    r"Price[-_ ]?List[-_ ]?(\d{1,2})[.\-_](\d{1,2})[.\-_](\d{4})[\w./%-]*?\.(?:webp|jpe?g|png)",
    re.IGNORECASE,
)
_SIZE = re.compile(r"(\d+(?:\.\d+)?)\s*kg", re.IGNORECASE)
_PRICE = r"(\d[\d,]*\.\d{2})"
_ROW = re.compile(rf"^\s*([A-Za-z][A-Za-z .']*?)\s+{_PRICE}\s+{_PRICE}\s+{_PRICE}\b")


def parse(html: str) -> list[tuple[date, str]]:
    """Each dated price list on the page, with its full-size image (the shortest URL;
    the longer ones are resized copies such as -300x374.webp)."""
    found: dict[date, str] = {}
    for match in _IMAGE.finditer(html):
        day = date(int(match.group(3)), int(match.group(2)), int(match.group(1)))
        url = match.group(0)
        if day not in found or len(url) < len(found[day]):
            found[day] = url
    if not found:
        raise ValueError("no dated price list image on the page")
    return sorted(found.items())


def parse_prices(text: str) -> tuple[list[str], dict[str, list[float]]]:
    """The sizes ("12.5 kg") and each district's price for each, from the OCR text of a
    price list. Raises ValueError when anything is missing or doesn't add up."""
    sizes: list[str] = []
    prices: dict[str, list[float]] = {}
    for line in text.splitlines():
        found = _SIZE.findall(line)
        if not sizes and len(found) >= 2:
            sizes = [f"{size} kg" for size in found]
            continue
        match = _ROW.match(line)
        if not match:
            continue
        district = _district(match.group(1))
        if district is None:
            raise ValueError(f"unknown district {match.group(1)!r}")
        if district in prices:
            raise ValueError(f"{district} is listed twice")
        prices[district] = [float(value.replace(",", "")) for value in match.groups()[1:]]
    if len(sizes) != 3:
        raise ValueError(f"expected three cylinder sizes, found {sizes}")
    missing = [district for district in DISTRICTS if district not in prices]
    if missing:
        raise ValueError(f"no prices for {', '.join(missing)}")
    kilograms = [float(size.split()[0]) for size in sizes]
    for district, values in prices.items():
        for value, weight in zip(values, kilograms, strict=True):
            if not _PER_KG[0] <= value / weight <= _PER_KG[1]:
                raise ValueError(f"{district}: {value} for {weight} kg doesn't add up")
    return sizes, {district: prices[district] for district in DISTRICTS}


def _district(name: str) -> str | None:
    name = " ".join(name.lower().split())
    if name in _ALIASES:
        return _ALIASES[name]
    lowered = {district.lower(): district for district in DISTRICTS}
    match = difflib.get_close_matches(name, list(lowered), n=1, cutoff=0.75)
    return lowered[match[0]] if match else None


def item_for(
    day: date,
    image: str,
    reading: dict[str, Any] | None = None,
    before: dict[str, Any] | None = None,
) -> Item:
    """The list's item; with `reading` (its prices) the headline district's prices are
    its key numbers, against the list `before` it when that one has them."""
    numbers: list[KeyNumber] = []
    data: dict[str, Any] = {}
    if reading:
        sizes, prices = reading["sizes"], reading["prices"]
        data = {"sizes": sizes, "districts": prices}
        previous = (
            before["prices"][HEADLINE_DISTRICT] if before and before["sizes"] == sizes else None
        )
        numbers = [
            KeyNumber(size, value, "LKR", previous[index] if previous else None)
            for index, (size, value) in enumerate(
                zip(sizes, prices[HEADLINE_DISTRICT], strict=True)
            )
        ]
        data["district"] = HEADLINE_DISTRICT
    return Item(
        id=f"gas-litro-{day.isoformat()}",
        source=NAME,
        topic="prices",
        issuer=ISSUER,
        headline_en=f"Litro gas prices from {short_date(day)}",
        published=day,
        effective=day,
        links={"image": image, "page": PAGE},
        key_numbers=numbers,
        data=data,
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    on_page = parse(web.get(PAGE).text)
    stored = {
        date.fromisoformat(item["effective"]): item["links"]["image"]
        for item in store.read_items(f"{NAME}-litro-")
        if item.get("effective") and item.get("links", {}).get("image")
    }
    lists = sorted(({**stored, **dict(on_page)}).items())
    lists = [(day, image) for day, image in lists if day >= HISTORY_START]

    readings: dict[str, Any] = (store.read_state(NAME) or {}).get("lists", {})
    if not ocr.available():
        print("gas: tesseract is not installed, so the price lists stay images")
    for day, image in lists:
        reading = readings.get(day.isoformat())
        if not ocr.available() or (
            reading and reading.get("image") == image and reading.get("reader") == READER
        ):
            continue
        web.pause(1.0)
        try:
            data = web.get(image).content
        except httpx.HTTPError:
            continue  # tried again on the next run
        reading = {"image": image, "reader": READER}
        try:
            reading["sizes"], reading["prices"] = parse_prices(ocr.table_text(data))
        except (ValueError, OSError, subprocess.SubprocessError) as error:
            reading["error"] = f"{type(error).__name__}: {error}"[:200]
        readings[day.isoformat()] = reading
    store.write_state(NAME, {"lists": readings})

    changed = 0
    before = None
    for day, image in lists:
        reading = readings.get(day.isoformat())
        read = (
            reading if reading and reading.get("image") == image and "prices" in reading else None
        )
        changed += store.put_item(item_for(day, image, read, before))
        before = read or before
    return changed
