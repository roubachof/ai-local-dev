# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with a unified nothink proxy, an MLX-first 27B path, and Ollama stacks for fast 8B or stronger 35B via one orchestrator command: `ai-local`.

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

# Launch client
ai-local goose
```

---

## Architecture

- **`bin/ai-local`** — Unified orchestrator for models, proxies, and clients
- **`bin/nothink_proxy.py`** — Unified proxy for 27B + shared Ollama path (8B/35B)
- **`bin/model_router.py`** — Optional planner/coder router endpoint
- **`config/.qwen-local.conf`** — Centralized configuration
- **`lib/qwen-config.sh`** — Shared shell helpers and config loading
- **`docs/`** — Architecture, setup, troubleshooting, think control, MLX migration

## Features

- 27B backend switch: `BACKEND_27B={mlx|llama}`
- Stable public 27B endpoint (`http://127.0.0.1:8081/v1`) regardless of backend
- Thinking disabled by default with force-think override (`AI_LOCAL_FORCE_THINK=1`)
- Persistent logs and PID files under `~/.local/state/ai-local/`
- Commands for restart, logs, download, and doctor checks

## Models

- **Qwen3.6-27B**: `mlx_lm.server` (default, port `8082`) or `llama-server` fallback (`8080`) behind proxy `8081`
- **Qwen3-8B**: Ollama (`11434`) behind shared Ollama proxy (`11435`)
- **Qwen3.6-35B-A3B**: Ollama (`11434`) behind proxy `11435`

## Useful commands

```bash
ai-local status
ai-local restart 27b
ai-local logs 27b
ai-local doctor
bin/verify_nothink.sh
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/SETUP_FIRST_TIME.md`](docs/SETUP_FIRST_TIME.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/THINK_CONTROL.md`](docs/THINK_CONTROL.md)
- [`docs/MLX_MIGRATION.md`](docs/MLX_MIGRATION.md)

## License

MIT