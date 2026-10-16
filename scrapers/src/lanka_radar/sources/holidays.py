"""Public holidays, Poya days included, from Google's public Sri Lanka holiday calendar.

They go to datasets/holidays.json for the app's "next holiday" and its reminders the
evening before; holidays are not feed items.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date

from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "holidays"
URL = (
    "https://calendar.google.com/calendar/ical/"
    "en.lk%23holiday%40group.v.calendar.google.com/public/basic.ics"
)
HISTORY_START = date(2026, 1, 1)

_LINE = re.compile(r"^([A-Z-]+)(?:;[^:]*)?:(.*)$")


@dataclass(frozen=True)
class Holiday:
    day: date
    name: str
    tentative: bool


def parse(ics: str) -> list[Holiday]:
    """Public holidays only; observances such as Mother's Day are left out."""
    # Unfold continuation lines (RFC 5545): a line break followed by a space or tab.
    text = re.sub(r"\r?\n[ \t]", "", ics).replace("\r\n", "\n")
    holidays = []
    for block in text.split("BEGIN:VEVENT")[1:]:
        fields = _fields(block)
        description = _unescape(fields.get("DESCRIPTION", ""))
        start = fields.get("DTSTART", "")
        if not description.startswith("Public holiday") or not re.fullmatch(r"\d{8}", start):
            continue
        name = re.sub(r"\s*\(tentative\)$", "", _unescape(fields.get("SUMMARY", "")).strip())
        day = date(int(start[:4]), int(start[4:6]), int(start[6:]))
        holidays.append(Holiday(day, name, "tentative" in description.lower()))
    return sorted(holidays, key=lambda holiday: (holiday.day, holiday.name))


def run(web: Web, store: Store, today: date) -> int:
    holidays = [holiday for holiday in parse(web.get(URL).text) if holiday.day >= HISTORY_START]
    if not holidays:
        raise ValueError("no public holidays in the calendar")
    rows = [
        {"date": holiday.day.isoformat(), "name": holiday.name, "tentative": holiday.tentative}
        for holiday in holidays
    ]
    store.write_dataset(NAME, {"holidays": rows})
    return 0


def _fields(block: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in block.split("\n"):
        match = _LINE.match(line.strip())
        if match:
            fields.setdefault(match.group(1), match.group(2))
    return fields


def _unescape(value: str) -> str:
    return (
        value.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";")
    ).replace("\\\\", "\\")
