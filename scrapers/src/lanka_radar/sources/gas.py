"""LP gas prices from Litro. The price list is one image whose file name carries the date
(e.g. Price-List-06.10.2026.webp), so a new file name means new prices. v1 links the
image; reading the prices off it comes later.
"""

from __future__ import annotations

import re
from datetime import date

from lanka_radar.items import Item, short_date
from lanka_radar.store import Store
from lanka_radar.web import Web

NAME = "gas"
PAGE = "https://www.litrogas.com/price-list/"
ISSUER = "Litro Gas Lanka"
HISTORY_START = date(2026, 1, 1)

_IMAGE = re.compile(
    r"https://www\.litrogas\.com/wp-content/uploads/[\w./%-]*?"
    r"Price[-_ ]?List[-_ ]?(\d{1,2})[.\-_](\d{1,2})[.\-_](\d{4})[\w./%-]*?\.(?:webp|jpe?g|png)",
    re.IGNORECASE,
)


def parse(html: str) -> list[tuple[date, str]]:
    """Each dated price list on the page, with its full-size image (the shortest URL;
    the longer ones are resized copies such as -300x374.webp)."""
    found: dict[date, str] = {}
    for match in _IMAGE.finditer(html):
        day = date(int(match.group(3)), int(match.group(2)), int(match.group(1)))
        url = match.group(0)
        if day not in found or len(url) < len(found[day]):
            found[day] = url
    if not found:
        raise ValueError("no dated price list image on the page")
    return sorted(found.items())


def item_for(day: date, image: str) -> Item:
    return Item(
        id=f"gas-litro-{day.isoformat()}",
        source=NAME,
        topic="prices",
        issuer=ISSUER,
        headline_en=f"Litro gas prices from {short_date(day)}",
        published=day,
        effective=day,
        links={"image": image, "page": PAGE},
        alert=True,
    )


def run(web: Web, store: Store, today: date) -> int:
    lists = parse(web.get(PAGE).text)
    return sum(store.put_item(item_for(day, image)) for day, image in lists if day >= HISTORY_START)
