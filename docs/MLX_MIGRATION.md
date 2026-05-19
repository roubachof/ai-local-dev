# MLX Migration (27B backend)

## Goal
Run 27B on MLX by default while preserving the existing public endpoint (`http://127.0.0.1:8081/v1`).

## Current model
- Upstream MLX server: `mlx_lm.server` on `MLX_PORT` (default `8082`)
- Public endpoint remains: `LLAMA_PROXY_PORT` (default `8081`)
- Proxy process: `bin/nothink_proxy.py --mode llama`

## Rollout steps
1. Ensure dependencies are installed:
   - `pip install -r requirements.txt`
2. Set backend:
   - `BACKEND_27B=mlx` in `config/.qwen-local.conf.local`
3. Start stack:
   - `ai-local 27b`
4. Validate:
   - `ai-local status`
   - `bin/verify_nothink.sh`

## Rollback
If MLX behavior is not acceptable, switch back to llama.cpp:

1. Edit `config/.qwen-local.conf.local`:
   - `BACKEND_27B=llama`
2. Restart 27B stack:
   - `ai-local restart 27b`

No client config changes are needed because proxy port `8081` stays stable.

## Notes
- `llama-server` remains optional unless `BACKEND_27B=llama`.
- The same think-control mechanism is used in both modes:
  - `chat_template_kwargs.enable_thinking`
