"""Extraordinary gazettes from the Department of Government Printing (documents.gov.lk).

The list is read 100 gazettes at a time through the site's TableDataAction (see
documents.py); after a rebuild of the site the new action ID is kept in state/.

Only gazettes from the groups that touch daily life become feed items: prices, taxes
and imports; energy and utilities; wages and labour; elections. Each item's English and
Tamil PDFs are read once (see pdfs.py) for the title on page 1, in price gazettes the
price table, and the English one's first pages as text for search (kept in text/); a
run reads at most PDF_BUDGET gazettes, newest first. When the reader improves (READER),
an older reading gets the PDFs it could gain from read again once.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any

import httpx

from lanka_radar import documents, pdfs
from lanka_radar.items import Item, KeyNumber
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "gazettes"
LIST_PAGE = f"{documents.SITE}/web/extra_gazettes"
# The internal endpoint the server action forwards to; the site's own page sends it.
ENDPOINT = "http://gvp-api:4500/website-data/extra-gazette/get-all"
KNOWN_ACTION = documents.KNOWN_ACTION
PAGE_SIZE = 100
# PDFs read per run, newest first; history catches up over a few runs.
PDF_BUDGET = 40
PDF_STATE = "gazette-pdfs"
# The PDF reader's version, kept with each reading: 2 reads the Tamil of Arial Unicode
# PDFs; 3 knows two more of its glyphs and gives shorter price labels; 4 knows nine more
# glyphs (ksha, nnu, tuu, nuu, yii, luu, vuu, sii and h with pulli); 5 drops a space drawn
# inside the letter before it; 6 keeps the English PDF's text for search.
READER = 6
TEXT_READER = 6
HISTORY_START = date(2026, 1, 1)
RECHECK = timedelta(days=21)


@dataclass(frozen=True)
class Gazette:
    number: str
    day: date
    description: str
    files: dict[str, str] = field(default_factory=dict)

    @property
    def issuer(self) -> str:
        return self.description.split(" - ")[0].strip()


@dataclass(frozen=True)
class Group:
    """A daily-life group, matched on the issuer (the text before the first " - ")."""

    name: str
    issuers: tuple[str, ...]
    needs: tuple[str, ...] = ()
    skips: tuple[str, ...] = ()

    def matches(self, gazette: Gazette) -> bool:
        issuer = gazette.issuer.lower()
        text = gazette.description.lower()
        return (
            any(word in issuer for word in self.issuers)
            and all(word not in text for word in self.skips)
            and (not self.needs or any(word in text for word in self.needs))
        )


GROUPS = (
    Group(
        "prices-taxes",
        (
            "consumer affairs",
            "customs",
            "fiscal policy",
            "import",
            "trade and investment",
            "central bank",
            "census and statistics",
            "finance",
            "inland revenue",
            "excise",
        ),
        # The weekly customs exchange-rate notices are routine.
        skips=("rates of exchange",),
    ),
    Group("prices-taxes", ("health",), needs=("price",)),
    Group("energy", ("energy", "public utilities")),
    Group("labour", ("labour",)),
    Group("elections", ("election",)),
)


def parse(text: str) -> tuple[list[Gazette], int]:
    """Reads one TableDataAction answer: the gazettes and how many pages there are."""
    rows, pages = documents.parse_table(text)
    return [_gazette(row) for row in rows], pages


def merge(gazettes: list[Gazette]) -> list[Gazette]:
    """One entry per number: some gazettes are listed twice, with the PDFs split between
    the copies or a fuller description on one of them."""
    merged: dict[str, Gazette] = {}
    for gazette in gazettes:
        known = merged.get(gazette.number)
        if known is None:
            merged[gazette.number] = gazette
            continue
        merged[gazette.number] = Gazette(
            gazette.number,
            min(known.day, gazette.day),
            max(known.description, gazette.description, key=len),
            {**gazette.files, **known.files},
        )
    return list(merged.values())


def group_of(gazette: Gazette) -> str | None:
    return next((group.name for group in GROUPS if group.matches(gazette)), None)


def routine(gazette: Gazette, title: str | None) -> bool:
    """True when the PDF's title shows a routine notice the list didn't (a weekly customs
    exchange-rate notice listed only as "Sri Lanka Customs")."""
    if not title:
        return False
    described = Gazette(gazette.number, gazette.day, f"{gazette.description} - {title}")
    return group_of(described) is None


def item_id(gazette: Gazette) -> str:
    return f"gazette-{gazette.number.replace('/', '-')}"


def headline(gazette: Gazette, title: str | None) -> str:
    """The list's description when it names a subject ("Ministry of Energy - Revise the
    Fuel Price"), otherwise the PDF's own title, otherwise whatever the list has."""
    if " - " in gazette.description:
        return gazette.description
    if title:
        return title
    if gazette.description in ("", gazette.number):
        return f"Extraordinary gazette {gazette.number}"
    return gazette.description


