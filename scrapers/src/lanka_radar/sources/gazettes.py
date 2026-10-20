"""Extraordinary gazettes from the Department of Government Printing (documents.gov.lk).

The site is a Next.js app. Its gazette table loads through a server action named
TableDataAction that answers with JSON, PDF file names included, so a plain POST with
the action's ID reads the list 100 gazettes at a time. A rebuild of the site changes
that ID; the scraper then finds the new one in the site's scripts and keeps it in state/.

Only gazettes from the groups that touch daily life become feed items: prices, taxes
and imports; energy and utilities; wages and labour; elections. Each item's English and
Tamil PDFs are read once (see pdfs.py) for the title on page 1 and, in price gazettes,
the price table; a run reads at most PDF_BUDGET gazettes, newest first. When the reader
improves (READER), an older reading gets the PDFs it could gain from read again once.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any
from urllib.parse import quote

import httpx

from lanka_radar import pdfs
from lanka_radar.items import Item, KeyNumber
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "gazettes"
SITE = "https://documents.gov.lk"
LIST_PAGE = f"{SITE}/web/extra_gazettes"
# The internal endpoint the server action forwards to; the site's own page sends it.
ENDPOINT = "http://gvp-api:4500/website-data/extra-gazette/get-all"
KNOWN_ACTION = "40f4893d604b59b307fb0473d42e9ac093be1e1655"
PAGE_SIZE = 100
ANSWER_ATTEMPTS = 3
# PDFs read per run, newest first; history catches up over a few runs.
PDF_BUDGET = 40
PDF_STATE = "gazette-pdfs"
# The PDF reader's version, kept with each reading: 2 reads the Tamil of Arial Unicode
# PDFs; 3 knows two more of its glyphs and gives shorter price labels; 4 knows nine more
# glyphs (ksha, nnu, tuu, nuu, yii, luu, vuu, sii and h with pulli).
READER = 4
HISTORY_START = date(2026, 1, 1)
RECHECK = timedelta(days=21)

LANGUAGES = {"ENGLISH": "en", "TAMIL": "ta", "SINHALA": "si"}

_ACTION = re.compile(r'createServerReference\)\("([0-9a-f]{40,})",[^"]*"TableDataAction"')
_CHUNK = re.compile(r"/_next/static/chunks/[^\"'\s]+\.js")


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
    # Rows are separated by "\n" only. splitlines() would also split on characters such
    # as U+2028 that can appear inside a description and cut a row in half.
    for line in text.split("\n"):
        try:
            payload = json.loads(line.partition(":")[2])
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and isinstance(payload.get("data"), list):
            pages = int(payload.get("pagination", {}).get("totalPages", 1))
            return [_gazette(row) for row in payload["data"]], pages
    raise ValueError(f"no gazette data in the answer: {text[:120]!r}")


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


def pdf_link(path: str) -> str:
    return f"{SITE}/api/content-file-proxy?file=/{quote(path, safe='/()')}"


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
    links |= {f"pdf_{language}": pdf_link(path) for language, path in sorted(gazette.files.items())}
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
            data = web.get(pdf_link(path)).content
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
    return reading


def stale(reading: dict[str, Any], files: dict[str, str]) -> tuple[str, ...]:
    """The PDFs to read again for a reading an older reader made: the Tamil one when it
    gave no Tamil title, the English one when it gave prices (their labels improved)."""
    if reading.get("reader", 1) >= READER:
        return ()
    languages = []
    if "en" in files and reading.get("numbers"):
        languages.append("en")
    if "ta" in files and not reading.get("title_ta"):
        languages.append("ta")
    return tuple(languages)


def fetch_page(web: Web, action: str, page: int) -> tuple[list[Gazette], int]:
    """One page of the list. The site sometimes answers briefly without data (its back end
    hiccups or throttles a burst), so such an answer is retried after a pause."""
    for attempt in range(1, ANSWER_ATTEMPTS + 1):
        try:
            return parse(_post_page(web, action, page).text)
        except ValueError:
            if attempt == ANSWER_ATTEMPTS:
                raise
            web.pause(10.0 * attempt)
    raise RuntimeError("unreachable")


def _post_page(web: Web, action: str, page: int) -> httpx.Response:
    body = [
        {
            "apiEndpoint": ENDPOINT,
            "page": page,
            "limit": PAGE_SIZE,
            "q": "",
            "search": "",
            "forwarded": {},
        }
    ]
    headers = {
        "next-action": action,
        "accept": "text/x-component",
        "content-type": "text/plain;charset=UTF-8",
    }
    return web.post(LIST_PAGE, content=json.dumps(body), headers=headers)


def find_action(web: Web) -> str:
    """Finds the TableDataAction ID in the site's scripts, after a rebuild changed it."""
    for chunk in sorted(set(_CHUNK.findall(web.get(LIST_PAGE).text))):
        match = _ACTION.search(web.get(SITE + chunk).text)
        if match:
            return match.group(1)
    raise ValueError("TableDataAction not found in the site's scripts")


def run(web: Web, store: Store, today: date) -> int:
    state = store.read_state(NAME) or {}
    action = state.get("action", KNOWN_ACTION)
    newest = date.fromisoformat(state["newest"]) if state.get("newest") else None
    # While older gazettes still wait for their PDFs, the whole year is read again so
    # they come back into view.
    if newest is None or state.get("backlog"):
        stop = HISTORY_START
    else:
        stop = max(HISTORY_START, newest - RECHECK)

    try:
        found, pages = fetch_page(web, action, 1)
    except (httpx.HTTPStatusError, ValueError):
        action = find_action(web)
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
        },
    )
    return changed


def _gazette(row: dict[str, Any]) -> Gazette:
    files = {
        LANGUAGES[content["language"]]: content["uploadedFile"]
        for content in row.get("contents") or []
        if content.get("language") in LANGUAGES and content.get("uploadedFile")
    }
    return Gazette(
        row["gazetteNoText"].strip(),
        date.fromisoformat(row["date"][:10]),
        (row.get("descriptionEnglish") or "").strip(),
        files,
    )
