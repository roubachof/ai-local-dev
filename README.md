# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with a unified nothink proxy — **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing and MTP speculative decoding (on by default) — via one orchestrator command: `ai-local`.

---

## Quick Start

```bash
# Install
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh

# Download models (llama.cpp GGUFs)
ai-local download 27b-mtp   # 27B MTP GGUF (default model file)
ai-local download 27b       # 27B non-MTP GGUF (optional fallback)
ai-local download 35b       # 35B-A3B + MTP, 128k ctx (recommended)

# Start stacks
ai-local 27b          # llama.cpp + checkpoint + MTP (on by default)
ai-local 35b          # llama.cpp + checkpoint + MTP, 128k ctx
```

---

## Architecture

- **`bin/ai-local`** — Unified orchestrator for models, proxies, and clients
- **`bin/__proxy.py`** — Unified nothink proxy for 27B/35B
- **`bin/model_router.py`** — Optional planner/coder router endpoint
- **`config/.qwen-local.conf`** — Centralized configuration
- **`lib/qwen-config.sh`** — Shared shell helpers and config loading
- **`docs/`** — Architecture, setup, troubleshooting, think control

## Features

- **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing (`--ctx-checkpoints`) for 40–80× warm-turn prefill speedup
- 27B: 64K context, Q4_K_XL (~18GB weights); MTP speculative decoding on by default (+42% decode throughput on Apple Silicon — see `bench/README.md`)
- 35B-A3B MoE: 128K context, Q4_K_XL + MTP (~22GB weights); MTP on by default (+23% decode throughput on Apple Silicon)
- MTP speculative decoding (`--spec-type draft-mtp`) on by default; disable with `LLAMA_MTP=0` (saves a little RAM)
- `--swa-full` for bounded KV on sliding-window attention layers (memory-efficient long context)
- `--chat-template-kwargs preserve_thinking=true` to keep reasoning in history for checkpoint prefix reuse
- Stable 27B endpoint (`http://127.0.0.1:8081/v1`) and 35B endpoint (`http://127.0.0.1:11435/v1`)
- Thinking disabled by default with force-think override (`AI_LOCAL_FORCE_THINK=1`)
- Persistent logs and PID files under `~/.local/state/ai-local/`
- Commands for restart, logs, download, and doctor checks

## Quantization rationale (M3 Max, 48GB)

| Model | Quant | Weights | Context | Rationale |
|-------|-------|---------|---------|----------|
| 27B dense | Q4_K_XL | ~18GB | 64K | Fits with headroom; `--spec-draft-n-max 3` if MTP enabled |
| 35B-A3B MoE | Q4_K_XL | ~22GB | 128K | Hybrid KV is tiny (10/40 full-attention layers); Q6 would leave no room for 128K + MTP |

Higher quants (Q6_K, Q8_0) are bandwidth-bound on Apple Silicon — the marginal quality gain is not worth the speed loss. MTP speculative decoding is on by default (`LLAMA_MTP=1`): on Apple Silicon/Metal it is a real net decode speedup (measured +42% on the 27B dense and +23% on the 35B-A3B MoE on M3 Max — see `bench/README.md`); disable with `LLAMA_MTP=0` to save a little RAM.

## Models

- **Qwen3.6-27B**: `llama-server` (port `8080`) behind proxy (`8081`) with 64K context, Q4_K_XL
- **Qwen3.6-35B-A3B**: `llama-server` (port `8083`) behind proxy (`11435`) with 128K context, Q4_K_XL + MTP

## Useful commands

```bash
ai-local status
ai-local restart 27b
ai-local restart 35b
ai-local logs 27b
ai-local logs 35b
ai-local doctor
ai-local config
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/SETUP_FIRST_TIME.md`](docs/SETUP_FIRST_TIME.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/THINK_CONTROL.md`](docs/THINK_CONTROL.md)
- [`docs/NGROK_ENDPOINTS.md`](docs/NGROK_ENDPOINTS.md)

## License

MIT
