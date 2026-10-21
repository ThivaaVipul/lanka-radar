"""The Department of Government Printing's site (documents.gov.lk), shared by the gazette
sources.

The site is a Next.js app. Its tables load through a server action named TableDataAction
that forwards to an internal endpoint and answers with JSON, PDF file names included, so
a plain POST with the action's ID reads a table page by page. A rebuild of the site
changes that ID; `find_action` then finds the new one in the site's scripts.
"""

from __future__ import annotations

import json
import re
from typing import Any
from urllib.parse import quote

import httpx

from lanka_radar.web import Web

SITE = "https://documents.gov.lk"
KNOWN_ACTION = "40f4893d604b59b307fb0473d42e9ac093be1e1655"
ANSWER_ATTEMPTS = 3
LANGUAGES = {"ENGLISH": "en", "TAMIL": "ta", "SINHALA": "si"}

_ACTION = re.compile(r'createServerReference\)\("([0-9a-f]{40,})",[^"]*"TableDataAction"')
_CHUNK = re.compile(r"/_next/static/chunks/[^\"'\s]+\.js")


def parse_table(text: str) -> tuple[list[dict[str, Any]], int]:
    """Reads one TableDataAction answer: its rows and how many pages there are."""
    # Rows are separated by "\n" only. splitlines() would also split on characters such
    # as U+2028 that can appear inside a description and cut a row in half.
    for line in text.split("\n"):
        try:
            payload = json.loads(line.partition(":")[2])
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and isinstance(payload.get("data"), list):
            pages = int(payload.get("pagination", {}).get("totalPages", 1))
            return payload["data"], pages
    raise ValueError(f"no table data in the answer: {text[:120]!r}")


def fetch_table(
    web: Web, page_url: str, endpoint: str, action: str, page: int, limit: int
) -> tuple[list[dict[str, Any]], int]:
    """One page of a table. The site sometimes answers briefly without data (its back end
    hiccups or throttles a burst), so such an answer is retried after a pause."""
    for attempt in range(1, ANSWER_ATTEMPTS + 1):
        try:
            return parse_table(_post(web, page_url, endpoint, action, page, limit).text)
        except ValueError:
            if attempt == ANSWER_ATTEMPTS:
                raise
            web.pause(10.0 * attempt)
    raise RuntimeError("unreachable")


def _post(
    web: Web, page_url: str, endpoint: str, action: str, page: int, limit: int
) -> httpx.Response:
    body = [
        {
            "apiEndpoint": endpoint,
            "page": page,
            "limit": limit,
            "q": "",
            "search": "",
            "forwarded": {},
        }
    ]
    headers = {
        "next-action": action,
        "accept": "text/x-component",
        "content-type": "text/plain;charset=UTF-8",
    }
    return web.post(page_url, content=json.dumps(body), headers=headers)


def find_action(web: Web, page_url: str) -> str:
    """Finds the TableDataAction ID in the site's scripts, after a rebuild changed it."""
    for chunk in sorted(set(_CHUNK.findall(web.get(page_url).text))):
        match = _ACTION.search(web.get(SITE + chunk).text)
        if match:
            return match.group(1)
    raise ValueError("TableDataAction not found in the site's scripts")


def pdf_link(path: str) -> str:
    return f"{SITE}/api/content-file-proxy?file=/{quote(path, safe='/()')}"
