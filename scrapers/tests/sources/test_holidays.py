from collections.abc import Callable
from datetime import date

import httpx

from lanka_radar.sources import holidays
from lanka_radar.store import Store

CALENDAR = "google_holidays_lk.ics"


def event(start: str, summary: str, description: str) -> str:
    return (
        "BEGIN:VEVENT\r\n"
        f"DTSTART;VALUE=DATE:{start}\r\n"
        f"DESCRIPTION:{description}\r\n"
        f"SUMMARY:{summary}\r\n"
        "END:VEVENT\r\n"
    )


def test_keeps_public_holidays_and_drops_observances(fixture_bytes: Callable[[str], bytes]) -> None:
    found = holidays.parse(fixture_bytes(CALENDAR).decode("utf-8"))
    rows = [(holiday.day.isoformat(), holiday.name, holiday.tentative) for holiday in found]

    assert ("2026-01-03", "Duruthu Full Moon Poya Day", False) in rows
    assert ("2026-04-14", "Sinhala and Tamil New Year's Day", False) in rows
    assert all(name != "Valentine's Day" for _, name, _ in rows)
    assert all(name != "Christmas Eve" for _, name, _ in rows)


def test_two_holidays_on_one_day_are_both_kept(fixture_bytes: Callable[[str], bytes]) -> None:
    found = holidays.parse(fixture_bytes(CALENDAR).decode("utf-8"))

    assert [holiday.name for holiday in found if holiday.day == date(2026, 4, 1)] == [
        "Bak Full Moon Poya Day",
        "Fuel Conservation Holiday",
    ]


def test_tentative_dates_are_flagged_and_the_name_cleaned(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    found = holidays.parse(fixture_bytes(CALENDAR).decode("utf-8"))

    assert holidays.Holiday(date(2027, 3, 10), "Eid al-Fitr", True) in found


def test_unfolds_long_lines() -> None:
    ics = (
        "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20260501\r\n"
        "DESCRIPTION:Public\r\n  holiday\r\nSUMMARY:Vesak Full Moon\r\n  Poya Day\r\nEND:VEVENT\r\n"
    )

    assert holidays.parse(ics) == [
        holidays.Holiday(date(2026, 5, 1), "Vesak Full Moon Poya Day", False)
    ]


def test_run_keeps_2026_onwards(make_web: Callable[..., object], store: Store) -> None:
    calendar = event("20251225", "Christmas Day", "Public holiday") + event(
        "20260115", "Tamil Thai Pongal Day", "Public holiday"
    )
    web = make_web({"calendar.google.com": lambda _: httpx.Response(200, text=calendar)})

    assert holidays.run(web, store, date(2026, 10, 16)) == 0

    dataset = store.read_dataset("holidays")
    assert dataset is not None
    assert dataset["holidays"] == [
        {"date": "2026-01-15", "name": "Tamil Thai Pongal Day", "tentative": False}
    ]
