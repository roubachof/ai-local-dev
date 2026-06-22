#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Model router for ai-local-dev.")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--planner-url", default="http://127.0.0.1:8081")
    parser.add_argument("--coder-url", default="http://127.0.0.1:11435")
    parser.add_argument("--default-url", default=None)
    return parser.parse_args(argv)


ARGS = parse_args(sys.argv[1:])
DEFAULT_URL = ARGS.default_url or ARGS.planner_url


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(timeout=600.0)
    yield
    await app.state.client.aclose()


app = FastAPI(lifespan=lifespan)


def choose_target(model_name: str | None) -> str:
    if not model_name:
        return DEFAULT_URL
    lowered = model_name.lower()
    if lowered in {"planner", "plan", "qwen-planner", "local-27b", "qwen3.6-27b"}:
        return ARGS.planner_url
    if lowered in {
        "coder",
        "code",
        "qwen-coder",
        "local-35b",
        "qwen3.6-35b",
    }:
        return ARGS.coder_url
    return DEFAULT_URL


def upstream_headers(request: Request, body_len: int | None = None) -> dict[str, str]:
    skip = {"host", "content-length", "connection", "authorization"}
    headers = {k: v for k, v in request.headers.items() if k.lower() not in skip}
    if body_len is not None:
        headers["Content-Length"] = str(body_len)
    return headers


def down_headers(resp: httpx.Response) -> dict[str, str]:
    skip = {"transfer-encoding", "content-length", "connection"}
    return {k: v for k, v in resp.headers.items() if k.lower() not in skip}


@app.post("/v1/chat/completions")
async def route_chat(request: Request):
    try:
        body = await request.json()
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"error": f"invalid json body: {exc}"}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"error": "chat body must be a JSON object"}, status_code=400)

    target = choose_target(body.get("model"))
    is_stream = bool(body.get("stream"))
    client: httpx.AsyncClient = app.state.client
    headers = upstream_headers(request)

    if not is_stream:
        try:
            resp = await client.post(f"{target}/v1/chat/completions", json=body, headers=headers)
        except Exception as exc:  # noqa: BLE001
            return JSONResponse({"error": str(exc)}, status_code=500)
        try:
            payload = resp.json()
            return JSONResponse(payload, status_code=resp.status_code, headers=down_headers(resp))
        except Exception:  # noqa: BLE001
            return Response(resp.content, status_code=resp.status_code, headers=down_headers(resp))

    async def stream_gen():
        try:
            async with client.stream(
                "POST",
                f"{target}/v1/chat/completions",
                json=body,
                headers=headers,
            ) as resp:
                if resp.status_code != 200:
                    err = await resp.aread()
                    yield f"data: {json.dumps({'error': err.decode('utf-8', 'replace')})}\n\n"
                    return
                async for line in resp.aiter_lines():
                    if not line:
                        continue
                    if line.startswith("data:"):
                        yield line + "\n\n"
                    else:
                        yield line + "\n"
        except Exception as exc:  # noqa: BLE001
            yield f"data: {json.dumps({'error': str(exc)})}\n\n"

    return StreamingResponse(stream_gen(), media_type="text/event-stream")


@app.get("/health")
async def health():
    return {"status": "ok", "planner_url": ARGS.planner_url, "coder_url": ARGS.coder_url}


@app.api_route(
    "/{full_path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
)
async def passthrough(full_path: str, request: Request):
    upstream = f"{DEFAULT_URL}/{full_path}"
    if request.url.query:
        upstream = f"{upstream}?{request.url.query}"
    body = await request.body()
    headers = upstream_headers(request, body_len=len(body) if body else None)
    client: httpx.AsyncClient = app.state.client
    try:
        resp = await client.request(
            request.method,
            upstream,
            content=body if body else None,
            headers=headers,
        )
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"error": str(exc)}, status_code=500)
    return Response(resp.content, status_code=resp.status_code, headers=down_headers(resp))


def main() -> int:
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=ARGS.port, log_level="warning", access_log=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
