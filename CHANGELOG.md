# Changelog

All notable changes to ai-local-dev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
