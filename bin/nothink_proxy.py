#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse

from _nothink import SseThinkFilter, apply_disable_fields, resolve_force_think, strip_think_blocks

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("nothink-proxy")


@dataclass
class ProxyConfig:
    upstream_url: str
    timeout_s: float
    force_think: bool
    nothink_temp: float
    nothink_top_p: float
    think_temp: float
    think_top_p: float
    warp_ctx_soft_limit: int


DEFAULT_UPSTREAM_URL = "http://127.0.0.1:8080"


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


CONFIG = ProxyConfig(
    upstream_url=os.environ.get("UPSTREAM_URL", DEFAULT_UPSTREAM_URL),
    timeout_s=_env_float("PROXY_TIMEOUT", 600.0),
    force_think=resolve_force_think(),
    nothink_temp=_env_float("AI_LOCAL_NOTHINK_TEMP", 0.6),
    nothink_top_p=_env_float("AI_LOCAL_NOTHINK_TOP_P", 0.95),
    think_temp=_env_float("AI_LOCAL_THINK_TEMP", 1.0),
    think_top_p=_env_float("AI_LOCAL_THINK_TOP_P", 0.95),
    warp_ctx_soft_limit=_env_int("AI_LOCAL_WARP_CTX_SOFT_LIMIT", 28000),
)


def json_log(event: str, **fields: Any) -> None:
    payload = {
        "ts": datetime.now(UTC).isoformat(),
        "event": event,
        "upstream": CONFIG.upstream_url,
    }
    payload.update(fields)
    log.info(json.dumps(payload, ensure_ascii=False))


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(timeout=CONFIG.timeout_s)
    json_log(
        "proxy_started",
        force_think=CONFIG.force_think,
        warp_ctx_soft_limit=CONFIG.warp_ctx_soft_limit,
    )
    try:
        yield
    finally:
        await app.state.client.aclose()
        json_log("proxy_stopped")


app = FastAPI(lifespan=lifespan)


def build_upstream_headers(request: Request, body_len: int | None = None) -> dict[str, str]:
    skip = {"host", "content-length", "connection", "authorization"}
    headers: dict[str, str] = {
        key: value for key, value in request.headers.items() if key.lower() not in skip
    }
    if body_len is not None:
        headers["Content-Length"] = str(body_len)
    return headers


def response_headers(resp: httpx.Response) -> dict[str, str]:
    skip = {"transfer-encoding", "content-length", "connection"}
    return {k: v for k, v in resp.headers.items() if k.lower() not in skip}


def apply_sampling_defaults(body: dict[str, Any], force_think: bool) -> None:
    temp = CONFIG.think_temp if force_think else CONFIG.nothink_temp
    top_p = CONFIG.think_top_p if force_think else CONFIG.nothink_top_p
    body.setdefault("temperature", temp)
    body.setdefault("top_p", top_p)


def patch_message_content(message: dict[str, Any], sse_filter: SseThinkFilter | None = None) -> None:
    content = message.get("content")
    if not isinstance(content, str):
        return
    if sse_filter is None:
        message["content"] = strip_think_blocks(content)
        return
    message["content"] = sse_filter.process(content)


def patch_chat_response(data: dict[str, Any]) -> None:
    for choice in data.get("choices", []):
        message = choice.get("message")
        if isinstance(message, dict):
            patch_message_content(message)
        delta = choice.get("delta")
        if isinstance(delta, dict):
            patch_message_content(delta)


def patch_stream_payload(data: dict[str, Any], filters: dict[int, SseThinkFilter]) -> None:
    for idx, choice in enumerate(data.get("choices", [])):
        sse_filter = filters.setdefault(idx, SseThinkFilter())
        message = choice.get("message")
        if isinstance(message, dict):
            patch_message_content(message, sse_filter)
        delta = choice.get("delta")
        if isinstance(delta, dict):
            patch_message_content(delta, sse_filter)


def usage_from_payload(payload: dict[str, Any]) -> dict[str, int | None]:
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        return {"prompt_tokens": None, "completion_tokens": None, "total_tokens": None}
    return {
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "total_tokens": usage.get("total_tokens"),
    }


