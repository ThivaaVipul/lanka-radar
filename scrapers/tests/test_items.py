from datetime import date

import pytest

from lanka_radar.items import Item, KeyNumber, short_date


def test_short_date_is_the_same_in_every_locale() -> None:
    assert short_date(date(2026, 9, 30)) == "30 Sep 2026"
    assert short_date(date(2026, 1, 3)) == "3 Jan 2026"


def test_item_json_matches_the_app_format() -> None:
    item = Item(
        id="fuel-2026-09-30",
        source="fuel",
        topic="prices",
        headline_en="Fuel prices from 30 Sep 2026",
        published=date(2026, 9, 30),
        effective=date(2026, 9, 30),
        key_numbers=[
            KeyNumber("Lanka Auto Diesel", 392.0, "LKR/l", 382.0),
            KeyNumber("Lanka Kerosene", 285.0, "LKR/l"),
        ],
        alert=True,
    )

    assert item.to_json() == {
        "id": "fuel-2026-09-30",
        "source": "fuel",
        "topic": "prices",
        "issuer": None,
        "headline": {"en": "Fuel prices from 30 Sep 2026", "ta": None},
        "keyNumbers": [
            {"label": "Lanka Auto Diesel", "value": 392.0, "unit": "LKR/l", "previous": 382.0},
            {"label": "Lanka Kerosene", "value": 285.0, "unit": "LKR/l"},
        ],
        "published": "2026-09-30",
        "effective": "2026-09-30",
        "links": {},
        "data": {},
        "alert": True,
    }


def test_unknown_topics_are_rejected() -> None:
    with pytest.raises(ValueError):
        Item(id="x", source="x", topic="sports", headline_en="x", published=date(2026, 1, 1))
