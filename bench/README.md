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
