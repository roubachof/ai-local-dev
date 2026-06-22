# Troubleshooting

## Quick diagnostics

Run:

```bash
ai-local doctor
ai-local status
```

These commands verify dependencies, config, and service health.

## Services do not start

### 27B backend fails

```bash
ai-local logs llama
```

Verify GGUF exists:

```bash
ls -la ~/.local/share/llama-models/mtp/Qwen3.6-27B-UD-Q4_K_XL.gguf   # default model file (MTP)
ls -la ~/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf       # non-MTP fallback
```

If missing:

```bash
ai-local download 27b-mtp   # 27B MTP GGUF (default model file)
ai-local download 27b       # non-MTP fallback
```

### 35B backend fails (llama.cpp, default)

```bash
ai-local logs 35b-llama   # llama-server 35B
ai-local logs 35b         # 35B proxy
```

Verify the MTP GGUF exists (~22GB):

```bash
ls -la ~/.local/share/llama-models/mtp/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
```

If missing, download it:

```bash
ai-local download 35b
```

## Proxy issues

### Proxy health endpoint fails
Check:

```bash
curl -s http://127.0.0.1:8081/health
curl -s http://127.0.0.1:11435/health
```

Then inspect logs:

```bash
ai-local logs 27b
ai-local logs 35b
ai-local logs 35b-llama   # llama-server 35B only
```

Restart only the impacted stack:

```bash
ai-local restart 27b
ai-local restart 35b
```

## How to tell if thinking is really off
Inspect proxy logs for `"enable_thinking"` or `` markers:

```bash
ai-local logs 27b
ai-local logs 35b
```

If you see thinking blocks, check that `AI_LOCAL_FORCE_THINK` is not globally set to `0`.

## Timeout errors
Increase timeout in `config/.qwen-local.conf.local`:

```bash
PROXY_TIMEOUT=1200
```

Then restart:

```bash
ai-local restart 27b
ai-local restart 35b
```

## llama.cpp: reading checkpoint / MTP logs

`ai-local logs 35b-llama` (and `ai-local logs llama` for 27B) show whether the hybrid-cache + MTP flags are actually helping:

- On a **warm turn** (repeat prompt), you should see `restored context checkpoint` — the prefix was reused from the cache (40–80× prefill speedup).
- If you instead see `forcing full prompt re-processing` on every turn, the checkpoint is not being reused. Common cause: `preserve_thinking` is off while thinking is on, so the chat template strips reasoning from history and the prefix changes every turn. Ensure `LLAMA_PRESERVE_THINKING=1` (default) and that your `llama-server` build accepts `--chat-template-kwargs`.
- MTP: only relevant when `LLAMA_MTP=1` (on by default — see `bench/README.md`). Look for `draft acceptance` lines. On the dense 27B expect ~70%+; on the MoE 35B expect a lower but still positive rate. If `draft acceptance` is 0%, confirm the MTP GGUF is present and `LLAMA_MTP=1`. On Apple Silicon/Metal this gives a real net decode speedup (measured +42% on 27B, +23% on 35B-A3B on M3 Max).

## Port already in use
Find the process:

```bash
lsof -i :8080   # llama-server (27B)
lsof -i :8081   # 27B proxy
lsof -i :8083   # llama-server (35B)
lsof -i :11435  # 35B proxy
```

Stop managed services cleanly first:

```bash
ai-local stop
```

## Python module errors
Reinstall dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## More references
- [`ARCHITECTURE.md`](ARCHITECTURE.md)
- [`THINK_CONTROL.md`](THINK_CONTROL.md)
