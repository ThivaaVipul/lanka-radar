"""Recruitments from the Public Service Commission. Its homepage lists the latest
announcements, each a PDF whose file name starts with the upload time (Unix seconds)
and whose link is titled with the post. Recruitments and calls for applications become
items; transfer and appeal decisions are left out.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

from lanka_radar.items import Item
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "jobs"
SITE = "https://psc.gov.lk"
PAGE = f"{SITE}/index.php?lang=en"
ISSUER = "Public Service Commission"
HISTORY_START = date(2026, 1, 1)
SRI_LANKA = timezone(timedelta(hours=5, minutes=30))

_LINK = re.compile(
    r'<a\b([^>]*\bhref="(/images/latest_document/psc_announcements/\d{4}/(\d{9,11})-[^"]+\.pdf)"'
    r"[^>]*)>(.*?)</a>",
    re.IGNORECASE | re.DOTALL,
)
_TITLE = re.compile(r'\btitle="([^"]*)"', re.IGNORECASE)
_TAGS = re.compile(r"<[^>]+>")
_SPACES = re.compile(r"\s+")
_JOB = re.compile(
    r"recruit|vacanc|calling for applications|applications (?:are )?(?:invited|called)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Announcement:
    stamp: int
    title: str
    pdf: str

    @property
    def day(self) -> date:
        """The day it was put up, in Sri Lanka."""
        return datetime.fromtimestamp(self.stamp, SRI_LANKA).date()

    @property
    def is_job(self) -> bool:
        return bool(_JOB.search(self.title))


def parse(page: str) -> list[Announcement]:
    """Every announcement on the homepage, newest first, once each. The link's title
    has the full post name; the text inside it is sometimes cut short."""
    found: dict[int, Announcement] = {}
    for match in _LINK.finditer(page):
        attributes, path, stamp, text = match.groups()
        titled = _TITLE.search(attributes)
        title = titled.group(1) if titled else _TAGS.sub(" ", text)
        title = _SPACES.sub(" ", html.unescape(title)).strip()
        if title and int(stamp) not in found:
            found[int(stamp)] = Announcement(int(stamp), title, f"{SITE}{path}")
    if not found:
        raise ValueError("no announcements on the Public Service Commission's homepage")
    return sorted(found.values(), key=lambda announcement: -announcement.stamp)


def item_for(announcement: Announcement) -> Item:
    return Item(
        id=f"jobs-psc-{announcement.stamp}",
        source=NAME,
        topic="jobs",
        issuer=ISSUER,
        headline_en=announcement.title,
        published=announcement.day,
        links={"pdf_en": announcement.pdf, "page": PAGE},
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    return sum(
        store.put_item(item_for(announcement))
        for announcement in parse(web.get(PAGE).text)
        if announcement.is_job and announcement.day >= HISTORY_START
    )
