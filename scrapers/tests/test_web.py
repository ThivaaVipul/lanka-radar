from collections.abc import Sequence

import httpx
import pytest

from lanka_radar.web import USER_AGENT, Web

Answer = int | type[httpx.TransportError]


def make(answers: Sequence[Answer]) -> tuple[Web, list[httpx.Request], list[float]]:
    requests: list[httpx.Request] = []
    sleeps: list[float] = []
    pending = iter(answers)

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        answer = next(pending)
        if isinstance(answer, int):
            return httpx.Response(answer, text="body")
        raise answer("dropped", request=request)

    return Web(transport=httpx.MockTransport(handler), sleep=sleeps.append), requests, sleeps


def test_names_the_project_in_the_user_agent() -> None:
    web, requests, _ = make([200])

    web.get("https://example.org/")

    assert requests[0].headers["User-Agent"] == USER_AGENT


def test_retries_server_errors_with_backoff() -> None:
    web, requests, sleeps = make([503, 502, 200])

    assert web.get("https://example.org/").text == "body"
    assert len(requests) == 3
    assert sleeps == [2.0, 4.0]


def test_gives_up_after_three_server_errors() -> None:
    web, requests, _ = make([500, 500, 500])

    with pytest.raises(httpx.HTTPStatusError):
        web.get("https://example.org/")
    assert len(requests) == 3


def test_client_errors_fail_at_once() -> None:
    web, requests, sleeps = make([404])

    with pytest.raises(httpx.HTTPStatusError):
        web.get("https://example.org/")
    assert len(requests) == 1
    assert sleeps == []


def test_retries_dropped_connections() -> None:
    web, _, _ = make([httpx.ConnectError, 200])

    assert web.get("https://example.org/").status_code == 200


def test_raises_after_three_dropped_connections() -> None:
    web, _, _ = make([httpx.ConnectError, httpx.ReadTimeout, httpx.ConnectError])

    with pytest.raises(httpx.ConnectError):
        web.get("https://example.org/")


def test_post_form_sends_url_encoded_fields() -> None:
    web, requests, _ = make([200])

    web.post_form("https://example.org/", {"chk_cur[]": "USD~US Dollar"})

    assert requests[0].headers["Content-Type"] == "application/x-www-form-urlencoded"
    assert requests[0].content == b"chk_cur%5B%5D=USD~US+Dollar"
