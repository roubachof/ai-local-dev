# Migrate Qwen3.6-27B from llama.cpp to MLX

## Problem

The `27b` path in `ai-local-dev` currently runs Qwen3.6-27B via `llama-server` (Metal backend of llama.cpp) on port 8080, fronted by a FastAPI `llama_nonthink_proxy.py` on 8081 that strips `reasoning_content` for OpenAI‑style clients (qwen-code, Goose). We want to swap the inference backend to MLX (Apple's native framework) for better throughput and memory behavior on the M3 Max, while keeping the public surface — port 8081 OpenAI endpoint, `ai-local 27b` command, qwen-code/Goose configs — unchanged so downstream clients don't notice.

## Current state (relevant facts)

- Launcher: `bin/ai-local` → `start_llama_server` invokes `llama-server` with flags from `config/.qwen-local.conf` (`LLAMA_CTX_SIZE=131072`, `LLAMA_TEMP=0.6`, `LLAMA_TOP_P=0.95`, `LLAMA_TOP_K=20`, `LLAMA_GPU_LAYERS=99`).
- Model file: `~/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf` (GGUF, ~17 GB).
- Proxy: `bin/llama_nonthink_proxy.py` forces `enable_thinking=false` in outgoing bodies and patches `reasoning_content → content` on responses (both JSON and SSE). Health check at `/health` proxies upstream.
- Clients written to expect OpenAI base URL `http://127.0.0.1:8081/v1` (qwen-code in `~/.qwen/settings.json`, Goose in `config/goose/config.yaml`).
- Prereq check in `install.sh:78` looks for `llama-server` binary.
- 35B/Ollama path is untouched by this migration.

## Backend choice

Use **`mlx_lm.server`** as the inference layer. It exposes an OpenAI‑compatible `/v1/chat/completions` and `/v1/models`, supports streaming SSE, and honors `chat_template_kwargs` in the request body — which is how Qwen3.6's chat template exposes `enable_thinking`. Model: `mlx-community/Qwen3.6-27B-4bit` (≈18 GB, vetted MLX build). An 8‑bit variant stays optional for a future "quality mode".

## Proxy strategy

The proxy stays, but its job changes:

- **Drop**: `reasoning_content → content` patching (MLX/Qwen3.6 emits a single `content` stream; thinking is controlled at the template level, not via a sidecar field).
- **Keep**: the `enable_thinking` injection (now as `chat_template_kwargs: {enable_thinking: false}` instead of a top‑level `enable_thinking`), Authorization header stripping for Goose, `/v1/models`, `/health`, and SSE pass‑through.
- **Add**: when `<think>…</think>` tags do leak into `content` (they shouldn't with thinking off, but defensive), strip them in both JSON and SSE paths.

This preserves the port 8081 contract so qwen-code and Goose configs need zero changes.

## Proposed changes

### 1. New launcher function and command

- Add `start_mlx_server` to `bin/ai-local` mirroring `start_llama_server`. It runs `mlx_lm.server --model $QWEN_27B_MLX_MODEL --port $MLX_PORT --host 127.0.0.1 --temp $MLX_TEMP --top-p $MLX_TOP_P` (`mlx_lm.server` doesn't support `--top-k` or context size as CLI flags today — sampling is per‑request, context is dynamic).
- Add `27b-mlx` command alongside the existing `27b` so both can coexist during cutover. After validation, repoint `27b` to `start_mlx_server` and keep `27b-llama` as a fallback.

### 2. Config additions in `config/.qwen-local.conf` and `lib/qwen-config.sh`

Add alongside the existing `LLAMA_*` vars:

- `MLX_PORT=8082` (the upstream that the existing 8081 proxy will now forward to; keeps the public port stable).
- `QWEN_27B_MLX_MODEL="mlx-community/Qwen3.6-27B-4bit"` (HF repo id; `mlx_lm.server` downloads on first run into `~/.cache/huggingface`).
- `MLX_TEMP=0.6`, `MLX_TOP_P=0.95` (reuse Qwen recommended sampling; document that `top_k=20` is forwarded per‑request via the proxy or omitted).
- `BACKEND_27B={mlx|llama}` switch read by `ai-local 27b` to pick the upstream.

### 3. Proxy refactor — `bin/llama_nonthink_proxy.py`

- Make `UPSTREAM` read from env (`UPSTREAM_URL`, default `http://127.0.0.1:8082` for MLX, `http://127.0.0.1:8080` for llama.cpp). Set in `ai-local` based on `BACKEND_27B`.
- Replace the `body["enable_thinking"] = not FORCE_THINK` line with:
    - `body.setdefault("chat_template_kwargs", {})["enable_thinking"] = not FORCE_THINK`
    - Keep the legacy top‑level key too for llama.cpp fallback.
- Drop `patch_message_dict`'s `reasoning_content` move (MLX doesn't emit it). Keep a defensive `<think>…</think>` regex strip on `content` for both JSON and SSE deltas.
- `/v1/models` and `/health` keep proxying upstream; verify `mlx_lm.server` exposes both (it exposes `/v1/models`; add a tiny local fallback in the proxy that returns `{"status":"ok"}` if upstream `/health` 404s, since `mlx_lm.server` lacks `/health`).

### 4. Installer updates — `install.sh`

- Drop the hard prereq check for `llama-server` (keep it as a soft check with a note).
- Add a soft prereq check for `mlx_lm` (`python -c "import mlx_lm"`).
- Append `mlx-lm>=0.20` to `requirements.txt` (versions current as of May 2026 ship Qwen3.6 support).

### 5. Client configs (no changes needed)

- `~/.qwen/settings.json` continues to point at `http://127.0.0.1:8081/v1`.
- `config/goose/config.yaml` `OPENAI_API_BASE` stays `http://localhost:8081/v1`.
- Only the `update_qwen_settings`/`update_goose_settings` calls in the `27b` branch of `bin/ai-local:455-456` need the model name updated to a stable identifier (`qwen3.6-27b-mlx` or kept as `Qwen3.6-27B-UD-Q4_K_XL.gguf` for backward compat — pick one).

### 6. Docs

- Update `docs/ARCHITECTURE.md` table at lines 22–25 to note MLX as the 27B backend; redraw the data‑flow block.
- Add `docs/MLX_MIGRATION.md` with rollback instructions (set `BACKEND_27B=llama` in `config/.qwen-local.conf`).
- Add a CHANGELOG entry under a new `[1.1.0]` section.

## Open decisions to confirm before execution

1. **Backend switch model**: replace the `27b` command in place, or keep `27b-llama` and `27b-mlx` side‑by‑side indefinitely? (Plan assumes side‑by‑side first, then flip `27b` to MLX after burn‑in.)
2. **Quantization**: start with `mlx-community/Qwen3.6-27B-4bit` only, or also pre‑download `Qwen3.6-27B-8bit` for a future quality mode?
3. **Model identifier in client settings**: keep `Qwen3.6-27B-UD-Q4_K_XL.gguf` for zero‑churn, or rename to something like `qwen3.6-27b` to reflect the new backend?
4. **Remove llama.cpp prereq entirely** in `install.sh`, or keep it as a soft optional check for the fallback path?

## Rollback plan

All changes are additive until the final `27b` repoint. Setting `BACKEND_27B=llama` in `config/.qwen-local.conf` restores the original `llama-server` path with no other changes. The legacy GGUF file remains on disk.
