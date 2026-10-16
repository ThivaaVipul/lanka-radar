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
