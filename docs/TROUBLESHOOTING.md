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
Check backend mode and logs:

```bash
ai-local config | grep BACKEND_27B
ai-local logs mlx       # when BACKEND_27B=mlx
ai-local logs llama     # when BACKEND_27B=llama
```

If `BACKEND_27B=llama`, verify GGUF exists:

```bash
ls -la ~/.local/share/llama-models/Qwen3.6-27B-UD-Q4_K_XL.gguf
```

### 8B/35B backend fails
Verify Ollama:

```bash
which ollama
ollama list
ai-local logs ollama
```

If model is missing:

```bash
ai-local download 8b
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
ai-local logs 8b
ai-local logs 35b
```

Restart only the impacted stack:

```bash
ai-local restart 27b
ai-local restart 8b
ai-local restart 35b
```

## How to tell if thinking is really off
Use the verifier:

```bash
bin/verify_nothink.sh
```

Expected result:

- nothink completion tokens are at least 5x smaller than force-think
- nothink latency is at least 2x faster than force-think

If it fails, inspect proxy logs and ensure force-think env vars are not globally set.

## Timeout errors
Increase timeout in `config/.qwen-local.conf.local`:

```bash
PROXY_TIMEOUT=1200
```

Then restart:

```bash
ai-local restart 27b
ai-local restart 8b
ai-local restart 35b
```

## Port already in use
Find the process:

```bash
lsof -i :8080
lsof -i :8081
lsof -i :8082
lsof -i :11434
lsof -i :11435
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
- [`MLX_MIGRATION.md`](MLX_MIGRATION.md)
