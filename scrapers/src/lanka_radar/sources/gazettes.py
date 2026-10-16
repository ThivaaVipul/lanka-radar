"""Extraordinary gazettes from the Department of Government Printing (documents.gov.lk).

The site is a Next.js app. Its gazette table loads through a server action named
TableDataAction that answers with JSON, PDF file names included, so a plain POST with
the action's ID reads the list 100 gazettes at a time. A rebuild of the site changes
that ID; the scraper then finds the new one in the site's scripts and keeps it in state/.

Only gazettes from the groups that touch daily life become feed items: prices, taxes
and imports; energy and utilities; wages and labour; elections.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any
from urllib.parse import quote

import httpx

from lanka_radar.items import Item
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


def pdf_link(path: str) -> str:
    return f"{SITE}/api/content-file-proxy?file=/{quote(path, safe='/()')}"


def item_for(gazette: Gazette, group: str) -> Item:
    text = gazette.description.lower()
    plain = gazette.description in ("", gazette.number)
    links = {"page": LIST_PAGE}
    links |= {f"pdf_{language}": pdf_link(path) for language, path in sorted(gazette.files.items())}
    return Item(
        id=f"gazette-{gazette.number.replace('/', '-')}",
        source=NAME,
        topic="prices" if "consumer affairs" in text or "price" in text else "gazettes",
        issuer=None if plain else gazette.issuer,
        headline_en=f"Extraordinary gazette {gazette.number}" if plain else gazette.description,
        published=gazette.day,
        links=links,
        data={"number": gazette.number, "group": group, "languages": sorted(gazette.files)},
        alert=True,
    )


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
    stop = HISTORY_START if newest is None else max(HISTORY_START, newest - RECHECK)

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
    changed = 0
    for gazette in gazettes:
        group = group_of(gazette)
        if group:
            changed += store.put_item(item_for(gazette, group))
    days = [gazette.day for gazette in gazettes] + ([newest] if newest else [])
    store.write_state(NAME, {"action": action, "newest": max(days).isoformat() if days else None})
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
