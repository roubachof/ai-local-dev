# ai-local-dev: Efficiency & Usability Improvements

## Goal

A pass over the current `ai-local-dev` codebase looking for low‑risk wins that make the project easier to live with day‑to‑day and a bit cheaper at runtime. Items are grouped by theme and ordered roughly by effort vs payoff. None of these are blockers — the project works — but most can be done in an hour each.

## Observations driving the suggestions

- `lib/qwen-config.sh` defines `show_config`, `is_service_running`, `wait_for_service`, `update_qwen_settings` — but `bin/ai-local` reimplements all of them locally and never sources the lib. The lib is dead code today.
- `update_qwen_settings` exists in two places with slightly different signatures (`bin/ai-local:264-288` and `lib/qwen-config.sh:94-119`).
- `bin/llama_nonthink_proxy.py` uses FastAPI; `bin/ollama_nothink_proxy.py` uses stdlib `http.server`. The two have different logging, different env var conventions (`OLLAMA_PROXY_THINK` vs `LLAMA_PROXY_FORCE_THINK`), and different error‑handling shapes.
- `start_llama_server` and `start_proxy_*` use `sleep $SERVICE_STARTUP_WAIT` / `sleep 3` after `nohup ... &` instead of the `wait_for_service` helper already defined in `bin/ai-local:78-90`.
- `httpx.AsyncClient(timeout=600.0)` is created per request inside `llama_nonthink_proxy.py:148,159,189,199`; no connection reuse.
- `start_ollama()` is defined in `bin/ai-local:115-123` but never called from any `case` branch in `main`. Dead code.
- `stop_all` doesn't stop `ollama serve` even though the script can start it.
- Logs go to `/tmp/llama-server.log`, `/tmp/proxy-27b.log`, `/tmp/proxy-35b.log`, `/tmp/ollama.log`. macOS clears `/tmp` on reboot; harder to diagnose intermittent issues after a restart.
- Process lifecycle relies on `pkill -f "<pattern>"`. No PID files; reliable enough but brittle across multiple shells / reboots.
- `docs/TROUBLESHOOTING.md` still references `qwen-switch` (the predecessor CLI) in 8 places — the project moved to `ai-local` per the CHANGELOG.
- `config/.qwen-local.conf` comment says "Copy to `.qwen-local.conf.local` to override" but no code path sources `.local`. The override is a documented feature that doesn't work.
- `.github/workflows/` directory exists but is empty; the CHANGELOG lists "GitHub Actions workflows for automated testing" under Future Roadmap.
- `requirements.txt` has no upper pins; FastAPI/httpx have broken minor releases historically.
- No tests at all. The proxy request/response patching (`patch_message_dict`, `patch_sse_data_line`, `_patch_chat_body`) is the kind of code where a few unit tests would catch regressions cheaply.
- `bin/ai-local` is zsh‑only (`#!/usr/bin/env zsh`, `${(%):-%x}` for self‑path). Not a blocker on macOS but limits portability.

## Proposed improvements

### Quick wins (under ~30 min each)

**A. Wire up `lib/qwen-config.sh` or delete it.** Either source it from `bin/ai-local` and remove the duplicated helpers, or drop the lib + the `lib/` directory entirely. Right now it's a footgun — someone will fix a bug in one copy and not the other.

**B. Fix the documented `.qwen-local.conf.local` override.** In `bin/ai-local` after sourcing `$CONF_FILE`, also `source "$CONF_FILE.local"` if it exists. Two lines, makes the documented behavior real.

**C. Replace fixed `sleep`s with `wait_for_service`.** In `start_llama_server`, `start_ollama`, `start_proxy_27b`, `start_proxy_35b`. The helper already exists. Speeds up startup (no 10‑second wait when the model is already warm) and fails faster when things break.

**D. Move logs to `~/.local/state/ai-local/logs/`.** Survive reboots, follow XDG basedirs. Add a `ai-local logs <service>` subcommand that tails the right file so users don't have to remember paths.

**E. Add `ai-local restart [27b|35b]`.** Equivalent to `stop` + start, but only touches the targeted backend. Today users `stop` (kills everything) then re‑issue the start command.

**F. Make `ai-local stop` also stop `ollama serve` when we started it.** Either record a PID file at startup (`/tmp/ai-local-ollama.pid`) or skip stopping Ollama if it was already running before our run (the `is_service_running` check at the top of `start_ollama` returns early in that case).

**G. Fix `docs/TROUBLESHOOTING.md`.** Find‑replace `qwen-switch` → `ai-local` (8 occurrences). Also update `q22` in line 104 — it's a dangling alias not defined anywhere in the repo.

