import json
from collections.abc import Callable, Sequence
from datetime import date
from typing import Any

import httpx
import pytest

from lanka_radar.sources import gazettes
from lanka_radar.sources.gazettes import Gazette
from lanka_radar.store import Store
from lanka_radar.web import Web

ANSWER = "documents_gov_extra_gazettes.txt"
NEW_ACTION = "a" * 42


def row(number: str, day: str, description: str, languages: Sequence[str] = ("ENGLISH",)) -> dict:
    return {
        "gazetteNoText": number,
        "date": f"{day}T00:00:00.000Z",
        "descriptionEnglish": description,
        "contents": [
            {
                "language": language,
                "uploadedFile": f"extra-gazette-content/G {number[-2:]} ({language[0]}).pdf",
            }
            for language in languages
        ],
    }


def answer(rows: list[dict], pages: int) -> str:
    payload = {"data": rows, "pagination": {"total": len(rows), "limit": 100, "totalPages": pages}}
    return '0:{"a":"$@1","f":"","q":"","i":false}\n1:' + json.dumps(payload) + "\n"


def site(
    pages: dict[int, str], actions: tuple[str, ...] = (gazettes.KNOWN_ACTION,)
) -> tuple[Web, list[Any]]:
    """A fake documents.gov.lk: the list action answers pages for the known action IDs."""
    calls: list[Any] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            action = request.headers["next-action"]
            page = json.loads(request.content)[0]["page"]
            calls.append((action, page))
            if action not in actions:
                return httpx.Response(404, text="Server action not found.")
            return httpx.Response(200, text=pages[page])
        calls.append(request.url.path)
        if request.url.path == "/web/extra_gazettes":
            html = (
                '<script src="/_next/static/chunks/aa1.js"></script>'
                '<script src="/_next/static/chunks/bb2.js"></script>'
            )
            return httpx.Response(200, text=html)
        if request.url.path.endswith("bb2.js"):
            script = (
                f'let C=(0,y.createServerReference)("{NEW_ACTION}",'
                'y.callServer,void 0,y.findSourceMapURL,"TableDataAction")'
            )
            return httpx.Response(200, text=script)
        return httpx.Response(200, text="console.log(1)")

    return Web(transport=httpx.MockTransport(handler), sleep=lambda seconds: None), calls


def test_parse_reads_the_action_answer(fixture_bytes: Callable[[str], bytes]) -> None:
    found, pages = gazettes.parse(fixture_bytes(ANSWER).decode("utf-8"))

    assert len(found) == 12
    assert pages == 3254
    assert found[0].number == "2510/36"
    assert found[0].day == date(2026, 10, 13)
    assert sorted(found[0].files) == ["en", "si", "ta"]
    assert found[0].files["ta"] == "extra-gazette-content/G 48278 (T)_1791884010.pdf"


def test_parse_keeps_line_separators_inside_descriptions() -> None:
    # U+2028 (line separator) is valid inside JSON but splitlines() would break on it.
    description = "Ministry of Labour - Dispute" + chr(0x2028) + "between A and B"
    text = answer([row("2480/01", "2026-03-10", description)], 1)

    found, _ = gazettes.parse(text)

    assert found[0].description == description


def test_parse_rejects_an_answer_without_data() -> None:
    with pytest.raises(ValueError):
        gazettes.parse('0:{"a":"$@1"}\n')


def test_merge_combines_copies_of_one_gazette() -> None:
    with_pdfs = Gazette(
        "2504/03", date(2026, 8, 31), "Ministry of Energy", {"en": "e.pdf", "ta": "t.pdf"}
    )
    fuller = Gazette("2504/03", date(2026, 8, 31), "Ministry of Energy - Revise the Fuel Price", {})

    assert gazettes.merge([fuller, with_pdfs]) == [
        Gazette(
            "2504/03",
            date(2026, 8, 31),
            "Ministry of Energy - Revise the Fuel Price",
            {"en": "e.pdf", "ta": "t.pdf"},
        )
    ]


