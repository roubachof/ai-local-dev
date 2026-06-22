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

## Result: 27B on Apple M3 Max (48 GB), llama.cpp build 9750, Q4_K_XL

| Run      | Aggregate tok/s | Notes                                  |
|----------|-----------------|----------------------------------------|
| MTP on   | 14.90           | Draft acceptance ~72% (from prior runs)|
| MTP off  | 15.83           | Baseline                               |

**MTP on / MTP off = 0.94× — no speedup on Metal.** Draft tokens were accepted
(~72% in earlier runs), so the speculative path works, but on the Metal backend
the per-draft verification cost offsets the accepted-token gains. MTP
speculative decoding shows real speedups on CUDA hardware; on Apple Silicon the
recommended stable config is `LLAMA_MTP=0` unless you are running on CUDA.

Raw JSON results live in `bench/results/`.
