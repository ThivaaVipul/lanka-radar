"""Vacancies and examinations from the weekly gazette (documents.gov.lk).

Each Friday's gazette comes in parts, one PDF per part and language. Part I Section (IIA)
carries "Posts - Vacant" and "Examinations, Results of Examinations": every notice in it
becomes an item, vacancies under jobs and examinations under exams. Its English PDF comes
out about five days after the gazette's date and is read once (again only when its file
changes). A notice is found by its heading, set bold and a little larger than the text: the
department in capitals, then the notice's title. Each item keeps the notice's page and the
closing date for applications when the notice gives one ("on or before 06.11.2026").

The notices don't alert one by one: the app makes one notification for the week.
"""

from __future__ import annotations

import hashlib
import io
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

import httpx
import pdfplumber

from lanka_radar import documents
from lanka_radar.items import Item
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "weekly"
LIST_PAGE = f"{documents.SITE}/web/gazettes"
ENDPOINT = "http://gvp-api:4500/website-data/gazette/get-all-gazette"
PAGE_SIZE = 100
SECTION_IIA = 2
HISTORY_START = date(2026, 9, 1)
# PDFs read per run; the first run reads the weeks since HISTORY_START.
PDF_BUDGET = 8
# The notice reader's version, kept with each week's reading.
READER = 1
# Pages of a notice kept for search.
TEXT_PAGES = 3

TOPICS = {"vacancies": "jobs", "exams": "exams"}

# Text is made plain ASCII as it is read (dashes and quotes), so the rules below are too.
_PLAIN = str.maketrans(
    {chr(0x2013): "-", chr(0x2014): "-", chr(0x2018): "'", chr(0x2019): "'"}
    | {chr(0x201C): '"', chr(0x201D): '"'}
)
_SECTIONS = (
    (re.compile(r"^posts?\s*-\s*vacan", re.IGNORECASE), "vacancies"),
    (re.compile(r"^examinations", re.IGNORECASE), "exams"),
)
_TITLE_WORDS = re.compile(
    r"examination|recruit|\bposts?\b|course|admission|appointment|vacan|application"
    r"|registration|enrol|selection|intake|training|diploma|degree|programme|scholarship",
    re.IGNORECASE,
)
# Headings of the forms, schedules and appendices that follow a notice.
_NOT_NOTICES = re.compile(
    r"^(specimen|schedule|(first|second|third)?\s*appendix|annex|application\s+(form|for)"
    r"|form\s+of\s+application|model\s+application)",
    re.IGNORECASE,
)
_ORGANISATION = re.compile(
    r"^(ministry|department|commission|institute|office|board|council|authority|university"
    r"|division|bureau|corporation|secretariat|sri lanka)\b",
    re.IGNORECASE,
)
_PREFIXES = re.compile(
    r"^(notice\s+)?(calling|inviting)\s+(for\s+)?applications\s+(for|to)\s+", re.IGNORECASE
)
_VACANCIES_AT = re.compile(r"^vacancies\s+(at|in)\s+(the\s+)?", re.IGNORECASE)
_NUMBER = re.compile(r"No\.\s*(\d[\d,]*)\s*-")
_UPLOADED = re.compile(r"_(\d+)\.pdf$", re.IGNORECASE)
_MONTHS = {
    name: number
    for number, names in enumerate(
        (
            ("jan", "january"),
            ("feb", "february"),
            ("mar", "march"),
            ("apr", "april"),
            ("may",),
            ("jun", "june"),
            ("jul", "july"),
            ("aug", "august"),
            ("sep", "sept", "september"),
            ("oct", "october"),
            ("nov", "november"),
            ("dec", "december"),
        ),
        start=1,
    )
    for name in names
}
# What comes before a closing date, and the date's three forms: 06.11.2026, 6th (of)
# November 2026 and November 6, 2026.
_CLOSING = re.compile(
    r"on\s+or\s+before|closing\s+date|clos(?:es|ed|e)\s+(?:at|on)|extended\s+(?:up\s*)?to"
    r"|not\s+later\s+than",
    re.IGNORECASE,
)
_DATE = re.compile(
    r"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b"
    r"|\b(\d{1,2})\s*(?:st|nd|rd|th)?\s+(?:of\s+)?([A-Za-z]{3,9})\.?,?\s+(\d{4})\b"
    r"|\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b",
)
# How far after "closing date" or "on or before" its date may come.
_CLOSING_REACH = 90
# Words further apart than this across the middle of the page are in two columns.
_GUTTER = 5.0


@dataclass(frozen=True)
class Week:
    day: date
    files: dict[str, str]


@dataclass(frozen=True)
class Heading:
    """One line of a notice heading: bold, set between the text's size and the section's."""

    page: int
    column: int
    top: float
    size: float
    text: str