**H. Pin `requirements.txt` upper bounds.** `fastapi>=0.100,<1`, `httpx>=0.24,<1`, `uvicorn>=0.23,<1`. Avoids surprise breakage from a major version bump.

**I. Delete dead code.** `start_ollama` in `bin/ai-local:115-123` is unreferenced.

### Medium effort (~1–2 hours each)

**J. Unify the two proxies.** They share 90% of behavior (forward to upstream, mutate one JSON field on POST `/v1/chat/completions`, stream SSE, log). Collapse into one file (`bin/nothink_proxy.py`) parameterized by `--mode {llama|ollama}` or by the upstream URL plus a small per‑backend mutation function. Two paths to thinking control (`reasoning_effort` for Ollama, `enable_thinking` / `chat_template_kwargs` for llama.cpp/MLX) become a registry. Halves the maintenance surface and lets the FastAPI vs stdlib split die.

**K. Reuse `httpx.AsyncClient`.** Construct once at FastAPI lifespan startup, share across requests. Removes the TLS/TCP handshake per call and the per‑request `with` block. Material speedup on streaming chat completions.

**L. PID files + cleaner lifecycle.** On start, write `~/.local/state/ai-local/run/<service>.pid`; on stop, read and `kill`. Falls back to `pkill -f` only if the PID file is stale. Makes `status` deterministic too.

**M. Single source of truth for thinking env vars.** Standardize on `AI_LOCAL_FORCE_THINK={0|1}` and keep the two existing names as deprecated aliases. The current `OLLAMA_PROXY_THINK` / `OLLAMA_PROXY_FORCE_THINK` / `LLAMA_PROXY_FORCE_THINK` trio is a small but real cognitive tax (and one source of the doc drift in `THINK_CONTROL.md`).

**N. Auto‑download model.** Add `ai-local download 27b` / `35b` that runs `huggingface-cli download …` for the GGUF (or `ollama pull` for the MoE). The CHANGELOG lists this under Future Roadmap and the command lives in `TROUBLESHOOTING.md` already.

**O. Add `ai-local doctor`.** One command that runs the install.sh prereq checks, validates the model file, hits each `/health`, and reports anything wrong. Useful both for users and for CI.

### Larger but high‑value

**P. Minimal test suite.** A `tests/` directory with pytest cases for the proxy mutation logic: `patch_full_response`, `patch_sse_data_line`, `_patch_chat_body`. Mock upstream with `respx` or stdlib `http.server`. ~150 lines of code covers the regression risk. Combine with a basic GitHub Actions workflow (the empty `.github/workflows/` is already waiting) running `ruff` + `pytest` on push.

**Q. Observability: structured logs + token counters.** Switch proxy logs to one‑line JSON (`{"ts":…,"req_id":…,"upstream":…,"in_tokens":…,"out_tokens":…,"latency_ms":…}`). Cheap to parse with `jq`, lets you build a simple `ai-local stats` later. The CHANGELOG lists "Metrics collection" under Future Roadmap.

**R. Per‑mode sampling parameters.** Qwen3.6 recommends different sampling for thinking vs non‑thinking modes (`temp 0.6 / top_p 0.95` for non‑thinking, `temp 1.0 / top_p 0.95` for thinking general). The proxy already knows the thinking mode — it can inject the correct sampling params when the client doesn't specify them, instead of fixing them at server startup.

**S. Multi‑model orchestration helper.** The CHANGELOG mentions this under Future Roadmap. Concretely: a small router that exposes one endpoint and dispatches to 27B for planning prompts (`/v1/chat/completions` with a `model: planner` hint) and 35B‑A3B for code prompts (`model: coder`). Lets clients keep a single base URL and switch behavior by model name. Probably most useful after item J (unified proxy) lands.

### Cosmetic / docs

**T. Make `bin/ai-local` bash‑compatible.** Replace the zsh‑only `${(%):-%x}` with `${BASH_SOURCE[0]:-$0}` and the shebang with `#!/usr/bin/env bash`. Removes one source of surprise on a fresh machine without zsh.

**U. Bring `docs/SETUP_FIRST_TIME.md` in line with the post‑MLX world.** If the MLX migration plan lands, the llama.cpp build steps become optional and `mlx-lm` becomes the main install step.

**V. Add a single "how it all fits together" diagram.** `ARCHITECTURE.md` has an ASCII box diagram but a Mermaid flowchart showing both backends + proxies + clients in one view would help newcomers understand the moving parts in 10 seconds.

## Suggested order

1. Quick wins A–I as a single PR (mostly cleanup, low risk).
2. Medium items J + K together (proxy unification + httpx client reuse — they touch the same file).
3. L + M + N + O across one or two PRs.
4. P (tests + CI) before any further refactors.
5. Q–S as larger discrete features once the foundation is tidy.
