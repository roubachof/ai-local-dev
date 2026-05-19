# Fix the nothink proxies

## Problem

The two proxies in `bin/` are not disabling Qwen3.6 thinking the way the code suggests. Specifically:

- `bin/llama_nonthink_proxy.py:141` sets `body["enable_thinking"] = not FORCE_THINK` at the **top level** of the chat‑completion body. `llama-server` does not read a top‑level `enable_thinking` field; the Qwen3 chat template only honors it when passed under `chat_template_kwargs`. The flag is silently dropped, the template renders with its default (`enable_thinking=true`), and the model thinks anyway. The output looks clean because recent `llama-server` builds default `--reasoning-format auto` for Qwen3 models, so `<think>…</think>` blocks get rerouted into `reasoning_content`, which the proxy then pops off in `patch_message_dict`. Net effect: thinking is **hidden**, not **disabled** — the user pays full thinking latency and token cost for no visible benefit.
- `bin/ollama_nothink_proxy.py:75` injects `reasoning_effort: "none"`. That parameter was originally defined for OpenAI's reasoning model family and its mapping to Qwen3's `enable_thinking` template variable depends on the Ollama version. The canonical Qwen3‑in‑Ollama ways to disable thinking are the native `think: false` field or `chat_template_kwargs.enable_thinking: false` in the body — not `reasoning_effort`. Status is currently unknown for this Ollama build (initial verification via curl returned an error body rather than a chat completion, so neither side was confirmed).

## Goal

Make both proxies actually prevent thinking at the model level (not just hide the output), with verifiable latency and token‑count differences between nothink and FORCE_THINK modes. Keep the public interface (ports 8081 / 11435) unchanged.

## Proposed changes

### 1. `bin/llama_nonthink_proxy.py`

**A. Fix the disable flag.** Replace the top‑level assignment with the chat‑template kwargs path, and keep the legacy field for older `llama-server` builds:

- `body.setdefault("chat_template_kwargs", {})["enable_thinking"] = not FORCE_THINK`
- Leave `body["enable_thinking"] = not FORCE_THINK` as a belt‑and‑suspenders fallback (harmless if ignored).

**B. Add a defensive `<think>…</think>` regex strip on response `content`.** Today `patch_message_dict` only handles `reasoning_content`. If a future `llama-server` change stops auto‑extracting reasoning, the model's thinking tokens would leak straight into the visible stream. A compiled regex (`re.compile(r"<think>.*?</think>\s*", re.DOTALL)`) applied to `content` in both JSON and SSE paths costs nothing and removes that failure mode. For SSE, buffer until a `</think>` boundary is seen before emitting, then resume token‑by‑token (small additional complexity; can be a follow‑up if the simple regex approach proves sufficient for non‑stream first).

**C. Verify and pin `llama-server` reasoning extraction.** Add `--reasoning-format deepseek` (or whatever the current Qwen3‑compatible value is on this `llama-server --help`) to the launch command in `bin/ai-local:102-110`. This guarantees `reasoning_content` is populated regardless of build defaults. The existing `patch_message_dict` logic then becomes load‑bearing instead of accidental.

### 2. `bin/ollama_nothink_proxy.py`

**D. Defense in depth on the disable side.** In `_patch_chat_body`, set three fields (each is a no‑op when not understood):

- `data.setdefault("reasoning_effort", "none")` (keep existing)
- `data.setdefault("chat_template_kwargs", {}).setdefault("enable_thinking", False)`
- `data.setdefault("think", False)` (Ollama‑native)

Respect a pre‑existing caller value for each (don't override). This way whichever channel the running Ollama build honors gets through.

**E. Same defensive regex strip on response content** as for the llama proxy. Ollama's `/v1/chat/completions` returns content in the standard OpenAI shape, so the same `<think>…</think>` filter applies. For SSE, mirror the buffering approach from item B.

### 3. Shared: a tiny `nothink.py` helper

The regex strip and the disable‑field setters are identical between both proxies. Extract to `bin/_nothink.py`:

- `apply_disable_fields(body, force_think: bool) -> None`
- `strip_think_blocks(text: str) -> str`
- `SseThinkFilter` class for stateful streaming strip

Import from both proxy files. ~40 lines, removes the drift that already exists between the two implementations.

### 4. Verification harness

Add `bin/verify_nothink.sh` that runs three measurements against each proxy and prints a small table:

1. Trivial prompt (`"What is 2+2?"`) — measure latency and `usage.completion_tokens`.
2. Same prompt with `LLAMA_PROXY_FORCE_THINK=1` / `OLLAMA_PROXY_FORCE_THINK=1` — measure latency and tokens again.
3. Assert that nothink completion_tokens is at least 5× smaller than FORCE_THINK, and nothink latency is at least 2× faster. If not, exit non‑zero.

This is the regression test: if a future change re‑breaks the disable path, the ratio collapses and the script flags it.

### 5. Documentation updates

- `docs/THINK_CONTROL.md`: replace the "How It Works" descriptions with the corrected mechanism (template kwargs, not top‑level field; defense‑in‑depth for Ollama).
- `docs/TROUBLESHOOTING.md`: add a "How to tell if thinking is really off" section citing `bin/verify_nothink.sh`.
- `docs/ARCHITECTURE.md` proxy section needs the same correction.

## Verification before declaring done

For the 27B proxy, after the fix:

- `curl ... "What is 2+2?"` returns in <1 s and yields completion_tokens ≤ 10.
- `LLAMA_PROXY_FORCE_THINK=1` mode on the same prompt yields completion_tokens ≥ 100 and visibly contains reasoning in the response.

For the 35B proxy, same two checks against port 11435 with the same prompts.

## Ordering

1. Land items A, B, D, E together — they're additive and the regex strip immediately makes both proxies safe regardless of which disable channel works.
2. Land item C (launch flag) right after, once the correct value for `--reasoning-format` is confirmed on the local `llama-server --help` (`auto` vs `deepseek` vs `qwen3`).
3. Land item 3 (shared helper) once 1 and 2 are validated.
4. Land items 4 and 5 (verifier + docs) last so the docs reflect the final shape.

## Open question

Whether to keep `enable_thinking` as a top‑level field in the llama proxy body at all. It's harmless today but it does increase the chance of an unfamiliar reader copying it as the supposed correct pattern. Leaning toward removing it once the `chat_template_kwargs` path is proven on the local `llama-server` build.

## Relationship to the MLX migration plan

When the MLX migration lands, `mlx_lm.server` uses the same `chat_template_kwargs.enable_thinking` convention as the corrected llama proxy. The fix here is therefore directly forward‑compatible: no extra MLX‑specific work is needed beyond pointing `UPSTREAM_URL` at the MLX port.
