# Changelog

All notable changes to ai-local-dev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [Unreleased]

### Added
- Qwen3 8B stack support through `ai-local 8b` (shared Ollama proxy path).
- New `QWEN_8B_OLLAMA_MODEL` config key in `config/.qwen-local.conf` and `lib/qwen-config.sh`.
- CLI coverage for `8b` in `download`, `restart`, `stop`, `logs`, and help output.
- Router aliases for `qwen3:8b` and `local-8b` in `bin/model_router.py`.

### Changed
- Docs and setup instructions updated for 8B workflows.
## [1.1.0] — 2026-05-15

### Added
- Unified proxy implementation in `bin/nothink_proxy.py` with:
  - mode support for 27B (`llama` mode) and 35B (`ollama` mode)
  - shared think-disable field injection
  - `<think>...</think>` stripping in JSON and SSE responses
  - structured JSON proxy logs with token/latency fields
- New shared helper module `bin/_nothink.py` for disable logic and streaming-safe think stripping.
- Verification harness `bin/verify_nothink.sh` to compare no-think vs force-think token and latency ratios.
- 27B backend migration support for MLX:
  - `start_mlx_server` flow in `ai-local`
  - `BACKEND_27B={mlx|llama}` config switch
  - `27b-mlx` and `27b-llama` commands
- New operational commands:
  - `ai-local restart [27b|35b]`
  - `ai-local logs <service>`
  - `ai-local download <target>`
  - `ai-local doctor`
  - `ai-local router {start|stop|status}`
- Model router helper `bin/model_router.py`.
- Test suite under `tests/` for request/response mutation logic.
- GitHub Actions workflow `.github/workflows/ci.yml` running `ruff` and `pytest`.
- `docs/MLX_MIGRATION.md` rollback/rollout guide.

### Changed
- `bin/ai-local` rewritten in bash-compatible form and now uses `lib/qwen-config.sh`.
- Config loading now supports `config/.qwen-local.conf.local` overrides.
- Runtime logs moved from `/tmp` to `~/.local/state/ai-local/logs`.
- Runtime PID files moved to `~/.local/state/ai-local/run`.
- Installer now treats `llama-server` as optional fallback and checks for `mlx_lm`.
- `requirements.txt` now includes upper version bounds and `mlx-lm`.
- Documentation updated for new architecture, commands, and troubleshooting flow.

## [1.0.0] — 2026-05-10

### Added
- **Unified CLI (`ai-local`)** — Single entry point for all local AI operations
  - `ai-local status` — Show running services
  - `ai-local 27b` — Launch Qwen 27B with llama.cpp
  - `ai-local 35b` — Launch Qwen 35B with Ollama
  - `ai-local goose` — Launch Goose with nothink proxy
  - `ai-local qwen` — Launch qwen-code
  - `ai-local [cmd] think` — Run in thinking-enabled mode
  - `ai-local config` — Display current configuration

- **Proxy servers** for thinking control
  - `ollama_nothink_proxy.py` — Disables Qwen3 thinking for Ollama (35B)
  - `llama_nonthink_proxy.py` — Disables Qwen3 thinking for llama.cpp (27B)
  - Environment variable: `OLLAMA_PROXY_FORCE_THINK=1` to enable thinking

- **Installer script (`install.sh`)**
  - Creates symlinks to `~/.local/bin/` (no file copies)
  - Sets up Python virtualenv with required dependencies
  - Validates prerequisites (Python, Ollama, llama-server, Node.js)
  - Dry-run mode (`--dry-run`) for testing
  - Configures shell aliases for quick access

- **Comprehensive documentation**
  - `ARCHITECTURE.md` — How proxies work, model comparison
  - `SETUP_FIRST_TIME.md` — Fresh machine setup guide
  - `THINK_CONTROL.md` — Feature documentation for thinking control
  - `TROUBLESHOOTING.md` — Common issues and solutions

- **Centralized configuration** at `config/.qwen-local.conf`
  - Port configuration (llama-server, proxies, Ollama)
  - Model paths
  - Performance tuning (context size, temperature, GPU layers)
  - Timeout settings

- **Python dependencies file** (`requirements.txt`)
  - fastapi, httpx, uvicorn for proxy servers

### Changed
- Migrated from scattered scripts in `ai-personal-assistant` to standalone repo
- Replaced generic `qwen-switch.sh` with unified `ai-local` CLI
- Updated environment variable naming: FORCE_SYNC → FORCE_THINK

### Removed
- Deprecated scripts from `ai-personal-assistant`:
  - `qwen-27b-server.sh`, `qwen-27b.sh`, `qwen-local.sh`
  - `restart-27b.sh`, `fix-llama-context.sh`, `restart-proxy-test.sh`
  - Old proxy copies and config from ai-personal-assistant

## Future Roadmap

- [ ] GitHub Actions workflows for automated testing
- [ ] Docker-based setup for fresh environments
- [ ] Model auto-download during installation
- [ ] Web UI for status monitoring
- [ ] Metrics collection (response times, token counts)
- [ ] Multi-model orchestration (chain models together)
