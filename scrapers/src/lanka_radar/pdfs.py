"""Reads gazette PDFs: the title block on page 1, and price tables.

Tamil gazettes use one of two kinds of font. Old Bamini-encoded fonts (Bamini, Tharmini,
the Government Printer's GP-Rasanji) have Latin letters in their text layer, which
Open-Tamil converts to Unicode Tamil. The rest use Arial Unicode MS, whose text maps in
these PDFs are scrambled, so that Tamil is read from the glyph IDs instead (the font's
glyph order never changed) and put back into reading order. Tamil in any other font is
not trusted. Sinhala runs (old FM fonts) are dropped, since Sinhala is not shown yet.
"""

from __future__ import annotations

import io
import re
import unicodedata
from collections import Counter
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass, field
from itertools import pairwise
from typing import Any

import pdfplumber
from pdfminer.converter import PDFPageAggregator
from pdfminer.layout import LTChar, LTContainer, LTItem
from pdfminer.pdfinterp import PDFPageInterpreter
from pdfplumber.page import Page
from pdfplumber.utils import dedupe_chars
from tamil.txt2unicode import bamini2unicode

from lanka_radar.items import KeyNumber

BAMINI_FONTS = ("bamini", "baamini", "tharmini", "rasanji")
SINHALA_FONTS = ("fm", "iskoola", "sandaru", "malithi")
ARIAL_UNICODE = "arialunicodems"
LINE_GAP = 3.0  # points: characters this close vertically are on one line
MASTHEAD_SIZE = 13.5  # the masthead and section headings are set larger than this
TITLE_LENGTH = 300
TABLE_PAGES = 3
# Text render modes: these fill the letters, these only outline them (Word draws bold
# that way, over the filled copy, in a font without a bold face); the rest are invisible.
FILL_MODES = (0, 2, 4, 6)
OUTLINE_MODES = (1, 5)

# Arial Unicode MS (version 1.01, never updated) has the Tamil of Unicode 3.0 at glyph
# IDs 1805 to 1865, in code point order.
_ARIAL_TAMIL_FROM = 1805
_ARIAL_TAMIL_RANGES = (
    (0x0B82, 0x0B83),
    (0x0B85, 0x0B8A),
    (0x0B8E, 0x0B90),
    (0x0B92, 0x0B95),
    (0x0B99, 0x0B9A),
    (0x0B9C, 0x0B9C),
    (0x0B9E, 0x0B9F),
    (0x0BA3, 0x0BA4),
    (0x0BA8, 0x0BAA),
    (0x0BAE, 0x0BB5),
    (0x0BB7, 0x0BB9),
    (0x0BBE, 0x0BC2),
    (0x0BC6, 0x0BC8),
    (0x0BCA, 0x0BCD),
    (0x0BD7, 0x0BD7),
    (0x0BE7, 0x0BF2),
)
# From 8064 on are ksha, then the shapes some letters take with u, uu, i, ii or pulli,
# named by their Unicode characters. Only the ones seen in gazettes are listed (each
# checked against the printed page); any other glyph leaves its line untrusted.
_ARIAL_LIGATURES = """
    8064 KA VIRAMA SSA, 8065 KA U, 8066 KA UU, 8070 CA U, 8071 CA UU, 8074 TTA I,
    8075 TTA II, 8076 TTA U, 8077 TTA UU, 8078 NNA U, 8080 TA U, 8081 TA UU, 8082 NA U,
    8083 NA UU, 8084 NNNA U, 8086 PA II, 8087 PA U, 8088 PA UU, 8089 MA U, 8090 MA UU,
    8091 YA II, 8092 YA U, 8093 YA UU, 8094 RA U, 8095 RA UU, 8096 RRA U, 8098 LA I,
    8099 LA II, 8100 LA U, 8101 LA UU, 8102 LLA U, 8103 LLA UU, 8104 LLLA U, 8106 VA II,
    8107 VA U, 8108 VA UU, 8109 SA I, 8110 SA II, 8111 SA VIRAMA RA II
"""
# From 8112 on: these letters with pulli, in this order.
_ARIAL_PULLI = "KA NGA CA JA NYA TTA NNA TA NA NNNA PA MA YA RA RRA LA LLA LLLA VA SSA SA HA"

