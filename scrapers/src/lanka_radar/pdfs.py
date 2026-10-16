"""Reads gazette PDFs: the title block on page 1, and price tables.

Tamil gazettes mostly use old Bamini-encoded fonts (Bamini, Tharmini, the Government
Printer's GP-Rasanji), whose text layer holds Latin letters; those runs are converted to
Unicode Tamil with Open-Tamil. Other Tamil PDFs use Arial Unicode with overprinted,
scrambled text, which is not trusted. Sinhala runs (old FM fonts) are dropped, since
Sinhala is not shown yet.
"""

from __future__ import annotations

import io
import re
from collections import Counter
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from typing import Any

import pdfplumber
from tamil.txt2unicode import bamini2unicode

from lanka_radar.items import KeyNumber

BAMINI_FONTS = ("bamini", "baamini", "tharmini", "rasanji")
SINHALA_FONTS = ("fm", "iskoola", "sandaru", "malithi")
LINE_GAP = 3.0  # points: characters this close vertically are on one line
MASTHEAD_SIZE = 13.5  # the masthead and section headings are set larger than this
TITLE_LENGTH = 300
TABLE_PAGES = 3

_REFERENCE = re.compile(r"[A-Z]{1,6}[\w/.-]*\d[\w/.-]*\.?")
_NUMBERED = re.compile(r"(?i)(order|direction|notice|notification)?\s*no\s*\.?\s*:?\s*\d+\.?")
# Tamil aytham: a "/" in a Bamini font converts to it, as in DGC/A877.
_AYTHAM = chr(0x0B83)
_NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")
_OLD_PRICE = ("current", "existing", "present", "old")


@dataclass(frozen=True)
class Line:
    text: str
    size: float
    bold: bool
    trusted: bool = True  # False when it holds Tamil from a font other than a Bamini one


@dataclass(frozen=True)
class Reading:
    title: str | None
    numbers: list[KeyNumber] = field(default_factory=list)


def read(data: bytes, tamil: bool) -> Reading:
    """The title of a gazette PDF and, for English ones, its price tables."""
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        if not pdf.pages:
            return Reading(None)
        heading = title(lines_of(pdf.pages[0].dedupe_chars().chars), tamil)
        if tamil:
            return Reading(heading)
        tables = [table for page in pdf.pages[:TABLE_PAGES] for table in page.extract_tables()]
        return Reading(heading, price_numbers(tables))


def lines_of(chars: Iterable[dict[str, Any]]) -> list[Line]:
    rows: list[list[dict[str, Any]]] = []
    for char in sorted(chars, key=lambda c: (c["top"], c["x0"])):
        if rows and abs(char["top"] - rows[-1][0]["top"]) <= LINE_GAP:
            rows[-1].append(char)
        else:
            rows.append([char])
    lines = (_line(sorted(row, key=lambda c: c["x0"])) for row in rows)
    return [line for line in lines if line is not None]


def title(lines: Sequence[Line], tamil: bool) -> str | None:
    """The bold, capitals or larger lines right after the masthead on page 1."""
    big = [index for index, line in enumerate(lines[:15]) if line.size >= MASTHEAD_SIZE]
    if not big:
        return None
    body = Counter(line.size for line in lines).most_common(1)[0][0]
    picked: list[Line] = []
    for line in lines[big[-1] + 1 :]:
        if not picked and _reference(line.text, tamil):
            continue
        if line.size < MASTHEAD_SIZE and (line.bold or _capitals(line.text) or line.size > body):
            picked.append(line)
        elif picked or len(line.text) > 80:
            break
    text = " ".join(line.text for line in picked)[:TITLE_LENGTH].strip()
    if not text:
        return None
    if tamil and (not all(line.trusted for line in picked) or not _mostly_tamil(text)):
        return None
    return text


