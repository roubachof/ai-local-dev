# ai-local-dev Roadmap

## Referenced plans

This roadmap orders the three implementation plans in `docs/roadmap/`. Each phase below points to one of them.

- **[NOTHINK]** *Fix the nothink proxies* — see [`01-fix-nothink-proxies.md`](01-fix-nothink-proxies.md). Small, focused bug fix: the 27B proxy is hiding thinking instead of disabling it (the user is paying thinking latency for nothing). The 35B proxy's disable path is unverified.
- **[IMPROVE]** *Efficiency & Usability Improvements* — see [`02-improvements.md`](02-improvements.md). Grab‑bag of code hygiene, missing features, and tests. Items A–V range from 10‑minute cleanups to multi‑hour refactors.
- **[MLX]** *Migrate Qwen3.6‑27B from llama.cpp to MLX* — see [`03-mlx-migration.md`](03-mlx-migration.md). The backend swap. Larger architectural change with a clean rollback path via a `BACKEND_27B={mlx|llama}` toggle.

## Recommended order

### Phase 1 — Execute **[NOTHINK]** in full

References: *Fix the nothink proxies* (`01-fix-nothink-proxies.md`), all of items A–E plus the verifier script and doc corrections.

**Why first.** It's a live bug costing real latency on every request right now. The fix is small (a few lines per proxy plus a verifier). It also produces `bin/verify_nothink.sh`, which becomes the regression check for every later phase. Critically, the corrected pattern (`chat_template_kwargs.enable_thinking`) is exactly what `mlx_lm.server` expects — so this phase makes the **[MLX]** migration cheaper, not more expensive.

**Exit criteria.** `verify_nothink.sh` shows nothink completion_tokens ≤ 1/5 of FORCE_THINK and nothink latency ≤ 1/2 of FORCE_THINK, on both ports.

**Estimated effort.** 2–4 hours.

### Phase 2 — Execute **[IMPROVE]** items A–I (quick wins only)

References: *Efficiency & Usability Improvements* (`02-improvements.md`), section "Quick wins (under ~30 min each)" only. Defer items J–V.

**Why second.** These are cheap cleanups that materially de‑risk Phase 3. Specifically:

- **[IMPROVE]** item B (fix `.qwen-local.conf.local` override) is needed before **[MLX]** adds new config vars — the override mechanism should actually work.
- **[IMPROVE]** item C (replace fixed `sleep`s with `wait_for_service`) makes startup races during the **[MLX]** rollout visible instead of papered over with a 10‑s wait.
- **[IMPROVE]** item A (wire up or delete `lib/qwen-config.sh`) prevents the **[MLX]** changes from drifting between two copies of helper functions.
- **[IMPROVE]** items D, E, F, G, H, I are pure hygiene and won't conflict with anything.

**Exit criteria.** All quick wins merged; `ai-local restart 27b` works; logs live under `~/.local/state/ai-local/logs/`; `docs/TROUBLESHOOTING.md` no longer references `qwen-switch`.

**Estimated effort.** 1–2 hours.

### Phase 3 — Execute **[MLX]** in full

References: *Migrate Qwen3.6‑27B from llama.cpp to MLX* (`03-mlx-migration.md`), all sections.

**Why third.** Phases 1 and 2 give us:

- A working nothink mechanism that's already MLX‑compatible (the proxy refactor in **[MLX]** §3 is now trivial — just swap `UPSTREAM_URL`).
- A working `wait_for_service` everywhere, so the new `start_mlx_server` from **[MLX]** §1 doesn't need its own ad‑hoc sleep.
- A working `.qwen-local.conf.local` override, so users can flip `BACKEND_27B=mlx` (defined in **[MLX]** §2) without touching the committed config.
- The `verify_nothink.sh` script from **[NOTHINK]** to prove MLX actually disables thinking (otherwise we'd have no way to tell during the cutover).

**Exit criteria.** `ai-local 27b` runs MLX upstream behind the same port 8081 OpenAI endpoint; `verify_nothink.sh` still passes; qwen‑code and Goose work unchanged. Keep llama.cpp as the rollback (`BACKEND_27B=llama`) until Phase 4 finishes.

**Estimated effort.** 3–5 hours including model download and burn‑in.

### Phase 4 — Execute **[IMPROVE]** items J–O (medium effort)

References: *Efficiency & Usability Improvements* (`02-improvements.md`), section "Medium effort (~1–2 hours each)".

**Why fourth.** **[IMPROVE]** item J (unify the two proxies) is much easier to do after **[MLX]** has settled, because the upstream surface area is then stable (MLX or Ollama — same OpenAI shape on both). Trying to unify while the 27B backend is changing would mean doing the same merge twice. **[IMPROVE]** items K–O (httpx client reuse, PID files, env‑var consolidation, model download, doctor command) all benefit from the stable proxy surface.

**Exit criteria.** A single `bin/nothink_proxy.py` replaces both files; `ai-local doctor` reports green; `ai-local download 27b` and `35b` work.

**Estimated effort.** 4–6 hours.

### Phase 5 — Execute **[IMPROVE]** items P–V (foundation)

References: *Efficiency & Usability Improvements* (`02-improvements.md`), sections "Larger but high‑value" and "Cosmetic / docs".

**Why last.** Tests, structured logs, per‑mode sampling, multi‑model router, Mermaid diagrams — these are valuable but only after the underlying architecture is settled. **[IMPROVE]** item P (tests + CI) is the most important of this group and should land first within the phase, because it locks in the behavior of all previous phases.

**Scope.** P first, then Q, then R/S/T/U/V as appetite allows.

**Exit criteria.** Pytest suite covers the proxy mutation logic; GitHub Actions runs ruff + pytest on push; proxy emits structured JSON logs.

**Estimated effort.** 4–8 hours.

## Dependency graph (informal)

- **[NOTHINK]** (Phase 1) produces `verify_nothink.sh`, which Phases 3, 4, and 5 all use as a regression check.
- **[IMPROVE]** item A (Phase 2) unblocks anything that touches helper functions: the new launcher functions in **[MLX]** §1 and the proxy unification in **[IMPROVE]** item J.
- **[IMPROVE]** item B (Phase 2) unblocks the `BACKEND_27B` toggle defined in **[MLX]** §2.
- **[MLX]** (Phase 3) must land before **[IMPROVE]** item J (Phase 4), to avoid a double merge of the proxy code.
- **[IMPROVE]** item P (Phase 5) should not predate Phase 4, because the proxy unification reshapes what we'd test.

## What NOT to do

- **Don't start with [MLX].** Tempting because it's the most exciting, but starting with **[MLX]** while the **[NOTHINK]** bug is in place means you can't tell if MLX is actually helping — latency would look bad because thinking is still happening.
- **Don't bundle Phase 1 and Phase 2.** **[NOTHINK]** is a bug fix that should ship in a clean PR you can revert; **[IMPROVE]** A–I is cleanup that touches different files.
- **Don't pull [IMPROVE] item J into Phase 1 or Phase 3.** Proxy unification looks tempting to combine with either, but it's much cleaner once the backend is settled and there's a test suite (Phase 5, **[IMPROVE]** P) to catch regressions.

## Total estimated effort

14–25 hours of focused work across five phases. Phases 1–3 (the critical path — fix the bug, clean up, migrate to MLX) are 6–11 hours. Everything else is polish that can be done at leisure.
