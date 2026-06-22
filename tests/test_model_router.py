from __future__ import annotations

import asyncio
import pathlib
import sys

import pytest
from starlette.applications import State

BIN_DIR = pathlib.Path(__file__).resolve().parents[1] / "bin"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

# model_router parses sys.argv at import time; neutralize it so pytest's own
# argv doesn't trip argparse.
_orig_argv = sys.argv
sys.argv = ["model_router"]
try:
    import model_router  # noqa: E402
finally:
    sys.argv = _orig_argv


@pytest.fixture(autouse=True)
def _stable_args(monkeypatch: pytest.MonkeyPatch):
    """Pin router args to deterministic URLs so tests don't depend on env."""
    monkeypatch.setattr(
        model_router.ARGS,
        "planner_url",
        "http://127.0.0.1:8081",
        raising=False,
    )
    monkeypatch.setattr(
        model_router.ARGS,
        "coder_url",
        "http://127.0.0.1:11435",
        raising=False,
    )
    monkeypatch.setattr(
        model_router,
        "DEFAULT_URL",
        model_router.ARGS.planner_url,
        raising=False,
    )


# --- resolve_route / target_for_route ---

@pytest.mark.parametrize(
    "model_name,expected_route",
    [
        ("planner", "planner"),
        ("plan", "planner"),
        ("qwen-planner", "planner"),
        ("local-27b", "planner"),
        ("Qwen3.6-27B", "planner"),
        ("coder", "coder"),
        ("code", "coder"),
        ("qwen-coder", "coder"),
        ("local-35b", "coder"),
        ("Qwen3.6-35B", "coder"),
        ("unknown-model", "default"),
        (None, "default"),
        ("", "default"),
    ],
)
def test_resolve_route(model_name, expected_route):
    assert model_router.resolve_route(model_name) == expected_route


def test_target_for_route():
    assert model_router.target_for_route("planner") == model_router.ARGS.planner_url
    assert model_router.target_for_route("coder") == model_router.ARGS.coder_url
    assert model_router.target_for_route("default") == model_router.DEFAULT_URL


# --- force_think_header_for_route ---

def test_force_think_header_for_planner_is_on():
    assert model_router.force_think_header_for_route("planner") == "1"


def test_force_think_header_for_coder_is_off():
    assert model_router.force_think_header_for_route("coder") == "0"


def test_force_think_header_for_default_is_none():
    assert model_router.force_think_header_for_route("default") is None


# --- upstream_headers strips client force-think header ---

class _FakeRequest:
    def __init__(self, headers: dict[str, str]):
        self.headers = headers


def test_upstream_headers_strips_client_force_think_header():
    req = _FakeRequest(
        {
            "host": "127.0.0.1:8090",
            "authorization": "Bearer secret",
            "X-AI-Local-Force-Think": "1",
            "content-type": "application/json",
        }
    )
    headers = model_router.upstream_headers(req)
    assert "X-AI-Local-Force-Think" not in headers
    assert "authorization" not in headers
    assert "host" not in headers
    assert headers["content-type"] == "application/json"


# --- route_chat end-to-end: header injection per route ---

class _CapturingClient:
    """Stand-in for httpx.AsyncClient that records the outbound call."""

    def __init__(self):
        self.captured = {}

    async def post(self, url, *, json=None, headers=None):
        self.captured["url"] = url
        self.captured["headers"] = dict(headers or {})
        self.captured["body"] = json
        return _FakeResp()


class _FakeResp:
    status_code = 200

    def json(self):
        return {"choices": [{"message": {"content": "ok"}}]}

    @property
    def headers(self):
        return {"content-type": "application/json"}


def _build_request(body_bytes: bytes, extra_headers: list[tuple[bytes, bytes]] | None = None):
    from fastapi import Request
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/v1/chat/completions",
        "headers": [(b"content-type", b"application/json")] + (extra_headers or []),
        "query_string": b"",
    }

    async def receive():
        return {"type": "http.request", "body": body_bytes, "more_body": False}

    return Request(scope, receive)


def _install_client() -> _CapturingClient:
    if not isinstance(getattr(model_router.app, "state", None), State):
        model_router.app.state = State()
    client = _CapturingClient()
    model_router.app.state.client = client
    return client


def test_route_chat_injects_force_think_header_for_planner():
    client = _install_client()
    req = _build_request(b'{"model":"planner","stream":false}')
    asyncio.run(model_router.route_chat(req))
    assert client.captured["url"].startswith(model_router.ARGS.planner_url)
    assert client.captured["url"].endswith("/v1/chat/completions")
    assert client.captured["headers"].get("X-AI-Local-Force-Think") == "1"


def test_route_chat_injects_force_think_header_for_coder():
    client = _install_client()
    req = _build_request(b'{"model":"coder","stream":false}')
    asyncio.run(model_router.route_chat(req))
    assert client.captured["url"].startswith(model_router.ARGS.coder_url)
    assert client.captured["headers"].get("X-AI-Local-Force-Think") == "0"


def test_route_chat_default_route_sends_no_force_think_header():
    client = _install_client()
    req = _build_request(b'{"model":"unknown","stream":false}')
    asyncio.run(model_router.route_chat(req))
    assert "X-AI-Local-Force-Think" not in client.captured["headers"]


def test_route_chat_strips_client_supplied_force_think_header():
    """A client header must NOT leak through; the router owns the per-route value."""
    client = _install_client()
    req = _build_request(
        b'{"model":"coder","stream":false}',
        extra_headers=[(b"x-ai-local-force-think", b"1")],
    )
    asyncio.run(model_router.route_chat(req))
    # coder route must be "0" regardless of the incoming header
    assert client.captured["headers"].get("X-AI-Local-Force-Think") == "0"
