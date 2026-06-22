# Changelog

All notable changes to ai-local-dev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [Unreleased]

### Added
- **llama.cpp is now the default backend for both 27B and 35B**, with hybrid Gated-DeltaNet cache checkpointing (`--ctx-checkpoints` / `--checkpoint-every-n-tokens`) and MTP speculative decoding (`--spec-type draft-mtp`) enabled by default. These flags deliver the 40–80× warm-turn prefill speedup and +75% (27B) / +12% (35B) decode that Ollama and MLX cannot expose for the Qwen3.6 architecture.
- New `ai-local 35b-llama` stack and `start_llama_server_35b` driving `llama-server` on `LLAMA_35B_PORT` (default `8083`) with 128K context (`LLAMA_35B_CTX_SIZE`).
- New download targets `27b-mtp` and `35b` / `35b-llama` for the MTP GGUFs (`unsloth/Qwen3.6-*-MTP-GGUF` Q4_K_XL).
- New config keys: `QWEN_27B_MTP_MODEL`, `QWEN_35B_MODEL`, `QWEN_35B_MTP_MODEL`, `LLAMA_35B_PORT`, `LLAMA_35B_CTX_SIZE`, `LLAMA_CTX_CHECKPOINTS`, `LLAMA_CHECKPOINT_EVERY_N_TOKENS`, `LLAMA_SWA_FULL`, `LLAMA_MTP`, `LLAMA_MTP_N_MAX_27B`, `LLAMA_MTP_N_MAX_35B`, `LLAMA_PRESERVE_THINKING`. `PROXY_35B_PORT` (with `OLLAMA_PROXY_PORT` kept as a backward-compat alias).
- `--swa-full` for bounded KV on the sliding-window-attention layers (memory-efficient long context).
- `--chat-template-kwargs {"preserve_thinking": true}` so the checkpoint cache can reuse prefixes across turns when thinking is on.
- `ai-local doctor` now requires `llama-server`, makes `ollama` optional, and warns (not fails) when the 35B MTP GGUF is absent.
- MLX backend support for Qwen3.6 27B and 35B-A3B as Apple-Silicon-native alternatives (kept from prior release).

### Changed
- `BACKEND_35B` default flipped from `ollama` to `llama`; `MLX_PORT_35B` moved from `8083` to `8084` to free `8083` for `llama-server` 35B.
- `start_llama_server` generalized to `start_llama_server_at` with a shared `llama_hybrid_flags` / `llama_mtp_flags` block used by both 27B and 35B.
- `show_status`, `enforce_single_model_mode`, `stop_35b`, `start_proxy_35b`, `download_model`, `doctor`, `usage`, and the top-level `case` dispatch updated for the new 35B llama stack and single-model mode between 27B/35B.
- Quant rationale (M3 Max, 48GB): 27B = Q4_K_XL + MTP (~18GB, +75% decode); 35B-A3B = Q4_K_XL + MTP (~22GB, 128k ctx, +12% decode). Q6/Q8 not recommended (bandwidth-bound; no room for 128k + MTP on 35B).
- `install.sh` no longer requires `ollama`; next-steps recommend `ai-local download 27b-mtp && ai-local download 35b`.
- `bin/model_router.py` coder alias set no longer includes 8B aliases.
- Docs (README, ARCHITECTURE, SETUP_FIRST_TIME, TROUBLESHOOTING) rewritten for the consolidated llama.cpp architecture.

### Removed
- **8B stack dropped**: `ai-local 8b`, `start_8b_stack`, `QWEN_8B_OLLAMA_MODEL`, the `ai8b` shell alias, 8B branches in `download`/`stop`/`logs`/`restart`/`usage`/dispatch, and 8B router aliases.
- Ollama is no longer a prerequisite and no longer the default 35B backend. The optional `ai-local 35b-ollama` legacy path remains for users who keep an Ollama install.
- Ollama-specific config keys (`OLLAMA_FLASH_ATTENTION`, `OLLAMA_KV_CACHE_TYPE`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_PORT`, `QWEN_35B_OLLAMA_MODEL`) removed from the default config; any such vars in `config/.qwen-local.conf.local` are now inert and can be deleted.
## [1.1.0] — 2026-05-15

### Added
- Unified proxy implementation in `bin/nothink_proxy.py` with:
  - mode support for 27B (`llama` mode) and 35B (`ollama` mode)
  - shared think-disable field injection
  - `<think>...</think>` stripping in JSON and SSE responses
  - structured JSON proxy logs with token/latency fields
- New shared helper module `bin/_nothink.py` for disable logic and streaming-safe think stripping.
- Verification harness `bin/verify_nothink.sh` to compare no-think vs force-think token and latency ratios.
- New operational commands:
  - `ai-local restart [27b|35b]`
  - `ai-local logs <service>`
  - `ai-local download <target>`
  - `ai-local doctor`
  - `ai-local router {start|stop|status}`
- Model router helper `bin/model_router.py`.
- Test suite under `tests/` for request/response mutation logic.
- GitHub Actions workflow `.github/workflows/ci.yml` running `ruff` and `pytest`.

### Changed
- `bin/ai-local` rewritten in bash-compatible form and now uses `lib/qwen-config.sh`.
- Config loading now supports `config/.qwen-local.conf.local` overrides.
- Runtime logs moved from `/tmp` to `~/.local/state/ai-local/logs`.
- Runtime PID files moved to `~/.local/state/ai-local/run`.
- Installer now treats `llama-server` as optional fallback.
- `requirements.txt` now includes upper version bounds.
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
