import json
from datetime import UTC, date, datetime, timedelta

from lanka_radar.items import Item
from lanka_radar.store import Store


def item(item_id: str, day: date, headline: str = "headline") -> Item:
    return Item(id=item_id, source="test", topic="prices", headline_en=headline, published=day)


def test_put_item_reports_new_changed_and_unchanged(store: Store) -> None:
    assert store.put_item(item("a", date(2026, 3, 1)))
    assert not store.put_item(item("a", date(2026, 3, 1)))
    assert store.put_item(item("a", date(2026, 3, 1), headline="corrected"))

    assert (store.root / "items" / "2026" / "03" / "a.json").exists()
    assert store.has_item("a")
    assert not store.has_item("b")


def test_latest_lists_the_newest_200_first(store: Store) -> None:
    for n in range(205):
        store.put_item(item(f"i{n:03d}", date(2026, 1, 1) + timedelta(days=n)))

    store.write_latest()

    latest = json.loads((store.root / "latest.json").read_text(encoding="utf-8"))
    assert latest["schema"] == 1
    assert len(latest["items"]) == 200
    assert [entry["id"] for entry in latest["items"][:2]] == ["i204", "i203"]


def test_datasets_carry_the_schema_and_skip_unchanged_writes(store: Store) -> None:
    assert store.write_dataset("fuel", {"products": {}})
    assert not store.write_dataset("fuel", {"products": {}})

    assert store.read_dataset("fuel") == {"schema": 1, "products": {}}
    assert store.read_dataset("missing") is None


def test_status_round_trip(store: Store) -> None:
    assert store.read_status() == {"sources": {}}

    store.write_status(
        {"sources": {"fuel": {"failures": 0}}}, datetime(2026, 10, 16, 5, 30, tzinfo=UTC)
    )

    assert store.read_status() == {
        "schema": 1,
        "checked": "2026-10-16T05:30:00Z",
        "sources": {"fuel": {"failures": 0}},
    }


def test_files_are_written_with_lf_and_utf8(store: Store) -> None:
    thai = chr(0x0BA4) + chr(0x0BC8)  # Tamil "Thai", built from code points to keep this file ASCII
    store.write_dataset("names", {"name": "Tamil Thai Pongal Day", "ta": thai})

    raw = (store.root / "datasets" / "names.json").read_bytes()
    assert b"\r\n" not in raw
    assert thai.encode() in raw
