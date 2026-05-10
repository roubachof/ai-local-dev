# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with proxies that disable thinking, switch between models easily, and deploy to any machine with one command.

---

## Quick Start

```bash
# Install
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh

# Switch to 27B model
qwen-switch 27b

# Launch qwen-code
q22
```

---

## Architecture

- **`bin/qwen-switch`** — Unified script to switch between Qwen models (27B dense, 35B MoE)
- **`bin/ollama_nothink_proxy.py`** — Disables thinking for Ollama/35B via `reasoning_effort:none`
- **`bin/llama_nonthink_proxy.py`** — Strips reasoning content for llama-server/27B
- **`config/.qwen-local.conf`** — Centralized configuration (ports, paths, timeouts)
- **`lib/qwen-config.sh`** — Shared library for shell scripts
- **`docs/`** — Comprehensive documentation

## Features

| Feature | Description |
|---------|-------------|
| **Model Switching** | Toggle between Qwen3.6-27B (dense) and Qwen3.6-35B-A3B (MoE) |
| **Thinking Control** | Enable/disable model thinking at runtime via env vars |
| **Health Checks** | Automatic service status monitoring |
| **Easy Install** | One-command setup on new machines |
| **Config Centralization** | All settings in one file |

## Models

| Model | Type | Service | Proxy | Port |
|-------|------|---------|-------|------|
| Qwen3.6-27B | Dense (llama.cpp) | llama-server | llama_nonthink_proxy.py | 8080 → 8081 |
| Qwen3.6-35B-A3B | MoE (Ollama) | ollama | ollama_nothink_proxy.py | 11434 → 11435 |

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — How the proxies work
- [`docs/SETUP_FIRST_TIME.md`](docs/SETUP_FIRST_TIME.md) — Fresh machine setup
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — Common issues and fixes
- [`docs/THINK_CONTROL.md`](docs/THINK_CONTROL.md) — Force thinking on demand
- [GitHub Workflows](.github/README_GITHUB.md) — CI/CD documentation

## License

MIT
