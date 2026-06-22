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

```bash
# MTP on
LLAMA_MTP=1 ai-local 27b
python3 bench/bench_mtp.py --label mtp-on

# MTP off (same MTP GGUF, speculative decoding disabled)
LLAMA_MTP=0 ai-local 27b
python3 bench/bench_mtp.py --label mtp-off
```

Options: `--url`, `--label`, `--max-tokens` (default 192), `--model` (default
`qwen`). Results are written to `bench/results/bench_<label>.json`.

## Results: Apple M3 Max (48 GB), llama.cpp build 9750, Q4_K_XL

Aggregate tok/s = `sum(completion_tokens) / sum(wall_s)` across the 8-prompt suite.
MTP was confirmed active by checking the `llama-server` log for the `--spec-type
draft-mtp` flag; prior runs that showed no speedup were invalid because the config
loader clobbered the `LLAMA_MTP=1` env override (now fixed — see `lib/qwen-config.sh:load_qwen_config`).

### 27B dense (Qwen3.6-27B-UD-Q4_K_XL, spec-draft-n-max=3)

| Run      | Aggregate tok/s | Notes             |
|----------|-----------------|-------------------|
| MTP on   | 14.47           | MTP enabled       |
| MTP off  | 10.19           | Baseline          |

**MTP on / MTP off = 1.42× (+42%) on the dense 27B.**

### 35B-A3B MoE (Qwen3.6-35B-A3B-UD-Q4_K_XL, spec-draft-n-max=2)

| Run      | Aggregate tok/s | Notes             |
|----------|-----------------|-------------------|
| MTP on   | 65.81           | MTP enabled       |
| MTP off  | 53.68           | Baseline          |

**MTP on / MTP off = 1.23× (+23%) on the 35B-A3B MoE.**

## Conclusion

MTP speculative decoding is a real net decode speedup on Apple Silicon/Metal on
both the dense 27B (+42%) and the 35B-A3B MoE (+23%), so it is **on by default**
(`LLAMA_MTP=1`). Set `LLAMA_MTP=0` only if you need the RAM the MTP draft context
occupies or want the non-MTP baseline.

Raw JSON results live in `bench/results/` (`bench_27b-mtp-{on,off}.json`,
`bench_35b-mtp-{on,off}.json`).
