import hashlib
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


def test_drop_item_removes_it(store: Store) -> None:
    store.put_item(item("a", date(2026, 3, 1)))

    assert store.drop_item("a")
    assert not store.has_item("a")
    assert not store.drop_item("a")


def test_latest_lists_the_newest_200_first(store: Store) -> None:
    for n in range(205):
        store.put_item(item(f"i{n:03d}", date(2026, 1, 1) + timedelta(days=n)))

    store.write_latest()

    latest = json.loads((store.root / "latest.json").read_text(encoding="utf-8"))
    assert latest["schema"] == 1
    assert len(latest["items"]) == 200
    assert [entry["id"] for entry in latest["items"][:2]] == ["i204", "i203"]


def test_months_hold_their_items_newest_first_with_an_index(store: Store) -> None:
    store.put_item(item("a", date(2026, 9, 3)))
    store.put_item(item("b", date(2026, 9, 28)))
    store.put_item(item("c", date(2026, 10, 2)))

    assert store.write_months()

    folder = store.root / "months"
    september = json.loads((folder / "2026-09.json").read_text(encoding="utf-8"))
    assert september["schema"] == 1
    assert september["month"] == "2026-09"
    assert [entry["id"] for entry in september["items"]] == ["b", "a"]
    index = json.loads((folder / "index.json").read_text(encoding="utf-8"))
    assert [(month["month"], month["count"]) for month in index["months"]] == [
        ("2026-10", 1),
        ("2026-09", 2),
    ]
    digest = hashlib.sha256((folder / "2026-09.json").read_bytes()).hexdigest()[:16]
    assert index["months"][1]["hash"] == digest


def test_months_change_only_with_their_items(store: Store) -> None:
    store.put_item(item("a", date(2026, 9, 3)))
    store.put_item(item("c", date(2026, 10, 2)))
    store.write_months()
    index = json.loads((store.root / "months" / "index.json").read_text(encoding="utf-8"))

    assert not store.write_months()

    store.put_item(item("a", date(2026, 9, 3), headline="corrected"))
    assert store.write_months()
    after = json.loads((store.root / "months" / "index.json").read_text(encoding="utf-8"))
    assert after["months"][0] == index["months"][0]
    assert after["months"][1]["hash"] != index["months"][1]["hash"]


def test_a_month_without_items_loses_its_file(store: Store) -> None:
    store.put_item(item("a", date(2026, 9, 3)))
    store.put_item(item("c", date(2026, 10, 2)))
    store.write_months()

    store.drop_item("a")

    assert store.write_months()
    assert not (store.root / "months" / "2026-09.json").exists()
    index = json.loads((store.root / "months" / "index.json").read_text(encoding="utf-8"))
    assert [month["month"] for month in index["months"]] == ["2026-10"]


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


def test_texts_are_bundled_by_month_with_an_index(store: Store) -> None:
    store.put_item(item("a", date(2026, 10, 2)))
    assert store.put_text("a", date(2026, 10, 2), "Fuel  prices\nrevised")
    assert not store.put_text("a", date(2026, 10, 2), "Fuel prices revised")
    store.put_text("b", date(2026, 9, 30), "Customs notice")

    assert store.write_texts()
    assert not store.write_texts()

    october = json.loads((store.root / "texts" / "2026-10.json").read_text(encoding="utf-8"))
    assert october == {"schema": 1, "month": "2026-10", "texts": {"a": "Fuel prices revised"}}
    index = json.loads((store.root / "texts" / "index.json").read_text(encoding="utf-8"))
    assert [(entry["month"], entry["count"]) for entry in index["months"]] == [
        ("2026-10", 1),
        ("2026-09", 1),
    ]


def test_dropping_an_item_drops_its_text(store: Store) -> None:
    store.put_item(item("a", date(2026, 10, 2)))
    store.put_text("a", date(2026, 10, 2), "text")
    store.write_texts()

    store.drop_item("a")
    store.write_texts()

    assert not store.has_text("a")
    assert not (store.root / "texts" / "2026-10.json").exists()
