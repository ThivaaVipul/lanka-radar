"""Reads and writes the data branch checkout.

Layout:
  items/<yyyy>/<mm>/<id>.json   one feed item per file
  latest.json                   the newest items, newest first
  datasets/<name>.json          values the app shows (USD/LKR, holidays)
  status.json                   per-source run history
  state/<name>.json             the scrapers' own bookkeeping, not for the app
"""

from __future__ import annotations

import json
from datetime import datetime
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
        """Removes an item that turned out not to belong in the feed; True if one was there."""
        paths = list(self.root.glob(f"items/*/*/{item_id}.json"))
        for path in paths:
            path.unlink()
        return bool(paths)

    def write_latest(self) -> bool:
        items = [_read_json(path) for path in self.root.glob("items/*/*/*.json")]
        items.sort(key=lambda item: (item["published"], item["id"]), reverse=True)
        return _write_json(
            self.root / "latest.json", {"schema": SCHEMA, "items": items[:LATEST_COUNT]}
        )

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
