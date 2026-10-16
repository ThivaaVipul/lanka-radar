from __future__ import annotations

from collections.abc import Callable, Mapping
from pathlib import Path

import httpx
import pytest

from lanka_radar.store import Store
from lanka_radar.web import Web

FIXTURES = Path(__file__).parent / "fixtures"

Route = Callable[[httpx.Request], httpx.Response]


@pytest.fixture
def fixture_bytes() -> Callable[[str], bytes]:
    """A saved source response, byte for byte."""
    return lambda name: (FIXTURES / name).read_bytes()


@pytest.fixture
def store(tmp_path: Path) -> Store:
    return Store(tmp_path / "data")


@pytest.fixture
def make_web() -> Callable[[Mapping[str, Route]], Web]:
    """A Web that answers each request with the first route whose key is in its URL."""

    def build(routes: Mapping[str, Route]) -> Web:
        def handler(request: httpx.Request) -> httpx.Response:
            for key, route in routes.items():
                if key in str(request.url):
                    return route(request)
            return httpx.Response(404)

        return Web(transport=httpx.MockTransport(handler), sleep=lambda seconds: None)

    return build
