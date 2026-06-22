# Changelog

All notable changes to ai-local-dev will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [Unreleased]

### Added
- **llama.cpp is now the sole backend for both 27B and 35B**, with hybrid Gated-DeltaNet cache checkpointing (`--ctx-checkpoints`) enabled by default, delivering the 40–80× warm-turn prefill speedup the removed Ollama/MLX backends could not expose for the Qwen3.6 architecture. MTP speculative decoding (`--spec-type draft-mtp`) is **on by default** (`LLAMA_MTP=1`) — a real net decode speedup on Apple Silicon/Metal (see Changed).
- `start_llama_server_35b` driving `llama-server` on `LLAMA_35B_PORT` (default `8083`) with 128K context (`LLAMA_35B_CTX_SIZE`).
- Download targets `27b-mtp` and `35b` / `35b-llama` for the MTP GGUFs (`unsloth/Qwen3.6-*-MTP-GGUF` Q4_K_XL).
- New config keys: `QWEN_27B_MTP_MODEL`, `QWEN_35B_MODEL`, `QWEN_35B_MTP_MODEL`, `LLAMA_35B_PORT`, `LLAMA_35B_CTX_SIZE`, `LLAMA_CTX_CHECKPOINTS`, `LLAMA_CHECKPOINT_EVERY_N_TOKENS`, `LLAMA_SWA_FULL`, `LLAMA_MTP`, `LLAMA_MTP_N_MAX_27B`, `LLAMA_MTP_N_MAX_35B`, `LLAMA_PRESERVE_THINKING`.
- `--swa-full` for bounded KV on the sliding-window-attention layers (memory-efficient long context).
- `--chat-template-kwargs {"preserve_thinking": true}` so the checkpoint cache can reuse prefixes across turns when thinking is on.
- `ai-local doctor` requires `llama-server` and warns (not fails) when the 35B MTP GGUF is absent.
- `bench/bench_mtp.py` + `bench/results/` measuring MTP on/off throughput (see `bench/README.md`).
- `AI_LOCAL_CONFIG_VARS` allowlist in `lib/qwen-config.sh` + `load_qwen_config` snapshot/restore of env-inherited values, so ad-hoc env overrides like `LLAMA_MTP=0 ai-local 27b` survive sourcing the config files.

### Changed
- **MTP speculative decoding on by default** (`LLAMA_MTP=1`): MTP gives a real net decode speedup on Apple Silicon/Metal — measured 1.42× (+42%) on the 27B dense and 1.23× (+23%) on the 35B-A3B MoE on M3 Max (see `bench/README.md`). Earlier docs claiming a 0.94× slowdown were invalid: the config loader sourced `.qwen-local.conf` after the env was set and clobbered `LLAMA_MTP=1`, so MTP was never actually enabled during those runs. Disable per-run with `LLAMA_MTP=0` (saves a little RAM). The MTP GGUF remains the default model file (it loads fine without `--spec-type`).
- `load_qwen_config` now snapshots env-inherited config vars before sourcing `.qwen-local.conf` / `.qwen-local.conf.local` and restores them afterward, so ad-hoc env overrides (e.g. `LLAMA_MTP=0 ai-local 27b`) win over config defaults. `--checkpoint-every-n-tokens` is no longer passed (removed in llama.cpp build 9750; the interval is auto-determined by `llama-server`); `LLAMA_CHECKPOINT_EVERY_N_TOKENS` is kept in config for documentation only.
- `start_llama_server` generalized to `start_llama_server_at` with a shared `llama_hybrid_flags` / `llama_mtp_flags` block used by both 27B and 35B.
- `start_proxy` simplified: the `mode` parameter and `ollama`/`mlx` upstream branches are gone; the proxy now targets a single llama.cpp upstream. `start_proxy_27b` / `start_proxy_35b` take no arguments.
- `show_status`, `enforce_single_model_mode`, `stop_27b`/`stop_35b`, `download_model`, `doctor`, `usage`, and the top-level `case` dispatch reduced to the llama.cpp-only paths.
- `bin/_nothink.py`: `resolve_force_think()` and `apply_disable_fields()` no longer take a `mode` argument; the Ollama-specific `reasoning_effort`/`think` request fields and the `OLLAMA_PROXY_FORCE_THINK` / `OLLAMA_PROXY_THINK` env aliases are removed. `LLAMA_PROXY_FORCE_THINK` remains as a legacy alias.
- Quant rationale (M3 Max, 48GB): 27B = Q4_K_XL (~18GB, 64k ctx); 35B-A3B = Q4_K_XL + MTP (~22GB, 128k ctx). Q6/Q8 not recommended (bandwidth-bound; no room for 128k + MTP on 35B).
- `install.sh` no longer checks for `ollama` or `mlx-lm`; next-steps recommend `ai-local download 27b-mtp && ai-local download 35b`.
- `bin/model_router.py` coder alias set replaced the stale `qwen3.6:35b-ud-q4xl` Ollama id with `qwen3.6-35b`.
- Docs (README, ARCHITECTURE, SETUP_FIRST_TIME, TROUBLESHOOTING, THINK_CONTROL, NGROK_ENDPOINTS) rewritten for the llama.cpp-only architecture; stale `-MTP-` GGUF filenames in troubleshooting paths corrected; MTP default + speedup claims corrected to reflect the re-run Apple Silicon measurements (MTP on by default, +42% 27B / +23% 35B-A3B).

### Removed
- **8B stack dropped**: `ai-local 8b`, `start_8b_stack`, `QWEN_8B_OLLAMA_MODEL`, the `ai8b` shell alias, 8B branches in `download`/`stop`/`logs`/`restart`/`usage`/dispatch, and 8B router aliases.
- **MLX backends dropped**: `ai-local 27b-mlx` / `35b-mlx`, `start_mlx_server`, `find_mlx_lm_server`, the `mlx` download targets, `MLX_PORT` / `MLX_PORT_35B` / `MLX_TEMP` / `MLX_TOP_P` / `MLX_TOP_K`, `QWEN_27B_MLX_MODEL` / `QWEN_35B_MLX_MODEL`, `BACKEND_27B` / `BACKEND_35B`, and the `mlx-lm` requirement in `requirements.txt`.
- **Ollama backend dropped**: `ai-local 35b-ollama`, `start_ollama`, the `35b-ollama` download target, the `ollama` proxy mode, and all `OLLAMA_*` config keys (`OLLAMA_PORT`, `OLLAMA_FLASH_ATTENTION`, `OLLAMA_KV_CACHE_TYPE`, `OLLAMA_KEEP_ALIVE`, `OLLAMA_PROXY_PORT`, `OLLAMA_PROXY_FORCE_THINK`, `OLLAMA_PROXY_THINK`, `QWEN_35B_OLLAMA_MODEL`). Any such vars in `config/.qwen-local.conf.local` are now inert and can be deleted.
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
