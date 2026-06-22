from __future__ import annotations

import pathlib
import sys

import pytest

BIN_DIR = pathlib.Path(__file__).resolve().parents[1] / "bin"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

from _nothink import (  # noqa: E402
    SseThinkFilter,
    apply_disable_fields,
    resolve_force_think,
    resolve_force_think_header,
    strip_think_blocks,
)


def test_apply_disable_fields_defaults():
    body = {}
    apply_disable_fields(body, force_think=False)
    assert body["enable_thinking"] is False
    assert body["chat_template_kwargs"]["enable_thinking"] is False


def test_apply_disable_fields_respects_existing_values():
    body = {
        "enable_thinking": True,
        "chat_template_kwargs": {"enable_thinking": True},
    }
    apply_disable_fields(body, force_think=False)
    assert body["enable_thinking"] is True
    assert body["chat_template_kwargs"]["enable_thinking"] is True


def test_apply_disable_fields_force_think_leaves_payload_untouched():
    body = {"messages": [{"role": "user", "content": "Hi"}]}
    apply_disable_fields(body, force_think=True)
    assert "chat_template_kwargs" not in body
    assert "enable_thinking" not in body


def test_strip_think_blocks():
    text = "<think>hidden reasoning</think>Visible answer"
    assert strip_think_blocks(text) == "Visible answer"


def test_sse_think_filter_handles_split_tags():
    filt = SseThinkFilter()
    assert filt.process("<thi") == ""
    assert filt.process("nk>private") == ""
    assert filt.process(" chain") == ""
    assert filt.process("</th") == ""
    assert filt.process("ink> visible") == "visible"
    assert filt.flush() == ""


def test_resolve_force_think_canonical_env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AI_LOCAL_FORCE_THINK", "1")
    assert resolve_force_think() is True


def test_resolve_force_think_legacy_alias(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv("AI_LOCAL_FORCE_THINK", raising=False)
    monkeypatch.setenv("LLAMA_PROXY_FORCE_THINK", "1")
    assert resolve_force_think() is True


# --- resolve_force_think_header ---

def test_resolve_force_think_header_one_means_on():
    assert resolve_force_think_header("1") is True


def test_resolve_force_think_header_zero_means_off():
    assert resolve_force_think_header("0") is False


def test_resolve_force_think_header_absent_is_none():
    assert resolve_force_think_header(None) is None


def test_resolve_force_think_header_empty_is_none():
    assert resolve_force_think_header("") is None


def test_resolve_force_think_header_garbage_is_none():
    # Any value other than "1"/"0" is treated as no override so the caller
    # falls back to the launch-time default.
    assert resolve_force_think_header("true") is None
    assert resolve_force_think_header("yes") is None
