# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with a unified nothink proxy — **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing + MTP speculative decoding, and optional MLX backends on Apple Silicon — via one orchestrator command: `ai-local`.

---

## Quick Start

```bash
# Install
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh

# Download models (llama.cpp GGUFs)
ai-local download 27b-mtp   # 27B + MTP (recommended; +75% decode)
ai-local download 27b       # 27B non-MTP fallback (optional)
ai-local download 35b       # 35B-A3B + MTP, 128k ctx (recommended)
# Optional MLX backends (Apple Silicon; requires `pip install 'mlx-lm>=0.31'`)
ai-local download 27b-mlx
ai-local download 35b-mlx

# Start stacks (llama.cpp is the default for both)
ai-local 27b          # llama.cpp + MTP + checkpoint (default 27B backend)
ai-local 35b          # llama.cpp + MTP + checkpoint, 128k ctx (default 35B backend)
ai-local 35b-mlx      # MLX alternative (native 4-bit; no MTP/checkpoint)
ai-local 27b-mlx      # MLX alternative for 27B
ai-local 35b-ollama   # legacy Ollama backend (optional; no MTP/checkpoint)
```

---

## Architecture

- **`bin/ai-local`** — Unified orchestrator for models, proxies, and clients
- **`bin/__proxy.py`** — Unified proxy for 27B/35B (llama/MLX/ollama modes)
- **`bin/model_router.py`** — Optional planner/coder router endpoint
- **`config/.qwen-local.conf`** — Centralized configuration
- **`lib/qwen-config.sh`** — Shared shell helpers and config loading
- **`docs/`** — Architecture, setup, troubleshooting, think control

## Features

- **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing (`--ctx-checkpoints`) and MTP speculative decoding (`--spec-type draft-mtp`)
- 27B: 64K context, Q4_K_XL + MTP (~18GB weights, +75% decode on dense model)
- 35B-A3B MoE: 128K context, Q4_K_XL + MTP (~22GB weights, +12% decode on Apple Silicon)
- `--swa-full` for bounded KV on sliding-window attention layers (memory-efficient long context)
- `--chat-template-kwargs preserve_thinking=true` to keep reasoning in history for checkpoint prefix reuse
- Optional MLX backends for 27B and 35B-A3B on Apple Silicon (native 4-bit, no MTP/checkpoint)
- Stable 27B endpoint (`http://127.0.0.1:8081/v1`) and 35B endpoint (`http://127.0.0.1:11435/v1`)
- Thinking disabled by default with force-think override (`AI_LOCAL_FORCE_THINK=1`)
- Persistent logs and PID files under `~/.local/state/ai-local/`
- Commands for restart, logs, download, and doctor checks
- Legacy Ollama backend preserved for 35B (`ai-local 35b-ollama`)

## Quantization rationale (M3 Max, 48GB)

| Model | Quant | Weights | MTP | Context | Rationale |
|-------|-------|---------|-----|---------|----------|
| 27B dense | Q4_K_XL | ~18GB | +75% decode | 64K | Best acceptance with `--spec-draft-n-max 3`; fits with headroom |
| 35B-A3B MoE | Q4_K_XL | ~22GB | +12% decode | 128K | Hybrid KV is tiny (10/40 full-attention layers); Q6 would leave no room for 128K + MTP |

Higher quants (Q6_K, Q8_0) are bandwidth-bound on Apple Silicon — the marginal quality gain is not worth the speed loss. Set `LLAMA_MTP=0` in config to disable MTP and fall back to non-MTP GGUFs.

## Models

- **Qwen3.6-27B**: `llama-server` (port `8080`) behind proxy (`8081`) with 64K context, Q4_K_XL + MTP; MLX alternative `mlx-community/Qwen3.6-27B-4bit` via `ai-local 27b-mlx`
- **Qwen3.6-35B-A3B**: `llama-server` (port `8083`) behind proxy (`11435`) with 128K context, Q4_K_XL + MTP; MLX alternative `mlx-community/Qwen3.6-35B-A3B-4bit-DWQ` via `ai-local 35b-mlx`; legacy Ollama via `ai-local 35b-ollama`

## Useful commands

```bash
ai-local status
ai-local restart 27b
ai-local restart 35b
ai-local logs 27b
ai-local logs 35b
ai-local doctor
ai-local config
# MLX variants: ai-local 27b-mlx, ai-local 35b-mlx
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/SETUP_FIRST_TIME.md`](docs/SETUP_FIRST_TIME.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/THINK_CONTROL.md`](docs/THINK_CONTROL.md)
- [`docs/NGROK_ENDPOINTS.md`](docs/NGROK_ENDPOINTS.md)

## License

MIT
