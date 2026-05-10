#!/usr/bin/env python3
"""llama-server nothink proxy — strips thinking from Qwen3.6-27B responses.

Purpose:
    Forward requests to a local llama-server instance (default port 8080)
    and convert reasoning_content fields into regular content fields so that
    downstream clients (qwen-code, custom scripts) can parse responses without
    needing to understand Qwen3's thinking output format.

Model:
    Designed for Qwen3.6-27B served via llama.cpp llama-server.
    (For Ollama-based models, use ollama_nothink_proxy.py instead.)

How it works:
    - Listens on 127.0.0.1:8081 (configurable via --port).
    - Forwards all API calls to upstream llama-server at 127.0.0.1:8080.
    - Sets enable_thinking:false on outgoing chat completion requests.
    - Patches response bodies: moves reasoning_content -> content.
    - Handles both JSON (non-streaming) and SSE (streaming) responses.

Reasoning vs reasoning_effort:
    - llama-server uses reasoning_content in its JSON response to hold the
      model's internal chain-of-thought. This is separate from the OpenAI
      reasoning_effort parameter used by Ollama.
    - This proxy strips reasoning_content so downstream clients see only the
      final answer in the content field.

Endpoints:
    POST /v1/chat/completions  — main chat endpoint (thinking disabled)
    GET  /v1/models             — list available models
    GET  /health                — health check

Usage:
    # Default mode
    .venv/bin/python bin/llama_nonthink_proxy.py --port 8081

    # Enable thinking (passthrough) — pass through thinking tokens
    LLAMA_PROXY_FORCE_THINK=1 .venv/bin/python bin/llama_nonthink_proxy.py --port 8081

Error handling:
    - Malformed requests return 400 with error details.
    - Upstream failures return 500 with traceback in logs.
    - SSE stream errors are caught and yielded as JSON error events.
    - All activity logged via Python stdlib logging.

Requires: fastapi, httpx, uvicorn (not stdlib).
"""
import json
import logging
import os
import sys
import traceback

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse
import httpx

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("proxy")

app = FastAPI()
UPSTREAM = "http://127.0.0.1:8080"

# When true, thinking is enabled (passthrough mode).
FORCE_THINK = os.environ.get("LLAMA_PROXY_FORCE_THINK", "0") == "1"


@app.middleware("http")
async def auth_header_stripper(request: Request, call_next):
    """Strip Authorization header before forwarding to upstream.
    
    Goose/OpenAI clients send Bearer tokens, but llama-server doesn't support auth
    and rejects non-standard API keys. We strip the header before forwarding.
    """
    # Rebuild request without Authorization header
    scope = request.scope.copy()
    headers = []
    for name, value in request.scope["headers"]:
        if name.lower() != b"authorization":
            headers.append((name, value))
    scope["headers"] = headers
    request._scope = scope
    
    response = await call_next(request)
    return response


@app.middleware("http")
async def log_all_requests(request: Request, call_next):
    log.info(">> %s %s from %s", request.method, request.url.path,
             request.client.host if request.client else "?")
    response = await call_next(request)
    log.info("<< %s %s -> %d", request.method, request.url.path, response.status_code)
    return response


def patch_message_dict(msg):
    if not isinstance(msg, dict):
        return
    reasoning = msg.pop("reasoning_content", None)
    content = msg.get("content")
    if reasoning and (content is None or content == ""):
        msg["content"] = reasoning


def patch_full_response(data):
    for choice in data.get("choices", []):
        if "message" in choice:
            patch_message_dict(choice["message"])
        if "delta" in choice:
            patch_message_dict(choice["delta"])


def patch_sse_data_line(line):
    if not line.startswith("data:"):
        return line
    payload = line[len("data:"):].strip()
    if payload == "[DONE]" or not payload:
        return line
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        return line
    for choice in obj.get("choices", []):
        if "delta" in choice:
            patch_message_dict(choice["delta"])
        if "message" in choice:
            patch_message_dict(choice["message"])
    return "data: " + json.dumps(obj, ensure_ascii=False)


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    try:
        body = await request.json()
    except Exception as e:
        log.error("Failed to parse request body: %s", e)
        return JSONResponse({"error": str(e)}, status_code=400)

    # Disable thinking unless FORCE_THINK passthrough mode is enabled.
    body["enable_thinking"] = not FORCE_THINK
    is_stream = bool(body.get("stream"))
    log.info("Request: stream=%s, msgs=%d, model=%s",
             is_stream, len(body.get("messages", [])), body.get("model"))

    if not is_stream:
        try:
            async with httpx.AsyncClient(timeout=600.0) as client:
                resp = await client.post(f"{UPSTREAM}/v1/chat/completions", json=body)
            data = resp.json()
            patch_full_response(data)
            return JSONResponse(content=data, status_code=resp.status_code)
        except Exception as e:
            log.error("Non-stream error: %s\n%s", e, traceback.format_exc())
            return JSONResponse({"error": str(e)}, status_code=500)

    async def stream_gen():
        try:
            async with httpx.AsyncClient(timeout=600.0) as client:
                async with client.stream(
                    "POST", f"{UPSTREAM}/v1/chat/completions", json=body
                ) as upstream:
                    if upstream.status_code != 200:
                        err_body = await upstream.aread()
                        log.error("Upstream %d: %s", upstream.status_code, err_body[:500])
                        yield f"data: {json.dumps({'error': err_body.decode('utf-8', 'replace')})}\n\n"
                        return
                    async for line in upstream.aiter_lines():
                        if not line:
                            # Skip blank separator lines from upstream;
                            # we add proper "\n\n" after each data line below.
                            continue
                        if line.startswith("data:"):
                            patched = patch_sse_data_line(line)
                            yield patched + "\n\n"
                        else:
                            yield line + "\n"
        except Exception as e:
            log.error("Stream error: %s\n%s", e, traceback.format_exc())
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(stream_gen(), media_type="text/event-stream")


@app.get("/v1/models")
async def models():
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(f"{UPSTREAM}/v1/models")
        return JSONResponse(content=resp.json(), status_code=resp.status_code)
    except Exception as e:
        log.error("Models error: %s", e)
        return JSONResponse({"error": str(e)}, status_code=500)


@app.get("/health")
async def health():
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(f"{UPSTREAM}/health")
        return JSONResponse(content=resp.json(), status_code=resp.status_code)
    except Exception as e:
        return JSONResponse({"status": "error", "error": str(e)}, status_code=500)


if __name__ == "__main__":
    import uvicorn
    port = 8081
    for i, a in enumerate(sys.argv):
        if a == "--port" and i + 1 < len(sys.argv):
            port = int(sys.argv[i + 1])
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info", access_log=True)
