# Architecture

## Overview
`ai-local-dev` exposes stable OpenAI-compatible local endpoints for llama.cpp (27B) and Ollama (8B/35B) stacks with think-control through a unified proxy.

## High-level flow
```mermaid
flowchart LR
    C[OpenCode / Warp]
    P27[nothink_proxy.py :8081]
    P35[nothink_proxy.py :11435]
    R[model_router.py :8090]
    Llama[llama-server :8080]
    Ollama[ollama serve :11434]

    C --> P27
    C --> P35
    C --> R
    R --> P27
    R --> P35
    P27 --> Llama
    P35 --> Ollama
```

## Components

### `bin/ai-local`
Primary orchestrator. Key responsibilities:

- starts/stops model backends and proxies
- maintains PID files under `~/.local/state/ai-local/run/`
- writes logs under `~/.local/state/ai-local/logs/`
- updates `~/.qwen/settings.json` for Warp/qwen-code integration

### `bin/nothink_proxy.py`
Unified proxy for 27B llama.cpp and Ollama stacks (8B/35B).

- mode `llama`: 27B upstream (llama.cpp)
- mode `ollama`: 8B/35B upstream (Ollama)
- request mutation:
  - `chat_template_kwargs.enable_thinking=false` (template-level switch)
  - `enable_thinking=false` (legacy fallback)
  - `think=false` and `reasoning_effort=none` (Ollama defense-in-depth)
- response mutation in nothink mode:
  - strips `` from JSON and SSE chunks
- exposes `/health` and `/v1/models` pass-throughs

### `bin/model_router.py`
Optional helper endpoint that dispatches to 27B or Ollama proxy by requested `model` hint (`planner` vs `coder`).

### Backends
- 27B: `llama-server` on `LLAMA_PORT` (default `8080`) with 64K context + Q8_0 KV cache quantization
- 8B: Ollama on `OLLAMA_PORT` (default `11434`)
- 35B: Ollama on `OLLAMA_PORT` (default `11434`) via `OLLAMA_PROXY_PORT` (default `11435`)

## Think-control behavior
- default: thinking disabled in proxy
- force thinking: `AI_LOCAL_FORCE_THINK=1` before starting stack
- backward-compatible aliases still supported:
  - `LLAMA_PROXY_FORCE_THINK`
  - `OLLAMA_PROXY_FORCE_THINK`
  - `OLLAMA_PROXY_THINK`

## Configuration model
Defaults live in `config/.qwen-local.conf`, and local overrides are loaded from `config/.qwen-local.conf.local` when present.

Important keys:

- `QWEN_27B_MODEL`
- `QWEN_35B_OLLAMA_MODEL`
- `QWEN_8B_OLLAMA_MODEL`
- `AI_LOCAL_FORCE_THINK`
- `LLAMA_CTX_SIZE`, `LLAMA_CACHE_TYPE_K/V`
- `AI_LOCAL_STATE_DIR`, `AI_LOCAL_LOG_DIR`, `AI_LOCAL_RUN_DIR`

## Security and locality
- all services bind to `127.0.0.1`
- no external auth expected for localhost usage
- credentials from client `Authorization` headers are stripped before upstream forwarding
