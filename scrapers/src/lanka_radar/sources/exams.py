"""Exam notices and timetables from the Department of Examinations (doenets.lk).

The site's CMS answers JSON for its news (type NEWS) and its exam calendar (type EXCA),
with titles in English, Sinhala and Tamil and a PDF per language. Only school exams
(O/L, A/L, Grade 5 scholarship, GIT) and the department's own press releases and
notices become feed items; admission cards for institutional exams, religious and
Piriven exams, recruitment exams and the monthly exam calendars are left out.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any
from urllib.parse import quote

from lanka_radar.items import Item
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "exams"
SITE = "https://www.doenets.lk"
API = f"{SITE}/cms/api/resources"
PAGES = {"NEWS": f"{SITE}/news", "EXCA": f"{SITE}/examcalendar"}
ISSUER = "Department of Examinations"
HISTORY_START = date(2026, 1, 1)
ROWS = 100
LANGUAGES = ("en", "ta", "si")

SCHOOL = (
    "ordinary level",
    "o/l",
    "advanced level",
    "a/l",
    "grade 5",
    "grade five",
    "scholarship",
    "general information technology",
)
NOTICES = ("press release", "special notice", "media notice")
LEFT_OUT = (
    "institutional",
    "piriven",
    "dharmacharya",
    "daham pasal",
    "dhamma school",
    "dheeniyath",
    "ahadhiyya",
    "recruitment",
    "competitive",
)


@dataclass(frozen=True)
class Notice:
    id: int
    type: str
    day: date
    titles: dict[str, str] = field(default_factory=dict)
    files: dict[str, str] = field(default_factory=dict)

    @property
    def title(self) -> str:
        return self.titles.get("en", "")


def parse(payload: dict[str, Any], resource_type: str) -> list[Notice]:
    notices = []
    for row in payload["resources"]:
        if not row.get("isEnabled", True):
            continue
        titles = {
            language: " ".join(text.split())
            for language, text in (row.get("title") or {}).items()
            if language in LANGUAGES and text and text.strip()
        }
        links = (row.get("links") or [{}])[0].get("link") or {}
        files = {language: links[language] for language in LANGUAGES if links.get(language)}
        day = date.fromisoformat(row["created_date"][:10])
        notices.append(Notice(int(row["id"]), resource_type, day, titles, files))
    return notices


def kind_of(notice: Notice) -> str | None:
    """The kind of item a notice is worth (school, notice or timetable), or None."""
    title = notice.title.lower()
    if any(word in title for word in LEFT_OUT):
        return None
    school = any(word in title for word in SCHOOL)
    if notice.type == "EXCA":
        timetable = "time table" in title or "timetable" in title
        return "timetable" if school and timetable else None
    if school:
        return "school"
    if any(word in title for word in NOTICES):
        return "notice"
    return None


def item_for(notice: Notice, kind: str) -> Item:
    links = {"page": PAGES[notice.type]}
    links |= {
        f"pdf_{language}": SITE + quote(path) for language, path in sorted(notice.files.items())
    }
    return Item(
        id=f"exam-{notice.id}",
        source=NAME,
        topic="exams",
        issuer=ISSUER,
        headline_en=notice.title or "Department of Examinations notice",
        headline_ta=notice.titles.get("ta"),
        published=notice.day,
        links=links,
        data={"kind": kind},
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    notices: list[Notice] = []
    for resource_type in ("NEWS", "EXCA"):
        params = {"isEnabled": "1", "rowCount": str(ROWS), "type": resource_type}
        notices += parse(web.get(API, params=params).json(), resource_type)
    if not notices:
        raise ValueError("no exam notices in the answers")
    changed = 0
    for notice in notices:
        kind = kind_of(notice) if notice.day >= HISTORY_START else None
        if kind:
            changed += store.put_item(item_for(notice, kind))
    return changed
