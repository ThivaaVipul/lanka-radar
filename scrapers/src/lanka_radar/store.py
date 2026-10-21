"""Reads and writes the data branch checkout.

Layout:
  items/<yyyy>/<mm>/<id>.json   one feed item per file
  latest.json                   the newest items, newest first
  months/<yyyy>-<mm>.json       every item of a month, newest first, for the app's history
  months/index.json             each month's item count and file hash
  text/<yyyy>/<mm>/<id>.txt     an item's text for search (a gazette's first pages)
  texts/<yyyy>-<mm>.json        every text of a month, by item ID, for the app
  texts/index.json              each month's text count and file hash
  datasets/<name>.json          values the app shows (USD/LKR, holidays)
  status.json                   per-source run history
  state/<name>.json             the scrapers' own bookkeeping, not for the app
"""

from __future__ import annotations

import hashlib
import json
from datetime import date, datetime
from pathlib import Path
from typing import Any

from lanka_radar.items import Item
from lanka_radar.status import stamp

SCHEMA = 1
LATEST_COUNT = 200


class Store:
    def __init__(self, root: Path) -> None:
        self.root = root

    def put_item(self, item: Item) -> bool:
        """Writes the item; True when it is new or changed."""
        day = item.published
        path = self.root / "items" / f"{day:%Y}" / f"{day:%m}" / f"{item.id}.json"
        return _write_json(path, item.to_json())

    def has_item(self, item_id: str) -> bool:
        return any(self.root.glob(f"items/*/*/{item_id}.json"))

    def drop_item(self, item_id: str) -> bool:
        """Removes an item that turned out not to belong in the feed, and its text; True if
        one was there."""
        paths = list(self.root.glob(f"items/*/*/{item_id}.json"))
        for path in [*paths, *self.root.glob(f"text/*/*/{item_id}.txt")]:
            path.unlink()
        return bool(paths)

    def read_items(self, prefix: str) -> list[dict[str, Any]]:
        """The stored items whose ID starts with `prefix`, oldest first."""
        items = [_read_json(path) for path in self.root.glob(f"items/*/*/{prefix}*.json")]
        return sorted(items, key=_by_date)

    def put_text(self, item_id: str, day: date, text: str) -> bool:
        """Keeps an item's text for search; True when it is new or changed."""
        path = self.root / "text" / f"{day:%Y}" / f"{day:%m}" / f"{item_id}.txt"
        text = " ".join(text.split())
        if path.exists() and path.read_text(encoding="utf-8") == text:
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        return True

    def has_text(self, item_id: str) -> bool:
        return any(self.root.glob(f"text/*/*/{item_id}.txt"))

    def write_latest(self) -> bool:
        items = [_read_json(path) for path in self.root.glob("items/*/*/*.json")]
        items.sort(key=_by_date, reverse=True)
        return _write_json(
            self.root / "latest.json", {"schema": SCHEMA, "items": items[:LATEST_COUNT]}
        )

    def write_months(self) -> bool:
        """One file per month with every item published in it, and an index of each
        month's item count and file hash, so the app downloads only the months that
        changed. A month left without items loses its file. True when anything changed."""
        months: dict[str, list[dict[str, Any]]] = {}
        for path in self.root.glob("items/*/*/*.json"):
            month = f"{path.parent.parent.name}-{path.parent.name}"
            months.setdefault(month, []).append(_read_json(path))
        folder = self.root / "months"
        changed = False
        index = []
        for month, items in sorted(months.items(), reverse=True):
            items.sort(key=_by_date, reverse=True)
            path = folder / f"{month}.json"
            changed |= _write_json(path, {"schema": SCHEMA, "month": month, "items": items})
            digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
            index.append({"month": month, "count": len(items), "hash": digest})
        for path in folder.glob("*-*.json"):
            if path.stem not in months:
                path.unlink()
                changed = True
        changed |= _write_json(folder / "index.json", {"schema": SCHEMA, "months": index})
        return changed

    def write_texts(self) -> bool:
        """The texts bundled by month, with an index of each month's count and file hash,
        as write_months does for items. True when anything changed."""
        months: dict[str, dict[str, str]] = {}
        for path in sorted(self.root.glob("text/*/*/*.txt")):
            month = f"{path.parent.parent.name}-{path.parent.name}"
            months.setdefault(month, {})[path.stem] = path.read_text(encoding="utf-8")
        folder = self.root / "texts"
        changed = False
        index = []
        for month, texts in sorted(months.items(), reverse=True):
            path = folder / f"{month}.json"
            changed |= _write_json(path, {"schema": SCHEMA, "month": month, "texts": texts})
            digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
            index.append({"month": month, "count": len(texts), "hash": digest})
        for path in folder.glob("*-*.json"):
            if path.stem not in months:
                path.unlink()
                changed = True
        if index or folder.exists():
            changed |= _write_json(folder / "index.json", {"schema": SCHEMA, "months": index})
        return changed

    def read_dataset(self, name: str) -> dict[str, Any] | None:
        path = self.root / "datasets" / f"{name}.json"
        return _read_json(path) if path.exists() else None

    def write_dataset(self, name: str, payload: dict[str, Any]) -> bool:
        return _write_json(self.root / "datasets" / f"{name}.json", {"schema": SCHEMA, **payload})

    def read_state(self, name: str) -> dict[str, Any] | None:
        path = self.root / "state" / f"{name}.json"
        return _read_json(path) if path.exists() else None

    def write_state(self, name: str, payload: dict[str, Any]) -> bool:
        return _write_json(self.root / "state" / f"{name}.json", payload)

    def read_status(self) -> dict[str, Any]:
        path = self.root / "status.json"
        return _read_json(path) if path.exists() else {"sources": {}}

    def write_status(self, report: dict[str, Any], now: datetime) -> bool:
        payload = {"schema": SCHEMA, "checked": stamp(now), "sources": report.get("sources", {})}
        return _write_json(self.root / "status.json", payload)


def _by_date(item: dict[str, Any]) -> tuple[str, str]:
    return item["published"], item["id"]


def _read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, payload: Any) -> bool:
    """Writes only when the content changed, so unchanged data makes no commit noise."""
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    return True
