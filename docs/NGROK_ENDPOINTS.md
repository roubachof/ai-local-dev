# Expose ai-local model endpoints with ngrok

Use this guide to expose each local model endpoint (27B, 35B, router) with `ngrok` and connect external clients like Warp.

## Prerequisites

1. `ngrok` installed and authenticated:
   ```bash
   brew install ngrok
   ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>
   ```
2. `ai-local` services running for the model you want to expose.

## Which local endpoint to expose

- **27B via unified proxy (recommended for 27B no-think defaults)**
  - Local URL: `http://127.0.0.1:8081/v1`
  - Start stack: `ai-local 27b`
  - Typical model name: `local-27b`

- **35B via proxy (no-think path, llama.cpp default)**
  - Local URL: `http://127.0.0.1:11435/v1`
  - Start stack: `ai-local 35b`
  - Typical model name: `Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL` (or `local-35b` / `coder` via the router)

- **35B direct Ollama (legacy think-mode path, requires `ollama`)**
  - Local URL: `http://127.0.0.1:11434/v1`
  - Start stack: `ai-local 35b-ollama`
  - Model name: `qwen3.6:35b-ud-q4xl`

- **Router endpoint (single URL for planner/coder split)**
  - Local URL: `http://127.0.0.1:8090/v1`
  - Start stack: `ai-local router start`
  - Example model aliases:
    - planner side: `planner`, `plan`, `local-27b`, `qwen3.6-27b`
    - coder side: `coder`, `code`, `local-35b`, `qwen3.6:35b-ud-q4xl`

## Start ngrok for a target port

Always use host-header rewrite to avoid upstream `403` responses from local services:

```bash
ngrok http --host-header=rewrite <PORT>
```

Examples:

```bash
# 27B proxy
ngrok http --host-header=rewrite 8081

# 35B proxy (llama.cpp default)
ngrok http --host-header=rewrite 11435

# 35B direct think (legacy Ollama)
ngrok http --host-header=rewrite 11434

# Router
ngrok http --host-header=rewrite 8090
```

## Run ngrok in background

```bash
nohup ngrok http --host-header=rewrite <PORT> > /tmp/ngrok-<PORT>.log 2>&1 &
```

Get the public URL:

```bash
curl -s http://127.0.0.1:4040/api/tunnels
```

Use the `public_url` returned by ngrok, then append `/v1`:

```text
https://<your-ngrok-domain>.ngrok-free.dev/v1
```

## Verify the public endpoint

```bash
curl -si https://<your-ngrok-domain>.ngrok-free.dev/v1/models
```

Optional chat completion check:

```bash
curl -s https://<your-ngrok-domain>.ngrok-free.dev/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-35b",
    "messages": [{"role":"user","content":"Reply with exactly OK"}],
    "max_tokens": 10
  }'
```

## Warp custom endpoint example

In Warp **Add custom endpoint**:

- **Endpoint URL**: `https://<your-ngrok-domain>.ngrok-free.dev/v1`
- **API key**: any placeholder (example: `local`)
- **Model name**: add the model IDs you want (`local-27b`, `local-35b`, `Qwen3.6-35B-A3B-MTP-UD-Q4_K_XL`, etc.)

If Warp rejects parsing, try endpoint URL without `/v1` and keep model names unchanged.

## Stop ngrok

```bash
pkill -f "ngrok http"
```

## Notes

- Free ngrok domains can change between sessions.
- Free ngrok usually allows one active tunnel at a time.
- The ngrok URL is public; stop tunnels when not needed.