_REFERENCE = re.compile(r"[A-Z]{1,6}[\w/.-]*\d[\w/.-]*\.?")
_NUMBERED = re.compile(r"(?i)(order|direction|notice|notification)?\s*no\s*\.?\s*:?\s*\d+\.?")
# Tamil aytham: a "/" in a Bamini font converts to it, as in DGC/A877.
_AYTHAM = chr(0x0B83)
# Tamil for "No." (il. or ilakkam) and a number at the end of a line: Direction No. 101.
_IL = chr(0x0B87) + chr(0x0BB2)
_ILAKKAM = _IL + chr(0x0B95) + chr(0x0BCD) + chr(0x0B95) + chr(0x0BAE) + chr(0x0BCD)
_TAMIL_NUMBERED = re.compile(rf"(?:^|\s)(?:{_ILAKKAM}|{_IL}\.?)\s*:?\s*\d+\.?$")
_NUMBER = re.compile(r"\d[\d,]*(?:\.\d+)?")
_OLD_PRICE = ("current", "existing", "present", "old")
# Price labels: Latin names in brackets go ("Tuna ( Katsuwonus pelamis ...)"), a sentence
# about a pack becomes its first quantity, and "l55g" (a printed typo) reads 155g.
_BRACKETS_WITHOUT_NUMBERS = re.compile(r"\s*\([^()\d]*\)")
_QUANTITY = re.compile(r"\d+(?:\.\d+)?\s*(?:kg|g|ml|l)\b", re.IGNORECASE)
_L_FOR_ONE = re.compile(r"\bl(?=\d+(?:\.\d+)?\s*(?:kg|g|ml)\b)")
_LONG_DETAIL = 20
# An opening bracket set against the word before it and apart from the one after, as a
# misplaced copy of the text leaves it: "word( 262" reads "word (262".
_OPEN_BRACKET_SPACE = re.compile(r"(?<=\S)\( ")

_RA, _LLA, _AA, _I, _II, _PULLI, _AU_LENGTH = map(
    chr, (0x0BB0, 0x0BB3, 0x0BBE, 0x0BBF, 0x0BC0, 0x0BCD, 0x0BD7)
)
_LETTERS = (0x0B95, 0x0BB9)  # the consonants, ka to ha
_SIGNS = frozenset(
    map(chr, (*range(0x0BBE, 0x0BC3), *range(0x0BC6, 0x0BC9), *range(0x0BCA, 0x0BCE), 0x0BD7))
)
# The e, ee and ai signs are drawn left of their letter, so glyph order has them first;
# the other signs follow the letter they belong to.
_LEFT_SIGNS = frozenset(map(chr, range(0x0BC6, 0x0BC9)))
_TRAILING_SIGNS = _SIGNS - _LEFT_SIGNS
_LEFT_SIGN = re.compile(f"([{chr(0x0BC6)}-{chr(0x0BC8)}])([{chr(0x0B95)}-{chr(0x0BB9)}])")
# Glyphs that look the same, drawn for each other: aa for ra before i, ii and pulli, and
# the au length mark for lla before pulli.
_LOOKALIKES = (
    (_AA + _I, _RA + _I),
    (_AA + _II, _RA + _II),
    (_AA + _PULLI, _RA + _PULLI),
    (_AU_LENGTH + _PULLI, _LLA + _PULLI),
)


@dataclass(frozen=True)
class Line:
    text: str
    size: float
    bold: bool
    trusted: bool = True  # False when it holds Tamil that couldn't be read reliably


@dataclass(frozen=True)
class Reading:
    title: str | None
    numbers: list[KeyNumber] = field(default_factory=list)
    # Arial Unicode Tamil glyphs not in ARIAL_TAMIL yet; their lines are not trusted.
    unknown: tuple[int, ...] = ()


def read(data: bytes, tamil: bool) -> Reading:
    """The title of a gazette PDF and, for English ones, its price tables."""
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        if not pdf.pages:
            return Reading(None)
        chars = page_chars(pdf.pages[0])
        heading = title(lines_of(chars), tamil)
        if tamil:
            return Reading(heading, unknown=unknown_glyphs(chars))
        tables = [table for page in pdf.pages[:TABLE_PAGES] for table in page.extract_tables()]
        return Reading(heading, price_numbers(tables))


