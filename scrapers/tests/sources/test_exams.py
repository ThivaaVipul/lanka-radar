import json
from collections.abc import Callable
from datetime import date

import httpx
import pytest

from lanka_radar.sources import exams
from lanka_radar.sources.exams import Notice
from lanka_radar.store import Store

NEWS = "doenets_news.json"
CALENDAR = "doenets_calendar.json"


def notices(fixture_bytes: Callable[[str], bytes], name: str, resource_type: str) -> list[Notice]:
    return exams.parse(json.loads(fixture_bytes(name)), resource_type)


def test_parse_reads_titles_in_three_languages_and_the_pdfs(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    found = notices(fixture_bytes, NEWS, "NEWS")
    git = next(notice for notice in found if notice.id == 2465)

    assert len(found) == 50
    assert git.day == date(2026, 9, 18)
    assert git.title == "General Information Technology Examination - 2026"
    assert sorted(git.titles) == ["en", "si", "ta"]
    assert sorted(git.files) == ["en", "si", "ta"]


@pytest.mark.parametrize(
    ("resource_type", "title", "kind"),
    [
        ("NEWS", "General Information Technology Examination - 2026", "school"),
        ("NEWS", "Grade 5 Scholarship Examinations - 2026", "school"),
        ("NEWS", "MEDIA NOTICE G.C.E. (A/L) EXAMINATION - 2025 Re-scrutiny of Results", "school"),
        ("NEWS", "Press Release", "notice"),
        ("NEWS", "Special Notice", "notice"),
        ("NEWS", "Notice on Issuance of Admission Cards for Institutional Examinations", None),
        ("NEWS", "PIRIVEN ORDINARY LEVEL EXAMINATION - 2026", None),
        ("NEWS", "Limited Competitive Examination for Recruitment to Grade III", None),
        ("NEWS", "Sri Lanka Law College General Entrance Examination - 2026", None),
        ("EXCA", "G.C.E. (Ordinary Level) Examination - 2026 Time Table", "timetable"),
        ("EXCA", "Examination Calendar for November 2026", None),
    ],
)
def test_kind_of(resource_type: str, title: str, kind: str | None) -> None:
    notice = Notice(1, resource_type, date(2026, 5, 1), {"en": title})

    assert exams.kind_of(notice) == kind


def test_item_keeps_the_tamil_title_and_links_each_pdf(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    timetable = next(n for n in notices(fixture_bytes, CALENDAR, "EXCA") if n.id == 2479)

    item = exams.item_for(timetable, "timetable")

    assert item.id == "exam-2479"
    assert item.topic == "exams"
    assert item.headline_ta == timetable.titles["ta"]
    assert item.links["page"] == "https://www.doenets.lk/examcalendar"
    assert item.links["pdf_en"] == (
        "https://www.doenets.lk/images/resources/EXCA/"
        "OL%20timetable%20English%20-%202026_1791794467174.pdf"
    )


def test_run_reads_news_and_the_calendar(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    asked: list[dict[str, str]] = []

    def cms(request: httpx.Request) -> httpx.Response:
        asked.append(dict(request.url.params))
        name = NEWS if request.url.params["type"] == "NEWS" else CALENDAR
        return httpx.Response(200, content=fixture_bytes(name))

    web = make_web({"doenets.lk/cms/api/resources": cms})

    assert exams.run(web, store, date(2026, 10, 16)) == 12
    assert [params["type"] for params in asked] == ["NEWS", "EXCA"]
    assert all(params["rowCount"] == "100" for params in asked)
    assert store.has_item("exam-2465")
    assert store.has_item("exam-2479")
    assert not store.has_item("exam-2468")


def test_notices_from_before_2026_make_no_item(
    make_web: Callable[..., object], store: Store
) -> None:
    old = {
        "resources": [
            {
                "id": 7,
                "isEnabled": True,
                "title": {"en": "Grade 5 Scholarship Examination - 2025"},
                "links": [],
                "created_date": "2025-12-30T10:00:00",
            }
        ]
    }
    web = make_web({"doenets.lk": lambda _: httpx.Response(200, json=old)})

    assert exams.run(web, store, date(2026, 1, 5)) == 0


OL_TIMETABLE = "doenets_ol_timetable_2026.pdf"
GIT_TIMETABLE = "doenets_git_timetable_2026.pdf"


def test_exam_days_reads_ordinals_with_their_raised_th(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    days = exams.exam_days(fixture_bytes(OL_TIMETABLE), 2026)

    assert days == [date(2026, 12, day) for day in (8, 9, 10, 11, 12, 14, 15, 16, 17)]


def test_exam_days_falls_back_to_the_tamil_date(fixture_bytes: Callable[[str], bytes]) -> None:
    assert exams.exam_days(fixture_bytes(GIT_TIMETABLE), 2026) == [date(2026, 10, 24)]


def word(text: str, x0: float, top: float) -> dict[str, object]:
    return {"text": text, "x0": x0, "x1": x0 + 5 * len(text), "top": top}


def test_english_days_pairs_a_day_with_the_month_beside_or_below_it() -> None:
    beside = [word("Monday,", 300, 100), word("10th", 340, 100), word("August", 362, 100)]
    below = [word("08", 72, 116), word("th", 81, 114), word("December", 72, 126)]
    below += [word("2025", 120, 126), word("1", 50, 120)]

    assert exams.english_days(beside, 2026) == {date(2026, 8, 10)}
    assert exams.english_days(below, 2026) == {date(2025, 12, 8)}


def test_tamil_days_reads_either_order() -> None:
    lines = ["2026 ஒக்ரோபர் 24", "ஓகஸ்ட் 09 ஞாயிற்றுக்கிழமை", "10 டிசம்பர் திங்கட்கிழமை"]

    assert exams.tamil_days(lines, 2027) == {
        date(2026, 10, 24),
        date(2027, 8, 9),
        date(2027, 12, 10),
    }


def test_timetables_are_the_calendars_and_school_news_with_a_timetable_pdf() -> None:
    git = Notice(1, "NEWS", date(2026, 9, 18), {}, {"en": "/NEWS/GIT Time Table 2026.pdf"})
    al = Notice(2, "NEWS", date(2026, 8, 7), {}, {"en": "/NEWS/AL_Time_Table _2026.pdf"})
    results = Notice(3, "NEWS", date(2026, 8, 7), {}, {"en": "/NEWS/Results 2026.pdf"})

    assert exams.is_timetable(git, "school")
    assert exams.is_timetable(al, "school")
    assert not exams.is_timetable(results, "school")
    assert not exams.is_timetable(git, "notice")
    assert exams.is_timetable(results, "timetable")


def test_run_reads_each_timetable_pdf_once_and_keeps_its_days(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    pdfs: list[str] = []

    def cms(request: httpx.Request) -> httpx.Response:
        name = NEWS if request.url.params["type"] == "NEWS" else CALENDAR
        return httpx.Response(200, content=fixture_bytes(name))

    def resources(request: httpx.Request) -> httpx.Response:
        pdfs.append(request.url.path)
        for key, name in (("OL timetable", OL_TIMETABLE), ("GIT Time Table", GIT_TIMETABLE)):
            if key in request.url.path:
                return httpx.Response(200, content=fixture_bytes(name))
        return httpx.Response(404)

    web = make_web({"cms/api/resources": cms, "images/resources": resources})

    exams.run(web, store, date(2026, 10, 19))

    def days(item_id: str) -> list[str] | None:
        path = next(store.root.glob(f"items/*/*/{item_id}.json"))
        return json.loads(path.read_text("utf-8"))["data"].get("days")

    assert days("exam-2465") == ["2026-10-24"]
    assert days("exam-2479") == [f"2026-12-{day:02}" for day in (8, 9, 10, 11, 12, 14, 15, 16, 17)]
    # The A/L and Grade 5 PDFs answered 404 here: no days, and not asked for again.
    assert days("exam-2421") is None
    assert len(pdfs) == 4

    pdfs.clear()
    assert exams.run(web, store, date(2026, 10, 20)) == 0
    assert pdfs == []
