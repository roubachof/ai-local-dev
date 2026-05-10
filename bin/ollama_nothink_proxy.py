#!/usr/bin/env python3
"""Ollama nothink proxy — disables Qwen3.x "thinking" for downstream clients.

Purpose:
    Forward all requests to the local Ollama server (default port 11434)
    while injecting reasoning_effort:"none" into chat completion bodies to
    disable Qwen3 thinking.  Useful when the downstream client (e.g. Goose
    CLI, qwen-code) doesn't support the thinking toggle natively.

Model:
    Designed for Qwen3.6-35B-A3B served via Ollama.

How it works:
    - Listens on 127.0.0.1:11435 (configurable via --port).
    - Forwards all HTTP methods/paths to upstream Ollama at 127.0.0.1:11434.
    - On POST /v1/chat/completions, injects reasoning_effort:"none" into the
      JSON request body (unless thinking is explicitly enabled).
    - Streams SSE responses chunk-by-chunk without buffering.

Reasoning control:
    - Default (no env var): reasoning_effort:"none" is injected → thinking OFF.
    - OLLAMA_PROXY_THINK=1 or OLLAMA_PROXY_FORCE_THINK=1: passthrough mode,
      no injection → thinking ON.
    - If the caller already sets reasoning_effort in the body, it is preserved.

Usage:
    # Default mode (thinking disabled)
    .venv/bin/python bin/ollama_nothink_proxy.py --port 11435

    # Enable thinking (passthrough)
    OLLAMA_PROXY_FORCE_THINK=1 .venv/bin/python bin/ollama_nothink_proxy.py

    Then point your client at http://localhost:11435 instead of 11434.

Error handling:
    - Malformed JSON bodies are forwarded as-is (no crash).
    - Upstream errors (non-200) are forwarded with their original status.
    - Broken client connections are caught and silently closed.
    - All errors logged to stderr with [ollama-proxy] prefix.

Stdlib only — no third-party dependencies.
"""
from __future__ import annotations

import argparse
import http.client
import http.server
import json
import os
import socket
import sys

UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 11434

# When true, the proxy is a pure passthrough (Qwen3 thinking is ON).
# When false (default), reasoning_effort:"none" is injected into chat requests.
# Two env var names supported for backward compatibility.
THINK_ENABLED = (
    os.environ.get("OLLAMA_PROXY_THINK", "0") == "1"
    or os.environ.get("OLLAMA_PROXY_FORCE_THINK", "0") == "1"
)


def _patch_chat_body(raw: bytes) -> bytes:
    """Inject reasoning_effort:'none' into a /v1/chat/completions body."""
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return raw
    if not isinstance(data, dict):
        return raw
    # Don't override if caller already set it (lets users opt back in per-call).
    if "reasoning_effort" not in data:
        data["reasoning_effort"] = "none"
    return json.dumps(data, separators=(",", ":")).encode("utf-8")


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write(f"[ollama-proxy] {fmt % args}\n")

    def _forward(self, method: str) -> None:
        cl = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(cl) if cl else b""

        # Inject reasoning_effort:"none" only on chat-completions POSTs in no-think mode.
        if (
            not THINK_ENABLED
            and method == "POST"
            and self.path == "/v1/chat/completions"
        ):
            body = _patch_chat_body(body)

        # Strip hop-by-hop / length headers; we'll set our own.
        skip = {"host", "content-length", "connection", "transfer-encoding"}
        fwd_headers: dict[str, str] = {
            k: v for k, v in self.headers.items() if k.lower() not in skip
        }
        fwd_headers["Host"] = f"{UPSTREAM_HOST}:{UPSTREAM_PORT}"
        if body:
            fwd_headers["Content-Length"] = str(len(body))

        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=600)
        try:
            conn.request(method, self.path, body=body or None, headers=fwd_headers)
            resp = conn.getresponse()

            self.send_response(resp.status, resp.reason)
            # Forward upstream headers verbatim except those we manage.
            for h, v in resp.getheaders():
                if h.lower() in {"transfer-encoding", "content-length", "connection"}:
                    continue
                self.send_header(h, v)

            # Use chunked transfer so streaming responses (SSE) are forwarded live.
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Connection", "close")
            self.end_headers()

            # Drain upstream as bytes arrive — read1 returns whatever is buffered.
            while True:
                try:
                    chunk = resp.read1(65536)
                except (http.client.IncompleteRead, ConnectionError):
                    break
                if not chunk:
                    break
                self.wfile.write(f"{len(chunk):x}\r\n".encode("ascii"))
                self.wfile.write(chunk)
                self.wfile.write(b"\r\n")
                try:
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    return
            # End of chunked stream
            try:
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        finally:
            conn.close()

    # Map all common HTTP verbs to our forwarder.
    def do_GET(self) -> None:  # noqa: N802
        self._forward("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._forward("POST")

    def do_PUT(self) -> None:  # noqa: N802
        self._forward("PUT")

    def do_DELETE(self) -> None:  # noqa: N802
        self._forward("DELETE")

    def do_PATCH(self) -> None:  # noqa: N802
        self._forward("PATCH")

    def do_HEAD(self) -> None:  # noqa: N802
        self._forward("HEAD")


class ThreadingHTTPServer(http.server.ThreadingHTTPServer):
    """Threaded server with SO_REUSEADDR so restarts are instant."""

    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self) -> None:
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        super().server_bind()


def main() -> int:
    global UPSTREAM_PORT  # noqa: PLW0603
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=11435, help="Listen port (default: 11435)")
    parser.add_argument(
        "--upstream-port",
        type=int,
        default=UPSTREAM_PORT,
        help="Upstream Ollama port (default: 11434)",
    )
    args = parser.parse_args()
    UPSTREAM_PORT = args.upstream_port

    server = ThreadingHTTPServer(("127.0.0.1", args.port), ProxyHandler)
    mode = "PASSTHROUGH (think ON)" if THINK_ENABLED else "INJECTING reasoning_effort=none (think OFF)"
    sys.stderr.write(
        f"[ollama-proxy] listening on http://127.0.0.1:{args.port} -> "
        f"http://{UPSTREAM_HOST}:{UPSTREAM_PORT}\n"
        f"[ollama-proxy] mode: {mode}\n"
        f"[ollama-proxy] point Goose at it with: export OLLAMA_HOST=http://localhost:{args.port}\n"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("[ollama-proxy] shutting down\n")
        server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