def maybe_log_context_pressure(
    req_id: str, usage: dict[str, int | None], *, stream: bool
) -> None:
    prompt_tokens = usage.get("prompt_tokens")
    if not isinstance(prompt_tokens, int):
        return

    soft_limit = CONFIG.warp_ctx_soft_limit
    if soft_limit <= 0 or prompt_tokens < soft_limit:
        return

    utilization_pct = round((prompt_tokens / soft_limit) * 100, 1)
    json_log(
        "context_pressure",
        req_id=req_id,
        stream=stream,
        prompt_tokens=prompt_tokens,
        completion_tokens=usage.get("completion_tokens"),
        total_tokens=usage.get("total_tokens"),
        soft_limit_tokens=soft_limit,
        utilization_pct=utilization_pct,
        recommendation="start_new_conversation_or_reduce_context",
    )


async def proxy_json_get(path: str, timeout: float = 30.0) -> Response:
    client: httpx.AsyncClient = app.state.client
    try:
        resp = await client.get(f"{CONFIG.upstream_url}{path}", timeout=timeout)
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"error": str(exc)}, status_code=500)
    try:
        payload = resp.json()
        return JSONResponse(payload, status_code=resp.status_code, headers=response_headers(resp))
    except Exception:  # noqa: BLE001
        return Response(resp.content, status_code=resp.status_code, headers=response_headers(resp))


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    req_id = str(uuid.uuid4())
    started = time.perf_counter()
    try:
        body = await request.json()
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"error": f"invalid json body: {exc}"}, status_code=400)

    if not isinstance(body, dict):
        return JSONResponse({"error": "chat body must be a JSON object"}, status_code=400)

    apply_disable_fields(body, force_think=CONFIG.force_think)
    apply_sampling_defaults(body, force_think=CONFIG.force_think)
    is_stream = bool(body.get("stream"))

    json_log(
        "request_started",
        req_id=req_id,
        path="/v1/chat/completions",
        stream=is_stream,
        model=body.get("model"),
        force_think=CONFIG.force_think,
    )

    client: httpx.AsyncClient = app.state.client
    upstream_headers = build_upstream_headers(request)
    if not is_stream:
        try:
            upstream = await client.post(
                f"{CONFIG.upstream_url}/v1/chat/completions",
                json=body,
                headers=upstream_headers,
            )
        except Exception as exc:  # noqa: BLE001
            json_log("request_failed", req_id=req_id, error=str(exc))
            return JSONResponse({"error": str(exc)}, status_code=500)

        elapsed_ms = int((time.perf_counter() - started) * 1000)
        content_type = upstream.headers.get("content-type", "")
        if "application/json" not in content_type:
            json_log(
                "request_finished",
                req_id=req_id,
                stream=False,
                status=upstream.status_code,
                latency_ms=elapsed_ms,
                prompt_tokens=None,
                completion_tokens=None,
                total_tokens=None,
            )
            return Response(
                content=upstream.content,
                status_code=upstream.status_code,
                headers=response_headers(upstream),
            )

        payload = upstream.json()
        if not CONFIG.force_think:
            patch_chat_response(payload)
        usage = usage_from_payload(payload)
        json_log(
            "request_finished",
            req_id=req_id,
            stream=False,
            status=upstream.status_code,
            latency_ms=elapsed_ms,
            **usage,
        )
        maybe_log_context_pressure(req_id, usage, stream=False)
        return JSONResponse(payload, status_code=upstream.status_code, headers=response_headers(upstream))

    async def stream_gen():
        filters: dict[int, SseThinkFilter] = {}
        usage: dict[str, int | None] = {
            "prompt_tokens": None,
            "completion_tokens": None,
            "total_tokens": None,
        }
        status_code = 200
        try:
            async with client.stream(
                "POST",
                f"{CONFIG.upstream_url}/v1/chat/completions",
                json=body,
                headers=upstream_headers,
            ) as upstream:
                status_code = upstream.status_code
                if upstream.status_code != 200:
                    err = await upstream.aread()
                    json_log(
                        "request_finished",
                        req_id=req_id,
                        stream=True,
                        status=upstream.status_code,
                        latency_ms=int((time.perf_counter() - started) * 1000),
                        **usage,
                    )
                    yield f"data: {json.dumps({'error': err.decode('utf-8', 'replace')})}\n\n"
                    return

                async for line in upstream.aiter_lines():
                    if not line:
                        continue
                    if not line.startswith("data:"):
                        yield line + "\n"
                        continue

                    payload = line[len("data:") :].strip()
                    if payload == "[DONE]" or payload == "":
                        yield line + "\n\n"
                        continue

                    try:
                        obj = json.loads(payload)
                    except json.JSONDecodeError:
                        yield line + "\n\n"
                        continue

                    if not CONFIG.force_think:
                        patch_stream_payload(obj, filters)
                    stream_usage = usage_from_payload(obj)
                    for key, value in stream_usage.items():
                        if value is not None:
                            usage[key] = value
                    yield "data: " + json.dumps(obj, ensure_ascii=False) + "\n\n"
        except Exception as exc:  # noqa: BLE001
            json_log("request_failed", req_id=req_id, stream=True, error=str(exc))
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"
            return
        finally:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            json_log(
                "request_finished",
                req_id=req_id,
                stream=True,
                status=status_code,
                latency_ms=elapsed_ms,
                **usage,
            )
            maybe_log_context_pressure(req_id, usage, stream=True)

    return StreamingResponse(stream_gen(), media_type="text/event-stream")


