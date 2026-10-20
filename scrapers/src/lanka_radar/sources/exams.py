"""Exam notices and timetables from the Department of Examinations (doenets.lk).

The site's CMS answers JSON for its news (type NEWS) and its exam calendar (type EXCA),
with titles in English, Sinhala and Tamil and a PDF per language. Only school exams
(O/L, A/L, Grade 5 scholarship, GIT) and the department's own press releases and
notices become feed items; admission cards for institutional exams, religious and
Piriven exams, recruitment exams and the monthly exam calendars are left out.

A timetable's exam days are read from its PDF, once (`state/exam-timetables.json`), and
kept in the item's data as `days`. An English date is an ordinal day ("08th", its "th"
often raised above the digits) with a month on its line or just below, and a year after
the month where one is given. A timetable with no English date (GIT's, Grade 5's) has it
in Bamini Tamil ("2026 ஒக்ரோபர் 24").
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Any
from urllib.parse import quote

import httpx
import pdfplumber

from lanka_radar import pdfs
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
TIMETABLES = "exam-timetables"
PDF_BUDGET = 5  # timetables read per run

MONTHS = (
    "january",
    "february",
    "march",
    "april",
    "may",
    "june",
    "july",
    "august",
    "september",
    "october",
    "november",
    "december",
)
TAMIL_MONTHS = {
    "ஜனவரி": 1,
    "பெப்ரவரி": 2,
    "பிப்ரவரி": 2,
    "மார்ச்": 3,
    "ஏப்ரல்": 4,
    "மே": 5,
    "ஜூன்": 6,
    "ஜூலை": 7,
    "ஓகஸ்ட்": 8,
    "ஆகஸ்ட்": 8,
    "செப்ரெம்பர்": 9,
    "செப்டெம்பர்": 9,
    "செப்டம்பர்": 9,
    "ஒக்ரோபர்": 10,
    "ஒக்டோபர்": 10,
    "நவம்பர்": 11,
    "டிசெம்பர்": 12,
    "டிசம்பர்": 12,
}
_TAMIL_MONTH = "|".join(TAMIL_MONTHS)
_ORDINAL = re.compile(r"(\d{1,2})(?:st|nd|rd|th)\W*", re.IGNORECASE)
_SUFFIX = re.compile(r"(?:st|nd|rd|th)\b", re.IGNORECASE)
_TAMIL_DATE = re.compile(
    rf"(?:(\d{{4}})\s+)?({_TAMIL_MONTH})\s+(\d{{1,2}})\b|\b(\d{{1,2}})\s+({_TAMIL_MONTH})"
)
_YEAR = re.compile(r"\b(20\d\d)\b")

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


def is_timetable(notice: Notice, kind: str) -> bool:
    """A timetable from the calendar, or school exam news whose PDF is one (GIT's)."""
    name = " ".join(notice.files.get("en", "").replace("_", " ").lower().split())
    return kind == "timetable" or (
        kind == "school" and ("time table" in name or "timetable" in name)
    )


def exam_days(pdf: bytes, year: int) -> list[date]:
    """The days a timetable PDF sets exams on; [year] is the exam's, for dates given
    without one."""
    with pdfplumber.open(io.BytesIO(pdf)) as document:
        days = {
            day
            for page in document.pages
            for day in english_days(page.extract_words(x_tolerance=1.5, y_tolerance=1), year)
        }
        if not days:
            days = {
                day
                for page in document.pages
                for day in tamil_days(
                    [line.text for line in pdfs.lines_of(pdfs.page_chars(page))], year
                )
            }
    return sorted(days)


def english_days(words: list[dict[str, Any]], year: int) -> set[date]:
    """Dates in English among a page's words: an ordinal day paired with the nearest
    month on its line (to its right) or just below it."""
    ordinals: list[tuple[int, dict[str, Any]]] = []
    for word in words:
        if match := _ORDINAL.fullmatch(word["text"]):
            ordinals.append((int(match[1]), word))
        elif re.fullmatch(r"\d{1,2}", word["text"]) and any(
            _SUFFIX.match(other["text"])
            and -1 <= other["x0"] - word["x1"] < 2
            and abs(other["top"] - word["top"]) < 4
            for other in words
        ):
            ordinals.append((int(word["text"]), word))
    months = [
        (MONTHS.index(name) + 1, word)
        for word in words
        if (name := word["text"].strip(",.").lower()) in MONTHS
    ]
    days: set[date] = set()
    for day, ordinal in ordinals:
        picked: tuple[tuple[int, float], int, dict[str, Any]] | None = None
        for month, word in months:
            below = word["top"] - ordinal["top"]
            beside = abs(below) < 3 and 0 <= word["x0"] - ordinal["x1"] < 60
            under = 3 <= below < 25 and abs(word["x0"] - ordinal["x0"]) < 30
            rank = (0 if beside else 1, abs(below))
            if (beside or under) and (picked is None or rank < picked[0]):
                picked = (rank, month, word)
        if picked is not None:
            _, month, word = picked
            given = [
                int(other["text"])
                for other in words
                if re.fullmatch(r"20\d\d", other["text"])
                and abs(other["top"] - word["top"]) < 3
                and 0 <= other["x0"] - word["x1"] < 30
            ]
            days |= _day(given[0] if given else year, month, day)
    return days


def tamil_days(lines: list[str], year: int) -> set[date]:
    """Dates in Tamil: "2026 ஒக்ரோபர் 24" or "24 ஒக்ரோபர்"."""
    days: set[date] = set()
    for line in lines:
        for match in _TAMIL_DATE.finditer(line):
            if match[2]:
                days |= _day(int(match[1] or year), TAMIL_MONTHS[match[2]], int(match[3]))
            else:
                days |= _day(year, TAMIL_MONTHS[match[5]], int(match[4]))
    return days


def _day(year: int, month: int, day: int) -> set[date]:
    try:
        return {date(year, month, day)}
    except ValueError:
        return set()


def item_for(notice: Notice, kind: str, days: list[str] | None = None) -> Item:
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
        data={"kind": kind, "days": days} if days else {"kind": kind},
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    notices: list[Notice] = []
    for resource_type in ("NEWS", "EXCA"):
        params = {"isEnabled": "1", "rowCount": str(ROWS), "type": resource_type}
        notices += parse(web.get(API, params=params).json(), resource_type)
    if not notices:
        raise ValueError("no exam notices in the answers")
    timetables: dict[str, dict[str, Any]] = store.read_state(TIMETABLES) or {}
    budget = PDF_BUDGET
    changed = 0
    for notice in notices:
        kind = kind_of(notice) if notice.day >= HISTORY_START else None
        if not kind:
            continue
        item = item_for(notice, kind)
        pdf = item.links.get("pdf_en")
        read = timetables.get(item.id, {}).get("pdf") == pdf
        if pdf and is_timetable(notice, kind) and not read and budget:
            budget -= 1
            if (days := _read_days(web, pdf, notice)) is not None:
                timetables[item.id] = {"pdf": pdf, "days": [f"{day}" for day in days]}
            web.pause(1.0)
        days = timetables.get(item.id, {}).get("days")
        changed += store.put_item(item_for(notice, kind, days) if days else item)
    store.write_state(TIMETABLES, timetables)
    return changed


def _read_days(web: Web, pdf: str, notice: Notice) -> list[date] | None:
    """A timetable's exam days near when it was published, or None to try again next
    run (the site didn't answer). A PDF that is gone or unreadable has none."""
    try:
        data = web.get(pdf).content
    except httpx.HTTPStatusError as error:
        return None if error.response.status_code >= 500 else []
    except httpx.TransportError:
        return None
    year = int(match[1]) if (match := _YEAR.search(notice.title)) else notice.day.year
    try:
        days = exam_days(data, year)
    except Exception:  # a broken PDF must not stop the exam notices
        return []
    first, last = notice.day - timedelta(days=31), notice.day + timedelta(days=366)
    return [day for day in days if first <= day <= last]
