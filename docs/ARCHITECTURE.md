# Architecture

## Overview
`ai-local-dev` exposes stable OpenAI-compatible local endpoints for **llama.cpp (27B + 35B)** and optional MLX (27B/35B-A3B, Apple Silicon) stacks with think-control through a unified proxy. llama.cpp is the default for both models because it is the only backend that exposes the hybrid Gated-DeltaNet cache checkpoint + MTP speculative-decoding flags the Qwen3.6 architecture needs for fast multi-turn agentic workloads.

## High-level flow
```mermaid
flowchart LR
    C[OpenCode / Warp]
    P27[nothink_proxy.py :8081]
    P35[nothink_proxy.py :11435]
    R[model_router.py :8090]
    Llama27[llama-server :8080]
    Llama35[llama-server :8083]
    Mlx27[mlx_lm.server :8082]
    Mlx35[mlx_lm.server :8084]
    Ollama[ollama serve :11434]

    C --> P27
    C --> P35
    C --> R
    R --> P27
    R --> P35
    P27 --> Llama27
    P27 --> Mlx27
    P35 --> Llama35
    P35 --> Mlx35
    P35 -. optional .-> Ollama
```

## Components

### `bin/ai-local`
Primary orchestrator. Key responsibilities:

- starts/stops model backends and proxies
- maintains PID files under `~/.local/state/ai-local/run/`
- writes logs under `~/.local/state/ai-local/logs/`
- updates `~/.qwen/settings.json` for Warp/qwen-code integration

### `bin/__proxy.py`
Unified proxy for 27B/35B with `llama`, `ollama`, and `mlx` modes.

- mode `llama`: llama.cpp upstream (`LLAMA_PORT` for 27B, `LLAMA_35B_PORT` for 35B)
- mode `ollama`: 35B upstream (Ollama on `OLLAMA_PORT`, legacy)
- mode `mlx`: MLX upstream (`mlx_lm.server` on `MLX_PORT` or `MLX_PORT_35B`)
- request mutation:
  - `chat_template_kwargs.enable_thinking=false` (template-level switch)
  - `enable_thinking=false` (legacy fallback)
  - `think=false` and `reasoning_effort=none` (Ollama defense-in-depth)
- `preserve_thinking` is set **server-side** by llama-server via `--chat-template-kwargs` (not injected by the proxy) so the checkpoint cache can reuse prefixes across turns when thinking is on. The proxy's nothink `enable_thinking=false` is orthogonal — it only governs whether the *current* turn reasons.
- response mutation in nothink mode:
  - strips `` from JSON and SSE chunks
- exposes `/health` and `/v1/models` pass-throughs

### `bin/model_router.py`
Optional helper endpoint that dispatches to the 27B or 35B proxy by requested `model` hint (`planner` vs `coder`).

### Backends
- **27B**: `llama-server` on `LLAMA_PORT` (default `8080`) with 64K context, Q4_K_XL + MTP, hybrid checkpoint + SWA flags; or `mlx_lm.server` on `MLX_PORT` (default `8082`) via `BACKEND_27B=mlx` / `ai-local 27b-mlx`
- **35B-A3B**: `llama-server` on `LLAMA_35B_PORT` (default `8083`) with 128K context, Q4_K_XL + MTP; or `mlx_lm.server` on `MLX_PORT_35B` (default `8084`) via `BACKEND_35B=mlx` / `ai-local 35b-mlx`; or Ollama on `OLLAMA_PORT` (default `11434`) via `BACKEND_35B=ollama` / `ai-local 35b-ollama` (legacy, no MTP/checkpoint)

### llama.cpp hybrid-cache + MTP flags
Both llama-server backends launch with the same flag block (see `bin/ai-local:llama_hybrid_flags`):

- `--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0` — flash attention + Q8 KV cache
- `--swa-full` — bounded KV for the sliding-window-attention layers (memory-efficient long context)
- `--ctx-checkpoints $LLAMA_CTX_CHECKPOINTS --checkpoint-every-n-tokens $LLAMA_CHECKPOINT_EVERY_N_TOKENS` — 40–80× warm-turn prefill speedup by reusing cached prefixes across turns (the multi-turn agentic perf fix)
- `--chat-template-kwargs {"preserve_thinking": true}` — keeps reasoning in history so checkpoint prefixes match across turns (required when thinking is on)
- `--spec-type draft-mtp --spec-draft-n-max N` — lossless MTP speculative decode (27B N=3, 35B N=2). Emitted only when `LLAMA_MTP=1` and an MTP GGUF is present; set `LLAMA_MTP=0` to disable and fall back to the non-MTP GGUF.

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

- `QWEN_27B_MODEL`, `QWEN_27B_MTP_MODEL`, `QWEN_27B_MLX_MODEL`
- `QWEN_35B_MODEL`, `QWEN_35B_MTP_MODEL`, `QWEN_35B_MLX_MODEL`
- `BACKEND_27B` (`llama` | `mlx`), `BACKEND_35B` (`llama` | `mlx` | `ollama`)
- `LLAMA_PORT`, `LLAMA_35B_PORT`, `LLAMA_PROXY_PORT`, `PROXY_35B_PORT`
- `LLAMA_CTX_SIZE` (27B, default 65536), `LLAMA_35B_CTX_SIZE` (35B, default 131072)
- `LLAMA_CACHE_TYPE_K/V` (default `q8_0`)
- `LLAMA_CTX_CHECKPOINTS`, `LLAMA_CHECKPOINT_EVERY_N_TOKENS`, `LLAMA_SWA_FULL`
- `LLAMA_MTP`, `LLAMA_MTP_N_MAX_27B`, `LLAMA_MTP_N_MAX_35B`, `LLAMA_PRESERVE_THINKING`
- `MLX_PORT`, `MLX_PORT_35B`, `MLX_TEMP`, `MLX_TOP_P`, `MLX_TOP_K`
- `AI_LOCAL_FORCE_THINK`
- `AI_LOCAL_STATE_DIR`, `AI_LOCAL_LOG_DIR`, `AI_LOCAL_RUN_DIR`

`OLLAMA_PROXY_PORT` is kept as a backward-compat alias for `PROXY_35B_PORT` (the 35B proxy listen port stays `11435` so existing client configs keep working).

## Security and locality
- all services bind to `127.0.0.1`
- no external auth expected for localhost usage
- credentials from client `Authorization` headers are stripped before upstream forwarding