@dataclass(frozen=True)
class Notice:
    section: str
    issuer: str | None
    title: str
    page: int
    closes: date | None = None

    def to_json(self) -> dict[str, Any]:
        data: dict[str, Any] = {"section": self.section, "title": self.title, "page": self.page}
        if self.issuer:
            data["issuer"] = self.issuer
        if self.closes:
            data["closes"] = self.closes.isoformat()
        return data

    @staticmethod
    def from_json(data: dict[str, Any]) -> Notice:
        closes = data.get("closes")
        return Notice(
            data["section"],
            data.get("issuer"),
            data["title"],
            data["page"],
            date.fromisoformat(closes) if closes else None,
        )


def weeks(rows: Iterable[dict[str, Any]]) -> list[Week]:
    """Each week's Part I (IIA) PDFs by language, the latest upload of each. A week can
    come back on the next page of the list with the same files, so they are merged."""
    found: dict[date, dict[str, str]] = {}
    for row in rows:
        files = found.setdefault(date.fromisoformat(row["fullDate"][:10]), {})
        for content in row.get("content") or []:
            language = documents.LANGUAGES.get(content.get("language", ""))
            path = content.get("uploadedFile") or ""
            if (
                content.get("sectionId") != SECTION_IIA
                or content.get("uploadedFileFormat") != "PDF"
                or not language
                or not path
            ):
                continue
            if language not in files or _uploaded(path) > _uploaded(files[language]):
                files[language] = path
    return [Week(day, files) for day, files in sorted(found.items(), reverse=True)]


def _uploaded(path: str) -> int:
    match = _UPLOADED.search(path)
    return int(match.group(1)) if match else 0


def read(data: bytes, day: date) -> tuple[str | None, list[Notice], dict[int, str]]:
    """The gazette's number, its notices, and the text of each page."""
    sections: list[tuple[int, str]] = []
    lines: list[Heading] = []
    texts: dict[int, str] = {}
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for number, page in enumerate(pdf.pages, start=1):
            rows = _rows(page)
            texts[number] = _text(rows)
            found_sections, found_lines = headings(number, rows)
            sections += found_sections
            lines += found_lines
    match = _NUMBER.search(texts.get(1, ""))
    number = match.group(1).replace(",", "") if match else None
    found = notices(sections, lines)
    starts = sorted({notice.page for notice in found}) + [len(texts) + 1]
    dated = []
    for notice in found:
        end = min(next(page for page in starts if page > notice.page), len(texts))
        span = " ".join(texts[page] for page in range(notice.page, end + 1))
        dated.append(
            Notice(notice.section, notice.issuer, notice.title, notice.page, closes(span, day))
        )
    return number, dated, texts


@dataclass(frozen=True)
class _Part:
    """The words of one line on one side of the page (column 0 or 1), or across it (-1)."""

    column: int
    top: float
    words: list[dict[str, Any]]

    @property
    def text(self) -> str:
        return " ".join(word["text"] for word in self.words).translate(_PLAIN)


def _rows(page: Any) -> list[list[_Part]]:
    """The page's lines, top to bottom, each split at the gutter when it has two columns."""
    middle = page.width / 2
    words = page.extract_words(extra_attrs=["fontname", "size"], x_tolerance=2)
    rows: dict[int, list[dict[str, Any]]] = {}
    for word in words:
        rows.setdefault(round(word["top"] / 3), []).append(word)
    lines = []
    for _, row in sorted(rows.items()):
        row.sort(key=lambda word: word["x0"])
        top = min(word["top"] for word in row)
        left = [word for word in row if word["x1"] <= middle]
        right = [word for word in row if word["x0"] >= middle]
        gap = (right[0]["x0"] if right else middle) - (left[-1]["x1"] if left else middle)
        if len(left) + len(right) == len(row) and (not left or not right or gap > _GUTTER):
            lines.append(
                [_Part(column, top, part) for column, part in ((0, left), (1, right)) if part]
            )
        else:
            lines.append([_Part(-1, top, row)])
    return lines


def _text(rows: Sequence[Sequence[_Part]]) -> str:
    """The page's text in reading order: where it has two columns, the left one first."""
    out: list[str] = []
    columns: list[list[str]] = [[], []]
    for row in rows:
        if row[0].column == -1:
            out += columns[0] + columns[1] + [row[0].text]
            columns = [[], []]
            continue
        for part in row:
            columns[part.column].append(part.text)
    out += columns[0] + columns[1]
    return " ".join(" ".join(out).split())