@pytest.mark.parametrize(
    ("description", "group"),
    [
        ("Consumer Affairs Authority", "prices-taxes"),
        ("Sri Lanka Customs", "prices-taxes"),
        ("Sri Lanka Customs - Rates of Exchange w.e.f 13.07.2026 to 19.07.2026", None),
        (
            "Department of Census and Statistics - National Consumer Price Index - May 2026",
            "prices-taxes",
        ),
        ("Ministry of Health - Maximum retail price of medicines", "prices-taxes"),
        ("Ministry of Health and Mass Media - Take Over Base Hospital - Puttalam", None),
        ("Ministry 0f Energy - Order under Section 66 (1) (a) Revise the Fuel Price", "energy"),
        ("Public Utilities Commission of Sri Lanka - Direction Issued under Section 18", "energy"),
        ("Presidential Secretariat - Hon. A, Ministry of Energy has Resigned", None),
        ("M/of Labour - Industrial Dispute", "labour"),
        ("Elections Commission - Revision of Electoral Registers", "elections"),
        ("Department Local Government - Meeting for the Election of the Chairman", None),
        ("Land Title Settlement Department", None),
    ],
)
def test_groups_match_on_the_issuer(description: str, group: str | None) -> None:
    assert gazettes.group_of(Gazette("2500/01", date(2026, 5, 1), description)) == group


def test_item_for_a_fuel_price_revision() -> None:
    gazette = Gazette(
        "2504/03",
        date(2026, 8, 31),
        "Ministry of Energy - Revise the Fuel Price",
        {"ta": "extra-gazette-content/G 48001 (T)_1.pdf"},
    )

    item = gazettes.item_for(gazette, "energy")

    assert item.id == "gazette-2504-03"
    assert item.topic == "prices"
    assert item.issuer == "Ministry of Energy"
    assert item.headline_en == "Ministry of Energy - Revise the Fuel Price"
    assert item.links["pdf_ta"] == (
        "https://documents.gov.lk/api/content-file-proxy"
        "?file=/extra-gazette-content/G%2048001%20(T)_1.pdf"
    )
    assert item.data == {"number": "2504/03", "group": "energy", "languages": ["ta"]}


def test_item_for_a_gazette_listed_only_by_number() -> None:
    item = gazettes.item_for(Gazette("2509/34", date(2026, 10, 7), "2509/34"), "elections")

    assert item.headline_en == "Extraordinary gazette 2509/34"
    assert item.issuer is None
    assert item.links == {"page": gazettes.LIST_PAGE}


def test_reads_back_to_january_then_rechecks_three_weeks(store: Store) -> None:
    pages = {
        1: answer(
            [
                row("2480/01", "2026-03-10", "Consumer Affairs Authority"),
                row("2470/05", "2026-02-01", "Land Title Settlement Dept"),
            ],
            3,
        ),
        2: answer(
            [
                row("2469/24", "2026-01-05", "Election Commission"),
                row("2468/10", "2025-12-30", "Sri Lanka Customs"),
            ],
            3,
        ),
    }
    web, calls = site(pages)

    assert gazettes.run(web, store, date(2026, 3, 11)) == 2
    assert store.has_item("gazette-2480-01")
    assert store.has_item("gazette-2469-24")
    assert not store.has_item("gazette-2470-05")
    assert not store.has_item("gazette-2468-10")
    assert calls == [(gazettes.KNOWN_ACTION, 1), (gazettes.KNOWN_ACTION, 2)]
    assert store.read_state("gazettes") == {"action": gazettes.KNOWN_ACTION, "newest": "2026-03-10"}

    calls.clear()
    assert gazettes.run(web, store, date(2026, 3, 12)) == 0
    assert calls == [(gazettes.KNOWN_ACTION, 1)]


def test_retries_an_answer_without_data() -> None:
    good = answer([row("2480/01", "2026-03-10", "Sri Lanka Customs")], 1)
    answers = iter(['0:{"a":"$@1"}\n', good])
    pauses: list[float] = []
    web = Web(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, text=next(answers))),
        sleep=pauses.append,
    )

    found, _ = gazettes.fetch_page(web, gazettes.KNOWN_ACTION, 1)

    assert [gazette.number for gazette in found] == ["2480/01"]
    assert pauses == [10.0]


def test_finds_the_new_action_id_after_a_rebuild(store: Store) -> None:
    pages = {1: answer([row("2480/01", "2026-03-10", "Consumer Affairs Authority")], 1)}
    web, calls = site(pages, actions=(NEW_ACTION,))

    assert gazettes.run(web, store, date(2026, 3, 11)) == 1
    assert calls == [
        (gazettes.KNOWN_ACTION, 1),
        "/web/extra_gazettes",
        "/_next/static/chunks/aa1.js",
        "/_next/static/chunks/bb2.js",
        (NEW_ACTION, 1),
    ]
    state = store.read_state("gazettes")
    assert state is not None
    assert state["action"] == NEW_ACTION