def item_for(gazette: Gazette, group: str, reading: dict[str, Any] | None = None) -> Item:
    """The feed item; `reading` holds what the PDFs gave (titles and price numbers)."""
    reading = reading or {}
    text = gazette.description.lower()
    plain = gazette.description in ("", gazette.number)
    numbers = [KeyNumber(**number) for number in reading.get("numbers", [])]
    # A price table in the PDF makes it a price gazette even when the list only names
    # the issuer ("Ministry of Energy" for a fuel price revision).
    priced = "consumer affairs" in text or "price" in text or bool(numbers)
    topic = "prices" if priced else "gazettes"
    links = {"page": LIST_PAGE}
    links |= {
        f"pdf_{language}": documents.pdf_link(path)
        for language, path in sorted(gazette.files.items())
    }
    data: dict[str, Any] = {"number": gazette.number, "group": group}
    data["languages"] = sorted(gazette.files)
    if reading.get("title_en"):
        data["title"] = reading["title_en"]
    return Item(
        id=item_id(gazette),
        source=NAME,
        topic=topic,
        issuer=None if plain else gazette.issuer,
        headline_en=headline(gazette, reading.get("title_en")),
        headline_ta=reading.get("title_ta"),
        published=gazette.day,
        links=links,
        key_numbers=numbers,
        data=data,
        alert=True,
    )


def read_pdfs(
    web: Web, gazette: Gazette, before: dict[str, Any] | None = None
) -> dict[str, Any] | None:
    """Titles (English and Tamil) and price numbers from one gazette's PDFs. With `before`,
    an older reader's reading of the same files, only the PDFs it could gain from are read
    again (see `stale`). None when a download failed, so the gazette is tried again on the
    next run."""
    reading: dict[str, Any] = dict(before) if before else {"files": gazette.files}
    languages = stale(before, gazette.files) if before else ("en", "ta")
    reading["reader"] = READER
    for language in languages:
        path = gazette.files.get(language)
        if not path:
            continue
        web.pause(1.0)
        try:
            data = web.get(documents.pdf_link(path)).content
        except httpx.HTTPError:
            return None
        reading.pop(f"error_{language}", None)
        if language == "en":
            reading.pop("numbers", None)
        else:
            reading.pop("unknown_glyphs", None)
        try:
            found = pdfs.read(data, tamil=language == "ta")
        except Exception as error:
            # A broken PDF must not stop the run. It is recorded and not retried
            # until the gazette's files change.
            reading[f"error_{language}"] = f"{type(error).__name__}: {error}"[:200]
            continue
        reading[f"title_{language}"] = found.title
        if found.numbers:
            reading["numbers"] = [number.to_json() for number in found.numbers]
        if found.unknown:
            # Glyphs to add to pdfs.ARIAL_TAMIL: until then this Tamil title stays out.
            reading["unknown_glyphs"] = list(found.unknown)
        if found.text:
            reading["text"] = found.text  # taken out by run() into the store's text/
    return reading