def headings(
    number: int, rows: Sequence[Sequence[_Part]]
) -> tuple[list[tuple[int, str]], list[Heading]]:
    """A page's section headings and notice heading lines, in reading order: the left
    column before the right (a line across the page counts with the left)."""
    sections: list[tuple[int, str]] = []
    found = []
    for row in rows:
        for part in row:
            words = part.words
            if part.top < 60 or not all("bold" in word["fontname"].lower() for word in words):
                continue
            size = max(word["size"] for word in words)
            found.append((max(part.column, 0), part.top, size, part.text))
    lines = []
    for column, top, size, text in sorted(found):
        if size >= 13:
            if number > 1:
                section = next((name for rule, name in _SECTIONS if rule.search(text)), "")
                sections.append((number, section))
        elif size > 10.6:
            lines.append(Heading(number, column, top, size, text))
    return sections, lines


def notices(sections: Sequence[tuple[int, str]], lines: Sequence[Heading]) -> list[Notice]:
    """Notices from the heading lines. Lines about a line apart are one paragraph (a name
    or a title wrapped); paragraphs close together are one heading. In a heading, the
    paragraph in capitals is the issuer and the first that names a post, an examination
    or a course is the title. A heading of capitals only, or one that starts like a form
    or an appendix, belongs to the notice before it."""
    found: list[Notice] = []
    seen: list[str] = []
    pending: tuple[int, str] | None = None
    for block in _blocks(lines):
        page = block[0][0].page
        section = _section_at(sections, page)
        texts = [" ".join(line.text for line in paragraph) for paragraph in block]
        if not section or _NOT_NOTICES.match(texts[0]):
            pending = None
            continue
        title_at = next(
            (
                i
                for i, text in enumerate(texts)
                if not _capitals(text) and _TITLE_WORDS.search(text)
            ),
            None,
        )
        if title_at is None:
            if all(_capitals(text) for text in texts) and any(map(_TITLE_WORDS.search, texts)):
                pending = None  # a form's heading
            elif _capitals(texts[-1]) or _ORGANISATION.match(texts[-1]):
                pending = (page, texts[-1])
            continue
        before = texts[:title_at]
        issuers = [text for text in before if _capitals(text)] or [
            text for text in before if _ORGANISATION.match(text)
        ]
        issuer = issuers[-1] if issuers else None
        if issuer is None and pending and page - pending[0] <= 2:
            issuer = pending[1]
        pending = None
        title = _tidy(texts[title_at], issuer)
        key = _key(title)
        if (
            _NOT_NOTICES.match(title)
            or "...." in title
            or (title.startswith("(") and title.endswith(")"))
            or any(key in other or other in key for other in seen)
        ):
            continue
        seen.append(key)
        found.append(Notice(section, _issuer(issuer) if issuer else None, title, page))
    return found


def _blocks(lines: Sequence[Heading]) -> list[list[list[Heading]]]:
    blocks: list[list[list[Heading]]] = []
    before: Heading | None = None
    for line in lines:
        same = before is not None and (before.page, before.column) == (line.page, line.column)
        step = line.top - before.top if before is not None and same else None
        if step is not None and step <= line.size * 1.5:
            blocks[-1][-1].append(line)
        elif step is not None and step <= line.size * 3.2:
            blocks[-1].append([line])
        else:
            blocks.append([[line]])
        before = line
    return blocks


def _section_at(sections: Sequence[tuple[int, str]], page: int) -> str:
    current = ""
    for start, name in sections:
        if start <= page:
            current = name
    return current


def _capitals(text: str) -> bool:
    letters = [char for char in text if char.isascii() and char.isalpha()]
    return len(letters) >= 3 and all(char.isupper() for char in letters)


def _key(title: str) -> str:
    """A title reduced to its letters and numbers, without the year at its end, so a
    form's heading that repeats its notice's title is found inside it."""
    return re.sub(r"[^a-z0-9]", "", re.sub(r"[-(\s]*\d{4}\)?\s*$", "", title.lower()))


_SMALL = {"of", "and", "the", "for", "to", "in", "at", "on", "or", "a", "an", "&"}


def _tidy(title: str, issuer: str | None) -> str:
    """The title without the department repeated in front of it or a "Calling for
    applications for" start: "Open Recruitment to Posts in ...", "Post of Registrar ..."."""
    title = " ".join(title.split())
    title = re.sub(r"\b(\d+) (st|nd|rd|th)\b", r"\1\2", title)
    if issuer and title.lower().startswith(issuer.lower() + " "):
        title = title[len(issuer) + 1 :]
    title = _PREFIXES.sub("", title)
    return title[:1].upper() + title[1:]


def _issuer(text: str) -> str:
    """A department printed in capitals, in title case: REGISTRAR GENERAL'S DEPARTMENT
    becomes Registrar General's Department."""
    words = _VACANCIES_AT.sub("", " ".join(text.split())).split(" ")
    return " ".join(
        word.lower() if index and word.lower() in _SMALL else word[:1] + word[1:].lower()
        for index, word in enumerate(words)
    )


