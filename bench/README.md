# Benchmarks

MTP (Multi-Token Prediction) speculative decoding benchmarks for the Qwen3.6
`llama.cpp` stack on Apple Silicon.

## What it measures

`bench_mtp.py` sends a fixed set of 8 prompts (code, explain, summarize, QA,
creative, stepwise math, code review) through the no-think proxy
(`http://127.0.0.1:8081/v1` by default) and records per-prompt
`completion_tokens` and wall time, then computes an aggregate `tok/s` as
`sum(completion_tokens) / sum(wall_s)`. It also scrapes draft-acceptance stats
from the `llama-server` log when present.

Run it twice on the same model — once with `LLAMA_MTP=1` (MTP on) and once with
`LLAMA_MTP=0` (MTP off) — then compare the aggregate `tok/s`.

## How to run

Each run = start a stack with a chosen `LLAMA_MTP` and (optionally)
`AI_LOCAL_FORCE_THINK`, then run `bench_mtp.py` against that stack's proxy.
Stop the stack before the next run so ports/RAM are clean.

```bash
# 27B, no-think, MTP on
LLAMA_MTP=1 ai-local 27b
python3 bench/bench_mtp.py --label 27b-mtp-on
ai-local stop 27b

# 27B, no-think, MTP off (same MTP GGUF, speculative decoding disabled)
LLAMA_MTP=0 ai-local 27b
python3 bench/bench_mtp.py --label 27b-mtp-off
ai-local stop 27b

# 27B, thinking mode, MTP on
AI_LOCAL_FORCE_THINK=1 LLAMA_MTP=1 ai-local 27b
python3 bench/bench_mtp.py --label 27b-mtp-on-think
ai-local stop 27b

# 35B: same pattern, point at the 35B proxy and use the 35b subcommand
AI_LOCAL_FORCE_THINK=1 LLAMA_MTP=1 ai-local 35b
python3 bench/bench_mtp.py --url http://127.0.0.1:11435/v1 --label 35b-mtp-on-think
ai-local stop 35b
```

Options: `--url` (default `http://127.0.0.1:8081/v1` — use `11435/v1` for the 35B
proxy), `--label`, `--max-tokens` (default 192), `--model` (default `qwen`).
Results are written to `bench/results/bench_<label>.json`.

## Testing the n-gram spec-decode axis

`bench_mtp.py` itself is spec-agnostic — it just hits the proxy. The spec-decode
backend is chosen at stack launch time via `LLAMA_SPEC_TYPE` (default
`draft-mtp`), gated by `LLAMA_MTP`. llama.cpp build 9750 supports a
comma-separated list: `draft-mtp,ngram-simple,ngram-map-k,ngram-map-k4v,ngram-mod,ngram-cache`.
The bench auto-records which backends actually ran by scraping the
`statistics <backend>:` line from the `llama-server` log, so the JSON output is
self-describing — check the `draft_acceptance.spec_types` field to confirm the
config you intended actually ran.

n-gram modes need no MTP head and work with any GGUF; they shine on repetitive /
structured output (code, reasoning that repeats its thinking in the answer).

```bash
# Baseline (draft-mtp) — same as the measured runs above
LLAMA_MTP=1 ai-local 27b
python3 bench/bench_mtp.py --label 27b-spec-draft-mtp
ai-local stop 27b

# ngram-mod only (hash-pool lookup, ~16 MB, shared across slots)
LLAMA_MTP=1 LLAMA_SPEC_TYPE=ngram-mod ai-local 27b
python3 bench/bench_mtp.py --label 27b-spec-ngram-mod
ai-local stop 27b

# ngram-map-k4v ("Key-4-Values": 4 m-gram values per n-gram key). Try the
# Reddit k4v96 tuning (size-m=96) vs the llama.cpp default (size-m=48).
LLAMA_MTP=1 LLAMA_SPEC_TYPE=ngram-map-k4v \
    LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_N=16 LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_M=96 ai-local 27b
python3 bench/bench_mtp.py --label 27b-spec-ngram-map-k4v-k4v96
ai-local stop 27b

# Combined draft-mtp + ngram-mod + ngram-map-k4v (ggerganov's combined recipe,
# PR #23269). --spec-draft-n-max=3 is emitted automatically because draft-mtp
# is in the list; LLAMA_SPEC_DRAFT_P_MIN=0.0 matches the upstream recipe.
LLAMA_MTP=1 LLAMA_SPEC_TYPE=draft-mtp,ngram-mod,ngram-map-k4v \
    LLAMA_SPEC_DRAFT_P_MIN=0.0 \
    LLAMA_SPEC_NGRAM_MOD_N_MATCH=24 LLAMA_SPEC_NGRAM_MOD_N_MIN=48 LLAMA_SPEC_NGRAM_MOD_N_MAX=64 \
    LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_N=16 LLAMA_SPEC_NGRAM_MAP_K4V_SIZE_M=24 \
    LLAMA_SPEC_NGRAM_MAP_K4V_MIN_HITS=1 ai-local 27b
python3 bench/bench_mtp.py --label 27b-spec-combined
ai-local stop 27b
```

