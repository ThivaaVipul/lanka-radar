"""A polite HTTP client: it names the project, times out, and retries brief failures."""

from __future__ import annotations

import time
from collections.abc import Callable, Mapping
from types import TracebackType
from typing import Any, Self

import httpx

USER_AGENT = "Mozilla/5.0 (compatible; LankaRadar/0.1; +https://github.com/ThivaaVipul/lanka-radar)"
ATTEMPTS = 3


class Web:
    def __init__(
        self,
        transport: httpx.BaseTransport | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self._client = httpx.Client(
            headers={"User-Agent": USER_AGENT},
            timeout=60.0,
            follow_redirects=True,
            transport=transport,
        )
        self._sleep = sleep

    def get(self, url: str, params: Mapping[str, str] | None = None) -> httpx.Response:
        return self._send("GET", url, params=params)

    def post_form(self, url: str, form: Mapping[str, str]) -> httpx.Response:
        return self._send("POST", url, data=form)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> Self:
        return self

    def __exit__(
        self,
        kind: type[BaseException] | None,
        error: BaseException | None,
        trace: TracebackType | None,
    ) -> None:
        self.close()

    def _send(self, method: str, url: str, **options: Any) -> httpx.Response:
        """Retries timeouts, dropped connections and 5xx answers; a 4xx answer fails at once."""
        for attempt in range(1, ATTEMPTS + 1):
            last = attempt == ATTEMPTS
            try:
                response = self._client.request(method, url, **options)
            except httpx.TransportError:
                if last:
                    raise
            else:
                if response.status_code < 500 or last:
                    response.raise_for_status()
                    return response
            self._sleep(2.0 * attempt)
        raise RuntimeError("unreachable")
