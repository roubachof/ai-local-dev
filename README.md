# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with a unified nothink proxy, llama.cpp for 27B, and Ollama stacks for 8B/35B via one orchestrator command: `ai-local`.

---

## Quick Start

```bash
# Install
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh

# Download models
ai-local download 27b
ai-local download 8b
ai-local download 35b

# Start stacks
ai-local 27b
ai-local 8b
ai-local 35b
```

---

## Architecture

- **`bin/ai-local`** — Unified orchestrator for models, proxies, and clients
- **`bin/nothink_proxy.py`** — Unified proxy for 27B + shared Ollama path (8B/35B)
- **`bin/model_router.py`** — Optional planner/coder router endpoint
- **`config/.qwen-local.conf`** — Centralized configuration
- **`lib/qwen-config.sh`** — Shared shell helpers and config loading
- **`docs/`** — Architecture, setup, troubleshooting, think control

## Features

- 27B llama.cpp backend with 64K context + Q8_0 KV cache quantization
- Stable 27B endpoint (`http://127.0.0.1:8081/v1`)
- Thinking disabled by default with force-think override (`AI_LOCAL_FORCE_THINK=1`)
- Persistent logs and PID files under `~/.local/state/ai-local/`
- Commands for restart, logs, download, and doctor checks

## Models

- **Qwen3.6-27B**: `llama-server` (port `8080`) behind proxy (`8081`) with 64K context
- **Qwen3-8B**: Ollama direct (`11434`)
- **Qwen3.6-35B-A3B**: Ollama (`11434`) behind proxy (`11435`)

## Useful commands

```bash
ai-local status
ai-local restart 27b
ai-local logs 27b
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
