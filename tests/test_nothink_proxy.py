from __future__ import annotations

import pathlib
import sys

BIN_DIR = pathlib.Path(__file__).resolve().parents[1] / "bin"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import nothink_proxy  # noqa: E402


def test_patch_chat_response_strips_think_tags():
    data = {
        "choices": [
            {"message": {"role": "assistant", "content": "<think>hidden</think>Final answer"}},
            {"delta": {"content": "<think>x</think>Chunk"}},
        ]
    }
    nothink_proxy.patch_chat_response(data)
    assert data["choices"][0]["message"]["content"] == "Final answer"
    assert data["choices"][1]["delta"]["content"] == "Chunk"


def test_patch_stream_payload_handles_partial_think_blocks():
    filters = {}
    first = {"choices": [{"delta": {"content": "<think>private chain"}}]}
    second = {"choices": [{"delta": {"content": " still private</think> public"}}]}
    nothink_proxy.patch_stream_payload(first, filters)
    nothink_proxy.patch_stream_payload(second, filters)
    assert first["choices"][0]["delta"]["content"] == ""
    assert second["choices"][0]["delta"]["content"] == "public"


def test_apply_sampling_defaults_uses_mode_specific_defaults():
    original = nothink_proxy.CONFIG
    try:
        nothink_proxy.CONFIG = nothink_proxy.ProxyConfig(
            mode="llama",
            upstream_url="http://127.0.0.1:8080",
            timeout_s=600.0,
            force_think=False,
            nothink_temp=0.6,
            nothink_top_p=0.95,
            think_temp=1.0,
            think_top_p=0.9,
        )
        body = {}
        nothink_proxy.apply_sampling_defaults(body, force_think=False)
        assert body["temperature"] == 0.6
        assert body["top_p"] == 0.95

        force_body = {}
        nothink_proxy.apply_sampling_defaults(force_body, force_think=True)
        assert force_body["temperature"] == 1.0
        assert force_body["top_p"] == 0.9
    finally:
        nothink_proxy.CONFIG = original


def test_usage_from_payload_with_missing_usage():
    usage = nothink_proxy.usage_from_payload({"id": "x"})
    assert usage == {"prompt_tokens": None, "completion_tokens": None, "total_tokens": None}


def test_usage_from_payload_extracts_tokens():
    usage = nothink_proxy.usage_from_payload(
        {"usage": {"prompt_tokens": 12, "completion_tokens": 34, "total_tokens": 46}}
    )
    assert usage["prompt_tokens"] == 12
    assert usage["completion_tokens"] == 34
    assert usage["total_tokens"] == 46
