import json
from collections.abc import Callable
from datetime import date
from typing import Any

import httpx
import pytest

from lanka_radar import documents
from lanka_radar.sources import weekly
from lanka_radar.sources.weekly import Heading, Notice
from lanka_radar.store import Store
from lanka_radar.web import Web

PDF = "weekly-2510-iia-en.pdf"
DAY = date(2026, 10, 9)


def content(file: str, language: str = "ENGLISH", section: int = 2, kind: str = "PDF") -> dict:
    return {
        "sectionId": section,
        "language": language,
        "uploadedFile": file,
        "uploadedFileFormat": kind,
    }


def week(day: str, *contents: dict) -> dict:
    return {"fullDate": f"{day}T00:00:00.000Z", "content": list(contents)}


def answer(rows: list[dict], pages: int = 1) -> str:
    payload = {"data": rows, "pagination": {"total": len(rows), "limit": 100, "totalPages": pages}}
    return '0:{"a":"$@1","f":"","q":"","i":false}\n1:' + json.dumps(payload) + "\n"


def site(pages: dict[int, str], pdfs: dict[str, bytes]) -> tuple[Web, list[Any]]:
    """A fake documents.gov.lk: the weekly list by page, and a PDF when its name holds one
    of the keys of `pdfs`."""
    calls: list[Any] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/api/content-file-proxy":
            name = request.url.params["file"]
            calls.append(name)
            match = next((data for key, data in pdfs.items() if key in name), None)
            return httpx.Response(200, content=match) if match else httpx.Response(404)
        body = json.loads(request.content)[0]
        calls.append((request.url.path, body["apiEndpoint"], body["page"]))
        return httpx.Response(200, text=pages[body["page"]])

    return Web(transport=httpx.MockTransport(handler), sleep=lambda seconds: None), calls


def test_reads_the_notices_of_a_weekly_gazette(fixture_bytes: Callable[[str], bytes]) -> None:
    number, found, texts = weekly.read(fixture_bytes(PDF), DAY)

    assert number == "2510"
    assert len(texts) == 45
    assert [(notice.section, notice.page) for notice in found] == [
        ("vacancies", 4),
        ("vacancies", 5),
        ("vacancies", 8),
        ("vacancies", 9),
        ("vacancies", 12),
        ("vacancies", 17),
        ("vacancies", 23),
        ("exams", 35),
        ("exams", 38),
        ("exams", 43),
        ("exams", 44),
    ]
    assert found[0] == Notice(
        "vacancies",
        "Registrar General's Department",
        "Post of Registrar of Muslim Marriages (Sinhala)",
        4,
        date(2026, 11, 9),
    )
    # The department isn't repeated in front of the title, nor "Calling Applications For".
    assert found[5].issuer == "Department of Government Factory"
    assert found[5].title.startswith("Open Recruitment To Posts In The Primary Unskilled")
    assert found[5].closes == date(2026, 11, 6)
    assert (
        found[7].title
        == "Open Competitive Examination for Recruitment to the Post of Excise Guard Driver - 2026"
    )
    assert found[7].closes == date(2026, 10, 30)


@pytest.mark.parametrize(
    ("text", "closes"),
    [
        ("forwarded on or before 09 th November, 2026, by registered post", date(2026, 11, 9)),
        ("on or before 06.11.2026 Open Recruitment", date(2026, 11, 6)),
        ("Applications closes on 9.00 pm of 2 nd of November, 2026.", date(2026, 11, 2)),
        ("the closing date is hereby extended to 12 November, 2026.", date(2026, 11, 12)),
        ("born on or before 28.09.2008 and on or after 28.09.1990", None),
        ("If recruited before 01.01.2027, salaries will be paid", None),
        ("as at the closing date of applications. Applications close", None),
    ],
)
def test_closing_dates(text: str, closes: date | None) -> None:
    assert weekly.closes(text, DAY) == closes


def test_weeks_keep_the_latest_upload_of_each_language() -> None:
    rows = [
        week(
            "2026-10-09",
            content("gazette-content/I-II(A) (E)_1792148816.pdf"),
            content("gazette-content/I-II(A) (E)_1792000000.pdf"),
            content("gazette-content/I-II(A) (E)_1792148835.epub", kind="EPUB"),
            content("gazette-content/II Legal (E)_1791786730.pdf", section=5),
        ),
        week("2026-10-09", content("gazette-content/I-II A (T)_1792131944.pdf", "TAMIL")),
        week("2026-10-02"),
    ]

    assert weekly.weeks(rows) == [
        weekly.Week(
            date(2026, 10, 9),
            {
                "en": "gazette-content/I-II(A) (E)_1792148816.pdf",
                "ta": "gazette-content/I-II A (T)_1792131944.pdf",
            },
        ),
        weekly.Week(date(2026, 10, 2), {}),
    ]