Caveats:
- The ~7x ngram-map-k4v gains reported on r/LocalLLM were on RTX 5090 (CUDA).
  On Apple Silicon/Metal the acceptance and verification cost differ — there is
  no guarantee n-gram beats draft-mtp here. Benchmark before trusting any win.
- `ngram-map-k4v` = Key-4-Values (4 m-gram values per n-gram key), NOT a KV-cache
  format. No need to change `LLAMA_CACHE_TYPE_K`.
- The 8-prompt suite mixes code, prose, and math; n-gram modes help most on
  repetitive output, so per-prompt variance will be high — read the per-prompt
  `tok/s` in the JSON, not just the aggregate.

## Results: Apple M3 Max (48 GB), llama.cpp build 9750, Q4_K_XL

Aggregate tok/s = `sum(completion_tokens) / sum(wall_s)` across the 8-prompt suite.
MTP was confirmed active by checking the `llama-server` log for the `--spec-type
draft-mtp` flag; prior runs that showed no speedup were invalid because the config
loader clobbered the `LLAMA_MTP=1` env override (now fixed — see `lib/qwen-config.sh:load_qwen_config`).

### 27B dense (Qwen3.6-27B-UD-Q4_K_XL, spec-draft-n-max=3)

| Mode     | MTP on | MTP off | Ratio | Gain |
|----------|-------:|--------:|------:|-----:|
| no-think | 14.47  | 10.19   | 1.42× | +42% |
| thinking | 15.53  | 12.19   | 1.27× | +27% |

The gain is largest in no-think mode (+42%); in thinking mode it drops to +27%.

### 35B-A3B MoE (Qwen3.6-35B-A3B-UD-Q4_K_XL, spec-draft-n-max=2)

| Mode     | MTP on | MTP off | Ratio | Gain |
|----------|-------:|--------:|------:|-----:|
| no-think | 65.81  | 53.68   | 1.23× | +23% |
| thinking | 66.84  | 52.64   | 1.27× | +27% |

The 35B-A3B holds a steady ~+25% across both modes (the small thinking/no-think
delta is within run-to-run noise on short ~23–29 s aggregates). In absolute
terms the 35B-A3B decodes ~4.5× faster than the 27B dense (~66 vs ~15 tok/s)
because only 3B of its 35B params are active per token.

### Caveat: the thinking-mode runs measure reasoning-token decode speed

`bench_mtp.py` caps `max_tokens` at 192, and every thinking-mode prompt hit
that cap (`completion_tokens=192` on all 16 thinking runs). Those runs therefore
measure decode speed *while the model is still inside the reasoning block* — they
never produced a final answer for most prompts. This is valid for comparing MTP
on vs off (identical cap on both sides) but is **not** evidence about whether
thinking should be the default; it only shows MTP accelerates reasoning-token
decoding just as it accelerates answer-token decoding.

## Conclusion

MTP speculative decoding is a real net decode speedup on Apple Silicon/Metal in
**every** measured scenario (+23% to +42%), across both the dense 27B and the
35B-A3B MoE and across both no-think and thinking modes, so it is **on by
default** (`LLAMA_MTP=1`). Set `LLAMA_MTP=0` only if you need the ~417 MiB the
MTP draft context occupies or want the non-MTP baseline.

Raw JSON results live in `bench/results/`:
- `bench_27b-mtp-{on,off}.json` — 27B, no-think
- `bench_27b-mtp-{on,off}-think.json` — 27B, thinking
- `bench_35b-mtp-{on,off}.json` — 35B-A3B, no-think
- `bench_35b-mtp-{on,off}-think.json` — 35B-A3B, thinking
