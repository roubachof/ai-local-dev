#!/usr/bin/env python3
from __future__ import annotations

import os
import re

THINK_BLOCK_RE = re.compile(r"<think>.*?</think>\s*", re.DOTALL)


def resolve_force_think() -> bool:
    """Resolve force-think from the canonical env var or the llama legacy alias."""
    if os.environ.get("AI_LOCAL_FORCE_THINK", "0") == "1":
        return True
    if os.environ.get("LLAMA_PROXY_FORCE_THINK", "0") == "1":
        return True
    return False


def apply_disable_fields(body: dict, force_think: bool) -> None:
    """Apply disable-thinking request fields in-place."""
    if force_think or not isinstance(body, dict):
        return

    chat_kwargs = body.setdefault("chat_template_kwargs", {})
    if isinstance(chat_kwargs, dict):
        chat_kwargs.setdefault("enable_thinking", False)

    # Harmless fallback for older upstreams that still read top-level key.
    body.setdefault("enable_thinking", False)


def strip_think_blocks(text: str) -> str:
    """Remove <think> blocks from content text."""
    if not text:
        return text
    return THINK_BLOCK_RE.sub("", text)


def _trailing_partial_prefix_len(text: str, token: str) -> int:
    max_len = min(len(token) - 1, len(text))
    for size in range(max_len, 0, -1):
        if text.endswith(token[:size]):
            return size
    return 0


class SseThinkFilter:
    """Stateful think-block remover for streamed content chunks."""

    OPEN = "<think>"
    CLOSE = "</think>"

    def __init__(self) -> None:
        self._buffer = ""
        self._inside_think = False

    def process(self, chunk: str) -> str:
        if not chunk:
            return chunk
        self._buffer += chunk
        return self._drain_safe_text()

    def flush(self) -> str:
        if self._inside_think:
            self._buffer = ""
            return ""
        remaining = strip_think_blocks(self._buffer)
        self._buffer = ""
        return remaining

    def _drain_safe_text(self) -> str:
        data = self._buffer
        out: list[str] = []
        cursor = 0
        while cursor < len(data):
            if self._inside_think:
                close_idx = data.find(self.CLOSE, cursor)
                if close_idx == -1:
                    tail = data[cursor:]
                    keep = _trailing_partial_prefix_len(tail, self.CLOSE)
                    self._buffer = tail[-keep:] if keep else ""
                    return "".join(out)
                cursor = close_idx + len(self.CLOSE)
                self._inside_think = False
                while cursor < len(data) and data[cursor].isspace():
                    cursor += 1
                continue

            open_idx = data.find(self.OPEN, cursor)
            if open_idx == -1:
                tail = data[cursor:]
                keep = _trailing_partial_prefix_len(tail, self.OPEN)
                if keep:
                    out.append(tail[:-keep])
                    self._buffer = tail[-keep:]
                else:
                    out.append(tail)
                    self._buffer = ""
                return "".join(out)

            out.append(data[cursor:open_idx])
            cursor = open_idx + len(self.OPEN)
            self._inside_think = True

        self._buffer = ""
        return "".join(out)