def heading(page: int, top: float, text: str, column: int = 0) -> Heading:
    return Heading(page, column, top, 11.0, text)


def test_a_wrapped_department_is_one_issuer_and_forms_are_not_notices() -> None:
    sections = [(4, "exams")]
    lines = [
        heading(4, 100, "MINISTRY OF EDUCATION, HIGHER"),
        heading(4, 112, "EDUCATION AND VOCATIONAL"),
        heading(4, 124, "EDUCATION"),
        heading(4, 150, "Efficiency Bar Examination III for Pirivena"),
        heading(4, 162, "Teachers - 2026"),
        # The application form after it repeats the title in capitals.
        heading(6, 100, "MINISTRY OF EDUCATION"),
        heading(6, 112, "EFFICIENCY BAR EXAMINATION III FOR PIRIVENA TEACHERS - 2026"),
        heading(7, 100, "Specimen Application Form"),
        heading(7, 112, "Efficiency Bar Examination III for Pirivena Teachers"),
    ]

    assert weekly.notices(sections, lines) == [
        Notice(
            "exams",
            "Ministry of Education, Higher Education and Vocational Education",
            "Efficiency Bar Examination III for Pirivena Teachers - 2026",
            4,
        )
    ]


def test_a_department_set_apart_from_its_title_is_still_its_issuer() -> None:
    lines = [
        heading(9, 100, "PUBLIC SERVICE COMMISSION"),
        heading(9, 140, "Ministry of Agriculture"),
        heading(10, 300, "Limited Competitive Examination for Recruitment - 2026"),
        # A form's heading that repeats the title inside a longer one.
        heading(14, 100, "Application for Limited Competitive Examination for Recruitment"),
    ]

    [notice] = weekly.notices([(9, "exams")], lines)

    assert notice.issuer == "Ministry of Agriculture"
    assert notice.title == "Limited Competitive Examination for Recruitment - 2026"


def test_runs_read_each_weeks_pdf_once(fixture_bytes: Callable[[str], bytes], store: Store) -> None:
    english = "gazette-content/I-II(A) - (09.10.2026) - Press (E)_1792148816.pdf"
    tamil = "gazette-content/I-II A (T) 09.10.2026_1792131944.pdf"
    old = "gazette-content/I-II(A) (E) 21.08.2026_1788000000.pdf"
    rows = [week("2026-10-09", content(english)), week("2026-08-21", content(old))]
    web, calls = site({1: answer(rows)}, {"(E)_1792148816": fixture_bytes(PDF)})

    assert weekly.run(web, store, date(2026, 10, 21)) == 11

    pdfs = [call for call in calls if isinstance(call, str)]
    assert pdfs == ["/" + english]  # nothing from before HISTORY_START
    item_id = (store.read_state("weekly") or {})["weeks"]["2026-10-09"]["items"][7]
    [path] = store.root.glob(f"items/2026/10/{item_id}.json")
    item = json.loads(path.read_text("utf-8"))
    assert item["source"] == "weekly"
    assert item["topic"] == "exams"
    assert item["issuer"] == "Sri Lanka Excise Department"
    assert item["alert"] is False
    assert item["data"] == {
        "week": "2026-10-09",
        "section": "exams",
        "page": 35,
        "number": "2510",
        "closes": "2026-10-30",
    }
    assert item["links"]["pdf_en"] == documents.pdf_link(english)
    assert "Excise Guard Driver" in (store.root / f"text/2026/10/{item_id}.txt").read_text("utf-8")

    # The Tamil PDF comes out: the items link it, and the English one isn't read again.
    calls.clear()
    rows[0] = week("2026-10-09", content(english), content(tamil, "TAMIL"))
    web, calls = site({1: answer(rows)}, {})

    assert weekly.run(web, store, date(2026, 10, 22)) == 11

    assert [call for call in calls if isinstance(call, str)] == []
    item = json.loads(path.read_text("utf-8"))
    assert item["links"]["pdf_ta"] == documents.pdf_link(tamil)