@app.get("/v1/models")
async def models() -> Response:
    return await proxy_json_get("/v1/models")


@app.get("/health")
async def health() -> Response:
    client: httpx.AsyncClient = app.state.client
    try:
        resp = await client.get(f"{CONFIG.upstream_url}/health", timeout=10.0)
        if resp.status_code == 404:
            return JSONResponse(
                {
                    "status": "ok",
                    "upstream": CONFIG.upstream_url,
                    "note": "upstream has no /health endpoint; proxy is reachable",
                }
            )
        try:
            return JSONResponse(resp.json(), status_code=resp.status_code, headers=response_headers(resp))
        except Exception:  # noqa: BLE001
            return Response(resp.content, status_code=resp.status_code, headers=response_headers(resp))
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"status": "error", "error": str(exc)}, status_code=500)


@app.api_route(
    "/{full_path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
)
async def passthrough(full_path: str, request: Request) -> Response:
    upstream_url = f"{CONFIG.upstream_url}/{full_path}"
    if request.url.query:
        upstream_url = f"{upstream_url}?{request.url.query}"
    body = await request.body()
    headers = build_upstream_headers(request, body_len=len(body) if body else None)
    client: httpx.AsyncClient = app.state.client
    try:
        resp = await client.request(
            request.method,
            upstream_url,
            content=body if body else None,
            headers=headers,
        )
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"error": str(exc)}, status_code=500)
    return Response(resp.content, status_code=resp.status_code, headers=response_headers(resp))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Unified nothink proxy for ai-local-dev.")
    parser.add_argument("--port", type=int, default=8081, help="Listen port (default 8081).")
    parser.add_argument("--upstream-url", default=None, help="Upstream base URL.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    import uvicorn
    global CONFIG  # noqa: PLW0603

    args = parse_args(sys.argv[1:] if argv is None else argv)
    upstream = args.upstream_url or CONFIG.upstream_url or DEFAULT_UPSTREAM_URL
    port = args.port
    CONFIG = ProxyConfig(
        upstream_url=upstream,
        timeout_s=_env_float("PROXY_TIMEOUT", 600.0),
        force_think=resolve_force_think(),
        nothink_temp=_env_float("AI_LOCAL_NOTHINK_TEMP", 0.6),
        nothink_top_p=_env_float("AI_LOCAL_NOTHINK_TOP_P", 0.95),
        think_temp=_env_float("AI_LOCAL_THINK_TEMP", 1.0),
        think_top_p=_env_float("AI_LOCAL_THINK_TOP_P", 0.95),
        warp_ctx_soft_limit=_env_int("AI_LOCAL_WARP_CTX_SOFT_LIMIT", 28000),
    )
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning", access_log=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