def stale(reading: dict[str, Any], files: dict[str, str]) -> tuple[str, ...]:
    """The PDFs to read again for a reading an older reader made: the Tamil one when it
    gave no Tamil title, the English one when it gave prices (their labels improved) or
    before the reader kept its text."""
    reader = reading.get("reader", 1)
    if reader >= READER:
        return ()
    languages = []
    if "en" in files and (reading.get("numbers") or reader < TEXT_READER):
        languages.append("en")
    if "ta" in files and not reading.get("title_ta"):
        languages.append("ta")
    return tuple(languages)


def fetch_page(web: Web, action: str, page: int) -> tuple[list[Gazette], int]:
    """One page of the list."""
    rows, pages = documents.fetch_table(web, LIST_PAGE, ENDPOINT, action, page, PAGE_SIZE)
    return [_gazette(row) for row in rows], pages


def run(web: Web, store: Store, today: date) -> int:
    state = store.read_state(NAME) or {}
    action = state.get("action", KNOWN_ACTION)
    newest = date.fromisoformat(state["newest"]) if state.get("newest") else None
    # While older gazettes still wait for their PDFs, the whole year is read again so
    # they come back into view; so it is after a reader version bump, for the older
    # readings it can improve.
    if newest is None or state.get("backlog") or state.get("reader") != READER:
        stop = HISTORY_START
    else:
        stop = max(HISTORY_START, newest - RECHECK)

    try:
        found, pages = fetch_page(web, action, 1)
    except (httpx.HTTPStatusError, ValueError):
        action = documents.find_action(web, LIST_PAGE)
        print(f"gazettes: the site has a new action ID, {action}")
        found, pages = fetch_page(web, action, 1)
    page = 1
    while found and found[-1].day >= stop and page < pages:
        page += 1
        web.pause(1.0)
        found += fetch_page(web, action, page)[0]

    gazettes = [gazette for gazette in merge(found) if gazette.day >= stop]
    picked = [(gazette, group) for gazette in gazettes if (group := group_of(gazette))]

    readings = store.read_state(PDF_STATE) or {}

    def unread(gazette: Gazette) -> bool:
        return readings.get(gazette.number, {}).get("files") != gazette.files

    def outdated(gazette: Gazette) -> bool:
        return bool(stale(readings.get(gazette.number, {}), gazette.files))

    def waiting(gazette: Gazette) -> bool:
        return unread(gazette) or outdated(gazette)

    queue = sorted((g for g, _ in picked if waiting(g)), key=lambda g: g.day, reverse=True)
    for gazette in queue[:PDF_BUDGET]:
        if unread(gazette):
            reading = read_pdfs(web, gazette)
        else:
            reading = read_pdfs(web, gazette, before=readings[gazette.number])
        if reading is not None:
            text = reading.pop("text", None)
            if text:
                store.put_text(item_id(gazette), gazette.day, text)
            readings[gazette.number] = reading
    store.write_state(PDF_STATE, readings)

    changed = 0
    for gazette, group in picked:
        reading = readings.get(gazette.number)
        if routine(gazette, (reading or {}).get("title_en")):
            changed += store.drop_item(item_id(gazette))
        else:
            changed += store.put_item(item_for(gazette, group, reading))
    days = [gazette.day for gazette in gazettes] + ([newest] if newest else [])
    backlog = sum(1 for gazette, _ in picked if waiting(gazette))
    store.write_state(
        NAME,
        {
            "action": action,
            "newest": max(days).isoformat() if days else None,
            "backlog": backlog,
            "reader": READER,
        },
    )
    return changed


def _gazette(row: dict[str, Any]) -> Gazette:
    files = {
        documents.LANGUAGES[content["language"]]: content["uploadedFile"]
        for content in row.get("contents") or []
        if content.get("language") in documents.LANGUAGES and content.get("uploadedFile")
    }
    return Gazette(
        row["gazetteNoText"].strip(),
        date.fromisoformat(row["date"][:10]),
        (row.get("descriptionEnglish") or "").strip(),
        files,
    )