def price_numbers(tables: Sequence[Sequence[Sequence[str | None]]]) -> list[KeyNumber]:
    """Prices from tables whose header names a price column. A table with a current and
    a revised price (fuel revisions) gives the revised one, with the current as before."""
    numbers: list[KeyNumber] = []
    for table in tables:
        if len(table) < 2:
            continue
        header = [_clean(cell).lower() for cell in table[0]]
        prices = [index for index, cell in enumerate(header) if "price" in cell]
        old = next((i for i in prices if any(word in header[i] for word in _OLD_PRICE)), None)
        new = next((i for i in prices if i != old), None)
        labels = [index for index in range(len(header)) if index not in prices]
        if new is None or not labels:
            continue
        first = ""
        for row in table[1:]:
            cells = [_clean(cell) for cell in row]
            first = cells[labels[0]] or first
            label = " ".join(part for part in [first, *(cells[i] for i in labels[1:])] if part)
            value = _number(cells[new])
            if label and value is not None:
                before = _number(cells[old]) if old is not None else None
                numbers.append(KeyNumber(label[:80], value, "LKR", before))
    return numbers


def _line(row: Sequence[dict[str, Any]]) -> Line | None:
    text = ""
    trusted = True
    before: dict[str, Any] | None = None
    skipped = False
    for font, run in _runs(row):
        piece = _join(run)
        if any(name in font for name in SINHALA_FONTS):
            skipped = True
            continue
        if any(name in font for name in BAMINI_FONTS):
            piece = bamini2unicode(piece)
        elif _has_tamil(piece):
            trusted = False
        # Runs touch inside a word (a Bamini bracket around a Latin letter), so a space
        # goes in only where the page leaves a word-sized gap or a dropped run was.
        if skipped or (before is not None and _gap(before, run[0])):
            piece = " " + piece
        text += piece
        before, skipped = run[-1], False
    text = " ".join(text.split())
    if not text:
        return None
    bold = Counter("bold" in c["fontname"].lower() for c in row).most_common(1)[0][0]
    return Line(text, round(max(c["size"] for c in row), 1), bold, trusted)


def _runs(row: Sequence[dict[str, Any]]) -> list[tuple[str, list[dict[str, Any]]]]:
    runs: list[tuple[str, list[dict[str, Any]]]] = []
    for char in row:
        font = char["fontname"].split("+")[-1].lower()
        if runs and runs[-1][0] == font:
            runs[-1][1].append(char)
        else:
            runs.append((font, [char]))
    return runs


def _join(chars: Sequence[dict[str, Any]]) -> str:
    """The run's text, with a space wherever the gap between letters is word-sized."""
    text = ""
    for before, char in zip([None, *chars], chars, strict=False):
        if before is not None and _gap(before, char):
            text += " "
        text += char["text"]
    return text


def _gap(before: dict[str, Any], char: dict[str, Any]) -> bool:
    return bool(char["x0"] - before["x1"] > char["size"] * 0.25)


def _has_tamil(text: str) -> bool:
    return any(0x0B80 <= ord(char) <= 0x0BFF for char in text)


def _mostly_tamil(text: str) -> bool:
    letters = [char for char in text if char.isalpha()]
    tamil = [char for char in letters if 0x0B80 <= ord(char) <= 0x0BFF]
    return bool(letters) and len(tamil) / len(letters) >= 0.6


def _capitals(text: str) -> bool:
    letters = [char for char in text if char.isascii() and char.isalpha()]
    return len(letters) >= 4 and all(char.isupper() for char in letters)


def _reference(text: str, tamil: bool) -> bool:
    """A reference printed above some titles: DGC/A877/PL305., Order No.: 97, and in a
    Tamil PDF any short line without Tamil in it."""
    text = text.strip()
    if _REFERENCE.fullmatch(text) or _NUMBERED.fullmatch(text):
        return True
    return tamil and len(text) <= 30 and not _has_tamil(text.replace(_AYTHAM, ""))


def _clean(cell: str | None) -> str:
    return " ".join((cell or "").split())


def _number(text: str) -> float | None:
    match = _NUMBER.search(text)
    return float(match.group().replace(",", "")) if match else None