def page_chars(page: Page) -> list[dict[str, Any]]:
    """The page's visible characters in pdfplumber's form, with exact overprints dropped.
    Arial Unicode MS Tamil comes from the glyph IDs (marked `glyph`), and Word's outline
    copies of bold text are marked `outline`."""
    device = _GlyphReader(page.pdf.rsrcmgr, laparams=None)
    PDFPageInterpreter(page.pdf.rsrcmgr, device).process_page(page.page_obj)
    layout = device.get_result()
    chars = []
    for char in _chars_in(layout):
        if char.mode not in FILL_MODES + OUTLINE_MODES:
            continue
        glyph = ARIAL_UNICODE in char.fontname.lower() and char.cid in ARIAL_TAMIL
        chars.append(
            {
                "text": ARIAL_TAMIL[char.cid] if glyph else char.get_text(),
                "fontname": char.fontname,
                "size": char.size,
                "upright": char.upright,
                "x0": char.x0,
                "x1": char.x1,
                "top": layout.y1 - char.y1,
                "bottom": layout.y1 - char.y0,
                "doctop": layout.y1 - char.y1,
                "cid": char.cid,
                "glyph": glyph,
                "outline": char.mode in OUTLINE_MODES,
            }
        )
    return dedupe_chars(chars, extra_attrs=("fontname", "size", "outline"))


def unknown_glyphs(chars: Iterable[dict[str, Any]]) -> tuple[int, ...]:
    """Glyph IDs of Arial Unicode Tamil that ARIAL_TAMIL doesn't list yet."""
    found = {
        char["cid"]
        for char in chars
        if ARIAL_UNICODE in char["fontname"].lower()
        and not char.get("glyph")
        and _has_tamil(char["text"])
    }
    return tuple(sorted(found))


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
        if picked and line.size <= body < picked[0].size and len(line.text) > 80:
            break  # a paragraph after a title set larger: bold body text, not the title
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
            first = _name(cells[labels[0]]) or first
            parts = [first, *(_detail(cells[i]) for i in labels[1:])]
            label = " ".join(part for part in parts if part)
            value = _number(cells[new])
            if label and value is not None:
                before = _number(cells[old]) if old is not None else None
                numbers.append(KeyNumber(label[:80], value, "LKR", before))
    return numbers


class _GlyphReader(PDFPageAggregator):
    """Keeps each character's glyph ID and text render mode, which pdfplumber drops."""

    mode = 0

    def render_string(self, textstate: Any, seq: Any, ncs: Any, graphicstate: Any) -> None:
        self.mode = textstate.render
        super().render_string(textstate, seq, ncs, graphicstate)

    def render_char(
        self,
        matrix: Any,
        font: Any,
        fontsize: float,
        scaling: float,
        rise: float,
        cid: int,
        ncs: Any,
        graphicstate: Any,
    ) -> float:
        advance = super().render_char(matrix, font, fontsize, scaling, rise, cid, ncs, graphicstate)
        char = self.cur_item._objs[-1]
        char.cid, char.mode = cid, self.mode
        return advance


def _chars_in(item: LTItem) -> Iterator[Any]:
    if isinstance(item, LTChar):
        yield item
    elif isinstance(item, LTContainer):
        for child in item:
            yield from _chars_in(child)


def _tamil(names: str) -> str:
    """Tamil text from short Unicode names: "KA U" is the letter ka with the u sign."""
    first, *rest = names.split()
    text = unicodedata.lookup(f"TAMIL LETTER {first}")
    for name in rest:
        for kind in ("VOWEL SIGN", "SIGN", "LETTER"):
            try:
                text += unicodedata.lookup(f"TAMIL {kind} {name}")
                break
            except KeyError:
                continue
        else:
            raise KeyError(name)
    return text


def _arial_tamil() -> dict[int, str]:
    codes = [code for first, last in _ARIAL_TAMIL_RANGES for code in range(first, last + 1)]
    glyphs = {_ARIAL_TAMIL_FROM + index: chr(code) for index, code in enumerate(codes)}
    for entry in _ARIAL_LIGATURES.split(","):
        glyph, names = entry.split(maxsplit=1)
        glyphs[int(glyph)] = _tamil(names)
    for glyph, letter in enumerate(_ARIAL_PULLI.split(), start=8112):
        glyphs[glyph] = _tamil(f"{letter} VIRAMA")
    return glyphs


