# ai-local-dev

**Local AI Development Infrastructure**

Run Qwen models locally with a unified nothink proxy — **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing and MTP speculative decoding (on by default) — via one orchestrator command: `ai-local`.

---

## Quick Start

```bash
# Install
git clone https://github.com/roubachof/ai-local-dev.git
cd ai-local-dev
./install.sh

# Download models (llama.cpp GGUFs)
ai-local download 27b-mtp   # 27B MTP GGUF (default model file)
ai-local download 27b       # 27B non-MTP GGUF (optional fallback)
ai-local download 35b       # 35B-A3B + MTP, 128k ctx (recommended)

# Start stacks
ai-local 27b          # llama.cpp + checkpoint + MTP (on by default)
ai-local 35b          # llama.cpp + checkpoint + MTP, 128k ctx
```

---

## Architecture

- **`bin/ai-local`** — Unified orchestrator for models, proxies, and clients
- **`bin/__proxy.py`** — Unified nothink proxy for 27B/35B
- **`bin/model_router.py`** — Optional planner/coder router endpoint
- **`config/.qwen-local.conf`** — Centralized configuration
- **`lib/qwen-config.sh`** — Shared shell helpers and config loading
- **`docs/`** — Architecture, setup, troubleshooting, think control

## Features

- **llama.cpp for both 27B and 35B** with hybrid DeltaNet cache checkpointing (`--ctx-checkpoints`) for 40–80× warm-turn prefill speedup
- 27B: 64K context, Q4_K_XL (~18GB weights); MTP speculative decoding on by default (+42% decode throughput on Apple Silicon — see `bench/README.md`)
- 35B-A3B MoE: 128K context, Q4_K_XL + MTP (~22GB weights); MTP on by default (+23% decode throughput on Apple Silicon)
- MTP speculative decoding (`--spec-type draft-mtp`) on by default; disable with `LLAMA_MTP=0` (saves a little RAM)
- `--swa-full` for bounded KV on sliding-window attention layers (memory-efficient long context)
- `--chat-template-kwargs preserve_thinking=true` to keep reasoning in history for checkpoint prefix reuse
- Stable 27B endpoint (`http://127.0.0.1:8081/v1`) and 35B endpoint (`http://127.0.0.1:11435/v1`)
- Thinking disabled by default with force-think override (`AI_LOCAL_FORCE_THINK=1`)
- Persistent logs and PID files under `~/.local/state/ai-local/`
- Commands for restart, logs, download, and doctor checks

## Quantization rationale (M3 Max, 48GB)

| Model | Quant | Weights | Context | Rationale |
|-------|-------|---------|---------|----------|
| 27B dense | Q4_K_XL | ~18GB | 64K | Fits with headroom; `--spec-draft-n-max 3` if MTP enabled |
| 35B-A3B MoE | Q4_K_XL | ~22GB | 128K | Hybrid KV is tiny (10/40 full-attention layers); Q6 would leave no room for 128K + MTP |

Higher quants (Q6_K, Q8_0) are bandwidth-bound on Apple Silicon — the marginal quality gain is not worth the speed loss. MTP speculative decoding is on by default (`LLAMA_MTP=1`): on Apple Silicon/Metal it is a real net decode speedup (see Benchmarks below); disable with `LLAMA_MTP=0` to save a little RAM.

## Benchmarks

Apple M3 Max (48 GB), llama.cpp build 9750, Q4_K_XL. Aggregate tok/s = `sum(completion_tokens) / sum(wall_s)` over an 8-prompt suite (`bench/bench_mtp.py`). MTP was confirmed active per-run via the `llama-server` log (`--spec-type draft-mtp`, `n_max=3` for 27B, `n_max=2` for 35B).

| Model | Mode | MTP on | MTP off | Ratio | Gain |
|-------|------|-------:|--------:|------:|-----:|
| 27B dense | no-think | 14.47 | 10.19 | 1.42× | +42% |
| 27B dense | thinking | 15.53 | 12.19 | 1.27× | +27% |
| 35B-A3B MoE | no-think | 65.81 | 53.68 | 1.23× | +23% |
| 35B-A3B MoE | thinking | 66.84 | 52.64 | 1.27× | +27% |

**MTP is a net decode speedup in every scenario** (+23% to +42%), across both models and both think/no-think modes. The gain is largest on the dense 27B in no-think mode (+42%); the 35B-A3B MoE holds a steady ~+25% across modes.

Caveats:
- An earlier reported 0.94× (no speedup) result was invalid: the config loader clobbered the `LLAMA_MTP=1` env override before launch, so MTP was never actually enabled. Fixed in `lib/qwen-config.sh:load_qwen_config` (env overrides now win over config defaults).
- All thinking-mode runs hit the 192-token completion cap on every prompt, so those runs measure *reasoning-token decode speed*, not completed end-to-end tasks. Valid for MTP on/off comparison (same cap both sides), but not evidence that thinking should be the default.
- The 35B-A3B runs ~4.5× faster in absolute tok/s than the 27B dense (~66 vs ~15 tok/s) because only 3B of its 35B params are active per token. It offers both higher throughput and higher quality, at the cost of a ~22 GB footprint.

Raw JSON results and how to re-run live in [`bench/README.md`](bench/README.md).

## Models

- **Qwen3.6-27B**: `llama-server` (port `8080`) behind proxy (`8081`) with 64K context, Q4_K_XL
- **Qwen3.6-35B-A3B**: `llama-server` (port `8083`) behind proxy (`11435`) with 128K context, Q4_K_XL + MTP

## MTP configuration

MTP (Multi-Token Prediction) speculative decoding is **on by default** (`LLAMA_MTP=1`) for both backends. The MTP GGUF is the default model file (it also loads fine without `--spec-type`); a non-MTP GGUF is kept as an optional fallback.

Relevant config keys (see `config/.qwen-local.conf`):

- `LLAMA_MTP` — `1` (on, default) / `0` (off). When on, `llama-server` launches with `--spec-type draft-mtp --spec-draft-n-max N`.
- `LLAMA_MTP_N_MAX_27B` — `3` (dense 27B: the acceptance sweet spot)
- `LLAMA_MTP_N_MAX_35B` — `2` (MoE 35B: 3+ degrades acceptance per MoE benchmarks)
- `QWEN_27B_MTP_MODEL`, `QWEN_35B_MTP_MODEL` — paths to the MTP GGUFs (live under `~/.local/share/llama-models/mtp/`)

Per-run overrides (env wins over config — see `lib/qwen-config.sh:load_qwen_config`):

```bash
LLAMA_MTP=0 ai-local 27b   # disable MTP for one run (saves ~417 MiB draft context)
LLAMA_MTP=1 ai-local 35b   # explicitly enable (default)
```

The MTP draft context costs ~417 MiB of RAM (per `llama-server` log), negligible against the 18–22 GB weights. Set `LLAMA_MTP=0` only if you need that headroom and are willing to trade 23–42% decode throughput.

MTP is orthogonal to think/no-think (`AI_LOCAL_FORCE_THINK`): the MTP axis accelerates decoding in either mode. See `bench/README.md` for the full think/no-think × MTP on/off matrix.

## Useful commands

```bash
ai-local status
ai-local restart 27b
ai-local restart 35b
ai-local logs 27b
ai-local logs 35b
ai-local doctor
ai-local config
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/SETUP_FIRST_TIME.md`](docs/SETUP_FIRST_TIME.md)
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/THINK_CONTROL.md`](docs/THINK_CONTROL.md)
- [`docs/NGROK_ENDPOINTS.md`](docs/NGROK_ENDPOINTS.md)

## License

MIT