def closes(text: str, day: date) -> date | None:
    """The closing date for applications: the first date soon after "on or before",
    "closing date", "closes on" and the like that falls within six months after the
    gazette (a notice also names older dates, such as the day an age limit counts from)."""
    dates = [(match.start(), _date(match.groups())) for match in _DATE.finditer(text)]
    for phrase in _CLOSING.finditer(text):
        for start, found in dates:
            if start < phrase.end():
                continue
            if start - phrase.end() > _CLOSING_REACH:
                break
            if found and day - timedelta(days=7) <= found <= day + timedelta(days=183):
                return found
    return None


def _date(groups: Sequence[str | None]) -> date | None:
    """A date from one of _DATE's three forms."""
    day, month, year = groups[0:3]
    if not day:
        day, month, year = groups[3:6]
    if not day:
        month, day, year = groups[6:9]
    number = int(month) if month and month.isdigit() else _MONTHS.get((month or "").lower())
    try:
        return date(int(year or 0), number or 0, int(day or 0))
    except ValueError:
        return None


def item_id(number: str | None, day: date, notice: Notice) -> str:
    key = f"{notice.issuer or ''}|{notice.title}".lower()
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:8]
    return f"weekly-{number or day.strftime('%Y%m%d')}-{digest}"


def item_for(week: Week, number: str | None, notice: Notice) -> Item:
    links = {"page": LIST_PAGE}
    links |= {
        f"pdf_{language}": documents.pdf_link(path) for language, path in sorted(week.files.items())
    }
    data: dict[str, Any] = {"week": week.day.isoformat(), "section": notice.section}
    data["page"] = notice.page
    if number:
        data["number"] = number
    if notice.closes:
        data["closes"] = notice.closes.isoformat()
    return Item(
        id=item_id(number, week.day, notice),
        source=NAME,
        topic=TOPICS[notice.section],
        issuer=notice.issuer,
        headline_en=notice.title,
        published=week.day,
        links=links,
        data=data,
        alert=False,
    )


def run(web: Web, store: Store, today: date) -> int:
    state = store.read_state(NAME) or {}
    action = state.get("action", documents.KNOWN_ACTION)
    try:
        rows, pages = _fetch(web, action, 1)
    except (httpx.HTTPStatusError, ValueError):
        action = documents.find_action(web, LIST_PAGE)
        print(f"weekly: the site has a new action ID, {action}")
        rows, pages = _fetch(web, action, 1)
    page = 1
    while rows and _oldest(rows) >= HISTORY_START and page < pages:
        page += 1
        web.pause(1.0)
        rows += _fetch(web, action, page)[0]

    readings: dict[str, Any] = state.get("weeks", {})
    budget = PDF_BUDGET
    changed = 0
    listed = [week for week in weeks(rows) if week.day >= HISTORY_START and "en" in week.files]
    for week in listed:
        reading = readings.get(week.day.isoformat())
        if reading and reading.get("file") == week.files["en"] and reading.get("reader") == READER:
            continue
        if budget == 0:
            continue
        budget -= 1
        web.pause(1.0)
        try:
            data = web.get(documents.pdf_link(week.files["en"])).content
        except httpx.HTTPError:
            continue
        number, found, texts = read(data, week.day)
        before = set((reading or {}).get("items", []))
        ids = []
        for notice in found:
            item = item_for(week, number, notice)
            last = min(notice.page + TEXT_PAGES - 1, len(texts))
            text = " ".join(texts[page] for page in range(notice.page, last + 1))
            store.put_text(item.id, item.published, text)
            ids.append(item.id)
        for gone in before - set(ids):
            changed += store.drop_item(gone)
        readings[week.day.isoformat()] = {
            "file": week.files["en"],
            "reader": READER,
            "number": number,
            "notices": [notice.to_json() for notice in found],
            "items": ids,
        }
    # Every run writes the items again, so links to the Tamil and Sinhala PDFs come in
    # when they are out.
    for week in listed:
        reading = readings.get(week.day.isoformat())
        if not reading or reading.get("file") != week.files["en"]:
            continue
        for notice in map(Notice.from_json, reading["notices"]):
            changed += store.put_item(item_for(week, reading.get("number"), notice))
    store.write_state(NAME, {"action": action, "weeks": readings})
    return changed


def _fetch(web: Web, action: str, page: int) -> tuple[list[dict[str, Any]], int]:
    return documents.fetch_table(web, LIST_PAGE, ENDPOINT, action, page, PAGE_SIZE)


def _oldest(rows: Sequence[dict[str, Any]]) -> date:
    return min(date.fromisoformat(row["fullDate"][:10]) for row in rows)