ARIAL_TAMIL = _arial_tamil()


def _line(row: Sequence[dict[str, Any]]) -> Line | None:
    filled = [char for char in row if not char.get("outline")]
    text = ""
    trusted = True
    before: dict[str, Any] | None = None
    skipped = False
    for font, run in _runs(filled):
        piece = _join(run)
        if any(name in font for name in SINHALA_FONTS):
            skipped = True
            continue
        if any(name in font for name in BAMINI_FONTS):
            piece = bamini2unicode(piece)
        elif any(char.get("glyph") for char in run):
            piece = _reading_order(piece)
            unread = "".join(char["text"] for char in run if not char.get("glyph"))
            trusted = trusted and _valid_tamil(piece) and not _has_tamil(unread)
        elif _has_tamil(piece):
            trusted = False
        # Runs touch inside a word (a Bamini bracket around a Latin letter), so a space
        # goes in only where the page leaves a word-sized gap or a dropped run was.
        if skipped or (before is not None and _gap(before, run[0])):
            piece = " " + piece
        text += piece
        before, skipped = run[-1], False
    text = _OPEN_BRACKET_SPACE.sub(" (", " ".join(text.split()))
    if not text:
        return None
    outlined = len(row) - len(filled) >= len(filled) / 2
    bold = outlined or Counter("bold" in c["fontname"].lower() for c in filled).most_common(1)[0][0]
    return Line(text, round(max(c["size"] for c in filled), 1), bold, trusted)


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
    """The run's text, with a space wherever the gap between letters is word-sized (but
    never before a Tamil sign that follows its letter, which a font may set apart). A space
    drawn inside the letter before it is a typing slip, not a word break, and is dropped."""
    text = ""
    before: dict[str, Any] | None = None
    for char in chars:
        if char["text"] == " " and before is not None and _inside(char, before):
            continue
        sign = char["text"][:1] in _TRAILING_SIGNS
        if before is not None and _gap(before, char) and not sign:
            text += " "
        text += char["text"]
        before = char
    return text


def _gap(before: dict[str, Any], char: dict[str, Any]) -> bool:
    return bool(char["x0"] - before["x1"] > char["size"] * 0.25)


def _inside(char: dict[str, Any], before: dict[str, Any]) -> bool:
    return bool(before["x1"] - char["x0"] > char["size"] * 0.25)


def _reading_order(text: str) -> str:
    """Tamil read from glyph IDs, put in reading order: signs drawn left of their letter
    move after it (NFC then joins the two halves of o, oo and au), and look-alike glyphs
    become the letters they stand for."""
    text = _LEFT_SIGN.sub(r"\2\1", text)
    for drawn, meant in _LOOKALIKES:
        text = text.replace(drawn, meant)
    return unicodedata.normalize("NFC", text)


def _valid_tamil(text: str) -> bool:
    """Every vowel sign and pulli comes right after a letter, as in any real Tamil word."""
    first, last = _LETTERS
    return all(
        first <= ord(before) <= last for before, char in pairwise(" " + text) if char in _SIGNS
    )


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
    Tamil PDF any short line without Tamil in it or ending in a number."""
    text = text.strip()
    if _REFERENCE.fullmatch(text) or _NUMBERED.fullmatch(text):
        return True
    if not tamil or len(text) > 30:
        return False
    return not _has_tamil(text.replace(_AYTHAM, "")) or bool(_TAMIL_NUMBERED.search(text))


def _name(cell: str) -> str:
    """A price label's item name, without Latin names in brackets."""
    return " ".join(_BRACKETS_WITHOUT_NUMBERS.sub(" ", cell).split())


def _detail(cell: str) -> str:
    """A price label's other cells; a sentence about a pack ("Net weight of 155g and
    drained weight of 105g or above") becomes its first quantity."""
    cell = _L_FOR_ONE.sub("1", cell)
    quantity = _QUANTITY.search(cell)
    return quantity.group() if quantity and len(cell) > _LONG_DETAIL else cell


def _clean(cell: str | None) -> str:
    return " ".join((cell or "").split())


def _number(text: str) -> float | None:
    match = _NUMBER.search(text)
    return float(match.group().replace(",", "")) if match else None
