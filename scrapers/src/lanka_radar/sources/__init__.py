"""One module per source, each with a NAME and run(web, store, today).

run() returns how many items were new or changed.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING, Protocol

from lanka_radar.sources import fuel, holidays, rates

if TYPE_CHECKING:
    from lanka_radar.store import Store
    from lanka_radar.web import Web


class Source(Protocol):
    NAME: str

    def run(self, web: Web, store: Store, today: date) -> int: ...


SOURCES: dict[str, Source] = {module.NAME: module for module in (fuel, rates, holidays)}
