import json
from collections.abc import Callable
from datetime import date

import httpx

from lanka_radar.sources import jobs
from lanka_radar.store import Store

PAGE = "psc_home.html"
UPLOADS = "https://psc.gov.lk/images/latest_document/psc_announcements"


def test_parse_reads_each_announcement_with_its_full_title(
    fixture_bytes: Callable[[str], bytes],
) -> None:
    found = jobs.parse(fixture_bytes(PAGE).decode("utf-8"))

    legal = next(a for a in found if a.stamp == 1789464305)
    assert legal.title == (
        "Recruitment to the Posts of Legal Officer (Executive Service Grade III) in "
        "Environment Ministry - Open Stream - 2026"
    )
    assert (
        legal.pdf
        == f"{UPLOADS}/2026/1789464305-Recruitment-to-the-Posts-of-Legal-Officer--English.pdf"
    )
    assert legal.day == date(2026, 9, 15)
    assert [a.stamp for a in found] == sorted((a.stamp for a in found), reverse=True)


def test_only_recruitments_and_calls_for_applications_are_jobs() -> None:
    def titled(title: str) -> jobs.Announcement:
        return jobs.Announcement(1789464305, title, f"{UPLOADS}/x.pdf")

    assert titled("Recruitment to the Posts of Legal Officer").is_job
    assert titled("Open Recruitment of Sri Lanka Education Administrative Service").is_job
    assert titled("Calling for Applications for the post of Director").is_job
    assert not titled("Annual Transfer Appeals Decisions (Grade Medical Officers) - 2026").is_job
    assert not titled("Formulation of Annual Internal Transfer Procedures").is_job


def test_parse_uses_the_link_text_without_a_title() -> None:
    page = (
        '<a href="/images/latest_document/psc_announcements/2026/1789464305-x.pdf">'
        "Recruitment of\n <b>Officers</b></a>"
    )

    assert jobs.parse(page)[0].title == "Recruitment of Officers"


def test_run_makes_an_item_per_recruitment_this_year(
    fixture_bytes: Callable[[str], bytes], make_web: Callable[..., object], store: Store
) -> None:
    web = make_web({"psc.gov.lk": lambda _: httpx.Response(200, content=fixture_bytes(PAGE))})

    made = jobs.run(web, store, date(2026, 10, 19))

    assert made >= 2
    item = json.loads((store.root / "items/2026/09/jobs-psc-1789464305.json").read_text("utf-8"))
    assert item["topic"] == "jobs"
    assert item["issuer"] == "Public Service Commission"
    assert item["links"]["pdf_en"].startswith(UPLOADS)
    assert item["alert"] is True
    assert not list(store.root.glob("items/2023/**/*.json"))
    assert jobs.run(web, store, date(2026, 10, 19)) == 0
